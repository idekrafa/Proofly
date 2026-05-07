import SwiftData
import SwiftUI

struct CaseDetailView: View {
    @Environment(\.proofKitServices) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var caseFile: CaseFile
    @State private var selectedSection: CaseDetailSection = .timeline
    @State private var sectionTransitionDirection: CaseDetailSectionTransitionDirection = .forward
    @State private var activeAddProofSheet: AddProofSheet?
    @State private var paywallNotice: PaywallAccessDecision?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Picker("Case section", selection: animatedSectionBinding) {
                    ForEach(CaseDetailSection.allCases) { section in
                        Text(section.title)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)

                selectedContent
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, selectedSection == .timeline ? 112 : 48)
        }
        .background(ProofKitVisual.screenBackground.ignoresSafeArea())
        .tint(ProofKitVisual.accent)
        .navigationTitle("Case")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeAddProofSheet) { sheet in
            switch sheet {
            case .importOptions:
                AddProofImportView(
                    caseFile: caseFile,
                    onManualEntryRequested: {
                        withAnimation(ProofKitMotion.standard) {
                            activeAddProofSheet = .manualEntry
                        }
                    },
                    onImportComplete: { _ in
                        animateSectionChange(to: .inbox)
                        dismissAddProofSheet()
                    }
                )
            case .manualEntry:
                ManualEvidenceEntryView(caseFile: caseFile) { _ in
                    animateSectionChange(to: .inbox)
                }
            }
        }
        .alert(item: $paywallNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var animatedSectionBinding: Binding<CaseDetailSection> {
        Binding(
            get: { selectedSection },
            set: { newValue in
                animateSectionChange(to: newValue)
            }
        )
    }

    private var sectionContentTransition: AnyTransition {
        reduceMotion ? .opacity : ProofKitMotion.horizontalCardTransition(forward: sectionTransitionDirection == .forward)
    }

    private enum AddProofSheet: Identifiable {
        case importOptions
        case manualEntry

        var id: String {
            switch self {
            case .importOptions:
                "importOptions"
            case .manualEntry:
                "manualEntry"
            }
        }
    }

    @MainActor
    private func showAddProofOptions() async {
        let decision = await services.paywall.canAddEvidence(to: caseFile, adding: 1)
        guard decision.isAllowed else {
            paywallNotice = decision
            return
        }

        activeAddProofSheet = .importOptions
    }

    private func animateSectionChange(to newSection: CaseDetailSection) {
        guard newSection != selectedSection else { return }

        let updateSection = {
            sectionTransitionDirection = CaseDetailSectionTransitionDirection(from: selectedSection, to: newSection)
            selectedSection = newSection
        }

        if reduceMotion {
            updateSection()
        } else {
            withAnimation(ProofKitMotion.horizontalCardSlide) {
                updateSection()
            }
        }
    }

    private func dismissAddProofSheet() {
        if reduceMotion {
            activeAddProofSheet = nil
        } else {
            withAnimation(ProofKitMotion.standard) {
                activeAddProofSheet = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(caseFile.caseDetailDisplayTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    metadataPills
                }

                Spacer(minLength: 12)

                Button {
                    Task { await showAddProofOptions() }
                } label: {
                    Label("Add Evidence", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if !caseFile.caseDetailSummaryText.isEmpty {
                Text(caseFile.caseDetailSummaryText)
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CaseWorkspaceProgressSummary(
                progress: caseFile.caseDetailWorkspaceProgress,
                currentStep: selectedSection.title,
                missingItems: caseFile.caseDetailMissingItems
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ProofKitVisual.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
        .proofKitAppear()
    }

    private var metadataPills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                MetadataPill(text: caseFile.caseType.displayName)
                MetadataPill(text: caseFile.status.displayName)
                MetadataPill(text: caseFile.evidenceItems.count.evidenceItemCountText)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    MetadataPill(text: caseFile.caseType.displayName)
                    MetadataPill(text: caseFile.status.displayName)
                }

                MetadataPill(text: caseFile.evidenceItems.count.evidenceItemCountText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var selectedContent: some View {
        Group {
            switch selectedSection {
            case .timeline:
                TimelineView(caseFile: caseFile)
            case .inbox:
                EvidenceInboxView(caseFile: caseFile)
            case .export:
                ExportPreviewView(caseFile: caseFile)
            case .settings:
                CaseSettingsView(caseFile: caseFile)
            }
        }
        .id(selectedSection)
        .transition(sectionContentTransition)
        .clipped()
    }
}

private enum CaseDetailSection: String, CaseIterable, Identifiable {
    case timeline
    case inbox
    case export
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline:
            "Timeline"
        case .inbox:
            "Inbox"
        case .export:
            "Export"
        case .settings:
            "Settings"
        }
    }

    var orderIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

private enum CaseDetailSectionTransitionDirection {
    case forward
    case backward

    init(from oldSection: CaseDetailSection, to newSection: CaseDetailSection) {
        self = newSection.orderIndex > oldSection.orderIndex ? .forward : .backward
    }
}

private struct MetadataPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(ProofKitVisual.helperText)
            .lineLimit(1)
            .minimumScaleFactor(0.94)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(ProofKitVisual.quietFill)
            }
    }
}

private struct CaseWorkspaceProgressSummary: View {
    let progress: Double
    let currentStep: String
    let missingItems: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(percentage)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Current step: \(currentStep)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ProofKitVisual.helperText)

                Spacer(minLength: 8)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(ProofKitVisual.quietFill)

                    Capsule(style: .continuous)
                        .fill(ProofKitVisual.accentGradient)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)

            if !missingItems.isEmpty {
                Text("Missing: \(missingItems.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Case progress")
        .accessibilityValue("\(percentage) percent complete. Current step: \(currentStep). \(missingAccessibilityText)")
    }

    private var percentage: Int {
        Int((min(max(progress, 0), 1) * 100).rounded())
    }

    private var missingAccessibilityText: String {
        missingItems.isEmpty ? "No missing evidence items." : "Missing \(missingItems.joined(separator: ", "))."
    }
}

private extension CaseFile {
    var caseDetailDisplayTitle: String {
        let trimmedTitle = userTitle.caseDetailTrimmedText
        return trimmedTitle.isEmpty ? "Untitled Case" : trimmedTitle
    }

    var caseDetailSummaryText: String {
        userSummary.caseDetailTrimmedText
    }

    var caseDetailWorkspaceProgress: Double {
        if status == .exported {
            return 1
        }

        let evidenceCount = evidenceItems.count
        let datedRatio = evidenceCount == 0 ? 0 : Double(evidenceItems.filter { $0.eventDate != nil }.count) / Double(evidenceCount)
        var score = 0.0

        if !userTitle.caseDetailTrimmedText.isEmpty {
            score += 0.12
        }

        if caseType != .general {
            score += 0.06
        }

        score += min(Double(evidenceCount), 4) / 4 * 0.34
        score += datedRatio * 0.20

        if !userSummary.caseDetailTrimmedText.isEmpty || !userNotes.caseDetailTrimmedText.isEmpty {
            score += 0.08
        }

        if status == .active {
            score += 0.05
        }

        if status == .readyForExport {
            score = max(score, 0.90)
        }

        score -= min(Double(caseDetailMissingItems.count) * 0.025, 0.10)

        let cappedScore: Double
        switch status {
        case .draft:
            cappedScore = min(score, 0.82)
        case .active:
            cappedScore = min(score, 0.96)
        case .readyForExport:
            cappedScore = min(score, 0.98)
        case .exported:
            cappedScore = 1
        case .archived:
            cappedScore = min(score, 0.90)
        }

        let clampedScore = min(max(cappedScore, 0), 1)
        return (clampedScore * 20).rounded() / 20
    }

    var caseDetailMissingItems: [String] {
        if status == .exported || status == .readyForExport {
            return []
        }

        if evidenceItems.isEmpty {
            return ["evidence items"]
        }

        var missingItems: [String] = []

        if caseType.caseDetailNeedsLandlordResponse, !caseDetailHasLandlordResponse {
            missingItems.append("landlord response")
        }

        if caseType.caseDetailNeedsRepairPhoto, !caseDetailHasRepairPhoto {
            missingItems.append("repair photo")
        }

        if evidenceItems.contains(where: { $0.eventDate == nil }) {
            missingItems.append("timeline dates")
        }

        if userTitle.caseDetailTrimmedText.isEmpty {
            missingItems.append("case title")
        }

        return Array(missingItems.prefix(3))
    }

    private var caseDetailHasLandlordResponse: Bool {
        evidenceItems.contains { evidenceItem in
            let text = evidenceItem.caseDetailSearchText
            let mentionsLandlord = text.contains("landlord") || text.contains("property manager") || text.contains("building manager")
            let suggestsResponse = text.contains("response") || text.contains("responded") || text.contains("replied") || text.contains("reply") || text.contains("from landlord") || text.contains("from property manager")
            return mentionsLandlord && suggestsResponse
        }
    }

    private var caseDetailHasRepairPhoto: Bool {
        evidenceItems.contains { evidenceItem in
            let hasPhotoAttachment = evidenceItem.category == .photo || evidenceItem.attachments.contains { attachment in
                attachment.attachmentType == .photo || attachment.attachmentType == .screenshot
            }
            let text = evidenceItem.caseDetailSearchText
            return hasPhotoAttachment && (text.contains("repair") || text.contains("fixed") || text.contains("after"))
        }
    }
}

private extension EvidenceItem {
    var caseDetailSearchText: String {
        [userTitle, userNotes, userCleanedNote, userWhyThisMatters, originalOCRText]
            .joined(separator: " ")
            .lowercased()
    }
}

private extension CaseType {
    var caseDetailNeedsLandlordResponse: Bool {
        switch self {
        case .apartmentIssue, .tenantLandlord:
            true
        default:
            false
        }
    }

    var caseDetailNeedsRepairPhoto: Bool {
        switch self {
        case .apartmentIssue, .tenantLandlord, .insuranceIssue, .insurance:
            true
        default:
            false
        }
    }
}

private extension String {
    var caseDetailTrimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    NavigationStack {
        CaseDetailView(
            caseFile: CaseFile.caseDetailTimelinePreviewCase
        )
    }
    .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self, AIResultCache.self], inMemory: true)
}

private extension CaseFile {
    static var caseDetailTimelinePreviewCase: CaseFile {
        let calendar = Calendar(identifier: .gregorian)
        let dayOne = calendar.date(from: DateComponents(year: 2026, month: 4, day: 21, hour: 8, minute: 30)) ?? .now
        let dayTwo = calendar.date(from: DateComponents(year: 2026, month: 4, day: 22, hour: 9, minute: 15)) ?? .now
        let dayThree = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 14, minute: 10)) ?? .now
        let dayFour = calendar.date(from: DateComponents(year: 2026, month: 4, day: 26, hour: 18, minute: 0)) ?? .now
        let caseFile = CaseFile(
            caseType: .apartmentIssue,
            status: .active,
            userTitle: "Ceiling Leaking Main Bedroom",
            userSummary: "Water damage evidence for the main bedroom ceiling.",
            userNotes: "Track photos, requests, dates, and repair documentation for the case.",
            createdAt: dayOne.addingTimeInterval(-86400),
            updatedAt: dayFour
        )

        caseFile.evidenceItems = [
            EvidenceItem(
                category: .note,
                userDateSource: .userEntered,
                userTitle: "Leak first noticed",
                userNotes: "Water spots appeared near the main bedroom ceiling light.",
                userProvidedEventDate: dayOne,
                createdAt: dayOne,
                caseFile: caseFile
            ),
            EvidenceItem(
                category: .photo,
                userDateSource: .userEntered,
                userTitle: "Ceiling damage photo",
                userNotes: "Photo showing the brown ceiling stain and bubbling paint.",
                userProvidedEventDate: dayTwo,
                userMarkedImportant: true,
                createdAt: dayTwo,
                caseFile: caseFile
            ),
            EvidenceItem(
                category: .message,
                userDateSource: .userEntered,
                userTitle: "Message to landlord",
                userNotes: "Sent the first written notice asking for inspection and repair timing.",
                userProvidedEventDate: dayThree,
                createdAt: dayThree,
                caseFile: caseFile
            ),
            EvidenceItem(
                category: .note,
                userDateSource: .userEntered,
                userTitle: "Repair follow-up note",
                userNotes: "Noted that the ceiling was still damp after the scheduled maintenance window.",
                userProvidedEventDate: dayFour,
                createdAt: dayFour,
                caseFile: caseFile
            )
        ]

        return caseFile
    }
}
