import Foundation
import Vision

struct OCRService: OCRServicing {
    func recognizeText(
        inImageAt localImageURL: URL,
        recognitionMode: OCRRecognitionMode = .accurate
    ) async throws -> OCRResult {
        guard localImageURL.isFileURL else {
            throw ProofKitError.localOnlyViolation("OCR only accepts local image file URLs.")
        }

        guard FileManager.default.fileExists(atPath: localImageURL.path(percentEncoded: false)) else {
            throw ProofKitError.missingLocalFile(localImageURL)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.performRecognition(
                        inImageAt: localImageURL,
                        recognitionMode: recognitionMode
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func performRecognition(
        inImageAt localImageURL: URL,
        recognitionMode: OCRRecognitionMode
    ) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionMode.visionRecognitionLevel
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(url: localImageURL, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let textBlocks = observations.compactMap { observation -> OCRTextBlock? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            return OCRTextBlock(
                text: candidate.string,
                confidence: Double(candidate.confidence),
                boundingBox: OCRBoundingBox(observation.boundingBox)
            )
        }
        let fullText = textBlocks
            .map(\.text)
            .joined(separator: "\n")
        let confidence = Self.averageConfidence(from: textBlocks)

        return OCRResult(
            recognizedText: fullText,
            confidence: confidence,
            textBlocks: textBlocks,
            sourceFilename: localImageURL.lastPathComponent
        )
    }

    private static func averageConfidence(from textBlocks: [OCRTextBlock]) -> Double? {
        let confidenceValues = textBlocks.compactMap(\.confidence)
        guard !confidenceValues.isEmpty else { return nil }

        let total = confidenceValues.reduce(0, +)
        return total / Double(confidenceValues.count)
    }
}

private extension OCRRecognitionMode {
    var visionRecognitionLevel: VNRequestTextRecognitionLevel {
        switch self {
        case .accurate:
            .accurate
        case .fast:
            .fast
        }
    }
}
