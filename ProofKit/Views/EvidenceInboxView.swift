import StoreKit
import SwiftData
import SwiftUI
import UIKit

struct EvidenceInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.proofKitServices) private var services
    @Environment(\.requestReview) private var requestReview

    let caseFile: CaseFile
    @Binding private var skippedEvidenceIDs: Set<UUID>
    @State private var didTrackReviewOpened = false

    init(
        caseFile: CaseFile,
        skippedEvidenceIDs: Binding<Set<UUID>> = .constant([])
    ) {
        self.caseFile = caseFile
        _skippedEvidenceIDs = skippedEvidenceIDs
    }

    private var reviewItems: [EvidenceItem] {
        caseFile.sortedEvidenceItems.filter { evidenceItem in
            evidenceItem.needsReview && !skippedEvidenceIDs.contains(evidenceItem.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            reviewHeader

            if caseFile.evidenceItems.isEmpty {
                PlaceholderPanel(
                    systemImage: "tray",
                    title: String(localized: "Inbox is empty"),
                    message: String(localized: "When you add proof, new imported items can appear here first so you can confirm the details before they join the timeline."),
                    steps: [
                        PlaceholderStep(
                            systemImage: "photo.on.rectangle",
                            title: String(localized: "Import or write"),
                            detail: String(localized: "Add a photo, screenshot, PDF, document, or note.")
                        ),
                        PlaceholderStep(
                            systemImage: "checkmark.circle",
                            title: String(localized: "Confirm what matters"),
                            detail: String(localized: "Review the title, date, category, and notes at your own pace.")
                        )
                    ],
                    footnote: String(localized: "Manual notes and imported files remain editable later.")
                )
            } else if reviewItems.isEmpty {
                InboxEmptyStateCard(imageName: "RookInboxEmpty")
            } else {
                VStack(spacing: ProofKitVisual.cardSpacing) {
                    ForEach(Array(reviewItems.enumerated()), id: \.element.id) { index, evidenceItem in
                        EvidenceReviewCard(
                            evidenceItem: evidenceItem,
                            onConfirm: {
                                confirm(evidenceItem)
                            },
                            onSkip: {
                                skip(evidenceItem)
                            }
                        )
                        .transition(ProofKitMotion.compactInsertion)
                        .proofKitAppear(delay: min(Double(index) * 0.025, 0.12))
                    }
                }
                .animation(ProofKitMotion.standard, value: reviewItems.map(\.id))
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 88)
        .onAppear(perform: trackReviewOpenedIfNeeded)
    }

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reviewTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(reviewSubtitle)
                .font(.subheadline)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reviewTitle: String {
        String(localized: "Review new proof")
    }

    private var reviewSubtitle: String {
        if caseFile.evidenceItems.isEmpty {
            return String(localized: "This is a quiet holding area for proof you have not reviewed yet.")
        }

        if reviewItems.isEmpty {
            return String(localized: "No action is needed here right now.")
        }

        let count = reviewItems.count
        if count == 1 {
            return String(localized: "1 item needs confirmation before it appears in your timeline.")
        }

        return String(localized: "\(count) items need confirmation before they appear in your timeline.")
    }

    private func confirm(_ evidenceItem: EvidenceItem) {
        let now = Date()
        withAnimation(ProofKitMotion.standard) {
            evidenceItem.isReviewed = true
            evidenceItem.reviewedAt = now
            evidenceItem.updatedAt = now
            evidenceItem.caseFile?.updatedAt = now
        }

        do {
            try modelContext.save()
            services.analytics.trackProofReviewed(evidenceItem)
            services.analytics.trackProofAddedToTimeline(evidenceItem)
            if AppReviewPromptCoordinator.shared.shouldRequestTimelineProofReview() {
                requestReview()
            }
        } catch {
            // Keep the card visible if a local save fails.
            withAnimation(ProofKitMotion.standard) {
                evidenceItem.isReviewed = false
                evidenceItem.reviewedAt = nil
            }
        }
    }

    private func skip(_ evidenceItem: EvidenceItem) {
        withAnimation(ProofKitMotion.standard) {
            _ = skippedEvidenceIDs.insert(evidenceItem.id)
        }
        services.analytics.trackProofSkipped(evidenceItem)
    }

    private func trackReviewOpenedIfNeeded() {
        guard !didTrackReviewOpened, !reviewItems.isEmpty else { return }
        didTrackReviewOpened = true
        services.analytics.trackOCRReviewOpened(caseFile: caseFile)
    }
}

private struct InboxEmptyStateCard: View {
    let imageName: String

    private let actions = [
        InboxEmptyAction(
            systemImage: "plus",
            title: String(localized: "Add more proof"),
            detail: String(localized: "Use Add Proof when you have another screenshot, file, or note.")
        ),
        InboxEmptyAction(
            systemImage: "calendar",
            title: String(localized: "Check the timeline"),
            detail: String(localized: "Reviewed proof is organized by date.")
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    copy
                        .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

                    mascot(width: 195, height: 130)
                        .layoutPriority(1)
                }

                VStack(alignment: .leading, spacing: 12) {
                    mascot(width: 218, height: 146)
                        .frame(maxWidth: .infinity, alignment: .center)

                    copy
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(actions) { action in
                    InboxEmptyActionRow(action: action)

                    if action.id != actions.last?.id {
                        Divider()
                            .padding(.leading, 34)
                    }
                }
            }
            .padding(.top, 2)
        }
        .proofKitCard(cornerRadius: ProofKitVisual.panelCornerRadius)
        .accessibilityElement(children: .contain)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Review queue is clear")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Everything you added has been reviewed or skipped for now.")
                .font(.subheadline)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mascot(width: CGFloat, height: CGFloat) -> some View {
        Image(imageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: width, height: height)
            .accessibilityHidden(true)
            .shadow(color: ProofKitVisual.accentSecondary.opacity(0.18), radius: 12, x: 0, y: 7)
    }
}

private struct InboxEmptyAction: Identifiable {
    let systemImage: String
    let title: String
    let detail: String

    var id: String { "\(systemImage)-\(title)" }
}

private struct InboxEmptyActionRow: View {
    let action: InboxEmptyAction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: action.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ProofKitVisual.helperText)
                .frame(width: 22, height: 22)
                .background {
                    Circle()
                        .fill(ProofKitVisual.fieldBackground)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }
}

private struct EvidenceReviewCard: View {
    let evidenceItem: EvidenceItem
    let onConfirm: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ReviewQueueThumbnail(evidenceItem: evidenceItem)

                VStack(alignment: .leading, spacing: 8) {
                    metadataLine

                    Text(displayTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let ocrLine {
                        Text(ocrLine.text)
                            .font(.subheadline)
                            .foregroundStyle(ocrLine.isPreview ? ProofKitVisual.helperText : ProofKitVisual.subduedText)
                            .lineLimit(ocrLine.isPreview ? 2 : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if evidenceItem.isIncompleteForReview {
                Label("Needs a little attention before it is complete", systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ProofKitVisual.helperText)
            }

            HStack(spacing: 10) {
                Button {
                    onConfirm()
                } label: {
                    ReviewActionLabel(
                        title: String(localized: "Confirm"),
                        foreground: ProofKitVisual.primaryActionForeground,
                        background: ProofKitVisual.primaryActionBackground
                    )
                }
                .buttonStyle(ProofKitCardButtonStyle())

                NavigationLink {
                    EvidenceDetailEditView(evidenceItem: evidenceItem)
                } label: {
                    ReviewActionLabel(
                        title: String(localized: "Edit"),
                        foreground: ProofKitVisual.accent,
                        background: ProofKitVisual.accent.opacity(0.12)
                    )
                }
                .buttonStyle(ProofKitCardButtonStyle())

                Button {
                    onSkip()
                } label: {
                    ReviewActionLabel(
                        title: String(localized: "Skip"),
                        foreground: ProofKitVisual.helperText,
                        background: ProofKitVisual.quietFill
                    )
                }
                .buttonStyle(ProofKitCardButtonStyle())
            }
            .font(.caption.weight(.semibold))
        }
        .padding(14)
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

    private var metadataLine: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(detectedDateText)
                .font(.caption.weight(.medium))
                .foregroundStyle(ProofKitVisual.helperText)
                .lineLimit(1)
                .minimumScaleFactor(0.88)

            Text(evidenceItem.category.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(ProofKitVisual.helperText)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule(style: .continuous)
                        .fill(ProofKitVisual.quietFill)
                }

            if evidenceItem.userMarkedImportant {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Important")
            }
        }
    }

    private var detectedDateText: String {
        if let detectedEventDate = evidenceItem.detectedEventDate {
            return String(localized: "Detected \(ProofKitDateFormatting.shortDate(detectedEventDate))")
        }

        if let eventDate = evidenceItem.eventDate {
            return String(localized: "Date \(ProofKitDateFormatting.shortDate(eventDate))")
        }

        if !evidenceItem.requiresEventDateForCompletion {
            return String(localized: "Date optional")
        }

        return String(localized: "No date detected")
    }

    private var displayTitle: String {
        let userTitle = evidenceItem.userTitle.reviewCleanedText
        if !userTitle.isGenericReviewTitle {
            return userTitle
        }

        if let inferredTitle = evidenceItem.inferredReviewTitle {
            return inferredTitle
        }

        if let filenameTitle = evidenceItem.primaryReviewFilenameTitle {
            return filenameTitle
        }

        switch evidenceItem.category {
        case .photo:
            return String(localized: "Proof photo")
        case .screenshot:
            return String(localized: "Proof screenshot")
        case .message:
            return String(localized: "Message screenshot")
        case .email:
            return String(localized: "Email record")
        case .receipt:
            return String(localized: "Receipt")
        case .document, .contract:
            return String(localized: "Document")
        case .note:
            return String(localized: "Case note")
        case .uncategorized, .other:
            return String(localized: "Proof item")
        }
    }

    private var ocrLine: ReviewOCRLine? {
        let previewText = evidenceItem.originalOCRText.reviewPreviewText
        if !previewText.isEmpty {
            return ReviewOCRLine(text: previewText, isPreview: true)
        }

        guard evidenceItem.shouldShowOCRStatus else {
            return nil
        }

        if evidenceItem.ocrHasFinished {
            return ReviewOCRLine(text: String(localized: "No text detected"), isPreview: false)
        }

        return ReviewOCRLine(text: String(localized: "OCR pending"), isPreview: false)
    }
}

private struct ReviewOCRLine {
    let text: String
    let isPreview: Bool
}

private struct ReviewActionLabel: View {
    let title: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .allowsTightening(true)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(background)
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct ReviewQueueThumbnail: View {
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
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background {
                        Capsule(style: .continuous)
                            .fill(ProofKitVisual.imageBadgeBackground)
                    }
                    .padding(4)
            }
        }
        .frame(width: 58, height: 58)
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
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            EvidenceLikeThumbnail(kind: evidenceItem.reviewThumbnailKind)
        }
    }

}

private struct EvidenceLikeThumbnail: View {
    let kind: ReviewThumbnailKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(kind.background)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(kind.tint.opacity(0.18), lineWidth: 1)
                .padding(7)

            Image(systemName: kind.systemImage)
                .font(.system(size: 23, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(kind.tint)
        }
        .frame(width: 58, height: 58)
    }
}

private enum ReviewThumbnailKind {
    case leak
    case wallDamage
    case receipt
    case screenshot
    case message
    case email
    case document
    case photo
    case note
    case other

    var systemImage: String {
        switch self {
        case .leak:
            return "drop.fill"
        case .wallDamage:
            return "exclamationmark.triangle.fill"
        case .receipt:
            return "receipt.fill"
        case .screenshot:
            return "rectangle.on.rectangle"
        case .message:
            return "message.fill"
        case .email:
            return "envelope.fill"
        case .document:
            return "doc.text.fill"
        case .photo:
            return "photo.fill"
        case .note:
            return "note.text"
        case .other:
            return "paperclip"
        }
    }

    var tint: Color {
        switch self {
        case .leak:
            return ProofKitVisual.accent
        case .wallDamage:
            return Color(red: 0.64, green: 0.38, blue: 0.16)
        case .receipt:
            return Color(red: 0.18, green: 0.50, blue: 0.32)
        case .screenshot, .message, .email:
            return ProofKitVisual.accent
        case .document:
            return Color(red: 0.40, green: 0.36, blue: 0.72)
        case .photo:
            return Color(red: 0.12, green: 0.42, blue: 0.62)
        case .note, .other:
            return ProofKitVisual.helperText
        }
    }

    var background: Color {
        switch self {
        case .leak:
            return ProofKitVisual.accent.opacity(0.12)
        case .wallDamage:
            return Color(red: 0.64, green: 0.38, blue: 0.16).opacity(0.13)
        case .receipt:
            return Color(red: 0.18, green: 0.50, blue: 0.32).opacity(0.12)
        case .screenshot, .message, .email:
            return ProofKitVisual.accent.opacity(0.11)
        case .document:
            return Color(red: 0.40, green: 0.36, blue: 0.72).opacity(0.11)
        case .photo:
            return Color(red: 0.12, green: 0.42, blue: 0.62).opacity(0.11)
        case .note, .other:
            return ProofKitVisual.fieldBackground
        }
    }
}

private extension String {
    var reviewPreviewText: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard trimmed.count > 180 else {
            return trimmed
        }

        return String(trimmed.prefix(177)) + "…"
    }

    var reviewCleanedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    var isGenericReviewTitle: Bool {
        let normalized = reviewCleanedText.lowercased()

        if normalized.isEmpty {
            return true
        }

        if normalized == "untitled proof" || normalized == "imported image" || normalized == "evidence item" {
            return true
        }

        return normalized.range(
            of: #"^(proofkit|proofly) image\s+\d+$"#,
            options: .regularExpression
        ) != nil
    }
}

private extension EvidenceItem {
    var primaryReviewAttachment: Attachment? {
        sortedAttachments.first
    }

    var primaryReviewFilenameTitle: String? {
        guard let filename = primaryReviewAttachment?.originalFilename.reviewFilenameTitle else {
            return nil
        }

        return filename.isGenericReviewTitle ? nil : filename
    }

    var inferredReviewTitle: String? {
        let searchableText = reviewSearchableText

        if searchableText.containsAnyReviewTerm(["ceiling", "leak", "water", "drip", "mold"]) {
            return String(localized: "Ceiling leak photo")
        }

        if searchableText.containsAnyReviewTerm(["wall", "damage", "crack", "hole", "paint"]) {
            return String(localized: "Wall damage photo")
        }

        if searchableText.containsAnyReviewTerm(["receipt", "invoice", "paid", "repair", "$"]) || category == .receipt {
            return String(localized: "Repair receipt")
        }

        if searchableText.containsAnyReviewTerm(["landlord", "message", "text", "sms", "conversation"]) || category == .message {
            return String(localized: "Landlord message screenshot")
        }

        if searchableText.containsAnyReviewTerm(["email", "from:", "subject:"]) || category == .email {
            return String(localized: "Email thread")
        }

        return nil
    }

    var reviewThumbnailKind: ReviewThumbnailKind {
        let searchableText = reviewSearchableText

        if searchableText.containsAnyReviewTerm(["ceiling", "leak", "water", "drip", "mold"]) {
            return .leak
        }

        if searchableText.containsAnyReviewTerm(["wall", "damage", "crack", "hole", "paint"]) {
            return .wallDamage
        }

        if searchableText.containsAnyReviewTerm(["receipt", "invoice", "paid", "repair", "$"]) || category == .receipt {
            return .receipt
        }

        if searchableText.containsAnyReviewTerm(["landlord", "message", "text", "sms", "conversation"]) || category == .message {
            return .message
        }

        if searchableText.containsAnyReviewTerm(["email", "from:", "subject:"]) || category == .email {
            return .email
        }

        if category == .screenshot || primaryReviewAttachment?.attachmentType == .screenshot {
            return .screenshot
        }

        if category == .document || category == .contract || primaryReviewAttachment?.attachmentType == .document || primaryReviewAttachment?.attachmentType == .pdf {
            return .document
        }

        if category == .note || primaryReviewAttachment?.attachmentType == .textNote {
            return .note
        }

        if category == .photo || primaryReviewAttachment?.attachmentType == .photo {
            return .photo
        }

        return .other
    }

    var shouldShowOCRStatus: Bool {
        guard originalOCRText.reviewPreviewText.isEmpty else {
            return false
        }

        if primaryReviewAttachment?.attachmentType == .textNote || category == .note {
            return false
        }

        return category == .photo ||
            category == .screenshot ||
            category == .receipt ||
            category == .document ||
            category == .email ||
            primaryReviewAttachment?.attachmentType == .photo ||
            primaryReviewAttachment?.attachmentType == .screenshot ||
            primaryReviewAttachment?.attachmentType == .pdf ||
            primaryReviewAttachment?.attachmentType == .document
    }

    var ocrHasFinished: Bool {
        originalOCRCompletedAt != nil ||
            primaryReviewAttachment?.originalOCRCompletedAt != nil
    }

    private var reviewSearchableText: String {
        [
            userTitle,
            originalOCRText,
            primaryReviewAttachment?.originalFilename ?? ""
        ]
            .joined(separator: " ")
            .lowercased()
    }
}

private extension String {
    var reviewFilenameTitle: String {
        URL(filePath: self)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .reviewCleanedText
    }

    func containsAnyReviewTerm(_ terms: [String]) -> Bool {
        terms.contains { contains($0) }
    }
}

#Preview {
    EvidenceInboxView(
        caseFile: CaseFile(
            caseType: .tenantLandlord,
            userTitle: "Ceiling leak case",
            evidenceItems: [
                EvidenceItem(
                    category: .photo,
                    userTitle: "Ceiling leak photo",
                    detectedEventDate: .now,
                    detectedDateSource: .visionOCR,
                    originalOCRText: "",
                    originalOCRCompletedAt: .now
                ),
                EvidenceItem(
                    category: .message,
                    userTitle: "Landlord message screenshot",
                    originalOCRText: "I will send someone next week. Please stop texting about the leak.",
                    originalOCRCompletedAt: .now
                ),
                EvidenceItem(
                    category: .receipt,
                    userTitle: "Repair receipt",
                    originalOCRText: "Emergency plumbing visit paid $185.00 on May 6, 2026.",
                    originalOCRCompletedAt: .now
                ),
                EvidenceItem(
                    category: .photo,
                    userTitle: "Wall damage photo",
                    originalOCRText: "",
                    originalOCRCompletedAt: .now
                ),
                EvidenceItem(
                    category: .screenshot,
                    userTitle: "Maintenance portal screenshot",
                    originalOCRText: "Ticket #4182 Status: open Submitted May 4",
                    originalOCRCompletedAt: .now
                ),
                EvidenceItem(
                    category: .email,
                    userTitle: "Property manager email",
                    originalOCRText: "Subject: Re: bedroom ceiling leak",
                    originalOCRCompletedAt: .now
                ),
                EvidenceItem(
                    category: .document,
                    userTitle: "Contractor estimate",
                    originalOCRText: "",
                    originalOCRCompletedAt: nil
                )
            ]
        )
    )
    .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self], inMemory: true)
}
