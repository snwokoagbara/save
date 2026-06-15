import Foundation
import UIKit

struct ClaimAdministratorTemplate: Hashable {
    let administratorName: String
    let version: String
    let supportedSubmissionMode: SubmissionMode
    let requiredFields: [String]
    let evidenceRequirements: [String]
    let submissionChecklist: [String]
    let instructions: [String]
}

enum ClaimAdministratorTemplateLibrary {
    static func template(for administratorName: String) -> ClaimAdministratorTemplate {
        let trimmedName = administratorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? "Administrator" : trimmedName
        let normalizedName = displayName.lowercased()

        if normalizedName.contains("healthequity") {
            return ClaimAdministratorTemplate(
                administratorName: "HealthEquity",
                version: "2026.1",
                supportedSubmissionMode: .guidedPacket,
                requiredFields: ["Account holder name", "Date of service", "Provider or merchant", "Claim amount"],
                evidenceRequirements: [
                    "Itemized receipt showing merchant, purchase date, eligible item, and amount",
                    "Proof of payment when the receipt does not show a paid card transaction"
                ],
                submissionChecklist: [
                    "Review the required claim fields before opening the administrator portal.",
                    "Attach the generated SAVE claim packet PDF in HealthEquity.",
                    "Return to SAVE and mark the packet submitted after upload."
                ],
                instructions: ["Submit through the HealthEquity member portal after reviewing the attached itemized evidence."]
            )
        }

        if normalizedName.contains("inspira") {
            return ClaimAdministratorTemplate(
                administratorName: "Inspira",
                version: "2026.1",
                supportedSubmissionMode: .inAppSubmission,
                requiredFields: ["Participant name", "Service date", "Expense type", "Claim amount"],
                evidenceRequirements: [
                    "Itemized receipt with merchant, date, item description, and amount",
                    "Card transaction match or paid invoice"
                ],
                submissionChecklist: [
                    "Review the required claim fields before starting the Inspira claim flow.",
                    "Submit directly through Inspira when in-app submission is available.",
                    "Return to SAVE and mark the packet submitted after confirmation."
                ],
                instructions: ["Use the Inspira claim flow when available; keep the guided packet as the fallback attachment."]
            )
        }

        if normalizedName.contains("wex") {
            return ClaimAdministratorTemplate(
                administratorName: "WEX",
                version: "2026.1",
                supportedSubmissionMode: .guidedPacket,
                requiredFields: ["Employee name", "Service date", "Provider or store", "Claim amount"],
                evidenceRequirements: [
                    "Itemized receipt or explanation of benefits",
                    "Proof the user paid the expense"
                ],
                submissionChecklist: [
                    "Review the required claim fields before opening WEX.",
                    "Attach the generated SAVE claim packet PDF in the WEX benefits portal.",
                    "Return to SAVE and mark the packet submitted after upload."
                ],
                instructions: ["Attach this packet in the WEX benefits portal and mark the claim submitted once uploaded."]
            )
        }

        return ClaimAdministratorTemplate(
            administratorName: displayName,
            version: "generic-2026.1",
            supportedSubmissionMode: .guidedPacket,
            requiredFields: ["Account holder name", "Date of service", "Provider or merchant", "Claim amount"],
            evidenceRequirements: ["Itemized receipt showing merchant, purchase date, eligible item, and amount"],
            submissionChecklist: [
                "Review the required claim fields before opening the administrator portal.",
                "Attach the generated SAVE claim packet PDF in the administrator portal.",
                "Return to SAVE and mark the packet submitted after upload."
            ],
            instructions: ["Submit this packet in the administrator portal, then return to SAVE so Kai can track the status."]
        )
    }
}

struct ClaimPacketDocument: Hashable {
    let filename: String
    let title: String
    let text: String
    let total: Double
    let lineItems: [ReceiptLineItem]
    let template: ClaimAdministratorTemplate
}

struct ClaimPacketDocumentBuilder {
    func build(from packet: ClaimPacket) -> ClaimPacketDocument {
        let template = ClaimAdministratorTemplateLibrary.template(for: packet.administratorName)
        let title = "\(packet.administratorName) claim packet"
        let itemLines = packet.lineItems.map { item in
            "\(item.name) - \(item.amount.currency) - \(item.eligibility.rawValue)"
        }

        let text = ([
            title,
            "Template: \(template.administratorName) \(template.version)",
            "Submission mode: \(packet.submissionMode.rawValue)",
            "Status: \(packet.status.rawValue)",
            "Total claim amount: \(packet.total.currency)",
            "",
            "Required fields:"
        ] + Self.bulletLines(template.requiredFields) + [
            "",
            "Evidence requirements:"
        ] + Self.bulletLines(template.evidenceRequirements) + [
            "",
            "Submission checklist:"
        ] + Self.bulletLines(template.submissionChecklist) + [
            "",
            "Administrator instructions:"
        ] + Self.bulletLines(template.instructions) + [
            "",
            "Line items:"
        ] + itemLines).joined(separator: "\n")

        return ClaimPacketDocument(
            filename: "save-claim-\(Self.slug(packet.administratorName)).pdf",
            title: title,
            text: text,
            total: packet.total,
            lineItems: packet.lineItems,
            template: template
        )
    }

    private static func bulletLines(_ values: [String]) -> [String] {
        values.map { "- \($0)" }
    }

    private static func slug(_ value: String) -> String {
        let separatedWords = value.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1-$2",
            options: .regularExpression
        )
        let scalars = separatedWords.lowercased().unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "administrator" : collapsed
    }
}

struct ClaimPacketPDFRenderer {
    func render(_ document: ClaimPacketDocument) -> Data {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        return renderer.pdfData { context in
            context.beginPage()

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.label
            ]
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.label
            ]

            document.title.draw(
                in: CGRect(x: 48, y: 48, width: 516, height: 34),
                withAttributes: titleAttributes
            )

            document.text.draw(
                in: CGRect(x: 48, y: 100, width: 516, height: 620),
                withAttributes: bodyAttributes
            )
        }
    }
}
