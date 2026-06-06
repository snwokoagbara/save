import Foundation
import UIKit

struct TaxExportDocument: Hashable {
    let csvFilename: String
    let pdfFilename: String
    let title: String
    let csvText: String
    let reportText: String
    let total: Double
}

struct TaxExportDocumentBuilder {
    func build(from export: TaxExport) -> TaxExportDocument {
        let title = "\(export.year) Schedule A medical expense report"
        let rowLines = export.rows.map { row in
            "\(row.merchant) - \(row.itemName) - \(row.amount.currency) - \(row.eligibility.rawValue)"
        }

        let reportText = ([
            title,
            "Total medical expenses: \(export.totalMedicalExpenses.currency)",
            "Itemized rows: \(export.rows.count)",
            "",
            "Medical expense backup:"
        ] + rowLines).joined(separator: "\n")

        return TaxExportDocument(
            csvFilename: "save-medical-expenses-\(export.year).csv",
            pdfFilename: "save-medical-expenses-\(export.year).pdf",
            title: title,
            csvText: export.csvPreview,
            reportText: reportText,
            total: export.totalMedicalExpenses
        )
    }
}

struct TaxExportPDFRenderer {
    func render(_ document: TaxExportDocument) -> Data {
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

            document.reportText.draw(
                in: CGRect(x: 48, y: 100, width: 516, height: 620),
                withAttributes: bodyAttributes
            )
        }
    }
}
