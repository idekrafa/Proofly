import PDFKit
import SwiftData
import SwiftUI

struct ExportPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.proofKitServices) private var services

    let caseFile: CaseFile
    private let skippedEvidenceIDs: Set<UUID>
    private let onAddProof: () -> Void

    @State private var includeStatementPlaceholder = true
    @State private var isExporting = false
    @State private var exportErrorMessage: String?
    @State private var latestExportURL: URL?
    @State private var activePreviewURL: URL?
    @State private var exportAccess = ProofKitExportAccess.placeholderFree
    @State private var showMissingItems = true
    @State private var isPacketDetailsExpanded = false

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
            "ready-\(estimatedPageCount)-\(caseFile.evidenceItems.count)-\(includeStatementPlaceholder)"
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
        .animation(ProofKitMotion.standard, value: previewPDFURL)
        .animation(ProofKitMotion.standard, value: latestExport?.id)
        .animation(ProofKitMotion.standard, value: exportScreenStateID)
        .task {
            await refreshExportAccess()
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
            subtitle: "About \(estimatedPageCount) pages with \(proofItemCountText) and your timeline."
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
                        sharePacketLink(url: url)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 10) {
                        viewPacketButton(url: url)
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
                ExportDetailsRow(title: "Proof items", value: "\(caseFile.evidenceItems.count)")
                ExportDetailsRow(title: "Timeline", value: timelineReady ? "Included" : "Needs proof")
                ExportDetailsRow(title: "Attachments", value: attachmentCount == 0 ? "None" : "\(attachmentCount)")
                ExportDetailsRow(title: "Watermark", value: watermarkSummary)

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

    private var attachmentCount: Int {
        caseFile.evidenceItems.reduce(0) { $0 + $1.attachments.count }
    }

    private var watermarkSummary: String {
        exportAccess.isWatermarked ? "Footer only" : "None"
    }

    private var estimatedPageCount: Int {
        let evidenceCount = caseFile.evidenceItems.count
        let timelinePages = max(1, Int(ceil(Double(max(evidenceCount, 1)) / 5.0)))
        let indexPages = max(1, Int(ceil(Double(max(evidenceCount, 1)) / 14.0)))
        let evidenceItemPages = evidenceCount
        let longTextOverflowPages = caseFile.evidenceItems.reduce(0) { count, evidenceItem in
            let textLength = evidenceItem.userNotes.count + evidenceItem.userCleanedNote.count + evidenceItem.userWhyThisMatters.count + evidenceItem.originalOCRText.count
            return count + max(0, Int(ceil(Double(textLength - 2_400) / 2_400.0)))
        }
        let attachmentOverflowPages = caseFile.evidenceItems.reduce(0) { count, evidenceItem in
            count + max(0, Int(ceil(Double(evidenceItem.attachments.count - 3) / 4.0)))
        }
        let statementPages = includeStatementPlaceholder ? 1 : 0

        return 2 + timelinePages + indexPages + evidenceItemPages + longTextOverflowPages + attachmentOverflowPages + statementPages
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

            let result = try await services.pdfExporter.exportCasePDF(
                PDFExportRequest(
                    caseFile: caseFile,
                    destinationDirectory: exportDirectory,
                    includeStatementPlaceholder: includeStatementPlaceholder,
                    includeProofKitWatermark: access.isWatermarked
                )
            )

            let now = result.generatedAt
            let caseExport = ExportPacket(
                userPacketTitle: result.caseTitle,
                userPacketNotes: "Generated locally from current ProofKit proof.",
                localPDFFilePath: result.url.path(percentEncoded: false),
                fileSizeBytes: result.fileSizeBytes,
                pageCount: result.pageCount,
                includedEvidenceItemIDsJSON: encodedEvidenceIDs(result.includedEvidenceItemIDs),
                exportOptionsJSON: exportOptionsJSON(access: access),
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
            .appending(path: "ProofKit")
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

    private func exportOptionsJSON(access: ProofKitExportAccess) -> String {
        let values: [String: Any] = [
            "includeStatementPlaceholder": includeStatementPlaceholder,
            "renderer": "PDFKit/UIKit",
            "aiUsed": false,
            "paywallPlan": access.plan.rawValue,
            "watermarked": access.isWatermarked,
            "watermarkPlacement": access.isWatermarked ? "footer" : "none",
            "diagonalWatermark": false,
            "freeExportWatermark": access.isWatermarked ? "Footer: Generated with ProofKit" : ""
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
            "Free export adds a small footer-only ProofKit mark. No diagonal watermark."
        case .paidUrgentExport:
            "Paid Urgent Export creates one final PDF for this case without a ProofKit watermark."
        case .pro:
            "Pro export creates PDFs without a ProofKit watermark."
        }
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
}

private enum ExportScreenState {
    case almostReady
    case ready
    case generated(ExportPacket, URL)
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
