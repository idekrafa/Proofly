import Foundation

protocol OCRServicing {
    func recognizeText(
        inImageAt localImageURL: URL,
        recognitionMode: OCRRecognitionMode
    ) async throws -> OCRResult
}

extension OCRServicing {
    func recognizeText(inImageAt localImageURL: URL) async throws -> OCRResult {
        try await recognizeText(
            inImageAt: localImageURL,
            recognitionMode: .accurate
        )
    }

    func recognizeText(
        in localFile: LocalEvidenceFile,
        recognitionMode: OCRRecognitionMode = .accurate
    ) async throws -> OCRResult {
        try await recognizeText(
            inImageAt: localFile.url,
            recognitionMode: recognitionMode
        )
    }
}

enum OCRRecognitionMode: String, CaseIterable, Identifiable {
    case accurate
    case fast

    var id: String { rawValue }
}
