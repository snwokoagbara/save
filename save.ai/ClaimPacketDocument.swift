import Foundation
import UIKit

struct ClaimPacketDocument: Hashable {
    let filename: String
    let title: String
    let text: String
    let total: Double
    let lineItems: [ReceiptLineItem]
}

struct ClaimPacketDocumentBuilder {
    func build(from packet: ClaimPacket) -> ClaimPacketDocument {
        let title = "\(packet.administratorName) claim packet"
        let itemLines = packet.lineItems.map { item in
            "\(item.name) - \(item.amount.currency) - \(item.eligibility.rawValue)"
        }

        let text = ([
            title,
            "Submission mode: \(packet.submissionMode.rawValue)",
            "Status: \(packet.status.rawValue)",
            "Total claim amount: \(packet.total.currency)",
            "",
            "Line items:"
        ] + itemLines).joined(separator: "\n")

        return ClaimPacketDocument(
            filename: "save-claim-\(Self.slug(packet.administratorName)).pdf",
            title: title,
            text: text,
            total: packet.total,
            lineItems: packet.lineItems
        )
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
