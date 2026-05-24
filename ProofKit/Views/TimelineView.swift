import SwiftData
import SwiftUI
import UIKit

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.proofKitServices) private var services
    let caseFile: CaseFile

    @State private var collapsedGroupIDs: Set<String> = []
    @State private var deletionNotice: TimelineDeletionNotice?
    @State private var aiNotice: TimelineAINotice?
    @State private var selectedEvidenceRoute: TimelineEvidenceRoute?
    @State private var pendingTimelineSummaryQuote: AIUsageQuote?
    @State private var aiTimelineSummaryText: String?
    @State private var timelineSummaryInlineError: String?
    @State private var timelineSummaryWasCacheHit = false
    @State private var isPreparingTimelineSummary = false
    @State private var isRunningTimelineSummary = false
    @State private var isAddingTimelineSummary = false
    @State private var timelineSummaryWasAddedToTimeline = false
    @State private var showingAIPaywall = false

    private var timelineGroups: [TimelineDateGroup] {
        TimelineDateGroup.groups(from: caseFile.evidenceItems)
    }

    private var evidenceItemCount: Int {
        timelineGroups.reduce(0) { $0 + $1.items.count }
    }

    private var allGroupsAreCollapsed: Bool {
        !timelineGroups.isEmpty && collapsedGroupIDs.count >= timelineGroups.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(
                title: "Timeline",
                subtitle: "Proof items grouped by the date they happened."
            )

            if timelineGroups.isEmpty {
                PlaceholderPanel(
                    systemImage: "calendar",
                    title: "Timeline is empty",
                    message: "Add your first proof item when you are ready. Proofly will place dated items into a calm chronological view.",
                    steps: [
                        PlaceholderStep(
                            systemImage: "plus",
                            title: "Add proof",
                            detail: "Use the Add Proof button above to import a file or write a note."
                        ),
                        PlaceholderStep(
                            systemImage: "calendar.badge.clock",
                            title: "Check the date",
                            detail: "Use the event date that best matches what happened."
                        ),
                        PlaceholderStep(
                            systemImage: "list.bullet.rectangle",
                            title: "Review the timeline",
                            detail: "Proof items will group by date so larger cases stay readable."
                        )
                    ],
                    footnote: "There is no need to finish everything at once."
                )
            } else {
                timelineAISummaryPanel
                timelineToolbar

                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(timelineGroups.enumerated()), id: \.element.id) { index, group in
                        TimelineDateGroupSection(
                            group: group,
                            isCollapsed: collapsedGroupIDs.contains(group.id),
                            onToggle: {
                                toggle(group)
                            },
                            onOpen: { evidenceItem in
                                openEvidence(evidenceItem)
                            },
                            onDelete: { evidenceItem in
                                deleteEvidence(evidenceItem)
                            }
                        )
                        .proofKitAppear(delay: min(Double(index) * 0.025, 0.12))
                    }
                }
            }
        }
        .alert(item: $deletionNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: $aiNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showingAIPaywall) {
            PaywallView()
        }
        .confirmationDialog(
            "Use AI credits?",
            isPresented: isTimelineSummaryConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let quote = pendingTimelineSummaryQuote {
                Button("Use \(quote.creditCost) AI credits") {
                    pendingTimelineSummaryQuote = nil
                    Task { await runTimelineSummary(quote: quote) }
                }
            }

            Button("Cancel", role: .cancel) {
                pendingTimelineSummaryQuote = nil
            }
        } message: {
            if let quote = pendingTimelineSummaryQuote {
                Text("\(quote.feature.displayName) uses \(quote.creditCost) credits. You have \(quote.creditsRemainingBefore), and will have \(quote.creditsRemainingAfter) after this run. \(quote.estimatedWaitMessage)")
            }
        }
        .navigationDestination(item: $selectedEvidenceRoute) { route in
            EvidenceDetailEditView(evidenceItem: route.evidenceItem)
        }
        .task {
            loadCachedTimelineSummary()
        }
    }

    private var isTimelineSummaryConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingTimelineSummaryQuote != nil },
            set: { isPresented in
                if !isPresented {
                    pendingTimelineSummaryQuote = nil
                }
            }
        )
    }

    private var timelineAISummaryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.accent)
                    .frame(width: 34, height: 34)
                    .background {
                        Circle()
                            .fill(ProofKitVisual.accent.opacity(0.12))
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Timeline Summary")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("AI can draft a short private overview from the reviewed timeline text. It never changes your original proof, OCR, or notes.")
                        .font(.caption)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            if isPreparingTimelineSummary || isRunningTimelineSummary {
                TimelineSummaryLoadingCard(
                    title: isPreparingTimelineSummary ? "Checking your AI credits" : "Writing your timeline summary",
                    message: isPreparingTimelineSummary ? "Proofly is confirming the credit cost before anything runs." : "This can take a little while for larger timelines. Keep this screen open and your proof stays unchanged."
                )
                .transition(ProofKitMotion.compactInsertion)
            }

            if let timelineSummaryInlineError {
                TimelineSummaryErrorCard(
                    message: timelineSummaryInlineError,
                    onRetry: {
                        Task { await prepareTimelineSummary() }
                    }
                )
                .transition(ProofKitMotion.compactInsertion)
            }

            if let aiTimelineSummaryText {
                TimelineSummaryResultCard(
                    summaryText: aiTimelineSummaryText,
                    wasCacheHit: timelineSummaryWasCacheHit,
                    isAddingToTimeline: isAddingTimelineSummary,
                    wasAddedToTimeline: timelineSummaryWasAddedToTimeline,
                    onAddToTimeline: {
                        Task { await addTimelineSummaryToTimeline() }
                    }
                )
                .transition(ProofKitMotion.cardInsertion)
            }

            Button {
                Task { await prepareTimelineSummary() }
            } label: {
                HStack(spacing: 8) {
                    if isPreparingTimelineSummary || isRunningTimelineSummary {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(timelineSummaryButtonTitle)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .disabled(isPreparingTimelineSummary || isRunningTimelineSummary)
            .accessibilityHint("Shows the credit cost before running the AI timeline summary.")

            Text("Uses 2 AI credits when a new server summary is generated. Local OCR, timeline editing, and exports do not use AI credits.")
                .font(.caption2)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ProofKitVisual.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ProofKitVisual.panelCornerRadius, style: .continuous)
                .fill(ProofKitVisual.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ProofKitVisual.panelCornerRadius, style: .continuous)
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
        .animation(ProofKitMotion.standard, value: isPreparingTimelineSummary)
        .animation(ProofKitMotion.standard, value: isRunningTimelineSummary)
        .animation(ProofKitMotion.standard, value: aiTimelineSummaryText)
        .animation(ProofKitMotion.standard, value: timelineSummaryInlineError)
    }

    private var timelineSummaryButtonTitle: String {
        if isPreparingTimelineSummary {
            return "Checking credits…"
        }

        if isRunningTimelineSummary {
            return "Summarizing…"
        }

        if aiTimelineSummaryText == nil {
            return "Summarize timeline with AI"
        }

        return "Refresh AI summary"
    }

    private var timelineToolbar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(timelineSummaryText)
                .font(.caption.weight(.medium))
                .foregroundStyle(ProofKitVisual.helperText)

            Spacer(minLength: 12)

            if timelineGroups.count > 1 {
                Button(allGroupsAreCollapsed ? "Expand all" : "Collapse all") {
                    withAnimation(ProofKitMotion.softSpring) {
                        if allGroupsAreCollapsed {
                            collapsedGroupIDs.removeAll()
                        } else {
                            collapsedGroupIDs = Set(timelineGroups.map(\.id))
                        }
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 2)
    }

    private var timelineSummaryText: String {
        let sectionText = timelineGroups.count == 1 ? "1 date section" : "\(timelineGroups.count) date sections"
        let evidenceText = evidenceItemCount == 1 ? "1 proof item" : "\(evidenceItemCount) proof items"
        return "Oldest first • \(evidenceText) across \(sectionText)"
    }

    private func toggle(_ group: TimelineDateGroup) {
        withAnimation(ProofKitMotion.softSpring) {
            if collapsedGroupIDs.contains(group.id) {
                collapsedGroupIDs.remove(group.id)
            } else {
                collapsedGroupIDs.insert(group.id)
            }
        }
    }

    private func openEvidence(_ evidenceItem: EvidenceItem) {
        selectedEvidenceRoute = TimelineEvidenceRoute(evidenceItem: evidenceItem)
    }

    private func deleteEvidence(_ evidenceItem: EvidenceItem) {
        do {
            try EvidenceDeletionService.deleteFromCase(evidenceItem, modelContext: modelContext)
        } catch {
            withAnimation(ProofKitMotion.standard) {
                deletionNotice = TimelineDeletionNotice(
                    title: "Proof not deleted",
                    message: "This proof item could not be deleted. Please try again."
                )
            }
        }
    }

    @MainActor
    private func prepareTimelineSummary() async {
        guard !isPreparingTimelineSummary, !isRunningTimelineSummary else { return }

        let accessDecision = await services.paywall.canUseAI()
        guard accessDecision.isAllowed else {
            timelineSummaryInlineError = accessDecision.message
            showingAIPaywall = true
            return
        }

        timelineSummaryInlineError = nil
        isPreparingTimelineSummary = true
        defer { isPreparingTimelineSummary = false }

        do {
            pendingTimelineSummaryQuote = try await services.aiActions.quoteAction(
                .timelineSummary,
                caseID: caseFile.id
            )
        } catch {
            if ServiceHealthMonitor.isServiceAvailabilityError(error) || services.serviceHealth.snapshot.state.isDegraded {
                services.serviceHealth.record(error, context: .supabaseEdgeFunction)
                do {
                    try services.aiQueue.enqueue(
                        .timelineSummary,
                        caseFile: caseFile,
                        quote: nil,
                        in: modelContext
                    )
                    aiNotice = TimelineAINotice(
                        title: "Timeline Summary Queued",
                        message: "AI will run when connection returns and credits are available. Your local timeline stays usable."
                    )
                    timelineSummaryInlineError = "Connection is unavailable right now, so the summary was queued for later."
                } catch {
                    timelineSummaryInlineError = Self.userMessage(for: error)
                    aiNotice = TimelineAINotice(
                        title: "Timeline Summary Unavailable",
                        message: Self.userMessage(for: error)
                    )
                }
                return
            }

            aiNotice = TimelineAINotice(
                title: Self.aiErrorTitle(for: error, fallback: "Timeline Summary Unavailable"),
                message: Self.userMessage(for: error)
            )
            timelineSummaryInlineError = Self.userMessage(for: error)
        }
    }

    @MainActor
    private func runTimelineSummary(quote: AIUsageQuote) async {
        guard !isRunningTimelineSummary else { return }

        services.analytics.trackAIActionStarted(actionType: .timelineSummary)
        let startedAt = Date()
        timelineSummaryInlineError = nil
        isRunningTimelineSummary = true
        defer { isRunningTimelineSummary = false }

        do {
            let result = try await services.aiActions.runAction(
                quote.feature,
                for: caseFile,
                in: modelContext,
                userTriggered: true
            )

            aiTimelineSummaryText = result.outputText
            timelineSummaryWasCacheHit = result.wasCacheHit
            timelineSummaryWasAddedToTimeline = false
            timelineSummaryInlineError = nil

            let durationMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
            services.analytics.trackAIActionCompleted(
                actionType: .timelineSummary,
                creditsSpent: result.creditsUsed,
                creditsRemaining: result.remainingCredits,
                durationMS: durationMS
            )

            if let creditsUsed = result.creditsUsed, creditsUsed > 0 {
                services.analytics.trackAICreditsSpent(
                    actionType: .timelineSummary,
                    creditsSpent: creditsUsed,
                    creditsRemaining: result.remainingCredits
                )
            }
        } catch {
            let durationMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
            services.analytics.trackAIActionFailed(
                actionType: .timelineSummary,
                durationMS: durationMS,
                errorType: AnalyticsErrorType(error)
            )
            if ServiceHealthMonitor.isServiceAvailabilityError(error) || services.serviceHealth.snapshot.state.isDegraded {
                services.serviceHealth.record(error, context: .aiProvider)
                do {
                    try services.aiQueue.enqueue(
                        quote.feature,
                        caseFile: caseFile,
                        quote: quote,
                        in: modelContext
                    )
                    aiNotice = TimelineAINotice(
                        title: "Timeline Summary Queued",
                        message: "AI will run when connection returns and credits are available. Your original proof and OCR are unchanged."
                    )
                    timelineSummaryInlineError = "Connection dropped before the summary finished, so it was queued for later."
                } catch {
                    timelineSummaryInlineError = Self.userMessage(for: error)
                    aiNotice = TimelineAINotice(
                        title: "Timeline Summary Failed",
                        message: Self.userMessage(for: error)
                    )
                }
                return
            }

            aiNotice = TimelineAINotice(
                title: Self.aiErrorTitle(for: error, fallback: "Timeline Summary Failed"),
                message: Self.userMessage(for: error)
            )
            timelineSummaryInlineError = Self.userMessage(for: error)
        }
    }

    @MainActor
    private func addTimelineSummaryToTimeline() async {
        guard !isAddingTimelineSummary,
              !timelineSummaryWasAddedToTimeline,
              let summaryText = aiTimelineSummaryText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summaryText.isEmpty else {
            return
        }

        isAddingTimelineSummary = true
        defer { isAddingTimelineSummary = false }

        let decision = await services.paywall.canAddEvidence(to: caseFile, adding: 1)
        guard decision.isAllowed else {
            timelineSummaryInlineError = decision.message
            return
        }

        let now = Date()
        let evidenceItem = EvidenceItem(
            category: .note,
            userDateSource: .userEntered,
            userTitle: "AI timeline summary",
            userNotes: summaryText,
            userWhyThisMatters: "Saved AI-generated overview of this case timeline.",
            userProvidedEventDate: now,
            userMarkedImportant: true,
            isReviewed: true,
            reviewedAt: now,
            createdAt: now,
            updatedAt: now,
            sortIndex: caseFile.evidenceItems.count
        )

        modelContext.insert(evidenceItem)
        caseFile.evidenceItems.append(evidenceItem)
        caseFile.updatedAt = now

        if caseFile.status == .draft {
            caseFile.status = .active
        }

        do {
            try modelContext.save()
            services.analytics.trackProofAdded(evidenceItem, caseFile: caseFile)
            services.analytics.trackTimelineItemCreated(evidenceItem)
            services.analytics.trackProofAddedToTimeline(evidenceItem)
            timelineSummaryInlineError = nil
            timelineSummaryWasAddedToTimeline = true
            aiNotice = TimelineAINotice(
                title: "Summary Added",
                message: "The AI summary is now saved as a reviewed timeline note. Your original proof and OCR were not changed."
            )
        } catch {
            modelContext.delete(evidenceItem)
            timelineSummaryInlineError = "The summary could not be added to the timeline. Please try again."
        }
    }

    @MainActor
    private func loadCachedTimelineSummary() {
        let taskRawValue = AITaskType.summarizeTimeline.rawValue
        let descriptor = FetchDescriptor<AIResultCache>(
            predicate: #Predicate<AIResultCache> { cache in
                cache.taskTypeRawValue == taskRawValue
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let cachedSummary = try? modelContext.fetch(descriptor).first(where: { cache in
            cache.caseFile?.id == caseFile.id && !cache.isExpired
        }),
        let data = cachedSummary.resultJSON.data(using: .utf8),
        let response = try? JSONDecoder().decode(AIProxyTextResponse.self, from: data),
        !response.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        aiTimelineSummaryText = response.outputText
        timelineSummaryWasCacheHit = true
        timelineSummaryWasAddedToTimeline = false
    }

    private static func userMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }

    private static func aiErrorTitle(for error: Error, fallback: String) -> String {
        guard let localizedError = error as? LocalizedError,
              let description = localizedError.errorDescription else {
            return fallback
        }

        if description.localizedCaseInsensitiveContains("out of AI credits") ||
            description.localizedCaseInsensitiveContains("AI credit") ||
            description.localizedCaseInsensitiveContains("insufficient_ai_credits") {
            return "Out of AI Credits"
        }

        return fallback
    }
}

private struct TimelineDateGroupSection: View {
    let group: TimelineDateGroup
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onOpen: (EvidenceItem) -> Void
    let onDelete: (EvidenceItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(group.itemCountText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ProofKitVisual.helperText)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ProofKitVisual.helperText)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .animation(ProofKitMotion.standard, value: isCollapsed)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCollapsed ? "Expand \(group.title)" : "Collapse \(group.title)")

            if !isCollapsed {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { itemIndex, evidenceItem in
                        HStack(alignment: .top, spacing: 10) {
                            TimelineRailMarker(isLastInGroup: itemIndex == group.items.count - 1)

                            ProofKitSwipeToDeleteRow(
                                deleteAccessibilityLabel: "Delete proof",
                                onOpen: {
                                    onOpen(evidenceItem)
                                },
                                onDelete: {
                                    onDelete(evidenceItem)
                                }
                            ) {
                                TimelineEvidenceCard(evidenceItem: evidenceItem)
                            }
                            .buttonStyle(ProofKitCardButtonStyle())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -4)),
                        removal: .opacity
                    )
                )
            }
        }
        .animation(ProofKitMotion.softSpring, value: isCollapsed)
    }
}

private struct TimelineEvidenceRoute: Identifiable, Hashable {
    let id: UUID
    let evidenceItem: EvidenceItem

    init(evidenceItem: EvidenceItem) {
        id = evidenceItem.id
        self.evidenceItem = evidenceItem
    }

    static func == (lhs: TimelineEvidenceRoute, rhs: TimelineEvidenceRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct TimelineDeletionNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct TimelineAINotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct TimelineSummaryLoadingCard: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ProofKitVisual.fieldBackground)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TimelineSummaryErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Summary needs attention")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Try again", action: onRetry)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct TimelineSummaryResultCard: View {
    let summaryText: String
    let wasCacheHit: Bool
    let isAddingToTimeline: Bool
    let wasAddedToTimeline: Bool
    let onAddToTimeline: () -> Void

    private var sections: [TimelineSummarySection] {
        TimelineSummarySection.parse(summaryText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Summary Ready")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(wasCacheHit ? "Cached" : "New")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(wasCacheHit ? ProofKitVisual.helperText : ProofKitVisual.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(ProofKitVisual.quietFill)
                    }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(sections) { section in
                    TimelineSummarySectionView(section: section)
                }
            }

            Text(wasCacheHit ? "Restored from this device. No new AI credits used." : "AI-generated content is saved separately from your original timeline.")
                .font(.caption.weight(.medium))
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onAddToTimeline()
            } label: {
                HStack(spacing: 8) {
                    if isAddingToTimeline {
                        ProgressView()
                            .controlSize(.small)
                    } else if wasAddedToTimeline {
                        Image(systemName: "checkmark.circle.fill")
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .accessibilityHidden(true)
                    }

                    Text(addButtonTitle)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .disabled(isAddingToTimeline || wasAddedToTimeline)
            .accessibilityHint("Saves the AI summary as a reviewed local note in this timeline.")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ProofKitVisual.fieldBackground)
        }
    }

    private var addButtonTitle: String {
        if isAddingToTimeline {
            return "Adding to timeline..."
        }

        if wasAddedToTimeline {
            return "Added to timeline"
        }

        return "Add summary to timeline"
    }
}

private struct TimelineSummarySectionView: View {
    let section: TimelineSummarySection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = section.title {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ProofKitVisual.accent)
                    .textCase(.uppercase)
            }

            ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 7) {
                    if line.isBullet {
                        Circle()
                            .fill(ProofKitVisual.accent.opacity(0.65))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                            .accessibilityHidden(true)
                    }

                    Text(line.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct TimelineSummarySection: Identifiable, Hashable {
    let id = UUID()
    let title: String?
    var lines: [TimelineSummaryLine]

    static func parse(_ text: String) -> [TimelineSummarySection] {
        var sections: [TimelineSummarySection] = []
        var currentTitle: String?
        var currentLines: [TimelineSummaryLine] = []

        func flush() {
            guard !currentLines.isEmpty else { return }
            sections.append(TimelineSummarySection(title: currentTitle, lines: currentLines))
            currentTitle = nil
            currentLines = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                flush()
                continue
            }

            if let heading = headingText(from: trimmedLine) {
                flush()
                currentTitle = heading
                continue
            }

            let parsedLine = TimelineSummaryLine.parse(trimmedLine)
            currentLines.append(parsedLine)
        }

        flush()

        if sections.isEmpty {
            return [
                TimelineSummarySection(
                    title: nil,
                    lines: [TimelineSummaryLine(text: text.trimmingCharacters(in: .whitespacesAndNewlines), isBullet: false)]
                )
            ]
        }

        return sections
    }

    private static func headingText(from line: String) -> String? {
        let markdownHeading = line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if line.hasPrefix("#"), !markdownHeading.isEmpty {
            return markdownHeading.trimmingTerminalColon
        }

        guard line.count <= 48,
              !line.contains("."),
              !line.contains("?"),
              !line.contains("!"),
              line.hasSuffix(":") else {
            return nil
        }

        return line.trimmingTerminalColon
    }
}

private struct TimelineSummaryLine: Hashable {
    let text: String
    let isBullet: Bool

    static func parse(_ line: String) -> TimelineSummaryLine {
        let bulletPrefixes = ["- ", "* ", "• "]

        for prefix in bulletPrefixes where line.hasPrefix(prefix) {
            return TimelineSummaryLine(
                text: String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines),
                isBullet: true
            )
        }

        if let first = line.first,
           first.isNumber,
           let dotIndex = line.firstIndex(of: ".") {
            let numberPrefix = line[..<dotIndex]
            let afterDot = line[line.index(after: dotIndex)...]
            if numberPrefix.allSatisfy(\.isNumber), afterDot.first == " " {
                return TimelineSummaryLine(
                    text: String(afterDot).trimmingCharacters(in: .whitespacesAndNewlines),
                    isBullet: true
                )
            }
        }

        return TimelineSummaryLine(text: line, isBullet: false)
    }
}

private extension String {
    var trimmingTerminalColon: String {
        trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TimelineRailMarker: View {
    let isLastInGroup: Bool

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(ProofKitVisual.subduedText.opacity(0.38))
                .frame(width: 7, height: 7)
                .overlay {
                    Circle()
                        .stroke(ProofKitVisual.screenBackground, lineWidth: 2)
                }
                .padding(.top, 22)
                .padding(.bottom, 5)

            if !isLastInGroup {
                Rectangle()
                    .fill(ProofKitVisual.divider.opacity(0.7))
                    .frame(width: 1, height: 76)
            }
        }
        .frame(width: 12)
        .accessibilityHidden(true)
    }
}

private struct TimelineEvidenceCard: View {
    let evidenceItem: EvidenceItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TimelineAttachmentPreview(evidenceItem: evidenceItem)

            VStack(alignment: .leading, spacing: 7) {
                metadata

                Text(evidenceItem.timelineDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let noteText {
                    Text(noteText)
                        .font(.footnote)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !whyThisMattersText.isEmpty {
                    Text("Why: \(whyThisMattersText)")
                        .font(.footnote)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: ProofKitVisual.fieldCornerRadius, style: .continuous)
                                .fill(ProofKitVisual.fieldBackground)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous)
                .fill(ProofKitVisual.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous)
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
    }

    private var metadata: some View {
        HStack(alignment: .center, spacing: 7) {
            Text(evidenceItem.category.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(ProofKitVisual.helperText)

            if !attachmentCountText.isEmpty {
                Text("•")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ProofKitVisual.subduedText)

                Text(attachmentCountText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ProofKitVisual.helperText)
            }

            Spacer(minLength: 0)

            if evidenceItem.userMarkedImportant {
                Label("Important", systemImage: "star.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private var attachmentCountText: String {
        let count = evidenceItem.attachments.count
        guard count > 0 else { return "" }
        return count == 1 ? "1 attachment" : "\(count) attachments"
    }

    private var noteText: String? {
        if !cleanedNoteText.isEmpty {
            return cleanedNoteText
        }

        if !userNoteText.isEmpty {
            return userNoteText
        }

        if !ocrTextSnippet.isEmpty {
            return ocrTextSnippet
        }

        return nil
    }

    private var cleanedNoteText: String {
        evidenceItem.userCleanedNote.timelineTrimmedText
    }

    private var userNoteText: String {
        evidenceItem.userNotes.timelineTrimmedText
    }

    private var ocrTextSnippet: String {
        evidenceItem.originalOCRText.timelineTrimmedText
    }

    private var whyThisMattersText: String {
        evidenceItem.userWhyThisMatters.timelineTrimmedText
    }
}

private struct TimelineAttachmentPreview: View {
    let evidenceItem: EvidenceItem

    private var primaryAttachment: Attachment? {
        evidenceItem.sortedAttachments.first { attachment in
            attachment.thumbnailLocalFilePath != nil
        } ?? evidenceItem.sortedAttachments.first
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            previewContent

            if evidenceItem.attachments.count > 1 {
                Text("+\(evidenceItem.attachments.count - 1)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background {
                        Capsule(style: .continuous)
                            .fill(ProofKitVisual.imageBadgeBackground)
                    }
                    .padding(3)
                    .accessibilityLabel("\(evidenceItem.attachments.count) attachments")
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var previewContent: some View {
        if
            let thumbnailPath = primaryAttachment?.thumbnailLocalFilePath,
            let image = UIImage(contentsOfFile: thumbnailPath)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(ProofKitVisual.fieldBackground)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: attachmentSystemImage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ProofKitVisual.helperText)
                }
        }
    }

    private var attachmentSystemImage: String {
        guard let attachmentType = primaryAttachment?.attachmentType else {
            return "note.text"
        }

        switch attachmentType {
        case .screenshot:
            return "rectangle.on.rectangle"
        case .photo:
            return "photo"
        case .pdf:
            return "doc.richtext"
        case .document:
            return "doc"
        case .textNote:
            return "note.text"
        case .other:
            return "paperclip"
        }
    }
}

private struct TimelineDateGroup: Identifiable {
    let id: String
    let date: Date?
    let items: [EvidenceItem]

    var title: String {
        guard let date else {
            return "Needs date"
        }

        return date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    var itemCountText: String {
        items.count == 1 ? "1 proof item" : "\(items.count) proof items"
    }

    static func groups(from evidenceItems: [EvidenceItem]) -> [TimelineDateGroup] {
        let calendar = Calendar.current
        var datedItems: [Date: [EvidenceItem]] = [:]
        var undatedItems: [EvidenceItem] = []

        for evidenceItem in evidenceItems {
            if let eventDate = evidenceItem.eventDate {
                let startOfDay = calendar.startOfDay(for: eventDate)
                datedItems[startOfDay, default: []].append(evidenceItem)
            } else {
                undatedItems.append(evidenceItem)
            }
        }

        var groups = datedItems.keys.sorted().map { date in
            TimelineDateGroup(
                id: ISO8601DateFormatter().string(from: date),
                date: date,
                items: sortedItems(datedItems[date] ?? [])
            )
        }

        if !undatedItems.isEmpty {
            groups.append(
                TimelineDateGroup(
                    id: "undated",
                    date: nil,
                    items: sortedItems(undatedItems)
                )
            )
        }

        return groups
    }

    private static func sortedItems(_ items: [EvidenceItem]) -> [EvidenceItem] {
        items.sorted { lhs, rhs in
            let lhsDate = lhs.eventDate ?? lhs.createdAt
            let rhsDate = rhs.eventDate ?? rhs.createdAt

            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }

            return lhs.createdAt < rhs.createdAt
        }
    }
}

private extension EvidenceItem {
    var timelineDisplayTitle: String {
        let trimmedTitle = userTitle.timelineTrimmedText
        if !trimmedTitle.isEmpty, !trimmedTitle.isGenericProofKitImageTitle {
            return trimmedTitle
        }

        if let fallbackTitle = [userCleanedNote, userNotes, originalOCRText]
            .map(\.timelineFallbackTitleText)
            .first(where: { !$0.isEmpty })
        {
            return fallbackTitle
        }

        let categoryTitle = category == .uncategorized ? "Proof item" : "\(category.displayName) proof item"
        if let eventDate {
            return "\(categoryTitle) from \(ProofKitDateFormatting.shortDate(eventDate))"
        }

        return categoryTitle
    }
}

private extension String {
    var timelineTrimmedText: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 160 else {
            return trimmed
        }

        return String(trimmed.prefix(157)) + "…"
    }

    var timelineFallbackTitleText: String {
        let condensed = timelineCondensedWhitespace
        guard !condensed.isEmpty else { return "" }

        let words = condensed.split(separator: " ")
        let title = words.prefix(8).joined(separator: " ")
        guard words.count > 8 else {
            return title.timelineTitleLimitedText
        }

        return "\(title)…".timelineTitleLimitedText
    }

    var timelineCondensedWhitespace: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    var timelineTitleLimitedText: String {
        guard count > 72 else { return self }
        return String(prefix(69)) + "…"
    }

    var isGenericProofKitImageTitle: Bool {
        range(
            of: #"^(ProofKit|Proofly) Image [0-9]+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

#Preview {
    let calendar = Calendar.current
    let firstDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 21, hour: 8, minute: 30)) ?? .now
    let secondDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 22, hour: 9, minute: 15)) ?? .now
    let thirdDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 14, minute: 10)) ?? .now
    let fourthDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 26, hour: 18, minute: 0)) ?? .now

    TimelineView(
        caseFile: CaseFile(
            caseType: .apartmentIssue,
            status: .active,
            userTitle: "Ceiling Leaking Main Bedroom",
            userSummary: "Water damage evidence for the main bedroom ceiling.",
            evidenceItems: [
                EvidenceItem(
                    category: .note,
                    userDateSource: .userEntered,
                    userTitle: "Leak first noticed",
                    userNotes: "Water spots appeared near the main bedroom ceiling light.",
                    userProvidedEventDate: firstDate
                ),
                EvidenceItem(
                    category: .photo,
                    userDateSource: .userEntered,
                    userTitle: "Ceiling damage photo",
                    userNotes: "Photo showing the brown ceiling stain and bubbling paint.",
                    userProvidedEventDate: secondDate,
                    userMarkedImportant: true
                ),
                EvidenceItem(
                    category: .message,
                    userDateSource: .userEntered,
                    userTitle: "Message to landlord",
                    userNotes: "Sent the first written notice asking for inspection and repair timing.",
                    userProvidedEventDate: thirdDate
                ),
                EvidenceItem(
                    category: .note,
                    userDateSource: .userEntered,
                    userTitle: "Repair follow-up note",
                    userNotes: "Noted that the ceiling was still damp after the scheduled maintenance window.",
                    userProvidedEventDate: fourthDate
                )
            ]
        )
    )
}
