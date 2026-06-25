import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AddProofImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.proofKitServices) private var services

    @Bindable var caseFile: CaseFile
    let onManualEntryRequested: () -> Void
    let onImportComplete: ([EvidenceItem]) -> Void

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isDocumentImporterPresented = false
    @State private var isImporting = false
    @State private var importErrorMessage: String?
    @State private var entitlementSnapshot = ProofKitEntitlementSnapshot.placeholder()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                topBar

                VStack(alignment: .leading, spacing: 18) {
                    intro
                        .proofKitAppear()
                    limitStatus
                        .proofKitAppear(delay: 0.04)
                    importOptions
                        .proofKitAppear(delay: 0.08)

                    if isImporting {
                        importingState
                            .transition(ProofKitMotion.compactInsertion)
                    }

                    if let importErrorMessage {
                        Text(importErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(ProofKitMotion.compactInsertion)
                    }
                }
            }
            .frame(maxWidth: 620, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)
                Color(.systemGroupedBackground)
                    .opacity(0.72)
            }
            .ignoresSafeArea()
        }
        .animation(ProofKitMotion.standard, value: isImporting)
        .animation(ProofKitMotion.standard, value: importErrorMessage)
        .presentationDetents([.custom(AddProofMediumSheetDetent.self)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(.regularMaterial)
        .presentationBackgroundInteraction(.disabled)
        .interactiveDismissDisabled(isImporting)
        .fileImporter(
            isPresented: $isDocumentImporterPresented,
            allowedContentTypes: supportedDocumentContentTypes,
            allowsMultipleSelection: true
        ) { result in
            Task {
                await importSelectedDocumentURLs(result)
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }

            Task {
                await importSelectedPhotoItems(newItems)
            }
        }
        .task {
            entitlementSnapshot = await services.paywall.currentEntitlement()
        }
    }

    private var topBar: some View {
        ZStack {
            Text("Add Proof")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .font(.body)
                .disabled(isImporting)

                Spacer()
            }
        }
        .frame(height: 44)
        .accessibilityElement(children: .contain)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What proof are you adding?")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .kerning(-0.35)

            Text("Imports stay local. OCR runs on your device first.")
                .font(.subheadline)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var importOptions: some View {
        VStack(spacing: 12) {
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: photoSelectionLimit,
                matching: .images,
                photoLibrary: .shared()
            ) {
                AddProofOptionRow(
                    emoji: "📸",
                    title: String(localized: "Photos or screenshots"),
                    subtitle: String(localized: "Add messages, damage photos, receipts, or proof.")
                )
            }
            .buttonStyle(AddProofOptionButtonStyle())
            .disabled(isImporting || evidenceSlotsAreFull)

            Button {
                isDocumentImporterPresented = true
            } label: {
                AddProofOptionRow(
                    emoji: "📄",
                    title: String(localized: "PDF or document"),
                    subtitle: String(localized: "Add leases, forms, letters, or official files.")
                )
            }
            .buttonStyle(AddProofOptionButtonStyle())
            .disabled(isImporting || evidenceSlotsAreFull)

            Button {
                services.analytics.trackProofAddStarted(caseFile: caseFile, proofType: .note, sourceScreen: .addProof)
                onManualEntryRequested()
            } label: {
                AddProofOptionRow(
                    emoji: "✍️",
                    title: String(localized: "Timeline note"),
                    subtitle: String(localized: "Write what happened when there’s no file.")
                )
            }
            .buttonStyle(AddProofOptionButtonStyle())
            .disabled(isImporting || evidenceSlotsAreFull)
        }
        .animation(ProofKitMotion.standard, value: isImporting)
    }

    @ViewBuilder
    private var limitStatus: some View {
        if let evidenceItemLimit = entitlementSnapshot.limits.evidenceItemLimit {
            let currentCount = caseFile.evidenceItems.count
            let remainingCount = max(0, evidenceItemLimit - currentCount)

            HStack(spacing: 10) {
                Image(systemName: remainingCount == 0 ? "lock.fill" : "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(remainingCount == 0 ? Color.orange : Color.green)

                Text("\(currentCount) of \(evidenceItemLimit) proof items used")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ProofKitVisual.cardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
            }
        }
    }

    private var importingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Importing locally…")
                .font(.footnote)
                .foregroundStyle(ProofKitVisual.helperText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ProofKitVisual.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
    }

    private func importSelectedPhotoItems(_ items: [PhotosPickerItem]) async {
        services.analytics.trackProofAddStarted(caseFile: caseFile, proofType: .photo, sourceScreen: .addProof)

        withAnimation(ProofKitMotion.standard) {
            isImporting = true
            importErrorMessage = nil
        }

        do {
            let decision = await services.paywall.canAddEvidence(to: caseFile, adding: items.count)
            guard decision.isAllowed else {
                withAnimation(ProofKitMotion.standard) {
                    importErrorMessage = decision.message
                    isImporting = false
                    selectedPhotoItems = []
                }
                services.analytics.trackProofImportFailed(proofType: .photo, errorType: .subscriptionFailed)
                return
            }

            var importedEvidenceItems: [EvidenceItem] = []

            for (index, item) in items.enumerated() {
                guard let imageData = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                let contentType = preferredImageContentType(for: item)
                let originalFilename = originalFilename(
                    at: index,
                    contentType: contentType
                )
                let localFile = try await services.localStorage.saveEvidenceImage(
                    data: imageData,
                    originalFilename: originalFilename,
                    contentType: contentType,
                    caseID: caseFile.id
                )
                let draft = createDraftEvidenceItem(
                    for: localFile,
                    contentType: contentType
                )

                await applyLocalOCR(
                    to: draft.evidenceItem,
                    attachment: draft.attachment,
                    localFile: localFile
                )
                await applyLocalDateCandidates(
                    to: draft.evidenceItem,
                    localFile: localFile
                )

                importedEvidenceItems.append(draft.evidenceItem)
            }

            guard !importedEvidenceItems.isEmpty else {
                withAnimation(ProofKitMotion.standard) {
                    importErrorMessage = String(localized: "No images were imported. Please choose a photo or screenshot and try again.")
                    isImporting = false
                    selectedPhotoItems = []
                }
                services.analytics.trackProofImportFailed(proofType: .photo, errorType: .importFailed)
                return
            }

            try modelContext.save()
            importedEvidenceItems.forEach { evidenceItem in
                services.analytics.trackProofAdded(evidenceItem, caseFile: caseFile)
            }
            onImportComplete(importedEvidenceItems)
            dismiss()
        } catch {
            services.analytics.trackProofImportFailed(proofType: .photo, errorType: .importFailed)
            withAnimation(ProofKitMotion.standard) {
                importErrorMessage = String(localized: "Images could not be imported. Please try again.")
            }
        }

        withAnimation(ProofKitMotion.standard) {
            isImporting = false
            selectedPhotoItems = []
        }
    }

    private func importSelectedDocumentURLs(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            await importDocumentURLs(urls)
        case .failure:
            services.analytics.trackProofImportFailed(proofType: .pdf, errorType: .importFailed)
            withAnimation(ProofKitMotion.standard) {
                importErrorMessage = String(localized: "Documents could not be selected. Please try again.")
            }
        }
    }

    private func importDocumentURLs(_ urls: [URL]) async {
        let documentURLs = urls.filter { !$0.lastPathComponent.isEmpty }
        guard !documentURLs.isEmpty else { return }
        let startedProofType = documentURLs.first.map(documentProofType(for:)) ?? .pdf
        services.analytics.trackProofAddStarted(caseFile: caseFile, proofType: startedProofType, sourceScreen: .addProof)

        withAnimation(ProofKitMotion.standard) {
            isImporting = true
            importErrorMessage = nil
        }

        do {
            let decision = await services.paywall.canAddEvidence(to: caseFile, adding: documentURLs.count)
            guard decision.isAllowed else {
                withAnimation(ProofKitMotion.standard) {
                    importErrorMessage = decision.message
                    isImporting = false
                }
                services.analytics.trackProofImportFailed(proofType: startedProofType, errorType: .subscriptionFailed)
                return
            }

            var importedEvidenceItems: [EvidenceItem] = []

            for sourceURL in documentURLs {
                let didStartSecurityScope = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if didStartSecurityScope {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                let contentType = UTType(filenameExtension: sourceURL.pathExtension)
                let kind = attachmentType(for: contentType)
                let localFile = try await services.localStorage.saveEvidenceFile(
                    from: sourceURL,
                    kind: kind,
                    caseID: caseFile.id
                )
                let evidenceItem = createDraftDocumentEvidenceItem(
                    for: localFile,
                    contentType: contentType,
                    attachmentType: kind
                )

                importedEvidenceItems.append(evidenceItem)
            }

            guard !importedEvidenceItems.isEmpty else {
                withAnimation(ProofKitMotion.standard) {
                    importErrorMessage = String(localized: "No documents were imported. Please choose a PDF or document and try again.")
                    isImporting = false
                }
                services.analytics.trackProofImportFailed(proofType: startedProofType, errorType: .importFailed)
                return
            }

            try modelContext.save()
            importedEvidenceItems.forEach { evidenceItem in
                services.analytics.trackProofAdded(evidenceItem, caseFile: caseFile)
            }
            onImportComplete(importedEvidenceItems)
            dismiss()
        } catch {
            services.analytics.trackProofImportFailed(proofType: startedProofType, errorType: .importFailed)
            withAnimation(ProofKitMotion.standard) {
                importErrorMessage = String(localized: "Documents could not be imported. Please try again.")
            }
        }

        withAnimation(ProofKitMotion.standard) {
            isImporting = false
        }
    }

    private var photoSelectionLimit: Int {
        guard let evidenceItemLimit = entitlementSnapshot.limits.evidenceItemLimit else {
            return 25
        }

        return max(1, min(25, evidenceItemLimit - caseFile.evidenceItems.count))
    }

    private var evidenceSlotsAreFull: Bool {
        guard let evidenceItemLimit = entitlementSnapshot.limits.evidenceItemLimit else {
            return false
        }

        return caseFile.evidenceItems.count >= evidenceItemLimit
    }

    private var supportedDocumentContentTypes: [UTType] {
        var types: [UTType] = [.pdf, .text, .rtf]
        let commonDocumentExtensions = [
            "doc",
            "docx",
            "pages",
            "xls",
            "xlsx",
            "numbers",
            "csv",
            "txt",
            "rtf"
        ]

        for filenameExtension in commonDocumentExtensions {
            guard let contentType = UTType(filenameExtension: filenameExtension) else { continue }
            if !types.contains(contentType) {
                types.append(contentType)
            }
        }

        return types
    }

    private func createDraftEvidenceItem(
        for localFile: LocalEvidenceFile,
        contentType: UTType?
    ) -> ImportedImageEvidenceDraft {
        let now = Date()
        let evidenceItem = EvidenceItem(
            category: .photo,
            userDateSource: .notSpecified,
            userTitle: draftTitle(from: localFile.originalFilename),
            createdAt: now,
            updatedAt: now,
            sortIndex: caseFile.evidenceItems.count
        )
        let attachment = Attachment(
            attachmentType: .photo,
            originalFilename: localFile.originalFilename,
            localFilePath: localFile.url.path(percentEncoded: false),
            thumbnailLocalFilePath: localFile.thumbnailURL?.path(percentEncoded: false),
            uniformTypeIdentifier: localFile.uniformTypeIdentifier ?? contentType?.identifier,
            fileSizeBytes: localFile.fileSizeBytes,
            contentHash: localFile.contentHash,
            fileCreatedAt: localFile.createdAt,
            importedMetadataJSON: importedMetadataJSON(for: localFile, importedAt: now),
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(evidenceItem)
        modelContext.insert(attachment)
        evidenceItem.attachments.append(attachment)
        caseFile.evidenceItems.append(evidenceItem)
        caseFile.updatedAt = now

        if caseFile.status == .draft {
            caseFile.status = .active
        }

        return ImportedImageEvidenceDraft(
            evidenceItem: evidenceItem,
            attachment: attachment
        )
    }

    private func createDraftDocumentEvidenceItem(
        for localFile: LocalEvidenceFile,
        contentType: UTType?,
        attachmentType: AttachmentType
    ) -> EvidenceItem {
        let now = Date()
        let evidenceItem = EvidenceItem(
            category: .document,
            userDateSource: .notSpecified,
            userTitle: documentDraftTitle(from: localFile.originalFilename),
            createdAt: now,
            updatedAt: now,
            sortIndex: caseFile.evidenceItems.count
        )
        let attachment = Attachment(
            attachmentType: attachmentType,
            originalFilename: localFile.originalFilename,
            localFilePath: localFile.url.path(percentEncoded: false),
            thumbnailLocalFilePath: localFile.thumbnailURL?.path(percentEncoded: false),
            uniformTypeIdentifier: localFile.uniformTypeIdentifier ?? contentType?.identifier,
            fileSizeBytes: localFile.fileSizeBytes,
            contentHash: localFile.contentHash,
            fileCreatedAt: localFile.createdAt,
            importedMetadataJSON: importedMetadataJSON(
                for: localFile,
                importedAt: now,
                source: "DocumentPicker"
            ),
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(evidenceItem)
        modelContext.insert(attachment)
        evidenceItem.attachments.append(attachment)
        caseFile.evidenceItems.append(evidenceItem)
        caseFile.updatedAt = now

        if caseFile.status == .draft {
            caseFile.status = .active
        }

        return evidenceItem
    }

    private func applyLocalOCR(
        to evidenceItem: EvidenceItem,
        attachment: Attachment,
        localFile: LocalEvidenceFile
    ) async {
        do {
            let ocrResult = try await services.ocr.recognizeText(
                inImageAt: localFile.url,
                recognitionMode: .accurate
            )
            let now = Date()
            let textBlocksJSON = textBlocksJSON(from: ocrResult.textBlocks)

            evidenceItem.ocrText = ocrResult.recognizedText
            evidenceItem.originalOCRConfidence = ocrResult.confidence
            evidenceItem.originalOCRCompletedAt = ocrResult.recognizedAt
            evidenceItem.originalOCRTextBlocksJSON = textBlocksJSON
            evidenceItem.updatedAt = now

            attachment.originalOCRText = ocrResult.recognizedText
            attachment.originalOCRConfidence = ocrResult.confidence
            attachment.originalOCRCompletedAt = ocrResult.recognizedAt
            attachment.originalOCRTextBlocksJSON = textBlocksJSON
            attachment.updatedAt = now
        } catch {
            services.analytics.trackProofImportFailed(proofType: .photo, errorType: .ocrFailed)
            // Keep the imported image even if Vision cannot recognize text in it.
            // OCR remains local-only; no remote fallback is attempted.
        }
    }

    private func applyLocalDateCandidates(
        to evidenceItem: EvidenceItem,
        localFile: LocalEvidenceFile
    ) async {
        let candidates = await services.dateCandidateExtractor.extractDateCandidates(
            imageFileURL: localFile.url,
            originalFilename: localFile.originalFilename,
            importedAt: localFile.createdAt,
            ocrText: evidenceItem.ocrText
        )
        let now = Date()

        evidenceItem.dateCandidates = candidates

        if
            evidenceItem.userProvidedEventDate == nil,
            let bestCandidate = services.dateCandidateExtractor.bestDefaultEventDateCandidate(from: candidates)
        {
            evidenceItem.detectedEventDate = bestCandidate.date
            evidenceItem.detectedDateSource = bestCandidate.source
        }

        evidenceItem.updatedAt = now
    }

    private func textBlocksJSON(from textBlocks: [OCRTextBlock]) -> String {
        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(textBlocks),
            let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return string
    }

    private func preferredImageContentType(for item: PhotosPickerItem) -> UTType? {
        item.supportedContentTypes.first { contentType in
            contentType.conforms(to: .image)
        }
    }

    private func originalFilename(at index: Int, contentType: UTType?) -> String {
        let number = index + 1
        let fileExtension = contentType?.preferredFilenameExtension ?? "jpg"
        return "\(String(localized: "Proofly Image \(number)")).\(fileExtension)"
    }

    private func draftTitle(from filename: String) -> String {
        let nameWithoutExtension = URL(filePath: filename)
            .deletingPathExtension()
            .lastPathComponent
        return nameWithoutExtension.isEmpty ? String(localized: "Imported image") : nameWithoutExtension
    }

    private func documentDraftTitle(from filename: String) -> String {
        let nameWithoutExtension = URL(filePath: filename)
            .deletingPathExtension()
            .lastPathComponent
        return nameWithoutExtension.isEmpty ? String(localized: "Imported document") : nameWithoutExtension
    }

    private func attachmentType(for contentType: UTType?) -> AttachmentType {
        guard let contentType else { return .document }

        if contentType.conforms(to: .pdf) {
            return .pdf
        }

        return .document
    }

    private func documentProofType(for url: URL) -> AnalyticsProofType {
        let contentType = UTType(filenameExtension: url.pathExtension)
        return contentType?.conforms(to: .pdf) == true ? .pdf : .other
    }

    private func importedMetadataJSON(
        for localFile: LocalEvidenceFile,
        importedAt: Date,
        source: String = "PhotosPicker"
    ) -> String {
        let importedAtString = ISO8601DateFormatter().string(from: importedAt)
        return """
        {"source":"\(source)","importedAt":"\(importedAtString)","localOnly":true,"fileID":"\(localFile.id.uuidString)"}
        """
    }
}

private struct ImportedImageEvidenceDraft {
    let evidenceItem: EvidenceItem
    let attachment: Attachment
}

private struct AddProofMediumSheetDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        min(560, max(460, context.maxDetentValue * 0.66))
    }
}

private struct AddProofOptionRow: View {
    let emoji: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(emoji)
                .font(.system(size: 24))
                .frame(width: 42, height: 42)
                .background {
                    Circle()
                        .fill(Color.accentColor.opacity(0.10))
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ProofKitVisual.subduedText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 74)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ProofKitVisual.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct AddProofOptionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.48)
            .animation(ProofKitMotion.quick, value: configuration.isPressed)
            .animation(ProofKitMotion.quick, value: isEnabled)
    }
}

#Preview {
    AddProofImportView(
        caseFile: CaseFile(
            caseType: .apartmentIssue,
            userTitle: "Housing lease timeline"
        ),
        onManualEntryRequested: {},
        onImportComplete: { _ in }
    )
    .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self, AIResultCache.self], inMemory: true)
}
