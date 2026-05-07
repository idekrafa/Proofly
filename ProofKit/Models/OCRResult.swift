import Foundation
import CoreGraphics

struct OCRResult: Identifiable, Equatable {
    let id: UUID
    let recognizedText: String
    let confidence: Double?
    let textBlocks: [OCRTextBlock]
    let recognizedAt: Date
    let sourceFilename: String?

    init(
        id: UUID = UUID(),
        recognizedText: String,
        confidence: Double? = nil,
        textBlocks: [OCRTextBlock] = [],
        recognizedAt: Date = .now,
        sourceFilename: String? = nil
    ) {
        self.id = id
        self.recognizedText = recognizedText
        self.confidence = confidence
        self.textBlocks = textBlocks
        self.recognizedAt = recognizedAt
        self.sourceFilename = sourceFilename
    }
}

struct OCRTextBlock: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let confidence: Double?
    let boundingBox: OCRBoundingBox

    init(
        id: UUID = UUID(),
        text: String,
        confidence: Double? = nil,
        boundingBox: OCRBoundingBox
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

struct OCRBoundingBox: Equatable, Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }
}
