import Foundation

enum Eligibility: String, CaseIterable, Identifiable, Codable {
    case fsaEligible = "FSA eligible"
    case hsaEligible = "HSA eligible"
    case scheduleADeductible = "Schedule A deductible"
    case notEligible = "Not eligible"
    case needsReview = "Needs review"

    var id: String { rawValue }

    var isReimbursable: Bool {
        self == .fsaEligible || self == .hsaEligible
    }

    var isTaxRelevant: Bool {
        isReimbursable || self == .scheduleADeductible
    }

    var symbolName: String {
        switch self {
        case .fsaEligible, .hsaEligible:
            return "checkmark.seal.fill"
        case .scheduleADeductible:
            return "doc.text.fill"
        case .notEligible:
            return "xmark.circle.fill"
        case .needsReview:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct ReceiptLineItem: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let amount: Double
    let eligibility: Eligibility
    let confidence: Double

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        eligibility: Eligibility,
        confidence: Double
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.eligibility = eligibility
        self.confidence = confidence
    }

    var isReimbursable: Bool {
        eligibility.isReimbursable
    }
}

struct Receipt: Codable, Identifiable, Hashable {
    let id: UUID
    let merchant: String
    let date: Date
    let source: ReceiptSource
    let lineItems: [ReceiptLineItem]

    init(
        id: UUID = UUID(),
        merchant: String,
        date: Date,
        source: ReceiptSource,
        lineItems: [ReceiptLineItem]
    ) {
        self.id = id
        self.merchant = merchant
        self.date = date
        self.source = source
        self.lineItems = lineItems
    }

    var total: Double {
        lineItems.reduce(0) { $0 + $1.amount }.roundedToCents()
    }

    var reimbursableTotal: Double {
        lineItems.filter(\.isReimbursable).reduce(0) { $0 + $1.amount }.roundedToCents()
    }

    var hasNeedsReviewItem: Bool {
        lineItems.contains { $0.eligibility == .needsReview }
    }
}

enum ReceiptSource: String, Codable {
    case camera = "Camera scan"
    case gmail = "Gmail"
    case bank = "Plaid match"
    case forwardedEmail = "Forwarded email"
}

enum SubmissionMode: String, Codable {
    case guidedPacket = "Guided packet"
    case inAppSubmission = "In-app submission"
}

enum ClaimSubmissionMethod: String, CaseIterable, Codable, Identifiable {
    case administratorPortal = "Administrator portal"
    case inApp = "In-app submission"
    case email = "Email"
    case other = "Other"

    var id: String { rawValue }
}

struct ClaimSubmission: Codable, Hashable {
    let submittedAt: Date
    let method: ClaimSubmissionMethod
    let confirmationNumber: String
    let notes: String
}

enum ClaimStatus: String, CaseIterable, Codable, Identifiable {
    case draft = "Draft"
    case ready = "Ready"
    case submittedByUser = "Submitted by user"
    case submittedInApp = "Submitted in app"
    case reimbursed = "Reimbursed"
    case rejected = "Rejected"
    case needsAction = "Needs action"

    var id: String { rawValue }

    func canTransition(to nextStatus: ClaimStatus) -> Bool {
        switch (self, nextStatus) {
        case (.draft, .ready),
             (.ready, .submittedByUser),
             (.ready, .submittedInApp),
             (.submittedByUser, .reimbursed),
             (.submittedInApp, .reimbursed),
             (.submittedByUser, .needsAction),
             (.submittedInApp, .needsAction),
             (.needsAction, .ready),
             (.ready, .rejected):
            return true
        default:
            return false
        }
    }
}

struct ClaimPacket: Codable, Identifiable, Hashable {
    let id: UUID
    let administratorName: String
    let lineItems: [ReceiptLineItem]
    let submissionMode: SubmissionMode
    var status: ClaimStatus
    var submission: ClaimSubmission?

    init(
        id: UUID = UUID(),
        administratorName: String,
        lineItems: [ReceiptLineItem],
        submissionMode: SubmissionMode,
        status: ClaimStatus = .ready,
        submission: ClaimSubmission? = nil
    ) {
        self.id = id
        self.administratorName = administratorName
        self.lineItems = lineItems
        self.submissionMode = submissionMode
        self.status = status
        self.submission = submission
    }

    var total: Double {
        lineItems.reduce(0) { $0 + $1.amount }.roundedToCents()
    }

    var isReadyForUserSubmission: Bool {
        !administratorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !lineItems.isEmpty &&
            lineItems.allSatisfy(\.isReimbursable)
    }
}

struct ClaimSummary {
    let receipts: [Receipt]

    var totalClaimable: Double {
        receipts.reduce(0) { $0 + $1.reimbursableTotal }.roundedToCents()
    }

    var readyClaimCount: Int {
        receipts.filter { $0.reimbursableTotal > 0 }.count
    }

    var needsReviewCount: Int {
        receipts.flatMap(\.lineItems).filter { $0.eligibility == .needsReview }.count
    }

    var assistantStatusLine: String {
        let packetLabel = readyClaimCount == 1 ? "claim packet" : "claim packets"
        let reviewPhrase = needsReviewCount == 1 ? "item needs" : "items need"
        let reviewObject = needsReviewCount == 1 ? "it" : "them"
        return "\(readyClaimCount) \(packetLabel) found. \(needsReviewCount) \(reviewPhrase) your review before Kai includes \(reviewObject)."
    }
}

struct TaxExport {
    let year: Int
    let receipts: [Receipt]

    var rows: [TaxExportRow] {
        receipts.flatMap { receipt in
            receipt.lineItems
                .filter { $0.eligibility.isTaxRelevant }
                .map { item in
                    TaxExportRow(
                        date: receipt.date,
                        merchant: receipt.merchant,
                        itemName: item.name,
                        amount: item.amount,
                        eligibility: item.eligibility
                    )
                }
        }
    }

    var totalMedicalExpenses: Double {
        rows.reduce(0) { $0 + $1.amount }.roundedToCents()
    }

    var csvRows: [String] {
        rows.map { row in
            "\(Self.dateFormatter.string(from: row.date)),\(row.merchant),\(row.itemName),\(String(format: "%.2f", row.amount)),\(row.eligibility.rawValue)"
        }
    }

    var csvPreview: String {
        (["date,merchant,item,amount,classification"] + csvRows).joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct TaxExportRow: Hashable {
    let date: Date
    let merchant: String
    let itemName: String
    let amount: Double
    let eligibility: Eligibility
}

enum DemoData {
    static let receipts: [Receipt] = [
        Receipt(
            merchant: "Walgreens",
            date: date(year: 2026, month: 5, day: 17),
            source: .gmail,
            lineItems: [
                ReceiptLineItem(name: "FSA Sunscreen SPF 50", amount: 18.77, eligibility: .fsaEligible, confidence: 0.96),
                ReceiptLineItem(name: "Vitamin bundle", amount: 44.99, eligibility: .needsReview, confidence: 0.51)
            ]
        ),
        Receipt(
            merchant: "Pearl Dental",
            date: date(year: 2026, month: 4, day: 28),
            source: .bank,
            lineItems: [
                ReceiptLineItem(name: "Dental cleaning balance", amount: 200.00, eligibility: .scheduleADeductible, confidence: 0.88),
                ReceiptLineItem(name: "Orthodontic copay", amount: 400.00, eligibility: .hsaEligible, confidence: 0.94)
            ]
        ),
        Receipt(
            merchant: "LensCrafters",
            date: date(year: 2026, month: 3, day: 11),
            source: .camera,
            lineItems: [
                ReceiptLineItem(name: "Prescription lenses", amount: 315.41, eligibility: .fsaEligible, confidence: 0.97)
            ]
        )
    ]

    static let claimSummary = ClaimSummary(receipts: receipts)

    static let claimPackets: [ClaimPacket] = [
        ClaimPacket(
            administratorName: "HealthEquity",
            lineItems: receipts[0].lineItems.filter(\.isReimbursable) + [receipts[2].lineItems[0]],
            submissionMode: .guidedPacket,
            status: .ready
        ),
        ClaimPacket(
            administratorName: "Inspira",
            lineItems: receipts[1].lineItems.filter(\.isReimbursable),
            submissionMode: .inAppSubmission,
            status: .submittedInApp
        )
    ]

    static let taxExport = TaxExport(year: 2026, receipts: receipts)

    static func date(year: Int, month: Int, day: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), year: year, month: month, day: day).date!
    }
}

extension Double {
    var currency: String {
        Self.currencyFormatter.string(from: NSNumber(value: self)) ?? "$\(String(format: "%.2f", self))"
    }

    func roundedToCents() -> Double {
        (self * 100).rounded() / 100
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()
}
