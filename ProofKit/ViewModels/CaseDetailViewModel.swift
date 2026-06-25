import Combine
import Foundation

@MainActor
final class CaseDetailViewModel: ObservableObject {
    let privacySummary = String(localized: "AI is text-only and user-triggered. Raw images are not uploaded.")

    func markCaseUpdated(_ caseFile: CaseFile) {
        caseFile.updatedAt = .now
    }
}
