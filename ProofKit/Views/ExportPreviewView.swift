import CryptoKit
import PDFKit
import SwiftData
import SwiftUI
import UIKit

struct ExportPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.proofKitServices) private var services

    let caseFile: CaseFile
    private let skippedEvidenceIDs: Set<UUID>
    private let onAddProof: () -> Void

    @State private var exportMode = PDFExportMode.cleanPacket
    @State private var includeStatementPlaceholder = false
    @State private var isExporting = false
    @State private var exportErrorMessage: String?
    @State private var latestExportURL: URL?
    @State private var activePreviewURL: URL?
    @State private var exportAccess = ProofKitExportAccess.placeholderFree
    @State private var showMissingItems = true
    @State private var isPacketDetailsExpanded = false
    @State private var signatureConfiguration: ExportSignatureConfiguration?
    @State private var isSignatureSheetPresented = false
    @State private var isSignaturePaywallPresented = false
    @State private var shouldOpenSignatureAfterPaywall = false
    @State private var isIssuingSignatureToken = false

    init(
        caseFile: CaseFile,
        skippedEvidenceIDs: Set<UUID> = [],
        onAddProof: @escaping () -> Void = {}
    ) {
        self.caseFile = caseFile
        self.skippedEvidenceIDs = skippedEvidenceIDs
        self.onAddProof = onAddProof
    }

    private var latestExport: ExportPacket? {
        caseFile.sortedExportPackets.first
    }

    private var generatedExport: (packet: ExportPacket, url: URL)? {
        guard let latestExport else { return nil }

        if let latestExportURL,
           FileManager.default.fileExists(atPath: latestExportURL.path(percentEncoded: false)) {
            return (latestExport, latestExportURL)
        }

        guard let localURL = localURL(for: latestExport) else { return nil }
        return (latestExport, localURL)
    }

    private var exportScreenState: ExportScreenState {
        if let generatedExport {
            return .generated(generatedExport.packet, generatedExport.url)
        }

        return missingExportItems.isEmpty ? .ready : .almostReady
    }

    private var exportScreenStateID: String {
        switch exportScreenState {
        case .almostReady:
            "almostReady-\(missingExportItems.map(\.id).joined(separator: "|"))-\(skippedEvidenceIDs.count)"
        case .ready:
            "ready-\(estimatedPageCount)-\(caseFile.evidenceItems.count)-\(exportMode.rawValue)-\(includeStatementPlaceholder)"
        case .generated(let packet, _):
            "generated-\(packet.id)-\(activePreviewURL?.path(percentEncoded: false) ?? "closed")"
        }
    }

    private var previewPDFURL: URL? {
        activePreviewURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Export",
                subtitle: "Create a PDF packet from proof saved on this device."
            )

            stateDrivenContent
                .transition(ProofKitMotion.cardInsertion)
                .proofKitAppear()

            if let previewPDFURL {
                pdfPreviewCard(url: previewPDFURL)
                    .transition(ProofKitMotion.cardInsertion)
                    .proofKitAppear(delay: 0.06)
            }

            Color.clear
                .frame(height: 88)
        }
        .animation(ProofKitMotion.standard, value: isExporting)
        .animation(ProofKitMotion.standard, value: isIssuingSignatureToken)
        .animation(ProofKitMotion.standard, value: previewPDFURL)
        .animation(ProofKitMotion.standard, value: latestExport?.id)
        .animation(ProofKitMotion.standard, value: exportScreenStateID)
        .task {
            await refreshExportAccess()
        }
        .sheet(isPresented: $isSignatureSheetPresented) {
            SignatureCaptureView(
                initialPage: signatureConfiguration?.page ?? .lastPage,
                initialPlacement: signatureConfiguration?.placement ?? .lowerRight,
                initialCustomOffset: signatureConfiguration?.customOffset
            ) { image, page, placement, customOffset in
                Task { await completeSignature(image: image, page: page, placement: placement, customOffset: customOffset) }
            }
        }
        .sheet(isPresented: $isSignaturePaywallPresented, onDismiss: openSignatureAfterPaywallIfNeeded) {
            PaywallView {
                await refreshExportAccess()
                let entitlement = await services.paywall.currentEntitlement()
                if entitlement.plan == .pro {
                    shouldOpenSignatureAfterPaywall = true
                }
            }
        }
    }

    @ViewBuilder
    private var stateDrivenContent: some View {
        switch exportScreenState {
        case .almostReady:
            VStack(alignment: .leading, spacing: 14) {
                almostReadyHero

                if showMissingItems {
                    missingItemsSection
                        .transition(ProofKitMotion.compactInsertion)
                }
            }
        case .ready:
            VStack(alignment: .leading, spacing: 14) {
                readyHero
                packetDetailsDisclosure
            }
        case .generated(let packet, let url):
            VStack(alignment: .leading, spacing: 14) {
                generatedHero(url: url)
                latestExportDetails(packet: packet)
                packetDetailsDisclosure
            }
        }
    }

    private var almostReadyHero: some View {
        exportHeroCard(
            imageName: "RookExportAlmostReady",
            accentColor: ExportPagePalette.guidance,
            title: "Almost ready",
            subtitle: almostReadySubtitle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    onAddProof()
                } label: {
                    Label("Add Proof", systemImage: "plus")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(ExportPagePalette.guidance)

                Button {
                    withAnimation(ProofKitMotion.standard) {
                        showMissingItems = true
                    }
                } label: {
                    Text("See what’s missing")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ExportPagePalette.guidance)

                exportMessages
            }
        }
    }

    private var readyHero: some View {
        exportHeroCard(
            imageName: "RookExportReady",
            accentColor: ExportPagePalette.ready,
            title: "Your packet is ready",
            subtitle: readyHeroSubtitle
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await generatePDF() }
                } label: {
                    HStack(spacing: 9) {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                                .transition(.opacity)
                        } else {
                            Image(systemName: "doc.badge.plus")
                                .transition(.opacity)
                        }

                        Text(isExporting ? "Generating packet…" : "Generate PDF Packet")
                            .fontWeight(.semibold)
                            .contentTransition(.opacity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(ExportPagePalette.ready)
                .disabled(isExporting)

                Text("Saved locally. Shared only when you choose.")
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)

                exportMessages
            }
        }
    }

    private func generatedHero(url: URL) -> some View {
        exportHeroCard(
            imageName: "RookExportReady",
            accentColor: ExportPagePalette.ready,
            title: "Packet generated",
            subtitle: "Your PDF is saved locally on this device."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        viewPacketButton(url: url)
                        signPacketButton()
                        sharePacketLink(url: url)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 10) {
                        viewPacketButton(url: url)
                        signPacketButton()
                        sharePacketLink(url: url)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                Button {
                    Task { await generatePDF() }
                } label: {
                    if isExporting {
                        Label("Regenerating…", systemImage: "arrow.clockwise")
                    } else {
                        Text("Regenerate")
                    }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(ExportPagePalette.ready)
                .disabled(isExporting)

                exportMessages
            }
        }
    }

    private func viewPacketButton(url: URL) -> some View {
        Button {
            withAnimation(ProofKitMotion.standard) {
                activePreviewURL = url
                exportErrorMessage = nil
            }
        } label: {
            ExportActionLabel(title: "View Packet", systemImage: "doc.text")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(ExportPagePalette.ready)
    }

    private func sharePacketLink(url: URL) -> some View {
        ShareLink(item: url) {
            ExportActionLabel(title: "Share", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func signPacketButton() -> some View {
        Button {
            Task { await beginSignatureFlow() }
        } label: {
            ExportActionLabel(
                title: isIssuingSignatureToken ? "Securing…" : (signatureConfiguration == nil ? "Sign" : "Edit Signature"),
                systemImage: "signature"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isExporting || isIssuingSignatureToken)
    }

    private func exportHeroCard<Content: View>(
        imageName: String,
        accentColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    ExportStatusPill(text: statePillText, color: accentColor)

                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ExportRookImage(imageName: imageName)
            }

            content()
        }
        .padding(ProofKitVisual.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(ProofKitVisual.surfaceGradient)
        }
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accentColor.opacity(0.32), lineWidth: 1)
        }
        .shadow(color: ProofKitVisual.elevatedShadow, radius: 18, x: 0, y: 10)
    }

    private var statePillText: String {
        switch exportScreenState {
        case .almostReady:
            "Next step"
        case .ready:
            "Ready"
        case .generated:
            "Saved PDF"
        }
    }

    @ViewBuilder
    private var exportMessages: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let blockedMessage = exportAccess.blockedMessage {
                Label(blockedMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ExportPagePalette.guidance)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(ProofKitMotion.compactInsertion)
            }

            if let exportErrorMessage {
                Label(exportErrorMessage, systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(ProofKitMotion.compactInsertion)
            }
        }
    }

    private var missingItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Before you export:")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 9) {
                ForEach(missingExportItems) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.systemImage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ExportPagePalette.guidance)
                            .frame(width: 22, height: 22)
                            .background {
                                Circle()
                                    .fill(ExportPagePalette.guidance.opacity(0.16))
                            }
                            .accessibilityHidden(true)

                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(ProofKitVisual.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ProofKitVisual.panelCornerRadius, style: .continuous)
                .fill(ProofKitVisual.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ProofKitVisual.panelCornerRadius, style: .continuous)
                .stroke(ExportPagePalette.guidance.opacity(0.22), lineWidth: 1)
        }
    }

    private var packetDetailsDisclosure: some View {
        DisclosureGroup(isExpanded: $isPacketDetailsExpanded) {
            VStack(spacing: 0) {
                ExportDetailsRow(title: "Mode", value: exportMode.displayName)
                ExportDetailsRow(title: "Proof items", value: "\(caseFile.evidenceItems.count)")
                ExportDetailsRow(title: "Timeline", value: timelineExportValue)
                ExportDetailsRow(title: "Attachments", value: attachmentCount == 0 ? "None" : "\(attachmentCount)")
                ExportDetailsRow(title: "Watermark", value: watermarkSummary)
                ExportDetailsRow(title: "Signature", value: signatureSummary)
                if let signatureConfiguration {
                    ExportDetailsRow(title: "Signature token", value: signatureConfiguration.validationToken)
                }

                Picker("Export mode", selection: $exportMode) {
                    ForEach(PDFExportMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 12)
                .padding(.bottom, 4)

                Text(exportMode.shortDescription)
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.subduedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)

                Toggle(isOn: $includeStatementPlaceholder) {
                    HStack(spacing: 8) {
                        Text("Statement page")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 12)

                        Text(includeStatementPlaceholder ? "On" : "Off")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ProofKitVisual.helperText)
                    }
                }
                .tint(ExportPagePalette.ready)
                .padding(.vertical, 11)

                signatureControls
                    .padding(.vertical, 8)

                Text(exportPlanMessage)
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.subduedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.helperText)

                Text("Packet details")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
        .tint(ProofKitVisual.helperText)
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
    }

    private func latestExportDetails(packet: ExportPacket) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest export details")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                ExportDetailsRow(title: "Generated", value: generatedDateText(for: packet))
                ExportDetailsRow(title: "Page count", value: pageCountText(for: packet))
                ExportDetailsRow(title: "File size", value: fileSizeText(for: packet))
            }
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
    }

    private func pdfPreviewCard(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Packet view")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Saved locally on this device.")
                        .font(.caption)
                        .foregroundStyle(ProofKitVisual.helperText)
                }

                Spacer(minLength: 12)

                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            PDFKitPreview(url: url)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
                }
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
    }

    private var missingExportItems: [MissingExportItem] {
        var items: [MissingExportItem] = []

        if caseFile.evidenceItems.isEmpty {
            items.append(
                MissingExportItem(
                    title: "Add at least 1 proof item",
                    systemImage: "plus"
                )
            )
        }

        if unreviewedProofCount > 0 {
            items.append(
                MissingExportItem(
                    title: unreviewedProofCount == 1 ? "Review new proof" : "Review new proof items",
                    systemImage: "checkmark"
                )
            )
        }

        if !caseDetailsReady {
            items.append(
                MissingExportItem(
                    title: "Add a case title",
                    systemImage: "textformat"
                )
            )
        }

        return items
    }

    private var almostReadySubtitle: String {
        guard let firstMissingItem = missingExportItems.first else {
            return "Rook is checking the latest case details before export."
        }

        return "\(firstMissingItem.title), then Rook can pack your timeline into a PDF."
    }

    private var unreviewedProofCount: Int {
        caseFile.evidenceItems.filter { evidenceItem in
            evidenceItem.needsReview && !skippedEvidenceIDs.contains(evidenceItem.id)
        }.count
    }

    private var caseDetailsReady: Bool {
        !caseFile.userTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var timelineReady: Bool {
        !caseFile.evidenceItems.isEmpty
    }

    private var proofItemCountText: String {
        let count = caseFile.evidenceItems.count
        return count == 1 ? "1 proof item" : "\(count) proof items"
    }

    private var localStorageBaseDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "ProofKit")
    }

    private var readyHeroSubtitle: String {
        switch exportMode {
        case .cleanPacket:
            "About \(estimatedPageCount) pages with rendered files only."
        case .fullArchive:
            "About \(estimatedPageCount) pages with \(proofItemCountText) and your timeline."
        }
    }

    private var timelineExportValue: String {
        switch exportMode {
        case .cleanPacket:
            "Not included"
        case .fullArchive:
            timelineReady ? "Included" : "Needs proof"
        }
    }

    private var attachmentCount: Int {
        caseFile.evidenceItems.reduce(0) { $0 + $1.attachments.count }
    }

    private var watermarkSummary: String {
        exportAccess.isWatermarked ? "Top + footer" : "None"
    }

    private var estimatedPageCount: Int {
        let evidenceCount = caseFile.evidenceItems.count
        let itemsWithAttachments = caseFile.evidenceItems.filter { !$0.attachments.isEmpty }.count
        let compactTimelineWeight = evidenceCount + itemsWithAttachments
        let timelinePages = max(1, Int(ceil(Double(max(compactTimelineWeight, 1)) / 4.0)))
        let longTextOverflowPages = caseFile.evidenceItems.reduce(0) { count, evidenceItem in
            let textLength = evidenceItem.userNotes.count + evidenceItem.userCleanedNote.count + evidenceItem.userWhyThisMatters.count + evidenceItem.originalOCRText.count
            return count + max(0, Int(ceil(Double(textLength - 2_400) / 2_400.0)))
        }
        let renderedFilePages = renderedAttachmentPageCount
        let statementPages = includeStatementPlaceholder ? 1 : 0

        switch exportMode {
        case .cleanPacket:
            let blankFallbackPages = renderedFilePages == 0 && statementPages == 0 ? 1 : 0
            return renderedFilePages + statementPages + blankFallbackPages
        case .fullArchive:
            let indexPages = max(1, Int(ceil(Double(max(evidenceCount, 1)) / 14.0)))
            let evidenceItemPages = evidenceCount
            let attachmentOverflowPages = caseFile.evidenceItems.reduce(0) { count, evidenceItem in
                count + max(0, Int(ceil(Double(evidenceItem.attachments.count - 3) / 4.0)))
            }
            return 2 + timelinePages + indexPages + evidenceItemPages + longTextOverflowPages + attachmentOverflowPages + renderedFilePages + statementPages
        }
    }

    private var renderedAttachmentPageCount: Int {
        caseFile.evidenceItems.reduce(0) { count, evidenceItem in
            count + evidenceItem.attachments.reduce(0) { attachmentCount, attachment in
                attachmentCount + renderedPageCount(for: attachment)
            }
        }
    }

    private func renderedPageCount(for attachment: Attachment) -> Int {
        guard attachmentCanBePDF(attachment),
              let documentURL = resolvedLocalFileURL(for: attachment.localFilePath),
              let document = PDFDocument(url: documentURL)
        else {
            return 1
        }

        return max(1, document.pageCount)
    }

    private func attachmentCanBePDF(_ attachment: Attachment) -> Bool {
        if attachment.attachmentType == .pdf {
            return true
        }

        if isPDFTypeIdentifier(attachment.uniformTypeIdentifier) {
            return true
        }

        let localFileExtension = URL(filePath: attachment.localFilePath).pathExtension
        let originalFileExtension = URL(filePath: attachment.originalFilename).pathExtension
        if localFileExtension.caseInsensitiveCompare("pdf") == .orderedSame ||
            originalFileExtension.caseInsensitiveCompare("pdf") == .orderedSame {
            return true
        }

        return attachment.attachmentType == .document || attachment.attachmentType == .other
    }

    private func isPDFTypeIdentifier(_ value: String?) -> Bool {
        guard let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty else {
            return false
        }

        return normalized == "com.adobe.pdf" ||
            normalized == "public.pdf" ||
            normalized.contains("pdf")
    }

    private func resolvedLocalFileURL(for storedPath: String?) -> URL? {
        guard let storedPath else { return nil }
        let trimmedPath = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        var candidates: [URL] = []
        appendResolvedURLCandidates(from: trimmedPath, to: &candidates)
        if let decodedPath = trimmedPath.removingPercentEncoding, decodedPath != trimmedPath {
            appendResolvedURLCandidates(from: decodedPath, to: &candidates)
        }

        let fileManager = FileManager.default
        return candidates.first { candidate in
            fileManager.fileExists(atPath: candidate.path(percentEncoded: false))
        }
    }

    private func appendResolvedURLCandidates(from path: String, to candidates: inout [URL]) {
        if let fileURL = URL(string: path), fileURL.isFileURL {
            appendUniqueURL(fileURL, to: &candidates)
        }

        appendUniqueURL(URL(filePath: path), to: &candidates)

        if let proofKitRange = path.range(of: "/ProofKit/") {
            let relativePath = String(path[proofKitRange.upperBound...])
            appendUniqueURL(localStorageBaseDirectory.appending(path: relativePath), to: &candidates)
        } else if path.hasPrefix("ProofKit/") {
            let relativePath = String(path.dropFirst("ProofKit/".count))
            appendUniqueURL(localStorageBaseDirectory.appending(path: relativePath), to: &candidates)
        } else if !path.hasPrefix("/") && !path.hasPrefix("file://") {
            appendUniqueURL(localStorageBaseDirectory.appending(path: path), to: &candidates)
        }
    }

    private func appendUniqueURL(_ url: URL, to candidates: inout [URL]) {
        let path = url.path(percentEncoded: false)
        guard !candidates.contains(where: { $0.path(percentEncoded: false) == path }) else {
            return
        }

        candidates.append(url)
    }

    @MainActor
    private func generatePDF() async {
        guard !isExporting else { return }
        let analyticsStartedAt = Date()
        services.analytics.trackPDFExportStarted(caseFile: caseFile)

        withAnimation(ProofKitMotion.standard) {
            isExporting = true
            exportErrorMessage = nil
        }

        do {
            let access = await services.paywall.exportAccess(for: caseFile)
            exportAccess = access
            guard access.isAllowed else {
                throw ProofKitError.planLimitReached(access.blockedMessage ?? "This plan has reached its export limit.")
            }
            let signatureForExport = access.plan == .pro ? signatureConfiguration : nil

            let result = try await services.pdfExporter.exportCasePDF(
                PDFExportRequest(
                    caseFile: caseFile,
                    destinationDirectory: exportDirectory,
                    exportMode: exportMode,
                    includeStatementPlaceholder: includeStatementPlaceholder,
                    includeProofKitWatermark: access.isWatermarked,
                    signatureStamp: signatureForExport?.stamp
                )
            )

            let now = result.generatedAt
            let exportID = UUID()
            let signedPDFSHA256 = try signatureForExport.map { _ in
                try Self.sha256HexDigest(forFileAt: result.url)
            }
            if let signatureForExport, let signedPDFSHA256 {
                let finalizeResponse = try await services.signatureValidation.finalizePDFSignatureToken(
                    PDFSignatureTokenFinalizeRequest(
                        validationToken: signatureForExport.validationToken,
                        signedPDFSHA256: signedPDFSHA256,
                        exportID: exportID
                    )
                )
                guard finalizeResponse.valid else {
                    throw ProofKitError.remotePolicyViolation(
                        finalizeResponse.reason ?? "Proofly could not finalize this signature token."
                    )
                }
            }

            let caseExport = ExportPacket(
                id: exportID,
                userPacketTitle: result.caseTitle,
                userPacketNotes: "Generated locally from current Proofly proof.",
                localPDFFilePath: result.url.path(percentEncoded: false),
                fileSizeBytes: result.fileSizeBytes,
                pageCount: result.pageCount,
                includedEvidenceItemIDsJSON: encodedEvidenceIDs(result.includedEvidenceItemIDs),
                exportOptionsJSON: exportOptionsJSON(access: access, signedPDFSHA256: signedPDFSHA256),
                createdAt: now,
                exportedAt: now
            )

            modelContext.insert(caseExport)
            caseFile.exportPackets.append(caseExport)
            caseFile.updatedAt = now
            try modelContext.save()

            withAnimation(ProofKitMotion.softSpring) {
                latestExportURL = result.url
                if activePreviewURL != nil {
                    activePreviewURL = result.url
                }
            }
            services.analytics.trackPDFExportCompleted(
                caseFile: caseFile,
                durationMS: Self.analyticsDurationMS(since: analyticsStartedAt)
            )
            await refreshExportAccess()
        } catch {
            services.analytics.trackPDFExportFailed(
                caseFile: caseFile,
                durationMS: Self.analyticsDurationMS(since: analyticsStartedAt),
                errorType: AnalyticsErrorType(error)
            )
            withAnimation(ProofKitMotion.standard) {
                exportErrorMessage = error.localizedDescription
            }
        }

        withAnimation(ProofKitMotion.standard) {
            isExporting = false
        }
    }

    private static func analyticsDurationMS(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }

    private var exportDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "Proofly")
            .appending(path: "Exports")
            .appending(path: "Cases")
            .appending(path: caseFile.id.uuidString)
    }

    private func encodedEvidenceIDs(_ ids: [UUID]) -> String {
        let values = ids.map(\.uuidString)
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return string
    }

    private func exportOptionsJSON(access: ProofKitExportAccess, signedPDFSHA256: String? = nil) -> String {
        let values: [String: Any] = [
            "exportMode": exportMode.rawValue,
            "includeStatementPlaceholder": includeStatementPlaceholder,
            "renderer": "PDFKit/UIKit",
            "aiUsed": false,
            "paywallPlan": access.plan.rawValue,
            "watermarked": access.isWatermarked,
            "watermarkPlacement": access.isWatermarked ? "top+footer" : "none",
            "diagonalWatermark": false,
            "freeExportWatermark": access.isWatermarked ? "Top: proofly; Footer: Generated with Proofly" : "",
            "signatureIncluded": access.plan == .pro && signatureConfiguration != nil,
            "signaturePage": signatureConfiguration?.page.rawValue ?? "",
            "signaturePlacement": signatureConfiguration?.placement.rawValue ?? "",
            "signatureSignedAt": signatureConfiguration.map { Self.exportOptionDateFormatter.string(from: $0.signedAt) } ?? "",
            "signatureValidationToken": signatureConfiguration?.validationToken ?? "",
            "signatureAlgorithm": signatureConfiguration?.algorithm ?? "",
            "signatureKeyVersion": signatureConfiguration?.keyVersion ?? "",
            "signatureManifestSHA256": signatureConfiguration?.manifestSHA256 ?? "",
            "signatureManifestSignature": signatureConfiguration?.manifestSignature ?? "",
            "signatureVerificationURL": signatureConfiguration?.verificationURL?.absoluteString ?? "",
            "signedPDFSHA256": signedPDFSHA256 ?? ""
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return string
    }

    @MainActor
    private func refreshExportAccess() async {
        exportAccess = await services.paywall.exportAccess(for: caseFile)
    }

    private var exportPlanMessage: String {
        switch exportAccess.plan {
        case .free:
            "Exports without active Pro add a small top Proofly mark and footer mark. No diagonal watermark."
        case .paidUrgentExport:
            "Paid Urgent Export creates one final PDF for this case without a Proofly watermark."
        case .pro:
            "Pro export creates PDFs without a Proofly watermark."
        }
    }

    private var signatureSummary: String {
        guard let signatureConfiguration else {
            return "Not added"
        }

        return "\(signatureConfiguration.page.displayName), \(signatureConfiguration.placement.displayName.lowercased())"
    }

    private var signatureControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label("PDF signature", systemImage: "signature")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Button {
                    Task { await beginSignatureFlow() }
                } label: {
                    Label(
                        isIssuingSignatureToken ? "Securing…" : (signatureConfiguration == nil ? "Add" : "Edit"),
                        systemImage: isIssuingSignatureToken ? "lock.shield" : (signatureConfiguration == nil ? "plus" : "pencil")
                    )
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(isIssuingSignatureToken || isExporting)
            }

            if let signatureConfiguration {
                HStack(spacing: 12) {
                    Image(uiImage: signatureConfiguration.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 54)
                        .padding(6)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(ProofKitVisual.fieldBackground)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(signatureSummary)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)

                        Text("Token \(signatureConfiguration.validationToken)")
                            .font(.caption2.monospaced().weight(.medium))
                            .foregroundStyle(ProofKitVisual.subduedText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Button("Remove signature") {
                            withAnimation(ProofKitMotion.standard) {
                                self.signatureConfiguration = nil
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }

                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: exportAccess.plan == .pro ? "checkmark.seal" : "lock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(exportAccess.plan == .pro ? ExportPagePalette.ready : ProofKitVisual.helperText)

                    Text(isIssuingSignatureToken ? "Creating secure validation token…" : (exportAccess.plan == .pro ? "Draw and place a signature before generating." : "Available with Pro."))
                        .font(.caption)
                        .foregroundStyle(ProofKitVisual.subduedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @MainActor
    private func completeSignature(image: UIImage, page: PDFSignaturePage, placement: PDFSignaturePlacement, customOffset: CGPoint?) async {
        let signedAt = Date()
        let sourceExport = generatedExport
        let shouldGenerateSignedPDF = sourceExport != nil

        withAnimation(ProofKitMotion.standard) {
            isSignatureSheetPresented = false
            isIssuingSignatureToken = true
            exportErrorMessage = nil
        }

        do {
            let signatureImageSHA256 = try Self.sha256HexDigest(for: image)
            let sourcePDFSHA256 = try sourceExport.map { try Self.sha256HexDigest(forFileAt: $0.url) }
            let issueResponse = try await services.signatureValidation.issuePDFSignatureToken(
                PDFSignatureTokenIssueRequest(
                    caseID: caseFile.id,
                    exportID: sourceExport?.packet.id,
                    sourcePDFSHA256: sourcePDFSHA256,
                    signatureImageSHA256: signatureImageSHA256,
                    signaturePage: page.rawValue,
                    signaturePlacement: placement.rawValue,
                    signedAt: Self.exportOptionDateFormatter.string(from: signedAt),
                    appVersion: Self.appVersion,
                    pdfExportMode: exportMode.rawValue,
                    includeStatementPlaceholder: includeStatementPlaceholder
                )
            )

            signatureConfiguration = ExportSignatureConfiguration(
                image: image,
                page: page,
                placement: placement,
                customOffset: customOffset,
                signedAt: signedAt,
                validationToken: issueResponse.validationToken,
                encryptedManifest: issueResponse.encryptedManifest,
                manifestSignature: issueResponse.manifestSignature,
                manifestSHA256: issueResponse.manifestSHA256,
                algorithm: issueResponse.algorithm,
                keyVersion: issueResponse.keyVersion,
                verificationURL: issueResponse.verificationURL
            )

            withAnimation(ProofKitMotion.standard) {
                isIssuingSignatureToken = false
            }

            guard shouldGenerateSignedPDF else { return }
            await generatePDF()
        } catch {
            withAnimation(ProofKitMotion.standard) {
                isIssuingSignatureToken = false
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func beginSignatureFlow() async {
        let entitlement = await services.paywall.currentEntitlement()
        await refreshExportAccess()

        guard entitlement.plan == .pro else {
            shouldOpenSignatureAfterPaywall = false
            isSignaturePaywallPresented = true
            return
        }

        isSignatureSheetPresented = true
    }

    @MainActor
    private func openSignatureAfterPaywallIfNeeded() {
        guard shouldOpenSignatureAfterPaywall else { return }
        shouldOpenSignatureAfterPaywall = false
        isSignatureSheetPresented = true
    }

    private func localURL(for caseExport: ExportPacket) -> URL? {
        guard let path = caseExport.localPDFFilePath,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        return URL(filePath: path)
    }

    private func generatedDateText(for caseExport: ExportPacket) -> String {
        guard let exportedAt = caseExport.exportedAt else { return "Unavailable" }
        return Self.exportDateFormatter.string(from: exportedAt)
    }

    private func pageCountText(for caseExport: ExportPacket) -> String {
        guard let pageCount = caseExport.pageCount else { return "Unavailable" }
        return pageCount == 1 ? "1 page" : "\(pageCount) pages"
    }

    private func fileSizeText(for caseExport: ExportPacket) -> String {
        guard let fileSizeBytes = caseExport.fileSizeBytes else { return "Unavailable" }
        return Self.fileSizeFormatter.string(fromByteCount: fileSizeBytes)
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private static let exportOptionDateFormatter = ISO8601DateFormatter()

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let value = [version, build]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return value.isEmpty ? "unknown" : value
    }

    private static func sha256HexDigest(for image: UIImage) throws -> String {
        guard let imageData = image.pngData() ?? image.jpegData(compressionQuality: 0.95) else {
            throw ProofKitError.remotePolicyViolation("Proofly could not prepare the signature for validation.")
        }

        return sha256HexDigest(for: imageData)
    }

    private static func sha256HexDigest(forFileAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return sha256HexDigest(for: data)
    }

    private static func sha256HexDigest(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private enum ExportScreenState {
    case almostReady
    case ready
    case generated(ExportPacket, URL)
}

private struct ExportSignatureConfiguration {
    let image: UIImage
    let page: PDFSignaturePage
    let placement: PDFSignaturePlacement
    let customOffset: CGPoint?
    let signedAt: Date
    let validationToken: String
    let encryptedManifest: String
    let manifestSignature: String
    let manifestSHA256: String
    let algorithm: String
    let keyVersion: String
    let verificationURL: URL?

    var stamp: PDFSignatureStamp {
        PDFSignatureStamp(
            image: image,
            page: page,
            placement: placement,
            customOffset: customOffset,
            signedAt: signedAt,
            validationToken: validationToken,
            encryptedManifest: encryptedManifest,
            manifestSignature: manifestSignature,
            manifestSHA256: manifestSHA256,
            algorithm: algorithm,
            keyVersion: keyVersion
        )
    }
}

private enum ExportPagePalette {
    static let ready = Color(red: 0.16, green: 0.82, blue: 0.78)
    static let guidance = Color(red: 0.91, green: 0.68, blue: 0.31)
}

private struct MissingExportItem: Identifiable {
    let title: String
    let systemImage: String

    var id: String { title }
}

private struct ExportRookImage: View {
    let imageName: String

    var body: some View {
        Image(imageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 124, height: 124)
            .accessibilityHidden(true)
            .shadow(color: ProofKitVisual.elevatedShadow, radius: 12, x: 0, y: 8)
    }
}

private struct ExportStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .textCase(.uppercase)
            .tracking(0.5)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(color.opacity(0.15))
            }
    }
}

private struct ExportActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .imageScale(.medium)

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.88)
                .allowsTightening(true)
        }
        .fontWeight(.semibold)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ExportDetailsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ProofKitVisual.helperText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ProofKitVisual.divider)
                .frame(height: 1)
        }
    }
}

private struct PDFKitPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = ProofKitVisual.pdfPreviewBackgroundUIColor
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
    }
}

#Preview {
    ExportPreviewView(
        caseFile: CaseFile(
            caseType: .apartmentIssue,
            status: .active,
            userTitle: "Housing lease timeline",
            userSummary: "Records related to repair requests, messages, photos, and receipts.",
            evidenceItems: [
                EvidenceItem(
                    category: .photo,
                    userDateSource: .userEntered,
                    userTitle: "Kitchen ceiling leak photo",
                    userNotes: "Photo taken after the first maintenance request.",
                    userProvidedEventDate: .now,
                    userMarkedImportant: true,
                    isReviewed: true
                )
            ]
        )
    )
    .padding()
    .background(Color(.systemGroupedBackground))
    .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self, AIResultCache.self], inMemory: true)
}
