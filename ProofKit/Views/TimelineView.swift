import SwiftData
import SwiftUI
import UIKit

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    let caseFile: CaseFile

    @State private var collapsedGroupIDs: Set<String> = []
    @State private var deletionNotice: TimelineDeletionNotice?
    @State private var selectedEvidenceRoute: TimelineEvidenceRoute?

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
                subtitle: "Evidence items grouped by the date they happened."
            )

            if timelineGroups.isEmpty {
                PlaceholderPanel(
                    systemImage: "calendar",
                    title: "Timeline is empty",
                    message: "Add your first evidence item when you are ready. ProofKit will place dated items into a calm chronological view.",
                    steps: [
                        PlaceholderStep(
                            systemImage: "plus",
                            title: "Add evidence",
                            detail: "Use the Add Evidence button above to import a file or write a note."
                        ),
                        PlaceholderStep(
                            systemImage: "calendar.badge.clock",
                            title: "Check the date",
                            detail: "Use the event date that best matches what happened."
                        ),
                        PlaceholderStep(
                            systemImage: "list.bullet.rectangle",
                            title: "Review the timeline",
                            detail: "Evidence items will group by date so larger cases stay readable."
                        )
                    ],
                    footnote: "There is no need to finish everything at once."
                )
            } else {
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
        .navigationDestination(item: $selectedEvidenceRoute) { route in
            EvidenceDetailEditView(evidenceItem: route.evidenceItem)
        }
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
        let evidenceText = evidenceItemCount == 1 ? "1 evidence item" : "\(evidenceItemCount) evidence items"
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
                    title: "Evidence not deleted",
                    message: "This evidence item could not be deleted. Please try again."
                )
            }
        }
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

                            SwipeToDeleteEvidenceRow(
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

private struct SwipeToDeleteEvidenceRow<Content: View>: View {
    private let deleteButtonWidth: CGFloat = 96
    private let revealThreshold: CGFloat = 42

    let onOpen: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @GestureState private var dragTranslation: CGFloat = 0
    @State private var restingOffset: CGFloat = 0
    @State private var isSuppressingTap = false
    @State private var rowHeight: CGFloat = 0

    private var visibleOffset: CGFloat {
        max(-deleteButtonWidth, min(0, restingOffset + dragTranslation))
    }

    private var isDeleteRevealed: Bool {
        restingOffset < 0
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteButton
                .frame(width: deleteButtonWidth, height: rowHeight)
                .opacity(visibleOffset < 0 && rowHeight > 0 ? 1 : 0)
                .allowsHitTesting(isDeleteRevealed)

            content()
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: SwipeRowHeightPreferenceKey.self, value: proxy.size.height)
                    }
                }
                .offset(x: visibleOffset)
                .contentShape(Rectangle())
                .onTapGesture(perform: handleTap)
                .simultaneousGesture(revealGesture)
        }
        .clipped()
        .onPreferenceChange(SwipeRowHeightPreferenceKey.self) { height in
            guard abs(rowHeight - height) > 0.5 else { return }
            rowHeight = height
        }
        .accessibilityAction(named: "Open") {
            onOpen()
        }
        .accessibilityAction(named: isDeleteRevealed ? "Hide Delete" : "Reveal Delete") {
            withAnimation(ProofKitMotion.standard) {
                restingOffset = isDeleteRevealed ? 0 : -deleteButtonWidth
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            withAnimation(ProofKitMotion.standard) {
                restingOffset = 0
            }
            onDelete()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))

                Text("Delete")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(width: deleteButtonWidth)
            .frame(maxHeight: .infinity)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous))
            .accessibilityLabel("Delete evidence")
        }
        .buttonStyle(.plain)
    }

    private var revealGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                isSuppressingTap = true
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    resetTapSuppressionSoon()
                    return
                }

                let projectedOffset = restingOffset + value.predictedEndTranslation.width
                let shouldReveal = projectedOffset < -deleteButtonWidth / 2 || value.translation.width < -revealThreshold

                withAnimation(ProofKitMotion.standard) {
                    restingOffset = shouldReveal ? -deleteButtonWidth : 0
                }

                resetTapSuppressionSoon()
            }
    }

    private func handleTap() {
        guard !isSuppressingTap else { return }

        if isDeleteRevealed {
            withAnimation(ProofKitMotion.standard) {
                restingOffset = 0
            }
        } else {
            onOpen()
        }
    }

    private func resetTapSuppressionSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isSuppressingTap = false
        }
    }
}

private struct SwipeRowHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
        items.count == 1 ? "1 evidence item" : "\(items.count) evidence items"
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

        let categoryTitle = category == .uncategorized ? "Evidence item" : "\(category.displayName) evidence item"
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
            of: #"^ProofKit Image [0-9]+$"#,
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
