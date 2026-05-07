import PDFKit
import SwiftData
import SwiftUI

struct ExportPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.proofKitServices) private var services

    let caseFile: CaseFile

    @State private var includeStatementPlaceholder = true
    @State private var isExporting = false
    @State private var exportErrorMessage: String?
    @State private var latestExportURL: URL?
    @State private var activePreviewURL: URL?
    @State private var exportAccess = ProofKitExportAccess.placeholderFree

    private var latestExport: ExportPacket? {
        caseFile.sortedExportPackets.first
    }

    private var currentExportURL: URL? {
        latestExportURL ?? latestExport.flatMap { localURL(for: $0) }
    }

    private var previewPDFURL: URL? {
        activePreviewURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Export",
                subtitle: "Create a professional PDF packet from the records stored on this device."
            )

            exportHero
                .proofKitAppear()
            readinessChecklist
                .proofKitAppear(delay: 0.04)
            packetSummaryCard
                .proofKitAppear(delay: 0.08)

            if let previewPDFURL {
                pdfPreviewCard(url: previewPDFURL)
                    .transition(ProofKitMotion.cardInsertion)
                    .proofKitAppear(delay: 0.06)
            }

            recentExportCard
                .transition(ProofKitMotion.compactInsertion)
                .proofKitAppear(delay: 0.10)

            Color.clear
                .frame(height: 88)
        }
        .animation(ProofKitMotion.standard, value: isExporting)
        .animation(ProofKitMotion.standard, value: previewPDFURL)
        .animation(ProofKitMotion.standard, value: latestExport?.id)
        .task {
            await refreshExportAccess()
        }
    }

    private var exportHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PacketDocumentIcon()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ExportStatusPill(text: "Export tab selected", systemImage: "checkmark.circle.fill")
                        ExportStatusPill(text: "\(estimatedPageCount)-page estimate", systemImage: "doc.text")
                    }

                    Text("Generate a clean evidence packet")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("A local PDF with cover page, timeline, evidence index, and attachment references.")
                        .font(.subheadline)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    primaryGenerateButton
                    previewPacketButton
                }

                VStack(spacing: 10) {
                    primaryGenerateButton
                    previewPacketButton
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(exportPlanMessage, systemImage: exportAccess.isWatermarked ? "text.badge.checkmark" : "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)

                Label("Private by default: the PDF is saved locally and shared only when you choose.", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let blockedMessage = exportAccess.blockedMessage {
                Text(blockedMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(ProofKitMotion.compactInsertion)
            }

            if let exportErrorMessage {
                Text(exportErrorMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(ProofKitMotion.compactInsertion)
            }
        }
        .padding(ProofKitVisual.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(ProofKitVisual.surfaceGradient)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
        .shadow(color: ProofKitVisual.elevatedShadow, radius: 18, x: 0, y: 10)
    }

    private var primaryGenerateButton: some View {
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
        .disabled(isExporting)
    }

    private var previewPacketButton: some View {
        Button {
            Task { await previewPacket() }
        } label: {
            Label("Preview packet", systemImage: "eye")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isExporting)
    }

    private var readinessChecklist: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Case readiness")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(caseTitle)
                        .font(.subheadline)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                ExportReadinessBadge(readyCount: readyChecklistCount, totalCount: readinessItems.count)
            }

            VStack(spacing: 0) {
                ForEach(readinessItems) { item in
                    ReadinessChecklistRow(item: item)

                    if item.id != readinessItems.last?.id {
                        Divider()
                            .padding(.leading, 34)
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
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
    }

    private var packetSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "doc.plaintext")
                    .font(.title2)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Packet summary")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("About \(estimatedPageCount) pages")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(attachmentBehaviorText)
                        .font(.caption)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ExportMetric(title: "Evidence", value: "\(caseFile.evidenceItems.count)")
                ExportMetric(title: "Timeline", value: timelineReady ? "Included" : "Add proof")
                ExportMetric(title: "Attachments", value: attachmentCount == 0 ? "None" : "\(attachmentCount)")
                ExportMetric(title: "Watermark", value: watermarkSummary)
            }

            Toggle(isOn: $includeStatementPlaceholder) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Statement placeholder optional")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("Adds one blank page for a statement prepared outside ProofKit.")
                        .font(.caption)
                        .foregroundStyle(ProofKitVisual.helperText)
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
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
    }

    private func pdfPreviewCard(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Packet preview")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            PDFKitPreview(url: url)
                .frame(height: 460)
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

    @ViewBuilder
    private var recentExportCard: some View {
        if let latestExport {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Latest export")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 12)

                    if let exportedAt = latestExport.exportedAt {
                        Text(Self.exportDateFormatter.string(from: exportedAt))
                            .font(.caption)
                            .foregroundStyle(ProofKitVisual.helperText)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(latestExport.userPacketTitle.caseTerminologyForDisplay)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        ExportMetadataPill(text: pageCountText(for: latestExport))
                        ExportMetadataPill(text: fileSizeText(for: latestExport))
                    }

                    latestExportActions(for: latestExport)
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
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Latest export")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc")
                        .font(.title3)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("No PDF packet yet")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Generate PDF Packet to create a local file you can view or share.")
                            .font(.caption)
                            .foregroundStyle(ProofKitVisual.helperText)
                            .fixedSize(horizontal: false, vertical: true)
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
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func latestExportActions(for latestExport: ExportPacket) -> some View {
        if let url = localURL(for: latestExport) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(ProofKitMotion.standard) {
                            activePreviewURL = url
                        }
                    } label: {
                        Label("View", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await generatePDF() }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExporting)
                }

                VStack(spacing: 10) {
                    Button {
                        withAnimation(ProofKitMotion.standard) {
                            activePreviewURL = url
                        }
                    } label: {
                        Label("View", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await generatePDF() }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExporting)
                }
            }
            .font(.subheadline.weight(.semibold))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("The saved PDF is no longer available on this device.")
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.helperText)

                Button {
                    Task { await generatePDF() }
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isExporting)
            }
        }
    }

    private var readinessItems: [CaseReadinessItem] {
        [
            CaseReadinessItem(
                title: "Case details complete",
                detail: caseDetailsReady ? "Title and case type are ready for the cover page." : "Add a title or ProofKit will use Untitled Case.",
                isReady: caseDetailsReady
            ),
            CaseReadinessItem(
                title: "Timeline included",
                detail: timelineReady ? "\(caseFile.evidenceItems.count) evidence records will be shown chronologically." : "Add proof to include timeline entries.",
                isReady: timelineReady
            ),
            CaseReadinessItem(
                title: "Evidence index ready",
                detail: evidenceIndexReady ? "Index will include every evidence item." : "Add proof to create an evidence index.",
                isReady: evidenceIndexReady
            ),
            CaseReadinessItem(
                title: "Attachments included",
                detail: attachmentsReady ? attachmentBehaviorText : "No local attachments yet. Text notes can still be included.",
                isReady: attachmentsReady
            ),
            CaseReadinessItem(
                title: "Statement placeholder optional",
                detail: includeStatementPlaceholder ? "One blank statement page will be added." : "No statement page will be added.",
                isReady: true
            )
        ]
    }

    private var readyChecklistCount: Int {
        readinessItems.filter(\.isReady).count
    }

    private var caseTitle: String {
        let title = caseFile.userTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "ProofKit Evidence Case" : "\(title) Evidence Case"
    }

    private var timelineReady: Bool {
        !caseFile.evidenceItems.isEmpty
    }

    private var caseDetailsReady: Bool {
        !caseFile.userTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var evidenceIndexReady: Bool {
        !caseFile.evidenceItems.isEmpty
    }

    private var attachmentsReady: Bool {
        attachmentCount > 0
    }

    private var attachmentCount: Int {
        caseFile.evidenceItems.reduce(0) { $0 + $1.attachments.count }
    }

    private var attachmentBehaviorText: String {
        switch attachmentCount {
        case 0:
            "No local attachments will be listed."
        case 1:
            "1 local attachment will be listed as a reference in the packet."
        default:
            "\(attachmentCount) local attachments will be listed as references in the packet."
        }
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
                userPacketNotes: "Generated locally from current ProofKit records.",
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
                activePreviewURL = result.url
            }
            await refreshExportAccess()
        } catch {
            withAnimation(ProofKitMotion.standard) {
                exportErrorMessage = error.localizedDescription
            }
        }

        withAnimation(ProofKitMotion.standard) {
            isExporting = false
        }
    }

    @MainActor
    private func previewPacket() async {
        guard !isExporting else { return }

        if let currentExportURL {
            withAnimation(ProofKitMotion.standard) {
                activePreviewURL = currentExportURL
                exportErrorMessage = nil
            }
        } else {
            await generatePDF()
        }
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
            "Free export: small footer-only “Generated with ProofKit” mark. No diagonal watermark."
        case .paidUrgentExport:
            "Paid Urgent Export: one final non-watermarked PDF for this case."
        case .pro:
            "Pro export: no ProofKit watermark."
        }
    }

    private func localURL(for caseExport: ExportPacket) -> URL? {
        guard let path = caseExport.localPDFFilePath,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        return URL(filePath: path)
    }

    private func pageCountText(for caseExport: ExportPacket) -> String {
        guard let pageCount = caseExport.pageCount else { return "Pages unavailable" }
        return pageCount == 1 ? "1 page" : "\(pageCount) pages"
    }

    private func fileSizeText(for caseExport: ExportPacket) -> String {
        guard let fileSizeBytes = caseExport.fileSizeBytes else { return "Size unavailable" }
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

private struct CaseReadinessItem: Identifiable {
    let title: String
    let detail: String
    let isReady: Bool

    var id: String { title }
}

private struct ReadinessChecklistRow: View {
    let item: CaseReadinessItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.isReady ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.isReady ? Color.green : ProofKitVisual.helperText)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }
}

private struct ExportReadinessBadge: View {
    let readyCount: Int
    let totalCount: Int

    var body: some View {
        Text("\(readyCount)/\(totalCount) ready")
            .font(.caption.weight(.semibold))
            .foregroundStyle(ProofKitVisual.helperText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(ProofKitVisual.quietFill)
            }
    }
}

private struct PacketDocumentIcon: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ProofKitVisual.cardBackground)
                .frame(width: 58, height: 74)
                .shadow(color: ProofKitVisual.elevatedShadow, radius: 10, x: 0, y: 5)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(ProofKitVisual.helperText.opacity(0.45))
                            .frame(width: 26, height: 3)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(ProofKitVisual.cardBorder)
                            .frame(width: 34, height: 3)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(ProofKitVisual.cardBorder)
                            .frame(width: 28, height: 3)
                    }
                    .padding(12)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
                }

            Text("PDF")
                .font(.caption2.weight(.bold))
                .foregroundStyle(ProofKitVisual.primaryActionForeground)
                .tracking(0.4)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background {
                    Capsule(style: .continuous)
                        .fill(ProofKitVisual.primaryActionBackground)
                }
                .offset(x: 7, y: 7)
        }
        .frame(width: 68, height: 82)
        .accessibilityHidden(true)
    }
}

private struct ExportStatusPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(ProofKitVisual.helperText)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(ProofKitVisual.quietFill)
            }
    }
}

private extension String {
    var caseTerminologyForDisplay: String {
        replacingOccurrences(of: "Evidence Packet", with: "Evidence Case")
            .replacingOccurrences(of: "evidence packet", with: "evidence case")
            .replacingOccurrences(of: "Packet", with: "Case")
            .replacingOccurrences(of: "packet", with: "case")
    }
}

private struct ExportMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ProofKitVisual.subduedText)

            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ProofKitVisual.fieldBackground)
        }
    }
}

private struct ExportMetadataPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(ProofKitVisual.helperText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(ProofKitVisual.quietFill)
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
            userTitle: "Apartment repair timeline",
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
