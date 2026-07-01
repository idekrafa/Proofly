import Combine
import SwiftData
import SwiftUI

@MainActor
final class CaseListViewModel: ObservableObject {
    func createCase(
        in modelContext: ModelContext,
        title: String,
        caseType: CaseType,
        summary: String = "",
        notes: String = ""
    ) -> CaseFile {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let caseFile = CaseFile(
            caseType: caseType,
            status: .draft,
            userTitle: trimmedTitle.isEmpty ? nextCaseTitle() : trimmedTitle,
            userSummary: trimmedSummary,
            userNotes: trimmedNotes
        )
        modelContext.insert(caseFile)
        return caseFile
    }

    private func nextCaseTitle() -> String {
        CaseFile.untitledCaseSentinel
    }
}
