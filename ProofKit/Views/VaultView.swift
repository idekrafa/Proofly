import PhotosUI
import QuickLook
import QuickLookThumbnailing
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct VaultView: View {
    private static let filesPerPage = 4
    private static let fileCardHeight: CGFloat = 96
    private static let fileCardSpacing: CGFloat = 14
    private static var pageListHeight: CGFloat {
        (fileCardHeight * CGFloat(filesPerPage)) + (fileCardSpacing * CGFloat(filesPerPage - 1))
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.proofKitServices) private var services

    @Query(sort: \Attachment.updatedAt, order: .reverse) private var attachments: [Attachment]
    @Query(sort: \CaseFile.updatedAt, order: .reverse) private var cases: [CaseFile]

    @State private var searchText = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var notice: VaultNotice?
    @State private var fileIDPendingRename: String?
    @State private var renameText = ""
    @State private var isRenameAlertPresented = false
    @State private var fileIDPendingDelete: String?
    @State private var isDeleteConfirmationPresented = false
    @State private var createdCaseToOpen: CaseFile?
    @State private var isOpeningCreatedCase = false
    @State private var currentPage = 0
    @State private var previewFileURL: URL?

    private var vaultFiles: [VaultFile] {
        var groupedAttachments: [String: [Attachment]] = [:]

        for attachment in attachments {
            let key = attachment.localFilePath.vaultTrimmedText
            guard !key.isEmpty else { continue }
            groupedAttachments[key, default: []].append(attachment)
        }

        return groupedAttachments
            .map { key, attachments in
                VaultFile(id: key, attachments: attachments)
            }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    private var filteredVaultFiles: [VaultFile] {
        let queryTokens = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !queryTokens.isEmpty else { return vaultFiles }

        return vaultFiles.filter { vaultFile in
            let searchableText = vaultFile.searchableText
            return queryTokens.allSatisfy { searchableText.contains($0) }
        }
    }

    private var totalPageCount: Int {
        guard !filteredVaultFiles.isEmpty else { return 1 }
        return Int(ceil(Double(filteredVaultFiles.count) / Double(Self.filesPerPage)))
    }

    private var clampedPageIndex: Int {
        min(max(currentPage, 0), max(totalPageCount - 1, 0))
    }

    private var pagedVaultFiles: [VaultFile] {
        guard !filteredVaultFiles.isEmpty else { return [] }

        let startIndex = clampedPageIndex * Self.filesPerPage
        let endIndex = min(startIndex + Self.filesPerPage, filteredVaultFiles.count)
        guard startIndex < endIndex else { return [] }

        return Array(filteredVaultFiles[startIndex..<endIndex])
    }

    private var currentPageRangeText: String {
        guard !filteredVaultFiles.isEmpty else { return String(localized: "0 of 0") }

        let start = clampedPageIndex * Self.filesPerPage + 1
        let end = min(start + Self.filesPerPage - 1, filteredVaultFiles.count)
        return String(localized: "\(start)-\(end) of \(filteredVaultFiles.count)")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    VaultSearchField(text: $searchText)
                        .proofKitAppear(delay: 0.03)

                    if isImporting {
                        importingBanner
                            .proofKitAppear(delay: 0.04)
                            .transition(ProofKitMotion.compactInsertion)
                    }

                    content
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .background(VaultPalette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .animation(ProofKitMotion.standard, value: vaultFiles.map(\.id))
            .animation(ProofKitMotion.standard, value: filteredVaultFiles.map(\.id))
            .animation(ProofKitMotion.standard, value: isImporting)
            .navigationDestination(isPresented: $isOpeningCreatedCase) {
                if let createdCaseToOpen {
                    CaseDetailView(caseFile: createdCaseToOpen)
                } else {
                    EmptyStateView(
                        title: String(localized: "Case created"),
                        message: String(localized: "Your new case was created from this vault file."),
                        systemImage: "checkmark.circle"
                    )
                }
            }
            .quickLookPreview($previewFileURL)
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }

                Task {
                    await importSelectedPhotoItems(newItems)
                }
            }
            .onChange(of: searchText) { _, _ in
                withAnimation(ProofKitMotion.standard) {
                    currentPage = 0
                }
            }
            .onChange(of: filteredVaultFiles.map(\.id)) { _, _ in
                clampCurrentPage()
            }
            .alert(item: $notice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert("Rename file", isPresented: $isRenameAlertPresented) {
                TextField("File name", text: $renameText)
                    .textInputAutocapitalization(.words)

                Button("Save") {
                    renamePendingFile()
                }

                Button("Cancel", role: .cancel) {
                    fileIDPendingRename = nil
                    renameText = ""
                }
            } message: {
                Text("Update the name shown inside Proofly.")
            }
            .confirmationDialog(
                "Delete file?",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete from app", role: .destructive) {
                    deletePendingFile()
                }

                Button("Cancel", role: .cancel) {
                    fileIDPendingDelete = nil
                }
            } message: {
                Text("Deleting this will ONLY delete it from the app and not your phone.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Vault")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)
                    .kerning(-0.7)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(VaultPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 25,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Image(systemName: isImporting ? "hourglass" : "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(VaultPalette.newFileForeground)
                    .frame(width: 46, height: 46)
                    .background {
                        Circle()
                            .fill(VaultPalette.newFileBackground)
                    }
            }
            .buttonStyle(VaultIconButtonStyle())
            .disabled(isImporting)
            .accessibilityLabel(String(localized: "Upload Images"))
        }
        .proofKitAppear()
    }

    private var headerSubtitle: String {
        if vaultFiles.isEmpty {
            return String(localized: "Upload files to keep reusable proof ready.")
        }

        return String(localized: "\(vaultFiles.count) files stored locally")
    }

    @ViewBuilder
    private var content: some View {
        if vaultFiles.isEmpty {
            VaultEmptyState(
                title: String(localized: "No files yet"),
                message: String(localized: "Upload reusable proof, receipts, screenshots, and documents. Rook will help keep them ready for any case."),
                footnote: String(localized: "Files stay local until you add them to a case."),
                mascotImageName: "RookVaultEmpty"
            ) {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 25,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text("+ Upload Files")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VaultPrimaryButtonStyle())
                .disabled(isImporting)
            }
            .proofKitAppear(delay: 0.06)
        } else if filteredVaultFiles.isEmpty {
            VaultEmptyState(
                title: String(localized: "No matching files"),
                message: String(localized: "Try searching by file name, type, linked case, or OCR text.")
            ) {
                Button {
                    withAnimation(ProofKitMotion.standard) {
                        searchText = ""
                    }
                } label: {
                    Text("Clear Search")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VaultPrimaryButtonStyle())
            }
            .proofKitAppear(delay: 0.06)
        } else {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "All Files") : String(localized: "Search Results"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .kerning(-0.25)

                    Spacer()

                    Text(filteredVaultFiles.count.fileCountText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(VaultPalette.secondaryText)
                }

                VStack(spacing: Self.fileCardSpacing) {
                    ForEach(Array(pagedVaultFiles.enumerated()), id: \.element.id) { index, vaultFile in
                        VaultFileCard(
                            file: vaultFile,
                            onPreview: {
                                previewFile(vaultFile)
                            },
                            onAddToNewCase: {
                                Task { await addFileToNewCase(fileID: vaultFile.id) }
                            },
                            onRename: {
                                prepareRename(for: vaultFile)
                            },
                            onDelete: {
                                prepareDelete(for: vaultFile)
                            }
                        )
                        .frame(height: Self.fileCardHeight)
                        .proofKitAppear(delay: min(Double(index) * 0.025, 0.16))
                    }
                }
                .frame(height: Self.pageListHeight, alignment: .top)

                VaultPaginationBar(
                    currentPage: clampedPageIndex + 1,
                    totalPages: totalPageCount,
                    rangeText: currentPageRangeText,
                    canMoveBack: clampedPageIndex > 0,
                    canMoveForward: clampedPageIndex < totalPageCount - 1,
                    onPrevious: goToPreviousPage,
                    onNext: goToNextPage
                )
                .proofKitAppear(delay: 0.08)
            }
            .transition(ProofKitMotion.cardInsertion)
        }
    }

    private var importingBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Uploading images locally…")
                .font(.footnote.weight(.medium))
                .foregroundStyle(VaultPalette.secondaryText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(VaultPalette.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(VaultPalette.hairline, lineWidth: 1)
        }
        .vaultSoftShadow(radius: 12, y: 6)
    }

    private func goToPreviousPage() {
        withAnimation(ProofKitMotion.standard) {
            currentPage = max(clampedPageIndex - 1, 0)
        }
    }

    private func goToNextPage() {
        withAnimation(ProofKitMotion.standard) {
            currentPage = min(clampedPageIndex + 1, max(totalPageCount - 1, 0))
        }
    }

    private func clampCurrentPage() {
        let clampedPage = clampedPageIndex
        guard currentPage != clampedPage else { return }

        withAnimation(ProofKitMotion.standard) {
            currentPage = clampedPage
        }
    }

    private func previewFile(_ vaultFile: VaultFile) {
        let path = vaultFile.primaryAttachment.localFilePath.vaultTrimmedText
        guard !path.isEmpty else {
            notice = VaultNotice(
                title: String(localized: "Preview unavailable"),
                message: String(localized: "This file does not have a local preview path.")
            )
            return
        }

        let fileURL = URL(filePath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            notice = VaultNotice(
                title: String(localized: "Preview unavailable"),
                message: String(localized: "The local file could not be found on this device.")
            )
            return
        }

        previewFileURL = fileURL
    }

    @MainActor
    private func importSelectedPhotoItems(_ items: [PhotosPickerItem]) async {
        withAnimation(ProofKitMotion.standard) {
            isImporting = true
            notice = nil
        }

        do {
            var importedCount = 0

            for (index, item) in items.enumerated() {
                guard let imageData = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                let contentType = preferredImageContentType(for: item)
                let localFile = try await services.localStorage.saveVaultImage(
                    data: imageData,
                    originalFilename: originalFilename(at: index, contentType: contentType),
                    contentType: contentType
                )
                let attachment = createVaultAttachment(
                    for: localFile,
                    contentType: contentType
                )

                await applyLocalOCR(to: attachment, localFile: localFile)
                importedCount += 1
            }

            guard importedCount > 0 else {
                notice = VaultNotice(
                    title: String(localized: "No images uploaded"),
                    message: String(localized: "Please choose a photo or screenshot and try again.")
                )
                withAnimation(ProofKitMotion.standard) {
                    isImporting = false
                    selectedPhotoItems = []
                }
                return
            }

            try modelContext.save()
        } catch {
            notice = VaultNotice(
                title: String(localized: "Upload failed"),
                message: String(localized: "Images could not be uploaded to the app. Please try again.")
            )
        }

        withAnimation(ProofKitMotion.standard) {
            isImporting = false
            selectedPhotoItems = []
        }
    }

    private func createVaultAttachment(
        for localFile: LocalEvidenceFile,
        contentType: UTType?
    ) -> Attachment {
        let now = Date()
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
        modelContext.insert(attachment)
        return attachment
    }

    private func applyLocalOCR(to attachment: Attachment, localFile: LocalEvidenceFile) async {
        do {
            let ocrResult = try await services.ocr.recognizeText(
                inImageAt: localFile.url,
                recognitionMode: .accurate
            )
            let now = Date()
            let textBlocksJSON = textBlocksJSON(from: ocrResult.textBlocks)

            attachment.originalOCRText = ocrResult.recognizedText
            attachment.originalOCRConfidence = ocrResult.confidence
            attachment.originalOCRCompletedAt = ocrResult.recognizedAt
            attachment.originalOCRTextBlocksJSON = textBlocksJSON
            attachment.updatedAt = now
        } catch {
            // Keep the vault image even if local Vision OCR cannot recognize text.
        }
    }

    @MainActor
    private func addFileToNewCase(fileID: String) async {
        guard let vaultFile = vaultFile(for: fileID) else { return }

        let createDecision = await services.paywall.canCreateCase(existingCases: cases)
        guard createDecision.isAllowed else {
            notice = VaultNotice(decision: createDecision)
            return
        }

        let now = Date()
        let caseFile = CaseFile(
            caseType: .general,
            status: .active,
            userTitle: newCaseTitle(for: vaultFile),
            createdAt: now,
            updatedAt: now
        )

        let evidenceDecision = await services.paywall.canAddEvidence(to: caseFile, adding: 1)
        guard evidenceDecision.isAllowed else {
            notice = VaultNotice(decision: evidenceDecision)
            return
        }

        let sourceAttachment = vaultFile.primaryAttachment
        let evidenceItem = EvidenceItem(
            category: evidenceCategory(for: sourceAttachment.attachmentType),
            userDateSource: .notSpecified,
            userTitle: evidenceTitle(for: vaultFile),
            originalOCRText: sourceAttachment.originalOCRText,
            originalOCRTextBlocksJSON: sourceAttachment.originalOCRTextBlocksJSON,
            originalOCRLanguageCode: sourceAttachment.originalOCRLanguageCode,
            originalOCRConfidence: sourceAttachment.originalOCRConfidence,
            originalOCRCompletedAt: sourceAttachment.originalOCRCompletedAt,
            createdAt: now,
            updatedAt: now,
            sortIndex: 0
        )
        let copiedAttachment = copyAttachment(sourceAttachment, now: now)

        modelContext.insert(caseFile)
        modelContext.insert(evidenceItem)
        modelContext.insert(copiedAttachment)
        evidenceItem.attachments.append(copiedAttachment)
        caseFile.evidenceItems.append(evidenceItem)

        do {
            try modelContext.save()
            createdCaseToOpen = caseFile
            isOpeningCreatedCase = true
        } catch {
            notice = VaultNotice(
                title: String(localized: "Case could not be created"),
                message: String(localized: "This file could not be added to a new case. Please try again.")
            )
        }
    }

    private func prepareRename(for vaultFile: VaultFile) {
        fileIDPendingRename = vaultFile.id
        renameText = vaultFile.displayName
        isRenameAlertPresented = true
    }

    private func renamePendingFile() {
        guard let fileID = fileIDPendingRename, let vaultFile = vaultFile(for: fileID) else {
            fileIDPendingRename = nil
            renameText = ""
            return
        }

        let newFilename = normalizedFilename(
            renameText,
            keepingExtensionFrom: vaultFile.displayName
        )
        guard !newFilename.isEmpty else {
            notice = VaultNotice(
                title: String(localized: "Name required"),
                message: String(localized: "Enter a file name before saving.")
            )
            return
        }

        let now = Date()
        matchingAttachments(for: fileID).forEach { attachment in
            attachment.originalFilename = newFilename
            attachment.updatedAt = now
            attachment.evidenceItem?.updatedAt = now
            attachment.evidenceItem?.caseFile?.updatedAt = now
        }

        do {
            try modelContext.save()
        } catch {
            notice = VaultNotice(
                title: String(localized: "Rename failed"),
                message: String(localized: "This file could not be renamed. Please try again.")
            )
        }

        fileIDPendingRename = nil
        renameText = ""
    }

    private func prepareDelete(for vaultFile: VaultFile) {
        fileIDPendingDelete = vaultFile.id
        isDeleteConfirmationPresented = true
    }

    private func deletePendingFile() {
        guard let fileID = fileIDPendingDelete else { return }
        let attachmentsToDelete = matchingAttachments(for: fileID)
        guard !attachmentsToDelete.isEmpty else {
            fileIDPendingDelete = nil
            return
        }

        do {
            try deleteLocalFiles(for: attachmentsToDelete)

            let now = Date()
            for attachment in attachmentsToDelete {
                attachment.evidenceItem?.updatedAt = now
                attachment.evidenceItem?.caseFile?.updatedAt = now
                modelContext.delete(attachment)
            }

            try modelContext.save()
        } catch {
            notice = VaultNotice(
                title: String(localized: "Delete failed"),
                message: String(localized: "This file could not be deleted from the app. Please try again.")
            )
        }

        fileIDPendingDelete = nil
    }

    private func vaultFile(for id: String) -> VaultFile? {
        vaultFiles.first { $0.id == id }
    }

    private func matchingAttachments(for fileID: String) -> [Attachment] {
        attachments.filter { $0.localFilePath.vaultTrimmedText == fileID }
    }

    private func deleteLocalFiles(for attachments: [Attachment]) throws {
        var localPaths = Set<String>()

        for attachment in attachments {
            let originalPath = attachment.localFilePath.vaultTrimmedText
            if !originalPath.isEmpty {
                localPaths.insert(originalPath)
            }

            if let thumbnailPath = attachment.thumbnailLocalFilePath?.vaultTrimmedText,
               !thumbnailPath.isEmpty {
                localPaths.insert(thumbnailPath)
            }
        }

        let fileManager = FileManager.default
        for path in localPaths {
            guard fileManager.fileExists(atPath: path) else { continue }
            try fileManager.removeItem(at: URL(filePath: path))
        }
    }

    private func preferredImageContentType(for item: PhotosPickerItem) -> UTType? {
        item.supportedContentTypes.first { contentType in
            contentType.conforms(to: .image)
        }
    }

    private func originalFilename(at index: Int, contentType: UTType?) -> String {
        let number = index + 1
        let fileExtension = contentType?.preferredFilenameExtension ?? "jpg"
        return "\(String(localized: "Vault Image \(number)")).\(fileExtension)"
    }

    private func importedMetadataJSON(
        for localFile: LocalEvidenceFile,
        importedAt: Date
    ) -> String {
        let importedAtString = ISO8601DateFormatter().string(from: importedAt)
        return """
        {"source":"VaultPhotosPicker","importedAt":"\(importedAtString)","localOnly":true,"fileID":"\(localFile.id.uuidString)"}
        """
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

    private func copyAttachment(_ attachment: Attachment, now: Date) -> Attachment {
        Attachment(
            attachmentType: attachment.attachmentType,
            originalFilename: attachment.originalFilename,
            localFilePath: attachment.localFilePath,
            thumbnailLocalFilePath: attachment.thumbnailLocalFilePath,
            uniformTypeIdentifier: attachment.uniformTypeIdentifier,
            fileSizeBytes: attachment.fileSizeBytes,
            contentHash: attachment.contentHash,
            fileCreatedAt: attachment.fileCreatedAt,
            fileModifiedAt: attachment.fileModifiedAt,
            originalOCRText: attachment.originalOCRText,
            originalOCRTextBlocksJSON: attachment.originalOCRTextBlocksJSON,
            originalOCRLanguageCode: attachment.originalOCRLanguageCode,
            originalOCRConfidence: attachment.originalOCRConfidence,
            originalOCRCompletedAt: attachment.originalOCRCompletedAt,
            importedMetadataJSON: attachment.importedMetadataJSON,
            createdAt: now,
            updatedAt: now
        )
    }

    private func evidenceCategory(for attachmentType: AttachmentType) -> EvidenceCategory {
        switch attachmentType {
        case .screenshot:
            return .screenshot
        case .photo:
            return .photo
        case .pdf, .document:
            return .document
        case .textNote:
            return .note
        case .other:
            return .other
        }
    }

    private func evidenceTitle(for vaultFile: VaultFile) -> String {
        let stem = vaultFile.displayName.vaultFilenameStem
        return stem.isEmpty ? String(localized: "Vault file") : stem
    }

    private func newCaseTitle(for vaultFile: VaultFile) -> String {
        let stem = vaultFile.displayName.vaultFilenameStem
        return stem.isEmpty ? String(localized: "Vault File Case") : String(localized: "Case from \(stem)")
    }

    private func normalizedFilename(_ candidate: String, keepingExtensionFrom currentFilename: String) -> String {
        let trimmed = candidate.vaultTrimmedText
        guard !trimmed.isEmpty else { return "" }

        let sanitized = trimmed
            .components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:"))
            .joined(separator: "-")
            .vaultTrimmedText
        guard !sanitized.isEmpty else { return "" }

        let currentExtension = URL(filePath: currentFilename).pathExtension
        let proposedExtension = URL(filePath: sanitized).pathExtension

        if proposedExtension.isEmpty, !currentExtension.isEmpty {
            return "\(sanitized).\(currentExtension)"
        }

        return sanitized
    }
}

private struct VaultNotice: Identifiable {
    let title: String
    let message: String

    var id: String { "\(title)-\(message)" }

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(decision: PaywallAccessDecision) {
        title = decision.title
        message = decision.message
    }
}

private struct VaultFile: Identifiable {
    let id: String
    let attachments: [Attachment]

    var primaryAttachment: Attachment {
        attachments.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }.first ?? attachments[0]
    }

    var displayName: String {
        let trimmedFilename = primaryAttachment.originalFilename.vaultTrimmedText
        return trimmedFilename.isEmpty ? String(localized: "Untitled File") : trimmedFilename
    }

    var updatedAt: Date {
        attachments.map(\.updatedAt).max() ?? primaryAttachment.updatedAt
    }

    var fileTypeText: String {
        primaryAttachment.attachmentType.displayName
    }

    var updatedText: String {
        Calendar.current.isDateInToday(updatedAt)
            ? String(localized: "Updated today")
            : String(localized: "Updated \(ProofKitDateFormatting.shortDate(updatedAt))")
    }

    var fileSizeText: String? {
        guard let fileSizeBytes = primaryAttachment.fileSizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    var linkedCaseTitles: [String] {
        var seen = Set<String>()
        var titles: [String] = []

        for attachment in attachments {
            guard let title = attachment.evidenceItem?.caseFile?.vaultDisplayTitle else { continue }
            if seen.insert(title).inserted {
                titles.append(title)
            }
        }

        return titles
    }

    var storageText: String {
        if linkedCaseTitles.isEmpty {
            return String(localized: "Vault only")
        }

        if linkedCaseTitles.count == 1, let title = linkedCaseTitles.first {
            return String(localized: "In \(title)")
        }

        return String(localized: "In \(linkedCaseTitles.count) cases")
    }

    var detailText: String {
        [fileTypeText, fileSizeText, storageText, updatedText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var searchableText: String {
        let attachmentText = attachments
            .map { attachment in
                [
                    attachment.originalFilename,
                    attachment.attachmentType.displayName,
                    attachment.uniformTypeIdentifier ?? "",
                    attachment.originalOCRText,
                    attachment.evidenceItem?.userTitle ?? "",
                    attachment.evidenceItem?.userNotes ?? "",
                    attachment.evidenceItem?.caseFile?.vaultDisplayTitle ?? ""
                ]
                .joined(separator: " ")
            }
            .joined(separator: " ")

        return [
            displayName,
            fileTypeText,
            storageText,
            attachmentText
        ]
        .joined(separator: " ")
        .lowercased()
    }
}

private struct VaultSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VaultPalette.tertiaryText)

            TextField("Search files", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    withAnimation(ProofKitMotion.quick) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(VaultPalette.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search"))
            }
        }
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(VaultPalette.searchField)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(VaultPalette.hairline, lineWidth: 1)
        }
        .vaultSoftShadow(radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }
}

private struct VaultPaginationBar: View {
    let currentPage: Int
    let totalPages: Int
    let rangeText: String
    let canMoveBack: Bool
    let canMoveForward: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(VaultPaginationButtonStyle())
            .disabled(!canMoveBack)
            .accessibilityLabel(String(localized: "Previous page"))

            Spacer(minLength: 4)

            VStack(spacing: 3) {
                Text("Page \(currentPage) of \(totalPages)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(rangeText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VaultPalette.secondaryText)
            }
            .frame(minWidth: 120)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(VaultPaginationButtonStyle())
            .disabled(!canMoveForward)
            .accessibilityLabel(String(localized: "Next page"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(VaultPalette.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(VaultPalette.hairline, lineWidth: 1)
        }
        .vaultSoftShadow(radius: 14, y: 7)
    }
}

private struct VaultFileCard: View {
    let file: VaultFile
    let onPreview: () -> Void
    let onAddToNewCase: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Button(action: onPreview) {
                VaultThumbnail(attachment: file.primaryAttachment)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background {
                                Circle()
                                    .fill(Color.black.opacity(0.42))
                            }
                            .padding(4)
                    }
            }
            .buttonStyle(VaultThumbnailButtonStyle())
            .accessibilityLabel(String(localized: "Preview \(file.displayName)"))
            .accessibilityHint(String(localized: "Opens this file"))

            VStack(alignment: .leading, spacing: 5) {
                Text(file.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)

                Text(file.detailText)
                    .font(.subheadline)
                    .foregroundStyle(VaultPalette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(VaultPalette.tertiaryText)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(VaultPalette.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(VaultPalette.hairline, lineWidth: 1)
        }
        .vaultSoftShadow(radius: 18, y: 9)
        .contextMenu {
            Button(action: onAddToNewCase) {
                Label("Add file to a new case", systemImage: "folder.badge.plus")
            }

            Button(action: onRename) {
                Label("Rename file", systemImage: "pencil")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(String(localized: "Long-press for file actions"))
    }
}

private struct VaultThumbnail: View {
    let attachment: Attachment

    var body: some View {
        preview
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(VaultPalette.thumbnailStroke, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var preview: some View {
        if
            let imagePath = attachment.thumbnailLocalFilePath ?? imagePreviewPath,
            let image = UIImage(contentsOfFile: imagePath)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let documentPreviewURL {
            VaultDocumentPreviewThumbnail(
                fileURL: documentPreviewURL,
                attachmentType: attachment.attachmentType
            )
        } else {
            VaultFallbackThumbnail(attachmentType: attachment.attachmentType)
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

    private var documentPreviewURL: URL? {
        switch attachment.attachmentType {
        case .pdf, .document, .textNote, .other:
            let path = attachment.localFilePath.vaultTrimmedText
            guard !path.isEmpty else { return nil }
            return URL(filePath: path)
        case .photo, .screenshot:
            return nil
        }
    }
}

private struct VaultDocumentPreviewThumbnail: View {
    let fileURL: URL
    let attachmentType: AttachmentType

    @Environment(\.displayScale) private var displayScale

    @State private var thumbnail: UIImage?
    @State private var didFailToLoad = false

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else if didFailToLoad {
                VaultFallbackThumbnail(attachmentType: attachmentType)
            } else {
                VaultDocumentPreviewPlaceholder(attachmentType: attachmentType)
            }
        }
        .task(id: fileURL.path(percentEncoded: false)) {
            await loadThumbnail()
        }
    }

    @MainActor
    private func loadThumbnail() async {
        guard thumbnail == nil, !didFailToLoad else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            didFailToLoad = true
            return
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: 180, height: 180),
            scale: displayScale,
            representationTypes: .all
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            thumbnail = representation.uiImage
        } catch {
            didFailToLoad = true
        }
    }
}

private struct VaultDocumentPreviewPlaceholder: View {
    let attachmentType: AttachmentType

    var body: some View {
        ZStack {
            VaultFallbackThumbnail(attachmentType: attachmentType)

            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .padding(5)
                .background {
                    Circle()
                        .fill(Color.black.opacity(0.34))
                }
        }
    }
}

private struct VaultFallbackThumbnail: View {
    let attachmentType: AttachmentType

    var body: some View {
        ZStack {
            LinearGradient(
                colors: fallbackColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .padding(8)

            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.92))
        }
    }

    private var systemImage: String {
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

    private var fallbackColors: [Color] {
        switch attachmentType {
        case .photo, .screenshot:
            return [Color(red: 0.27, green: 0.47, blue: 0.78), Color(red: 0.15, green: 0.25, blue: 0.43)]
        case .pdf, .document:
            return [Color(red: 0.36, green: 0.42, blue: 0.50), Color(red: 0.17, green: 0.22, blue: 0.28)]
        case .textNote:
            return [Color(red: 0.47, green: 0.41, blue: 0.56), Color(red: 0.27, green: 0.22, blue: 0.35)]
        case .other:
            return [Color(red: 0.39, green: 0.47, blue: 0.56), Color(red: 0.20, green: 0.27, blue: 0.34)]
        }
    }
}

private struct VaultEmptyState<PrimaryAction: View>: View {
    let title: String
    let message: String
    var footnote: String? = nil
    var mascotImageName: String? = nil
    @ViewBuilder let primaryAction: PrimaryAction

    var body: some View {
        VStack(alignment: .leading, spacing: ProofKitEmptyCardMetrics.contentSpacing) {
            if let mascotImageName {
                ProofKitEmptyMascotImage(
                    imageName: mascotImageName,
                    shadowColor: VaultPalette.mascotShadow
                )
            }

            VStack(alignment: .leading, spacing: ProofKitEmptyCardMetrics.textSpacing) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(VaultPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            primaryAction

            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(VaultPalette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ProofKitEmptyCardMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ProofKitEmptyCardMetrics.cornerRadius, style: .continuous)
                .fill(VaultPalette.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ProofKitEmptyCardMetrics.cornerRadius, style: .continuous)
                .stroke(VaultPalette.hairline, lineWidth: 1)
        }
        .vaultSoftShadow(
            radius: ProofKitEmptyCardMetrics.shadowRadius,
            y: ProofKitEmptyCardMetrics.shadowY
        )
    }
}

private struct VaultPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(VaultPalette.newFileForeground)
            .padding(.vertical, 15)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(VaultPalette.newFileBackground.opacity(configuration.isPressed ? 0.86 : 1))
            }
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

private struct VaultPaginationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background {
                Circle()
                    .fill(configuration.isPressed ? VaultPalette.controlFillPressed : VaultPalette.controlFill)
            }
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(ProofKitMotion.quick, value: configuration.isPressed)
    }
}

private struct VaultThumbnailButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(ProofKitMotion.quick, value: configuration.isPressed)
    }
}

private struct VaultIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(ProofKitMotion.quick, value: configuration.isPressed)
    }
}

private enum VaultPalette {
    static let background = dynamicColor(
        light: UIColor(red: 0.972, green: 0.968, blue: 0.958, alpha: 1),
        dark: UIColor(red: 0.047, green: 0.059, blue: 0.078, alpha: 1)
    )
    static let card = dynamicColor(
        light: .systemBackground,
        dark: UIColor(red: 0.082, green: 0.102, blue: 0.133, alpha: 1)
    )
    static let searchField = dynamicColor(
        light: .systemBackground,
        dark: UIColor(red: 0.098, green: 0.122, blue: 0.157, alpha: 1)
    )
    static let secondaryText = dynamicColor(
        light: .secondaryLabel,
        dark: UIColor(red: 0.69, green: 0.74, blue: 0.80, alpha: 1)
    )
    static let tertiaryText = dynamicColor(
        light: .tertiaryLabel,
        dark: UIColor(red: 0.50, green: 0.56, blue: 0.63, alpha: 1)
    )
    static let hairline = dynamicColor(
        light: UIColor(red: 0.22, green: 0.24, blue: 0.27, alpha: 0.13),
        dark: UIColor(white: 1, alpha: 0.10)
    )
    static let controlFill = dynamicColor(
        light: .systemGray6,
        dark: UIColor(red: 0.125, green: 0.157, blue: 0.204, alpha: 1)
    )
    static let controlFillPressed = dynamicColor(
        light: .systemGray4,
        dark: UIColor(red: 0.176, green: 0.220, blue: 0.286, alpha: 1)
    )
    static let newFileBackground = dynamicColor(
        light: .black,
        dark: UIColor(red: 0.16, green: 0.56, blue: 1.00, alpha: 1)
    )
    static let newFileForeground = Color.white
    static let thumbnailStroke = dynamicColor(
        light: UIColor(white: 1, alpha: 0.72),
        dark: UIColor(white: 1, alpha: 0.18)
    )
    static let shadow = dynamicColor(
        light: UIColor(white: 0, alpha: 0.052),
        dark: UIColor(white: 0, alpha: 0.32)
    )
    static let mascotShadow = dynamicColor(
        light: UIColor(white: 0, alpha: 0.10),
        dark: UIColor(white: 0, alpha: 0.24)
    )

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(
            UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}

private extension View {
    func vaultSoftShadow(radius: CGFloat, y: CGFloat) -> some View {
        shadow(color: VaultPalette.shadow, radius: radius, x: 0, y: y)
    }
}

private extension CaseFile {
    var vaultDisplayTitle: String {
        CaseFile.displayTitle(forTrimmedTitle: userTitle.vaultTrimmedText)
    }
}

private extension Int {
    var fileCountText: String {
        self == 1 ? String(localized: "1 file") : String(localized: "\(self) files")
    }
}

private extension String {
    var vaultTrimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var vaultFilenameStem: String {
        let stem = URL(filePath: self)
            .deletingPathExtension()
            .lastPathComponent
            .vaultTrimmedText
        return stem
    }
}

#Preview {
    VaultPreview()
        .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self, AIResultCache.self], inMemory: true)
}

private struct VaultPreview: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var attachments: [Attachment]

    var body: some View {
        VaultView()
            .onAppear(perform: insertSampleDataIfNeeded)
    }

    private func insertSampleDataIfNeeded() {
        guard attachments.isEmpty else { return }

        let now = Date()
        let caseFile = CaseFile(
            caseType: .general,
            status: .active,
            userTitle: "Sample Case",
            createdAt: now.addingTimeInterval(-86400 * 3),
            updatedAt: now
        )
        let evidenceItem = EvidenceItem(
            category: .photo,
            userTitle: "Receipt photo",
            originalOCRText: "Sample receipt text",
            createdAt: now.addingTimeInterval(-86400),
            updatedAt: now,
            caseFile: caseFile
        )
        let linkedAttachment = Attachment(
            attachmentType: .photo,
            originalFilename: "Receipt Photo.jpg",
            localFilePath: "/tmp/receipt-photo.jpg",
            fileSizeBytes: 245_000,
            originalOCRText: "Sample receipt text",
            createdAt: now.addingTimeInterval(-86400),
            updatedAt: now,
            evidenceItem: evidenceItem
        )
        let vaultAttachment = Attachment(
            attachmentType: .photo,
            originalFilename: "Lease Walkthrough.jpg",
            localFilePath: "/tmp/lease-walkthrough.jpg",
            fileSizeBytes: 518_000,
            createdAt: now.addingTimeInterval(-3600),
            updatedAt: now.addingTimeInterval(-3600)
        )

        modelContext.insert(caseFile)
        modelContext.insert(evidenceItem)
        modelContext.insert(linkedAttachment)
        modelContext.insert(vaultAttachment)
        evidenceItem.attachments.append(linkedAttachment)
        caseFile.evidenceItems.append(evidenceItem)
    }
}
