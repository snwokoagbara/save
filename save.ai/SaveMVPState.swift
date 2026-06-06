import Foundation

enum ConnectedSource: String, Codable, Hashable {
    case gmail
    case bank
    case forwardingInbox

    var title: String {
        switch self {
        case .gmail:
            return "Gmail"
        case .bank:
            return "Bank"
        case .forwardingInbox:
            return "Forwarding inbox"
        }
    }
}

struct MVPTask: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let amount: Double?
    let actionTitle: String
    let symbol: String
}

struct TaxReportArtifact: Hashable {
    let filename: String
    let csvPreview: String
    let total: Double
}

struct SaveMVPState {
    private(set) var hasCompletedOnboarding: Bool
    private(set) var connectedSources: Set<ConnectedSource>
    private(set) var receipts: [Receipt]
    private(set) var claimPackets: [ClaimPacket]
    private(set) var taxReportArtifact: TaxReportArtifact?
    private var excludedFirstReviewItem: Bool
    private var preparedFirstDraftClaim: Bool
    private var exportedTaxReport: Bool
    private var importedSampleReceipt: Bool
    private var importedReceiptDrafts: [ReceiptDraft]
    private var submittedClaimAdministratorNames: Set<String>
    private var reimbursedClaimAdministratorNames: Set<String>

    init(
        hasCompletedOnboarding: Bool = false,
        connectedSources: Set<ConnectedSource> = [],
        receipts: [Receipt] = DemoData.receipts,
        claimPackets: [ClaimPacket] = SaveMVPState.initialClaimPackets,
        taxReportArtifact: TaxReportArtifact? = nil,
        excludedFirstReviewItem: Bool = false,
        preparedFirstDraftClaim: Bool = false,
        exportedTaxReport: Bool = false,
        importedSampleReceipt: Bool = false,
        importedReceiptDrafts: [ReceiptDraft] = [],
        submittedClaimAdministratorNames: Set<String> = [],
        reimbursedClaimAdministratorNames: Set<String> = []
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.connectedSources = connectedSources
        self.receipts = receipts
        self.claimPackets = claimPackets
        self.taxReportArtifact = taxReportArtifact
        self.excludedFirstReviewItem = excludedFirstReviewItem
        self.preparedFirstDraftClaim = preparedFirstDraftClaim
        self.exportedTaxReport = exportedTaxReport
        self.importedSampleReceipt = importedSampleReceipt
        self.importedReceiptDrafts = importedReceiptDrafts
        self.submittedClaimAdministratorNames = submittedClaimAdministratorNames
        self.reimbursedClaimAdministratorNames = reimbursedClaimAdministratorNames
    }

    init(persisted: SaveMVPPersistedState) {
        self.init(hasCompletedOnboarding: persisted.hasCompletedOnboarding)
        connectedSources = persisted.connectedSources

        if persisted.excludedFirstReviewItem {
            excludeFirstReviewItem()
        }

        if persisted.preparedFirstDraftClaim {
            prepareFirstDraftClaim()
        }

        if persisted.exportedTaxReport {
            exportTaxReport()
        }

        persisted.submittedClaimAdministratorNames.forEach { administratorName in
            submitClaimPacket(administratorName: administratorName)
        }

        persisted.reimbursedClaimAdministratorNames.forEach { administratorName in
            markClaimReimbursed(administratorName: administratorName)
        }

        if persisted.importedSampleReceipt {
            try? importSampleReceipt()
        }

        persisted.importedReceiptDrafts.forEach { draft in
            importReceiptDraft(draft, persistsDraft: false)
        }

        persisted.receiptLineItemClassifications.forEach { classification in
            apply(classification)
        }
    }

    var persisted: SaveMVPPersistedState {
        SaveMVPPersistedState(
            hasCompletedOnboarding: hasCompletedOnboarding,
            connectedSources: connectedSources,
            excludedFirstReviewItem: excludedFirstReviewItem,
            preparedFirstDraftClaim: preparedFirstDraftClaim,
            exportedTaxReport: exportedTaxReport,
            importedSampleReceipt: importedSampleReceipt,
            importedReceiptDrafts: importedReceiptDrafts,
            receiptLineItemClassifications: receiptLineItemClassifications,
            submittedClaimAdministratorNames: submittedClaimAdministratorNames,
            reimbursedClaimAdministratorNames: reimbursedClaimAdministratorNames
        )
    }

    var isReadyForEstimate: Bool {
        connectedSources.contains(.gmail) && connectedSources.contains(.bank)
    }

    var summary: ClaimSummary {
        ClaimSummary(receipts: receipts)
    }

    var taxExport: TaxExport {
        TaxExport(year: 2026, receipts: receipts)
    }

    var activeTasks: [MVPTask] {
        var tasks: [MVPTask] = []

        if !connectedSources.contains(.gmail) {
            tasks.append(
                MVPTask(
                    id: "connect-gmail",
                    title: "Connect Gmail",
                    detail: "Let Kai scan receipt emails and find missed medical purchases.",
                    amount: nil,
                    actionTitle: "Connect",
                    symbol: "envelope.fill"
                )
            )
        }

        if !connectedSources.contains(.bank) {
            tasks.append(
                MVPTask(
                    id: "link-bank",
                    title: "Link bank",
                    detail: "Match card charges to receipts and surface claims you forgot.",
                    amount: nil,
                    actionTitle: "Link bank",
                    symbol: "building.columns.fill"
                )
            )
        }

        if let reviewReceipt = firstNeedsReviewReceipt,
           let reviewItem = reviewReceipt.lineItems.first(where: { $0.eligibility == .needsReview }) {
            tasks.append(
                MVPTask(
                    id: "review-receipt-\(reviewReceipt.id.uuidString)",
                    title: "Review \(reviewReceipt.merchant) item",
                    detail: "Kai is unsure about \(reviewItem.name). Choose a classification before claim generation.",
                    amount: reviewItem.amount,
                    actionTitle: "Review item",
                    symbol: "exclamationmark.triangle.fill"
                )
            )
        }

        if claimPackets.contains(where: { $0.status == .draft }) {
            tasks.append(
                MVPTask(
                    id: "prepare-health-equity",
                    title: "Prepare HealthEquity packet",
                    detail: "Eligible items are grouped with receipt evidence and form fields.",
                    amount: summary.totalClaimable,
                    actionTitle: "Prepare claim",
                    symbol: "doc.badge.arrow.up.fill"
                )
            )
        }

        if taxReportArtifact == nil {
            tasks.append(
                MVPTask(
                    id: "export-tax-report",
                    title: "Export 2026 Schedule A report",
                    detail: "Itemized medical-expense backup is ready for CPA or TurboTax.",
                    amount: taxExport.totalMedicalExpenses,
                    actionTitle: "Export",
                    symbol: "square.and.arrow.down.fill"
                )
            )
        }

        return tasks
    }

    var firstNeedsReviewReceipt: Receipt? {
        receipts.first(where: \.hasNeedsReviewItem)
    }

    mutating func connect(_ source: ConnectedSource) {
        connectedSources.insert(source)
    }

    mutating func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    mutating func excludeFirstReviewItem() {
        guard let receiptIndex = receipts.firstIndex(where: \.hasNeedsReviewItem),
              let lineItem = receipts[receiptIndex].lineItems.first(where: { $0.eligibility == .needsReview }) else {
            return
        }

        replaceLineItem(
            lineItem.id,
            with: ReceiptLineItem(
                id: lineItem.id,
                name: lineItem.name,
                amount: lineItem.amount,
                eligibility: .notEligible,
                confidence: lineItem.confidence
            )
        )
        excludedFirstReviewItem = true
    }

    mutating func prepareFirstDraftClaim() {
        guard let index = claimPackets.firstIndex(where: { $0.status == .draft }) else {
            return
        }

        claimPackets[index].status = .ready
        preparedFirstDraftClaim = true
    }

    mutating func submitClaimPacket(_ id: UUID) {
        guard let index = claimPackets.firstIndex(where: { $0.id == id }) else {
            return
        }

        submitClaimPacket(at: index)
    }

    mutating func markClaimReimbursed(_ id: UUID) {
        guard let index = claimPackets.firstIndex(where: { $0.id == id }) else {
            return
        }

        markClaimReimbursed(at: index)
    }

    mutating func exportTaxReport() {
        taxReportArtifact = TaxReportArtifact(
            filename: "save-medical-expenses-\(taxExport.year).csv",
            csvPreview: taxExport.csvPreview,
            total: taxExport.totalMedicalExpenses
        )
        exportedTaxReport = true
    }

    mutating func importReceiptDraft(_ draft: ReceiptDraft) {
        importReceiptDraft(draft, persistsDraft: true)
    }

    private mutating func importReceiptDraft(_ draft: ReceiptDraft, persistsDraft: Bool) {
        let receipt = Receipt(
            merchant: draft.merchant,
            date: draft.purchasedAt,
            source: .camera,
            lineItems: draft.lineItems.map { item in
                ReceiptLineItem(
                    name: item.name,
                    amount: item.amount,
                    eligibility: .needsReview,
                    confidence: item.confidence
                )
            }
        )

        receipts.insert(receipt, at: 0)

        if persistsDraft {
            importedReceiptDrafts.append(draft)
        }
    }

    mutating func importSampleReceipt() throws {
        guard !importedSampleReceipt else {
            return
        }

        let draft = try ReceiptOCRParser().parse(ReceiptOCRFixtures.sampleCVS)
        importReceiptDraft(draft, persistsDraft: false)
        importedSampleReceipt = true
    }

    mutating func classifyLineItem(_ id: UUID, as eligibility: Eligibility) {
        guard let lineItem = receipts.flatMap(\.lineItems).first(where: { $0.id == id }) else {
            return
        }

        replaceLineItem(
            id,
            with: ReceiptLineItem(
                id: lineItem.id,
                name: lineItem.name,
                amount: lineItem.amount,
                eligibility: eligibility,
                confidence: lineItem.confidence
            )
        )
    }

    private var receiptLineItemClassifications: [ReceiptLineItemClassification] {
        receipts.flatMap { receipt in
            receipt.lineItems
                .filter { $0.eligibility != .needsReview }
                .map { item in
                    ReceiptLineItemClassification(
                        merchant: receipt.merchant,
                        purchasedAt: receipt.date,
                        itemName: item.name,
                        amount: item.amount,
                        eligibility: item.eligibility
                    )
                }
        }
    }

    private mutating func apply(_ classification: ReceiptLineItemClassification) {
        guard let receipt = receipts.first(where: { receipt in
            receipt.merchant == classification.merchant &&
                receipt.date == classification.purchasedAt
        }),
              let lineItem = receipt.lineItems.first(where: { item in
                  item.name == classification.itemName &&
                      item.amount == classification.amount
              }) else {
            return
        }

        classifyLineItem(lineItem.id, as: classification.eligibility)
    }

    private mutating func submitClaimPacket(administratorName: String) {
        guard let index = claimPackets.firstIndex(where: { $0.administratorName == administratorName }) else {
            return
        }

        submitClaimPacket(at: index)
    }

    private mutating func submitClaimPacket(at index: Int) {
        guard claimPackets[index].status.canTransition(to: .submittedByUser) else {
            return
        }

        claimPackets[index].status = .submittedByUser
        submittedClaimAdministratorNames.insert(claimPackets[index].administratorName)
    }

    private mutating func markClaimReimbursed(administratorName: String) {
        guard let index = claimPackets.firstIndex(where: { $0.administratorName == administratorName }) else {
            return
        }

        markClaimReimbursed(at: index)
    }

    private mutating func markClaimReimbursed(at index: Int) {
        guard claimPackets[index].status.canTransition(to: .reimbursed) else {
            return
        }

        claimPackets[index].status = .reimbursed
        reimbursedClaimAdministratorNames.insert(claimPackets[index].administratorName)
    }

    mutating func resetProgress() {
        self = SaveMVPState()
    }

    mutating func perform(_ task: MVPTask) {
        switch task.id {
        case "connect-gmail":
            connect(.gmail)
        case "link-bank":
            connect(.bank)
        case let taskID where taskID.hasPrefix("review-receipt-"):
            excludeFirstReviewItem()
        case "prepare-health-equity":
            prepareFirstDraftClaim()
        case "export-tax-report":
            exportTaxReport()
        default:
            break
        }
    }

    private mutating func replaceLineItem(_ id: UUID, with replacement: ReceiptLineItem) {
        receipts = receipts.map { receipt in
            Receipt(
                id: receipt.id,
                merchant: receipt.merchant,
                date: receipt.date,
                source: receipt.source,
                lineItems: receipt.lineItems.map { $0.id == id ? replacement : $0 }
            )
        }
    }

    private static var initialClaimPackets: [ClaimPacket] {
        DemoData.claimPackets.enumerated().map { index, packet in
            ClaimPacket(
                id: packet.id,
                administratorName: packet.administratorName,
                lineItems: packet.lineItems,
                submissionMode: packet.submissionMode,
                status: index == 0 ? .draft : packet.status
            )
        }
    }
}
