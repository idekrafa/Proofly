import SwiftData
import SwiftUI
import UIKit

struct CaseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.proofKitServices) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var caseFile: CaseFile
    @State private var selectedSection: CaseDetailSection = .timeline
    @State private var sectionTransitionDirection: CaseDetailSectionTransitionDirection = .forward
    @State private var sectionTransitionUsesHorizontalMotion = true
    @State private var activeAddProofSheet: AddProofSheet?
    @State private var paywallNotice: PaywallAccessDecision?
    @State private var skippedReadinessEvidenceIDs: Set<UUID> = []
    @State private var hasTrackedInitialOpen = false
    @State private var lastTrackedReadinessSignature: String?
    @State private var isDeleteCaseConfirmationPresented = false
    @State private var caseDeletionNotice: CaseDetailDeletionNotice?

    private var readiness: CaseReadinessResult {
        CaseReadinessCalculator.calculate(
            for: caseFile,
            skippedEvidenceIDs: skippedReadinessEvidenceIDs
        )
    }

    private var readinessAnalyticsSignature: String {
        readiness.analyticsSignature
    }

    var body: some View {
        ScrollView(.vertical) {
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
            .padding(.bottom, bottomContentPadding)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
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
        .alert(item: $caseDeletionNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            "Delete this case?",
            isPresented: $isDeleteCaseConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete case", role: .destructive) {
                deleteCurrentCase()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteCaseConfirmationMessage)
        }
        .task {
            trackInitialOpenAndReadiness()
        }
        .onChange(of: readinessAnalyticsSignature) { _, _ in
            trackReadinessIfNeeded()
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
        if reduceMotion || !sectionTransitionUsesHorizontalMotion {
            return .opacity
        }

        return ProofKitMotion.horizontalCardTransition(forward: sectionTransitionDirection == .forward)
    }

    private var bottomContentPadding: CGFloat {
        switch selectedSection {
        case .timeline:
            112
        case .manage:
            140
        case .inbox, .export:
            96
        }
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
            sectionTransitionUsesHorizontalMotion = selectedSection != .manage && newSection != .manage
            selectedSection = newSection
            trackSectionOpened(newSection)
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
            headerHeroLayout

            CaseWorkspaceProgressSummary(
                readiness: readiness
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
        .shadow(color: ProofKitVisual.elevatedShadow.opacity(0.85), radius: 18, x: 0, y: 10)
        .proofKitAppear()
    }

    private var headerHeroLayout: some View {
        ViewThatFits(in: .horizontal) {
            regularHeaderHeroLayout
            compactHeaderHeroLayout
        }
    }

    private var regularHeaderHeroLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            headerTextStack
                .frame(minWidth: 188, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            headerArtworkActionStack(size: 116)
        }
    }

    private var compactHeaderHeroLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                titleAndMetadata
                    .layoutPriority(1)

                Spacer(minLength: 8)

                headerRookArtwork(size: 88)
                    .padding(.top, -4)
            }

            summaryText

            addProofButton
        }
    }

    private var headerTextStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleAndMetadata
            summaryText
        }
    }

    private func headerArtworkActionStack(size: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 10) {
            headerRookArtwork(size: size)

            addProofButton
        }
        .frame(width: size + 10, alignment: .trailing)
    }

    private func headerRookArtwork(size: CGFloat) -> some View {
        CaseDetailHeaderRookArtwork(
            assetName: caseFile.caseDetailRookArtworkAssetName,
            size: size
        )
    }

    private var titleAndMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caseFile.caseDetailDisplayTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.92)
                .fixedSize(horizontal: false, vertical: true)

            metadataPills
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var summaryText: some View {
        if !caseFile.caseDetailSummaryText.isEmpty {
            Text(caseFile.caseDetailSummaryText)
                .font(.subheadline)
                .foregroundStyle(ProofKitVisual.helperText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addProofButton: some View {
        Button {
            Task { await showAddProofOptions() }
        } label: {
            Label("Add Proof", systemImage: "plus")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.88)
                .allowsTightening(true)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHint("Opens proof import options.")
    }

    private var metadataPills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                MetadataPill(text: readiness.category.displayName)
                MetadataPill(text: caseFile.status.displayName)
                MetadataPill(text: caseFile.evidenceItems.count.evidenceItemCountText)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    MetadataPill(text: readiness.category.displayName)
                    MetadataPill(text: caseFile.status.displayName)
                }

                MetadataPill(text: caseFile.evidenceItems.count.evidenceItemCountText)
            }

            VStack(alignment: .leading, spacing: 6) {
                MetadataPill(text: readiness.category.displayName)
                MetadataPill(text: caseFile.status.displayName)
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
                EvidenceInboxView(
                    caseFile: caseFile,
                    skippedEvidenceIDs: $skippedReadinessEvidenceIDs
                )
            case .export:
                ExportPreviewView(
                    caseFile: caseFile,
                    skippedEvidenceIDs: skippedReadinessEvidenceIDs
                ) {
                    Task { await showAddProofOptions() }
                }
            case .manage:
                CaseSettingsView(
                    caseFile: caseFile,
                    onRequestExportPDF: {
                        animateSectionChange(to: .export)
                    },
                    onRequestDeleteCase: {
                        isDeleteCaseConfirmationPresented = true
                    }
                )
            }
        }
        .id(selectedSection)
        .transition(sectionContentTransition)
        .clipped()
    }

    @MainActor
    private func trackInitialOpenAndReadiness() {
        guard !hasTrackedInitialOpen else { return }
        hasTrackedInitialOpen = true
        services.analytics.trackCaseOpened(caseFile, sourceScreen: .caseDetail)
        trackSectionOpened(selectedSection)
        trackReadinessIfNeeded()
    }

    @MainActor
    private func trackReadinessIfNeeded() {
        let signature = readinessAnalyticsSignature
        guard signature != lastTrackedReadinessSignature else { return }
        lastTrackedReadinessSignature = signature
        services.analytics.trackTimelineReadyStateChanged(caseFile: caseFile, readiness: readiness)
    }

    private func trackSectionOpened(_ section: CaseDetailSection) {
        switch section {
        case .timeline:
            services.analytics.trackTimelineOpened(caseFile: caseFile)
        case .inbox:
            break
        case .manage:
            services.analytics.trackCaseManageOpened(caseFile)
        case .export:
            break
        }
    }

    private var deleteCaseConfirmationMessage: String {
        "This removes the case timeline, proof links, notes, and local case data from this device. This can’t be undone."
    }

    private func deleteCurrentCase() {
        do {
            try CaseDeletionService.deleteCase(caseFile, modelContext: modelContext)
            services.analytics.trackCaseDeleted(caseFile)
            dismiss()
        } catch {
            caseDeletionNotice = CaseDetailDeletionNotice(
                title: "Case not deleted",
                message: "This case could not be deleted. Please try again."
            )
        }
    }
}

private enum CaseDetailSection: String, CaseIterable, Identifiable {
    case timeline
    case inbox
    case export
    case manage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline:
            "Timeline"
        case .inbox:
            "Inbox"
        case .export:
            "Export"
        case .manage:
            "Manage"
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

private struct CaseDetailDeletionNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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

private struct CaseDetailHeaderRookArtwork: View {
    let assetName: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            ProofKitVisual.accentSecondary.opacity(0.24),
                            ProofKitVisual.accent.opacity(0.10),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size * 0.08,
                        endRadius: size * 0.66
                    )
                )
                .frame(width: size * 1.18, height: size * 1.18)
                .blur(radius: 6)

            Image(assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.30), radius: 12, x: 0, y: 7)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct CaseWorkspaceProgressSummary: View {
    let readiness: CaseReadinessResult

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(readiness.score)% ready")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("·")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.subduedText)
                    .accessibilityHidden(true)

                Text(readiness.nextStepLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ProofKitVisual.helperText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .allowsTightening(true)

                Spacer(minLength: 8)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(ProofKitVisual.quietFill)

                    Capsule(style: .continuous)
                        .fill(ProofKitVisual.accentGradient)
                        .frame(width: proxy.size.width * min(max(readiness.progress, 0), 1))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)

            if !readiness.blockers.isEmpty {
                Text("Improve: \(readiness.blockers.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Case readiness")
        .accessibilityValue("\(readiness.score) percent ready. \(readiness.nextStepLabel). \(missingAccessibilityText)")
    }

    private var missingAccessibilityText: String {
        readiness.blockers.isEmpty ? "No immediate readiness blockers." : "Improve \(readiness.blockers.joined(separator: ", "))."
    }
}

private extension CaseFile {
    var caseDetailDisplayTitle: String {
        let trimmedTitle = userTitle.caseDetailTrimmedText
        return trimmedTitle.isEmpty ? "Untitled Case" : trimmedTitle
    }

    var caseDetailSummaryText: String {
        let trimmedSummary = userSummary.caseDetailTrimmedText
        if !trimmedSummary.isEmpty {
            return trimmedSummary
        }

        if caseReadinessCategory.isSchool {
            return "Deadlines, emails, essays, documents, and confirmations — organized into one timeline."
        }

        return trimmedSummary
    }

    var caseDetailRookArtworkAssetName: String {
        CaseDetailRookArtwork.assetName(for: caseReadinessCategory.analyticsValue)
    }
}

private enum CaseDetailRookArtwork {
    private static let generalAssetName = "RookPurposeOther"

    static func assetName(for categoryAnalyticsValue: String) -> String {
        let preferredAssetName: String

        switch categoryAnalyticsValue {
        case "apartment":
            preferredAssetName = "RookPurposeRental"
        case "refund":
            preferredAssetName = "RookPurposeRefund"
        case "school":
            preferredAssetName = "RookPurposeCollege"
        case "work":
            preferredAssetName = "RookPurposeWork"
        default:
            preferredAssetName = generalAssetName
        }

        return existingAssetName(preferredAssetName)
    }

    private static func existingAssetName(_ preferredAssetName: String) -> String {
        UIImage(named: preferredAssetName) == nil ? generalAssetName : preferredAssetName
    }
}

private extension String {
    var caseDetailTrimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Date {
    var caseReadinessAgeInDays: Int {
        max(0, Calendar.current.dateComponents([.day], from: self, to: .now).day ?? 0)
    }
}

#Preview {
    NavigationStack {
        CaseDetailView(
            caseFile: CaseFile.caseDetailTimelinePreviewCase
        )
    }
    .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self], inMemory: true)
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
