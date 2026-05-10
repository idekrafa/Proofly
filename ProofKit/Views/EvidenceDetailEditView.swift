import QuickLook
import SwiftData
import SwiftUI
import UIKit

struct EvidenceDetailEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.proofKitServices) private var services

    @Bindable var evidenceItem: EvidenceItem

    @State private var hasEventDate: Bool
    @State private var eventDate: Date
    @State private var title: String
    @State private var category: EvidenceCategory
    @State private var userNote: String
    @State private var cleanedNote: String
    @State private var whyThisMatters: String
    @State private var userMarkedImportant: Bool
    @State private var saveMessage: String?
    @State private var saveErrorMessage: String?
    @State private var aiCleanupMessage: String?
    @State private var aiCleanupErrorMessage: String?
    @State private var isCleaningNoteWithAI = false
    @State private var isOriginalOCRExpanded = false
    @State private var originalFilePreviewURL: URL?
    @State private var isDeleteConfirmationPresented = false
    @State private var savedSnapshot: EvidenceEditSnapshot

    private static let editableProofTypeCategories: [EvidenceCategory] = [
        .photo,
        .screenshot,
        .document,
        .message,
        .receipt,
        .other
    ]

    init(evidenceItem: EvidenceItem) {
        self.evidenceItem = evidenceItem

        let currentEventDate = evidenceItem.eventDate
        let editableTitle = Self.initialEditableTitle(for: evidenceItem)
        let editableCategory = Self.editableProofTypeCategory(for: evidenceItem.category)
        let initialSnapshot = EvidenceEditSnapshot(
            hasEventDate: currentEventDate != nil,
            eventDate: currentEventDate,
            title: editableTitle.detailTrimmedText,
            category: editableCategory,
            userNote: evidenceItem.userNotes.detailTrimmedText,
            cleanedNote: evidenceItem.userCleanedNote.detailTrimmedText,
            whatThisProves: evidenceItem.userWhyThisMatters.detailTrimmedText,
            userMarkedImportant: evidenceItem.userMarkedImportant
        )

        _hasEventDate = State(initialValue: currentEventDate != nil)
        _eventDate = State(initialValue: currentEventDate ?? .now)
        _title = State(initialValue: editableTitle)
        _category = State(initialValue: editableCategory)
        _userNote = State(initialValue: evidenceItem.userNotes)
        _cleanedNote = State(initialValue: evidenceItem.userCleanedNote)
        _whyThisMatters = State(initialValue: evidenceItem.userWhyThisMatters)
        _userMarkedImportant = State(initialValue: evidenceItem.userMarkedImportant)
        _savedSnapshot = State(initialValue: initialSnapshot)
    }

    private var primaryAttachment: Attachment? {
        evidenceItem.sortedAttachments.first { attachment in
            attachment.thumbnailLocalFilePath != nil
        } ?? evidenceItem.sortedAttachments.first
    }

    private var canSave: Bool {
        hasUnsavedChanges && !title.detailTrimmedText.isEmpty
    }

    private var hasUnsavedChanges: Bool {
        !currentSnapshot.matches(savedSnapshot)
    }

    private var shouldShowProofNameSaveHelper: Bool {
        hasUnsavedChanges && title.detailTrimmedText.isEmpty
    }

    private var currentSnapshot: EvidenceEditSnapshot {
        EvidenceEditSnapshot(
            hasEventDate: hasEventDate,
            eventDate: hasEventDate ? eventDate : nil,
            title: title.detailTrimmedText,
            category: category,
            userNote: userNote.detailTrimmedText,
            cleanedNote: cleanedNote.detailTrimmedText,
            whatThisProves: whyThisMatters.detailTrimmedText,
            userMarkedImportant: userMarkedImportant
        )
    }

    private var summaryTitle: String {
        let trimmedTitle = title.detailTrimmedText
        return trimmedTitle.isEmpty ? "Add a clear proof name" : trimmedTitle
    }

    private var summaryTitleIsPlaceholder: Bool {
        title.detailTrimmedText.isEmpty
    }

    private var proofTypeText: String {
        Self.proofTypeDisplayName(for: category)
    }

    private var proofTypeSystemImage: String {
        switch category {
        case .photo:
            return "photo"
        case .screenshot:
            return "rectangle.on.rectangle"
        case .document, .contract, .note:
            return "doc"
        case .message, .email:
            return "message"
        case .receipt:
            return "receipt"
        case .uncategorized, .other:
            return "paperclip"
        }
    }

    private var sourceText: String {
        guard let primaryAttachment else {
            return "Manual entry"
        }

        return sourceDescription(for: primaryAttachment)
    }

    private var originalFilenameText: String {
        guard let primaryAttachment else {
            return "No file attached"
        }

        let originalFilename = primaryAttachment.originalFilename.detailTrimmedText
        guard !originalFilename.isEmpty else {
            return "Not available"
        }

        if Self.isGenericProofKitImageName(originalFilename) {
            return "Original filename unavailable"
        }

        return originalFilename
    }

    private var importedDateText: String {
        if let primaryAttachment {
            return ProofKitDateFormatting.shortDateTime(primaryAttachment.createdAt)
        }

        return ProofKitDateFormatting.shortDateTime(evidenceItem.createdAt)
    }

    private var fileSizeText: String {
        formattedFileSize(primaryAttachment?.fileSizeBytes)
    }

    private var originalFileURL: URL? {
        guard
            let path = primaryAttachment?.localFilePath.detailTrimmedText,
            !path.isEmpty
        else {
            return nil
        }

        return URL(filePath: path)
    }

    private var ocrStatusText: String {
        originalOCRText.isEmpty ? "No text detected" : "Text detected"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ProofKitVisual.cardSpacing) {
                evidenceSummarySection
                    .proofKitAppear()
                coreDetailsSection
                    .proofKitAppear(delay: 0.04)
                notesSection
                    .proofKitAppear(delay: 0.08)
                originalOCRSection
                    .proofKitAppear(delay: 0.12)
                metadataSection
                    .proofKitAppear(delay: 0.16)
                fileActionsSection
                    .proofKitAppear(delay: 0.2)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 154)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Edit Proof")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .quickLookPreview($originalFilePreviewURL)
        .confirmationDialog(
            "Delete proof from this case?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete from case", role: .destructive) {
                deleteFromCase()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the proof from this case. Your original file stays on this device unless you delete it separately.")
        }
        .animation(ProofKitMotion.standard, value: saveMessage)
        .animation(ProofKitMotion.standard, value: saveErrorMessage)
        .animation(ProofKitMotion.standard, value: aiCleanupMessage)
        .animation(ProofKitMotion.standard, value: aiCleanupErrorMessage)
        .animation(ProofKitMotion.standard, value: isCleaningNoteWithAI)
    }

    private var evidenceSummarySection: some View {
        EvidenceDetailCard {
            VStack(alignment: .leading, spacing: 14) {
                EvidenceDetailFieldHeader(
                    title: "Proof preview",
                    subtitle: "Original file is stored locally and never overwritten."
                )

                HStack(alignment: .top, spacing: 14) {
                    if let primaryAttachment {
                        EvidenceAttachmentPreview(attachment: primaryAttachment)
                    } else {
                        EvidenceNoAttachmentState()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(summaryTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(summaryTitleIsPlaceholder ? ProofKitVisual.helperText : .primary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 7) {
                            EvidenceSummaryChip(
                                systemImage: proofTypeSystemImage,
                                text: "Proof type: \(proofTypeText)"
                            )
                            EvidenceSummaryChip(
                                systemImage: "photo.on.rectangle",
                                text: "Source: \(sourceText)"
                            )
                            EvidenceSummaryChip(
                                systemImage: originalOCRText.isEmpty ? "text.viewfinder" : "checkmark.viewfinder",
                                text: "OCR: \(ocrStatusText)"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var coreDetailsSection: some View {
        EvidenceDetailCard {
            VStack(alignment: .leading, spacing: ProofKitVisual.sectionSpacing) {
                EvidenceDetailFieldHeader(
                    title: "Proof details",
                    subtitle: "Use a human-readable name for the proof. The original filename stays separate below."
                )

                VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                    EvidenceDetailFieldHeader(
                        title: "Event date",
                        subtitle: "Use the date this happened, or the date this record refers to."
                    )

                    Toggle("Use event date", isOn: animatedEventDateToggleBinding)
                        .font(.subheadline.weight(.medium))

                    if hasEventDate {
                        DatePicker(
                            "Event date",
                            selection: $eventDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .transition(ProofKitMotion.compactInsertion)
                    } else if let detectedEventDate = evidenceItem.detectedEventDate {
                        Text("A locally detected date is still available: \(ProofKitDateFormatting.shortDate(detectedEventDate)).")
                            .font(.footnote)
                            .foregroundStyle(ProofKitVisual.helperText)
                            .transition(ProofKitMotion.compactInsertion)
                    }
                }

                VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                    EvidenceDetailFieldHeader(title: "Proof name")

                    TextField("Ceiling leak photo", text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.sentences)
                        .padding(12)
                        .proofKitFieldBackground()

                    if shouldShowProofNameSaveHelper {
                        Text("Add a proof name to save changes.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(ProofKitMotion.compactInsertion)
                    } else {
                        Text("Example: Ceiling leak photo. Avoid using the filename as the proof name.")
                            .font(.footnote)
                            .foregroundStyle(ProofKitVisual.helperText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                    EvidenceDetailFieldHeader(title: "Proof type")

                    Picker("Proof type", selection: $category) {
                        ForEach(Self.editableProofTypeCategories, id: \.id) { category in
                            Text(Self.proofTypeDisplayName(for: category))
                                .tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .proofKitFieldBackground()
                }
            }
        }
    }

    private var notesSection: some View {
        EvidenceDetailCard {
            VStack(alignment: .leading, spacing: ProofKitVisual.sectionSpacing) {
                EvidenceDetailFieldHeader(
                    title: "Notes",
                    subtitle: "Keep your own context separate from OCR and any AI cleanup."
                )

                VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                    EvidenceDetailFieldHeader(
                        title: "Your note",
                        subtitle: "Your original context and observations."
                    )

                    EvidenceDetailTextEditor(
                        text: $userNote,
                        minHeight: 112,
                        accessibilityLabel: "Your note"
                    )
                }

                VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                    HStack(alignment: .top, spacing: 12) {
                        EvidenceDetailFieldHeader(
                            title: "AI-cleaned note",
                            subtitle: "A tidy version you can use later in the case. AI cleanup does not change your note or OCR text."
                        )

                        Spacer(minLength: 12)

                        Button {
                            Task {
                                await cleanUpNoteWithAI()
                            }
                        } label: {
                            HStack(spacing: 7) {
                                if isCleaningNoteWithAI {
                                    ProgressView()
                                        .controlSize(.small)
                                        .transition(.opacity)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.footnote.weight(.semibold))
                                        .transition(.opacity)
                                }

                                Text(isCleaningNoteWithAI ? "Cleaning…" : "Clean up with AI")
                                    .font(.footnote.weight(.semibold))
                                    .contentTransition(.opacity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCleaningNoteWithAI || userNote.detailTrimmedText.isEmpty)
                    }

                    EvidenceDetailTextEditor(
                        text: $cleanedNote,
                        minHeight: 112,
                        accessibilityLabel: "AI-cleaned note"
                    )

                    if userNote.detailTrimmedText.isEmpty {
                        Text("Add a note to clean it up with AI.")
                            .font(.caption)
                            .foregroundStyle(ProofKitVisual.helperText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("AI only sees your note, selected OCR text, and basic details. Raw files stay on this device.")
                        .font(.caption)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Uses 1 AI credit. Local OCR and proof editing are free.")
                        .font(.caption)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let aiCleanupMessage {
                        Text(aiCleanupMessage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ProofKitVisual.helperText)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(ProofKitMotion.compactInsertion)
                    }

                    if let aiCleanupErrorMessage {
                        Text(aiCleanupErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(ProofKitMotion.compactInsertion)
                    }
                }

                VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                    EvidenceDetailFieldHeader(
                        title: "What this proves",
                        subtitle: "Describe what this record helps show or explain."
                    )

                    EvidenceDetailTextEditor(
                        text: $whyThisMatters,
                        minHeight: 92,
                        accessibilityLabel: "What this proves"
                    )
                }

                Toggle(isOn: $userMarkedImportant) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mark important")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Show this first when building your timeline.")
                            .font(.footnote)
                            .foregroundStyle(ProofKitVisual.helperText)
                    }
                }
            }
        }
    }

    private var originalOCRSection: some View {
        EvidenceDetailCard {
            DisclosureGroup(isExpanded: animatedOCRBinding) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Read-only source text captured locally by Apple Vision. Editing notes above does not change this original OCR output.")
                        .font(.footnote)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)

                    if originalOCRText.isEmpty {
                        Text("No text detected.")
                            .font(.subheadline)
                            .foregroundStyle(ProofKitVisual.subduedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(ProofKitVisual.fieldBackground)
                            }
                    } else {
                        ScrollView {
                            Text(originalOCRText)
                                .font(.footnote.monospaced())
                                .foregroundStyle(ProofKitVisual.helperText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(12)
                        }
                        .frame(minHeight: 160, maxHeight: 280)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(ProofKitVisual.fieldBackground)
                        }
                    }
                }
                .padding(.top, 12)
                .transition(ProofKitMotion.compactInsertion)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Original OCR text")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(ocrStatusText)
                        .font(.footnote)
                        .foregroundStyle(ProofKitVisual.helperText)
                }
            }
        }
    }

    private var animatedEventDateToggleBinding: Binding<Bool> {
        Binding(
            get: { hasEventDate },
            set: { newValue in
                withAnimation(ProofKitMotion.standard) {
                    hasEventDate = newValue
                }
            }
        )
    }

    private var animatedOCRBinding: Binding<Bool> {
        Binding(
            get: { isOriginalOCRExpanded },
            set: { newValue in
                withAnimation(ProofKitMotion.softSpring) {
                    isOriginalOCRExpanded = newValue
                }
            }
        )
    }

    private var metadataSection: some View {
        EvidenceDetailCard {
            VStack(alignment: .leading, spacing: 14) {
                EvidenceDetailFieldHeader(
                    title: "File details",
                    subtitle: "Metadata is shown separately from the proof name so the proof reads clearly."
                )

                VStack(spacing: 0) {
                    EvidenceMetadataRow(
                        title: "Original file",
                        value: originalFilenameText
                    )
                    EvidenceMetadataRow(
                        title: "Source",
                        value: sourceText
                    )
                    EvidenceMetadataRow(
                        title: "OCR",
                        value: ocrStatusText
                    )
                    EvidenceMetadataRow(
                        title: "Imported",
                        value: importedDateText
                    )
                    EvidenceMetadataRow(
                        title: "File size",
                        value: fileSizeText
                    )
                }
            }
        }
    }

    private var fileActionsSection: some View {
        EvidenceDetailCard {
            VStack(alignment: .leading, spacing: ProofKitVisual.sectionSpacing) {
                EvidenceDetailFieldHeader(
                    title: "File actions",
                    subtitle: "View the local original or remove this proof from the case."
                )

                VStack(spacing: 10) {
                    Button {
                        viewOriginalFile()
                    } label: {
                        Label("View original file", systemImage: "doc.viewfinder")
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(originalFileURL == nil)

                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Label("Delete from case", systemImage: "trash")
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(.red)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var bottomActionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let saveMessage {
                Text(saveMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(ProofKitMotion.compactInsertion)
            }

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(ProofKitMotion.compactInsertion)
            }

            Button {
                saveChanges()
            } label: {
                Text("Save changes")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(.label))
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ProofKitVisual.divider)
                .frame(height: 1)
        }
    }

    private var originalOCRText: String {
        let itemText = evidenceItem.originalOCRText.detailTrimmedText
        if !itemText.isEmpty {
            return itemText
        }

        return evidenceItem.sortedAttachments
            .map(\.originalOCRText)
            .map { $0.detailTrimmedText }
            .first { !$0.isEmpty } ?? ""
    }

    private static func initialEditableTitle(for evidenceItem: EvidenceItem) -> String {
        let trimmedTitle = evidenceItem.userTitle.detailTrimmedText
        return isGenericProofKitImageName(trimmedTitle) ? "" : trimmedTitle
    }

    private static func isGenericProofKitImageName(_ value: String) -> Bool {
        let trimmedValue = value.detailTrimmedText
        guard !trimmedValue.isEmpty else { return false }

        if trimmedValue.caseInsensitiveCompare("Imported image") == .orderedSame {
            return true
        }

        return trimmedValue.range(
            of: #"^(ProofKit|Proofly) Image [0-9]+(\.[A-Za-z0-9]+)?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func editableProofTypeCategory(for category: EvidenceCategory) -> EvidenceCategory {
        switch category {
        case .photo:
            return .photo
        case .screenshot:
            return .screenshot
        case .document, .contract, .note:
            return .document
        case .message, .email:
            return .message
        case .receipt:
            return .receipt
        case .uncategorized, .other:
            return .other
        }
    }

    private static func proofTypeDisplayName(for category: EvidenceCategory) -> String {
        switch editableProofTypeCategory(for: category) {
        case .photo:
            return "Photo"
        case .screenshot:
            return "Screenshot"
        case .document:
            return "Document"
        case .message:
            return "Message"
        case .receipt:
            return "Receipt"
        case .other:
            return "Other"
        case .uncategorized, .email, .contract, .note:
            return "Other"
        }
    }

    private func sourceDescription(for attachment: Attachment) -> String {
        if let source = importedMetadataValue("source", for: attachment) {
            switch source {
            case "PhotosPicker":
                return "Photos Library"
            case "FilesPicker", "DocumentPicker":
                return "Files app"
            default:
                return source
            }
        }

        switch attachment.attachmentType {
        case .photo, .screenshot:
            return "Photos Library"
        case .pdf, .document:
            return "Files app"
        case .textNote:
            return "Manual entry"
        case .other:
            return "Local file"
        }
    }

    private func importedMetadataValue(_ key: String, for attachment: Attachment) -> String? {
        guard
            let data = attachment.importedMetadataJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = object[key] as? String
        else {
            return nil
        }

        let trimmedValue = value.detailTrimmedText
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func saveChanges() {
        let trimmedTitle = title.detailTrimmedText
        guard !trimmedTitle.isEmpty else {
            withAnimation(ProofKitMotion.standard) {
                saveMessage = nil
                saveErrorMessage = nil
            }
            return
        }

        let wasReviewed = evidenceItem.isReviewed

        evidenceItem.userTitle = trimmedTitle
        if shouldPersistProofType {
            evidenceItem.category = category
        }
        evidenceItem.userNotes = userNote.detailTrimmedText
        evidenceItem.userCleanedNote = cleanedNote.detailTrimmedText
        evidenceItem.userWhyThisMatters = whyThisMatters.detailTrimmedText
        evidenceItem.userMarkedImportant = userMarkedImportant

        if hasEventDate {
            if shouldSaveUserEventDate {
                evidenceItem.userProvidedEventDate = eventDate
                evidenceItem.userDateSource = .userEntered
            }
        } else {
            evidenceItem.userProvidedEventDate = nil
            evidenceItem.userDateSource = .notSpecified
        }

        let now = Date()
        evidenceItem.isReviewed = true
        evidenceItem.reviewedAt = now
        evidenceItem.updatedAt = now
        evidenceItem.caseFile?.updatedAt = now

        do {
            try modelContext.save()
            services.analytics.trackTimelineItemEdited(evidenceItem)
            if !wasReviewed {
                services.analytics.trackProofReviewed(evidenceItem)
                services.analytics.trackProofAddedToTimeline(evidenceItem)
            }
            withAnimation(ProofKitMotion.standard) {
                savedSnapshot = currentSnapshot
                saveMessage = "Saved locally."
                saveErrorMessage = nil
            }
        } catch {
            withAnimation(ProofKitMotion.standard) {
                saveMessage = nil
                saveErrorMessage = "Changes could not be saved. Please try again."
            }
        }
    }

    private func viewOriginalFile() {
        guard let originalFileURL else {
            withAnimation(ProofKitMotion.standard) {
                saveMessage = nil
                saveErrorMessage = "No original file is linked to this proof."
            }
            return
        }

        guard FileManager.default.fileExists(atPath: originalFileURL.path(percentEncoded: false)) else {
            withAnimation(ProofKitMotion.standard) {
                saveMessage = nil
                saveErrorMessage = "The local original file could not be found on this device."
            }
            return
        }

        withAnimation(ProofKitMotion.standard) {
            saveMessage = nil
            saveErrorMessage = nil
        }
        originalFilePreviewURL = originalFileURL
    }

    private func deleteFromCase() {
        do {
            try EvidenceDeletionService.deleteFromCase(evidenceItem, modelContext: modelContext)
            dismiss()
        } catch {
            withAnimation(ProofKitMotion.standard) {
                saveMessage = nil
                saveErrorMessage = "This proof could not be deleted. Please try again."
            }
        }
    }

    private func cleanUpNoteWithAI() async {
        let trimmedUserNote = userNote.detailTrimmedText
        guard !trimmedUserNote.isEmpty else {
            withAnimation(ProofKitMotion.standard) {
                aiCleanupMessage = nil
                aiCleanupErrorMessage = "Add a note to clean it up with AI."
            }
            return
        }

        let analyticsActionType = AnalyticsAIActionType.other
        let analyticsStartedAt = Date()
        services.analytics.trackAIActionStarted(actionType: analyticsActionType)

        withAnimation(ProofKitMotion.standard) {
            isCleaningNoteWithAI = true
            aiCleanupMessage = nil
            aiCleanupErrorMessage = nil
            saveMessage = nil
            saveErrorMessage = nil
        }

        do {
            withAnimation(ProofKitMotion.standard) {
                aiCleanupMessage = "Checking AI credits…"
            }
            _ = try await requireAvailableAICredits()
            withAnimation(ProofKitMotion.standard) {
                aiCleanupMessage = "Cleaning note with the text-only AI proxy…"
            }

            let result = try await services.aiRouter.cleanUpNote(
                for: evidenceItem,
                userNote: trimmedUserNote,
                in: modelContext,
                userTriggered: true
            )

            let rewrittenNote = result.outputText.detailTrimmedText
            guard !rewrittenNote.isEmpty else {
                throw ProofKitError.remotePolicyViolation("The AI proxy returned an empty rewrite.")
            }

            withAnimation(ProofKitMotion.standard) {
                cleanedNote = rewrittenNote
            }
            evidenceItem.userNotes = trimmedUserNote
            evidenceItem.userCleanedNote = rewrittenNote

            let now = Date()
            evidenceItem.updatedAt = now
            evidenceItem.caseFile?.updatedAt = now

            try modelContext.save()

            let durationMS = Self.analyticsDurationMS(since: analyticsStartedAt)
            services.analytics.trackAIActionCompleted(
                actionType: analyticsActionType,
                creditsSpent: result.creditsUsed,
                creditsRemaining: result.remainingCredits,
                durationMS: durationMS
            )
            if let creditsUsed = result.creditsUsed, creditsUsed > 0 {
                services.analytics.trackAICreditsSpent(
                    actionType: analyticsActionType,
                    creditsSpent: creditsUsed,
                    creditsRemaining: result.remainingCredits
                )
            }

            withAnimation(ProofKitMotion.standard) {
                savedSnapshot.userNote = trimmedUserNote
                savedSnapshot.cleanedNote = rewrittenNote
                aiCleanupMessage = cleanupSuccessMessage(for: result)
                aiCleanupErrorMessage = nil
            }
        } catch {
            services.analytics.trackAIActionFailed(
                actionType: analyticsActionType,
                durationMS: Self.analyticsDurationMS(since: analyticsStartedAt),
                errorType: AnalyticsErrorType(error)
            )
            withAnimation(ProofKitMotion.standard) {
                aiCleanupMessage = nil
                aiCleanupErrorMessage = cleanupErrorMessage(for: error)
            }
        }

        withAnimation(ProofKitMotion.standard) {
            isCleaningNoteWithAI = false
        }
    }

    private func requireAvailableAICredits() async throws -> AICreditBalance {
        let planDecision = await services.paywall.canUseAI()
        guard planDecision.isAllowed else {
            throw ProofKitError.planLimitReached(planDecision.message)
        }

        guard services.account.isConfigured else {
            throw ProofKitError.supabaseNotConfigured
        }

        let balance = try await services.aiCredits.fetchAICreditBalance()
        guard balance.availableCredits > 0 else {
            throw ProofKitError.remotePolicyViolation(
                "You’re out of AI credits. Local OCR, importing, timeline editing, and free watermarked exports still work."
            )
        }

        return balance
    }

    private var shouldPersistProofType: Bool {
        category != savedSnapshot.category ||
            Self.editableProofTypeCategories.contains(evidenceItem.category)
    }

    private var shouldSaveUserEventDate: Bool {
        guard hasEventDate else { return false }

        if evidenceItem.userProvidedEventDate != nil {
            return true
        }

        guard let currentPersistedEventDate = evidenceItem.eventDate else {
            return true
        }

        return !Calendar.current.isDate(eventDate, inSameDayAs: currentPersistedEventDate)
    }

    private static func analyticsDurationMS(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }

    private func formattedFileSize(_ bytes: Int64?) -> String {
        guard let bytes else {
            return "—"
        }

        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func cleanupSuccessMessage(for result: AITaskRouteResult) -> String {
        if result.wasCacheHit {
            return "AI-cleaned note restored from local cache. No new AI credits were used."
        }

        if let remainingCredits = result.remainingCredits {
            if let creditsUsed = result.creditsUsed {
                return "AI-cleaned note saved locally. \(creditsUsed) AI credit\(creditsUsed == 1 ? "" : "s") used server-side. \(remainingCredits) remaining."
            }

            return "AI-cleaned note saved locally. Credits were handled server-side. \(remainingCredits) remaining."
        }

        return "AI-cleaned note saved locally. Credits were handled server-side."
    }

    private func cleanupErrorMessage(for error: Error) -> String {
        if let proofKitError = error as? ProofKitError {
            switch proofKitError {
            case .supabaseNotConfigured:
                return "AI credits are not configured for this build. Local OCR and proof organization still work."
            case .supabaseSDKUnavailable:
                return "AI credits are unavailable in this build. Local OCR and proof organization still work."
            default:
                break
            }
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return "Proofly could not clean up this note. Please try again."
    }
}

private struct EvidenceEditSnapshot {
    var hasEventDate: Bool
    var eventDate: Date?
    var title: String
    var category: EvidenceCategory
    var userNote: String
    var cleanedNote: String
    var whatThisProves: String
    var userMarkedImportant: Bool

    func matches(_ other: EvidenceEditSnapshot, calendar: Calendar = .current) -> Bool {
        hasEventDate == other.hasEventDate &&
            eventDateMatches(other.eventDate, calendar: calendar) &&
            title == other.title &&
            category == other.category &&
            userNote == other.userNote &&
            cleanedNote == other.cleanedNote &&
            whatThisProves == other.whatThisProves &&
            userMarkedImportant == other.userMarkedImportant
    }

    private func eventDateMatches(_ otherDate: Date?, calendar: Calendar) -> Bool {
        switch (eventDate, otherDate) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return calendar.isDate(lhs, inSameDayAs: rhs)
        default:
            return false
        }
    }
}

private struct EvidenceNoAttachmentState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ProofKitVisual.helperText)
                .accessibilityHidden(true)

            Text("No file")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ProofKitVisual.helperText)
        }
        .frame(width: 118, height: 118)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ProofKitVisual.fieldBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
        .accessibilityLabel("No attachment linked")
    }
}

private struct EvidenceAttachmentPreview: View {
    let attachment: Attachment

    var body: some View {
        preview
            .frame(width: 118, height: 118)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
            }
            .accessibilityLabel("Attachment preview")
    }

    @ViewBuilder
    private var preview: some View {
        if
            let path = attachment.thumbnailLocalFilePath ?? imagePreviewPath,
            let image = UIImage(contentsOfFile: path)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            VStack(spacing: 8) {
                Image(systemName: evidenceAttachmentSystemImage(for: attachment.attachmentType))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.helperText)

                Text("Preview unavailable")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.helperText)
                    .multilineTextAlignment(.center)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ProofKitVisual.fieldBackground)
        }
    }

    private var imagePreviewPath: String? {
        switch attachment.attachmentType {
        case .photo, .screenshot:
            attachment.localFilePath
        case .pdf, .document, .textNote, .other:
            nil
        }
    }
}

private struct EvidenceSummaryChip: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ProofKitVisual.helperText)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(ProofKitVisual.helperText)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(ProofKitVisual.fieldBackground)
        }
    }
}

private struct EvidenceMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ProofKitVisual.helperText)
                .tracking(0.3)

            Text(value.isEmpty ? "—" : value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ProofKitVisual.divider)
                .frame(height: 1)
        }
    }
}

private struct EvidenceDetailCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(ProofKitVisual.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous)
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
    }
}

private struct EvidenceDetailFieldHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct EvidenceDetailTextEditor: View {
    @Binding var text: String
    let minHeight: CGFloat
    let accessibilityLabel: String

    var body: some View {
        TextEditor(text: $text)
            .frame(minHeight: minHeight)
            .padding(10)
            .scrollContentBackground(.hidden)
            .proofKitFieldBackground()
            .accessibilityLabel(accessibilityLabel)
    }
}

private func evidenceAttachmentSystemImage(for type: AttachmentType) -> String {
    switch type {
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

private extension String {
    var detailTrimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum EvidenceDetailEditPreviewData {
    static func makeEvidenceItem() -> EvidenceItem {
        let imageURL = makeCeilingLeakPhotoURL()
        let imageSize = (try? Data(contentsOf: imageURL).count).map(Int64.init)
        let evidenceItem = EvidenceItem(
            category: .photo,
            userDateSource: .userEntered,
            userTitle: "Ceiling leak photo",
            userNotes: "Water stains spread across the bedroom ceiling after the overnight leak.",
            userCleanedNote: "Photo showing ceiling staining and moisture from the bedroom leak.",
            userWhyThisMatters: "Shows the condition before a repair visit.",
            userProvidedEventDate: .now,
            userMarkedImportant: true,
            originalOCRText: ""
        )
        let attachment = Attachment(
            attachmentType: .photo,
            originalFilename: "IMG_4821.jpeg",
            localFilePath: imageURL.path(percentEncoded: false),
            thumbnailLocalFilePath: imageURL.path(percentEncoded: false),
            uniformTypeIdentifier: "public.jpeg",
            fileSizeBytes: imageSize,
            importedMetadataJSON: "{\"source\":\"PhotosPicker\",\"localOnly\":true}",
            createdAt: .now,
            updatedAt: .now,
            evidenceItem: evidenceItem
        )
        evidenceItem.attachments.append(attachment)
        return evidenceItem
    }

    private static func makeCeilingLeakPhotoURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "proofkit-ceiling-leak-photo-preview")
            .appendingPathExtension("jpeg")

        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            return url
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 680))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 900, height: 680)
            UIColor(red: 0.78, green: 0.75, blue: 0.68, alpha: 1).setFill()
            context.fill(rect)

            UIColor(red: 0.58, green: 0.55, blue: 0.48, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 512, width: 900, height: 168))

            UIColor(red: 0.91, green: 0.88, blue: 0.78, alpha: 1).setFill()
            context.fill(CGRect(x: 42, y: 38, width: 816, height: 456))

            UIColor(red: 0.74, green: 0.62, blue: 0.42, alpha: 0.55).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 318, y: 126, width: 280, height: 150))
            UIColor(red: 0.50, green: 0.38, blue: 0.22, alpha: 0.32).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 374, y: 158, width: 172, height: 92))

            UIColor(red: 0.43, green: 0.34, blue: 0.25, alpha: 0.42).setStroke()
            let dripPath = UIBezierPath()
            dripPath.lineWidth = 9
            dripPath.move(to: CGPoint(x: 450, y: 238))
            dripPath.addCurve(
                to: CGPoint(x: 435, y: 358),
                controlPoint1: CGPoint(x: 470, y: 280),
                controlPoint2: CGPoint(x: 424, y: 308)
            )
            dripPath.stroke()

            UIColor(red: 0.36, green: 0.30, blue: 0.24, alpha: 0.26).setStroke()
            let crackPath = UIBezierPath()
            crackPath.lineWidth = 5
            crackPath.move(to: CGPoint(x: 523, y: 202))
            crackPath.addLine(to: CGPoint(x: 592, y: 228))
            crackPath.addLine(to: CGPoint(x: 650, y: 224))
            crackPath.stroke()

            UIColor(white: 1, alpha: 0.10).setFill()
            context.fill(CGRect(x: 76, y: 72, width: 748, height: 34))
            UIColor(white: 0, alpha: 0.16).setFill()
            context.fill(CGRect(x: 74, y: 492, width: 752, height: 10))
        }

        if let data = image.jpegData(compressionQuality: 0.86) {
            try? data.write(to: url, options: [.atomic])
        }

        return url
    }
}

#Preview {
    let evidenceItem = EvidenceDetailEditPreviewData.makeEvidenceItem()

    NavigationStack {
        EvidenceDetailEditView(evidenceItem: evidenceItem)
    }
    .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self, AIResultCache.self], inMemory: true)
}
