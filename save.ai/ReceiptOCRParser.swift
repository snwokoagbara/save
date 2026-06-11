import Foundation

struct ReceiptDraftLineItem: Codable, Hashable {
    let name: String
    let amount: Double
    let confidence: Double
}

struct ReceiptDraft: Codable, Hashable {
    let merchant: String
    let purchasedAt: Date
    let totalAmount: Double
    let rawText: String
    let lineItems: [ReceiptDraftLineItem]
}

enum ReceiptOCRParserError: Error, Equatable {
    case missingMerchant
    case missingDate
    case missingTotal
    case missingLineItems
}

struct ReceiptOCRParser {
    func parse(_ rawText: String) throws -> ReceiptDraft {
        let lines = rawText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let merchant = lines.first else {
            throw ReceiptOCRParserError.missingMerchant
        }

        guard let dateLine = lines.first(where: { Self.date(from: $0) != nil }),
              let purchasedAt = Self.date(from: dateLine) else {
            throw ReceiptOCRParserError.missingDate
        }

        guard let totalLine = lines.last(where: { $0.lowercased().hasPrefix("total") }),
              let totalAmount = amount(in: totalLine) else {
            throw ReceiptOCRParserError.missingTotal
        }

        let lineItems = lines.compactMap { line -> ReceiptDraftLineItem? in
            guard line != merchant,
                  line != dateLine,
                  !Self.isSummaryLine(line),
                  let amount = amount(in: line) else {
                return nil
            }

            let name = name(in: line, amount: amount)

            guard !name.isEmpty else {
                return nil
            }

            return ReceiptDraftLineItem(
                name: name,
                amount: amount,
                confidence: 0.78
            )
        }

        guard !lineItems.isEmpty else {
            throw ReceiptOCRParserError.missingLineItems
        }

        return ReceiptDraft(
            merchant: merchant,
            purchasedAt: purchasedAt,
            totalAmount: totalAmount.roundedToCents(),
            rawText: rawText,
            lineItems: lineItems
        )
    }

    private func amount(in line: String) -> Double? {
        let pattern = #"\d+\.\d{2}"#
        guard let range = line.range(of: pattern, options: .regularExpression) else {
            return nil
        }

        return Double(line[range])
    }

    private func name(in line: String, amount: Double) -> String {
        line
            .replacingOccurrences(of: String(format: "%.2f", amount), with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSummaryLine(_ line: String) -> Bool {
        let lowercasedLine = line.lowercased()
        return ["total", "subtotal", "tax", "balance"].contains { lowercasedLine.hasPrefix($0) }
    }

    private static func date(from line: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: line) {
                return date
            }
        }

        return nil
    }

    private static let dateFormatters: [DateFormatter] = [
        makeDateFormatter("yyyy-MM-dd"),
        makeDateFormatter("MM/dd/yyyy"),
        makeDateFormatter("M/d/yyyy")
    ]

    private static func makeDateFormatter(_ dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat
        return formatter
    }
}

enum ReceiptOCRFixtures {
    static let sampleCVS = """
    CVS Pharmacy
    2026-05-22
    Bandages 8.99
    Saline Solution 23.48
    Total 32.47
    """
}
