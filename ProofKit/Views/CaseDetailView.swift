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
    @State private var skippedReadinessEvidenceIDs: Set<UUID> = []
    @State private var subscriptionTier = "unknown"
    @State private var hasLoadedAnalyticsContext = false
    @State private var lastTrackedReadinessSignature: String?

    private var readiness: CaseReadinessResult {
        CaseReadinessCalculator.calculate(
            for: caseFile,
            skippedEvidenceIDs: skippedReadinessEvidenceIDs
        )
    }

    private var readinessAnalyticsSignature: String {
        "\(readiness.analyticsSignature)|\(subscriptionTier)"
    }

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
        .task {
            await loadReadinessAnalyticsContext()
        }
        .onChange(of: readinessAnalyticsSignature) { _, _ in
            trackReadinessIfReady()
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
            titleActionLayout

            if !caseFile.caseDetailSummaryText.isEmpty {
                Text(caseFile.caseDetailSummaryText)
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

    private var titleActionLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                titleAndMetadata
                    .layoutPriority(1)

                Spacer(minLength: 14)

                addProofButton
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 12) {
                titleAndMetadata
                addProofButton
            }
        }
    }

    private var titleAndMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caseFile.caseDetailDisplayTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.92)
                .fixedSize(horizontal: false, vertical: true)

            metadataPills
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            case .settings:
                CaseSettingsView(caseFile: caseFile)
            }
        }
        .id(selectedSection)
        .transition(sectionContentTransition)
        .clipped()
    }

    @MainActor
    private func loadReadinessAnalyticsContext() async {
        guard !hasLoadedAnalyticsContext else { return }
        let entitlement = await services.paywall.currentEntitlement()
        subscriptionTier = entitlement.plan.rawValue
        hasLoadedAnalyticsContext = true
        trackReadinessIfReady()
    }

    @MainActor
    private func trackReadinessIfReady() {
        guard hasLoadedAnalyticsContext else { return }

        let signature = readinessAnalyticsSignature
        guard signature != lastTrackedReadinessSignature else { return }
        lastTrackedReadinessSignature = signature

        services.analytics.trackCaseReadinessCalculated(
            readiness.analyticsPayload(
                caseIDHash: AnalyticsHashing.sha256(caseFile.id.uuidString),
                userIDHash: services.analytics.currentUserIDHash,
                subscriptionTier: subscriptionTier,
                createdAtAgeDays: caseFile.createdAt.caseReadinessAgeInDays
            )
        )
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
        if caseReadinessCategory.isSchool {
            return "Deadlines, emails, essays, documents, and confirmations — organized into one timeline."
        }

        return userSummary.caseDetailTrimmedText
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
