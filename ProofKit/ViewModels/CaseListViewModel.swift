import Combine
import SwiftData
import SwiftUI

@MainActor
final class CaseListViewModel: ObservableObject {
    func createCase(
        in modelContext: ModelContext,
        title: String,
        caseType: CaseType
    ) -> CaseFile {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let caseFile = CaseFile(
            caseType: caseType,
            status: .draft,
            userTitle: trimmedTitle.isEmpty ? nextCaseTitle() : trimmedTitle
        )
        modelContext.insert(caseFile)
        return caseFile
    }

    private func nextCaseTitle() -> String {
        "Untitled Case"
    }
}
