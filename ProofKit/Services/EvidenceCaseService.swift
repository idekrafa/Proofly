import Foundation

struct EvidenceCasePreview {
    let caseID: UUID
    let generatedAt: Date
    let evidenceItemCount: Int
    let exportCaseCount: Int
}

@MainActor
protocol EvidenceCaseServicing {
    func buildCasePreview(for caseFile: CaseFile) async throws -> EvidenceCasePreview
}

struct EvidenceCaseService: EvidenceCaseServicing {
    func buildCasePreview(for caseFile: CaseFile) async throws -> EvidenceCasePreview {
        EvidenceCasePreview(
            caseID: caseFile.id,
            generatedAt: .now,
            evidenceItemCount: caseFile.evidenceItems.count,
            exportCaseCount: caseFile.exportPackets.count
        )
    }
}
