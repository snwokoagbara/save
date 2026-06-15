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

struct TaxReportArtifact: Codable, Hashable {
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
    private var receiptEdits: [ReceiptEdit]
    private var receiptLineItemEdits: [ReceiptLineItemEdit]
    private var submittedClaimAdministratorNames: Set<String>
    private var reimbursedClaimAdministratorNames: Set<String>
    private var usesFullDomainPersistence: Bool

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
        receiptEdits: [ReceiptEdit] = [],
        receiptLineItemEdits: [ReceiptLineItemEdit] = [],
        submittedClaimAdministratorNames: Set<String> = [],
        reimbursedClaimAdministratorNames: Set<String> = [],
        usesFullDomainPersistence: Bool = false
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
        self.receiptEdits = receiptEdits
        self.receiptLineItemEdits = receiptLineItemEdits
        self.submittedClaimAdministratorNames = submittedClaimAdministratorNames
        self.reimbursedClaimAdministratorNames = reimbursedClaimAdministratorNames
        self.usesFullDomainPersistence = usesFullDomainPersistence
    }

    init(persisted: SaveMVPPersistedState) {
        if let receipts = persisted.receipts,
           let claimPackets = persisted.claimPackets {
            self.init(
                hasCompletedOnboarding: persisted.hasCompletedOnboarding,
                connectedSources: persisted.connectedSources,
                receipts: receipts,
                claimPackets: claimPackets,
                taxReportArtifact: persisted.taxReportArtifact,
                excludedFirstReviewItem: persisted.excludedFirstReviewItem,
                preparedFirstDraftClaim: persisted.preparedFirstDraftClaim,
                exportedTaxReport: persisted.exportedTaxReport,
                importedSampleReceipt: persisted.importedSampleReceipt,
                importedReceiptDrafts: persisted.importedReceiptDrafts,
                receiptEdits: persisted.receiptEdits,
                receiptLineItemEdits: persisted.receiptLineItemEdits,
                submittedClaimAdministratorNames: persisted.submittedClaimAdministratorNames,
                reimbursedClaimAdministratorNames: persisted.reimbursedClaimAdministratorNames,
                usesFullDomainPersistence: true
            )
            return
        }

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

        persisted.receiptEdits.forEach { edit in
            apply(edit)
        }

        persisted.receiptLineItemEdits.forEach { edit in
            apply(edit)
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
            receiptEdits: receiptEdits,
            receiptLineItemEdits: receiptLineItemEdits,
            receiptLineItemClassifications: receiptLineItemClassifications,
            submittedClaimAdministratorNames: submittedClaimAdministratorNames,
            reimbursedClaimAdministratorNames: reimbursedClaimAdministratorNames,
            receipts: usesFullDomainPersistence ? receipts : nil,
            claimPackets: usesFullDomainPersistence ? claimPackets : nil,
            taxReportArtifact: usesFullDomainPersistence ? taxReportArtifact : nil
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

    mutating func editReceipt(_ id: UUID, merchant: String, date: Date) {
        guard let receipt = receipts.first(where: { $0.id == id }) else {
            return
        }

        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMerchant.isEmpty else {
            return
        }

        let editIndex = receiptEdits.firstIndex { edit in
            edit.merchant == receipt.merchant &&
                edit.purchasedAt == receipt.date
        }
        let originalMerchant = editIndex.map { receiptEdits[$0].originalMerchant } ?? receipt.merchant
        let originalPurchasedAt = editIndex.map { receiptEdits[$0].originalPurchasedAt } ?? receipt.date
        let edit = ReceiptEdit(
            originalMerchant: originalMerchant,
            originalPurchasedAt: originalPurchasedAt,
            merchant: trimmedMerchant,
            purchasedAt: date
        )

        if let editIndex {
            receiptEdits[editIndex] = edit
        } else {
            receiptEdits.append(edit)
        }

        receiptLineItemEdits = receiptLineItemEdits.map { lineItemEdit in
            guard lineItemEdit.receiptMerchant == receipt.merchant,
                  lineItemEdit.receiptPurchasedAt == receipt.date else {
                return lineItemEdit
            }

            return ReceiptLineItemEdit(
                receiptMerchant: trimmedMerchant,
                receiptPurchasedAt: date,
                originalItemName: lineItemEdit.originalItemName,
                originalAmount: lineItemEdit.originalAmount,
                itemName: lineItemEdit.itemName,
                amount: lineItemEdit.amount
            )
        }

        replaceReceipt(id, merchant: trimmedMerchant, date: date)
    }

    mutating func editLineItem(_ id: UUID, name: String, amount: Double) {
        guard let receipt = receipts.first(where: { receipt in
            receipt.lineItems.contains { $0.id == id }
        }),
              let lineItem = receipt.lineItems.first(where: { $0.id == id }) else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let roundedAmount = amount.roundedToCents()
        guard !trimmedName.isEmpty, roundedAmount >= 0 else {
            return
        }

        let editIndex = receiptLineItemEdits.firstIndex { edit in
            edit.receiptMerchant == receipt.merchant &&
                edit.receiptPurchasedAt == receipt.date &&
                edit.itemName == lineItem.name &&
                edit.amount == lineItem.amount
        }
        let originalItemName = editIndex.map { receiptLineItemEdits[$0].originalItemName } ?? lineItem.name
        let originalAmount = editIndex.map { receiptLineItemEdits[$0].originalAmount } ?? lineItem.amount
        let edit = ReceiptLineItemEdit(
            receiptMerchant: receipt.merchant,
            receiptPurchasedAt: receipt.date,
            originalItemName: originalItemName,
            originalAmount: originalAmount,
            itemName: trimmedName,
            amount: roundedAmount
        )

        if let editIndex {
            receiptLineItemEdits[editIndex] = edit
        } else {
            receiptLineItemEdits.append(edit)
        }

        replaceLineItem(
            id,
            with: ReceiptLineItem(
                id: lineItem.id,
                name: trimmedName,
                amount: roundedAmount,
                eligibility: lineItem.eligibility,
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

    private mutating func apply(_ edit: ReceiptEdit) {
        guard let receipt = receipts.first(where: { receipt in
            receipt.merchant == edit.originalMerchant &&
                receipt.date == edit.originalPurchasedAt
        }) else {
            return
        }

        replaceReceipt(receipt.id, merchant: edit.merchant, date: edit.purchasedAt)
        receiptEdits.append(edit)
    }

    private mutating func apply(_ edit: ReceiptLineItemEdit) {
        guard let receipt = receipts.first(where: { receipt in
            receipt.merchant == edit.receiptMerchant &&
                receipt.date == edit.receiptPurchasedAt
        }),
              let lineItem = receipt.lineItems.first(where: { item in
                  item.name == edit.originalItemName &&
                      item.amount == edit.originalAmount
              }) else {
            return
        }

        replaceLineItem(
            lineItem.id,
            with: ReceiptLineItem(
                id: lineItem.id,
                name: edit.itemName,
                amount: edit.amount,
                eligibility: lineItem.eligibility,
                confidence: lineItem.confidence
            )
        )
        receiptLineItemEdits.append(edit)
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

    private mutating func replaceReceipt(_ id: UUID, merchant: String, date: Date) {
        receipts = receipts.map { receipt in
            guard receipt.id == id else {
                return receipt
            }

            return Receipt(
                id: receipt.id,
                merchant: merchant,
                date: date,
                source: receipt.source,
                lineItems: receipt.lineItems
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
