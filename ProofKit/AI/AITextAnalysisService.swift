import Foundation

struct AITextAnalysisInput {
    let caseID: UUID
    let extractedTextSnippets: [String]
    let metadata: [String: String]
    let userTriggered: Bool
}

struct AITextAnalysisDraft {
    let suggestedCaseSummary: String
    let suggestedTimelineEntries: [String]
}

protocol AITextAnalysisServicing {
    func draftTimelineSuggestions(from input: AITextAnalysisInput) async throws -> AITextAnalysisDraft
}

struct TextOnlyAIPlaceholderService: AITextAnalysisServicing {
    func draftTimelineSuggestions(from input: AITextAnalysisInput) async throws -> AITextAnalysisDraft {
        guard input.userTriggered else {
            throw ProofKitError.localOnlyViolation("AI analysis must be explicitly triggered by the user.")
        }

        // Future implementation: send extracted text and metadata only.
        // This service intentionally has no API for raw image, PDF, or photo bytes.
        throw ProofKitError.notImplemented("Text-only AI analysis")
    }
}
