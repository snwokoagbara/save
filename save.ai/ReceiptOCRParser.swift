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

        guard let dateLine = lines.first(where: { Self.dateFormatter.date(from: $0) != nil }),
              let purchasedAt = Self.dateFormatter.date(from: dateLine) else {
            throw ReceiptOCRParserError.missingDate
        }

        guard let totalLine = lines.last(where: { $0.lowercased().hasPrefix("total") }),
              let totalAmount = amount(in: totalLine) else {
            throw ReceiptOCRParserError.missingTotal
        }

        let lineItems = lines.compactMap { line -> ReceiptDraftLineItem? in
            guard line != merchant,
                  line != dateLine,
                  !line.lowercased().hasPrefix("total"),
                  let amount = amount(in: line) else {
                return nil
            }

            let name = line
                .replacingOccurrences(of: String(format: "%.2f", amount), with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
