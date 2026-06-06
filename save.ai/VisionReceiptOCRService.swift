import UIKit
import Vision

enum VisionReceiptOCRError: LocalizedError {
    case imageDataUnavailable
    case noRecognizedText

    var errorDescription: String? {
        switch self {
        case .imageDataUnavailable:
            return "Kai couldn't read that image. Try a clearer receipt photo."
        case .noRecognizedText:
            return "Kai didn't find receipt text in that image."
        }
    }
}

struct VisionReceiptOCRService {
    private let parser = ReceiptOCRParser()

    func draft(from image: UIImage) async throws -> ReceiptDraft {
        guard let cgImage = image.cgImage else {
            throw VisionReceiptOCRError.imageDataUnavailable
        }

        let recognizedText = try await recognizeText(in: cgImage)
        guard !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VisionReceiptOCRError.noRecognizedText
        }

        return try parser.parse(recognizedText)
    }

    private func recognizeText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                continuation.resume(returning: lines.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
