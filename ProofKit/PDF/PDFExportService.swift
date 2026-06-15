import Foundation
import ImageIO
import PDFKit
import UIKit

private extension UIColor {
    static let pdfInk = UIColor(red: 0.09, green: 0.09, blue: 0.085, alpha: 1)
    static let pdfSecondary = UIColor(red: 0.31, green: 0.31, blue: 0.29, alpha: 1)
    static let pdfTertiary = UIColor(red: 0.52, green: 0.52, blue: 0.49, alpha: 1)
    static let pdfDivider = UIColor(red: 0.73, green: 0.72, blue: 0.68, alpha: 1)
    static let pdfPanel = UIColor(red: 0.985, green: 0.982, blue: 0.965, alpha: 1)
    static let pdfPanelAlt = UIColor(red: 0.955, green: 0.952, blue: 0.93, alpha: 1)
}

struct PDFExportRequest {
    let caseFile: CaseFile
    let destinationDirectory: URL
    let exportMode: PDFExportMode
    let includeStatementPlaceholder: Bool
    let includeProofKitWatermark: Bool
    let signatureStamp: PDFSignatureStamp?
    let generatedAt: Date

    init(
        caseFile: CaseFile,
        destinationDirectory: URL,
        exportMode: PDFExportMode = .cleanPacket,
        includeStatementPlaceholder: Bool = false,
        includeProofKitWatermark: Bool = true,
        signatureStamp: PDFSignatureStamp? = nil,
        generatedAt: Date = .now
    ) {
        self.caseFile = caseFile
        self.destinationDirectory = destinationDirectory
        self.exportMode = exportMode
        self.includeStatementPlaceholder = includeStatementPlaceholder
        self.includeProofKitWatermark = includeProofKitWatermark
        self.signatureStamp = signatureStamp
        self.generatedAt = generatedAt
    }
}

struct PDFSignatureStamp {
    let image: UIImage
    let page: PDFSignaturePage
    let placement: PDFSignaturePlacement
    let signedAt: Date
    let validationToken: String
}

enum PDFSignaturePage: String, CaseIterable, Hashable, Identifiable {
    case firstPage
    case lastPage
    case everyPage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firstPage:
            "First page"
        case .lastPage:
            "Last page"
        case .everyPage:
            "Every page"
        }
    }
}

enum PDFSignaturePlacement: String, CaseIterable, Hashable, Identifiable {
    case upperLeft
    case upperRight
    case center
    case lowerLeft
    case lowerRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .upperLeft:
            "Upper left"
        case .upperRight:
            "Upper right"
        case .center:
            "Center"
        case .lowerLeft:
            "Lower left"
        case .lowerRight:
            "Lower right"
        }
    }
}

enum PDFExportMode: String, CaseIterable, Hashable, Identifiable {
    case cleanPacket
    case fullArchive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cleanPacket:
            "Clean Packet"
        case .fullArchive:
            "Full Archive"
        }
    }

    var shortDescription: String {
        switch self {
        case .cleanPacket:
            "Rendered files only on blank pages"
        case .fullArchive:
            "Adds cover, timeline, index, notes, metadata, and rendered files"
        }
    }
}

struct PDFExportResult {
    let url: URL
    let pageCount: Int
    let fileSizeBytes: Int64
    let generatedAt: Date
    let caseTitle: String
    let includedEvidenceItemIDs: [UUID]
}

@MainActor
protocol PDFExportServicing {
    func exportCasePDF(_ request: PDFExportRequest) async throws -> PDFExportResult
}

struct PDFExportService: PDFExportServicing {
    func exportCasePDF(_ request: PDFExportRequest) async throws -> PDFExportResult {
        try FileManager.default.createDirectory(
            at: request.destinationDirectory,
            withIntermediateDirectories: true
        )

        let caseTitle = PDFCaseRenderer.caseTitle(for: request.caseFile)
        let filename = Self.exportFilename(title: caseTitle, generatedAt: request.generatedAt)
        let destinationURL = Self.uniqueDestinationURL(
            in: request.destinationDirectory,
            filename: filename
        )

        let renderer = PDFCaseRenderer(request: request, caseTitle: caseTitle)
        try renderer.render(to: destinationURL)

        let fileSize = try Self.fileSize(at: destinationURL)
        let pageCount = PDFDocument(url: destinationURL)?.pageCount ?? renderer.renderedPageCount

        return PDFExportResult(
            url: destinationURL,
            pageCount: pageCount,
            fileSizeBytes: fileSize,
            generatedAt: request.generatedAt,
            caseTitle: caseTitle,
            includedEvidenceItemIDs: renderer.includedEvidenceItemIDs
        )
    }

    private static func exportFilename(title: String, generatedAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"

        return "\(safeFilename(title))-\(formatter.string(from: generatedAt)).pdf"
    }

    private static func safeFilename(_ value: String) -> String {
        let fallback = "Proofly-Proof-Packet"
        let illegalCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: illegalCharacters)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "-")

        let collapsed = cleaned
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")

        return collapsed.isEmpty ? fallback : String(collapsed.prefix(80))
    }

    private static func uniqueDestinationURL(in directory: URL, filename: String) -> URL {
        let baseURL = directory.appending(path: filename)
        guard FileManager.default.fileExists(atPath: baseURL.path(percentEncoded: false)) else {
            return baseURL
        }

        let baseName = baseURL.deletingPathExtension().lastPathComponent
        let pathExtension = baseURL.pathExtension

        for suffix in 2...10_000 {
            let candidate = directory
                .appending(path: "\(baseName)-\(suffix)")
                .appendingPathExtension(pathExtension)
            if !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }

        return directory
            .appending(path: "\(baseName)-overflow")
            .appendingPathExtension(pathExtension)
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false)
        )
        let size = attributes[.size] as? NSNumber
        return size?.int64Value ?? 0
    }
}

@MainActor
private final class PDFCaseRenderer {
    private let request: PDFExportRequest
    private let caseFile: CaseFile
    private let caseTitleValue: String
    private let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    private let margin: CGFloat = 44
    private let contentBottom: CGFloat = 732
    private let headerTop: CGFloat = 34
    private let headerBottom: CGFloat = 78
    private var cursorY: CGFloat = 0
    private var currentPageTitle = ""
    private var currentPageSubtitle: String?
    private var hasOpenPage = false
    private var pageNumber = 0

    var renderedPageCount: Int { pageNumber }

    var includedEvidenceItemIDs: [UUID] {
        evidenceItems.map(\.id)
    }

    private var contentWidth: CGFloat {
        pageRect.width - (margin * 2)
    }

    private var localStorageBaseDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "ProofKit")
    }

    private var evidenceItems: [EvidenceItem] {
        caseFile.evidenceItems.sorted { lhs, rhs in
            let lhsDate = localEventDate(for: lhs) ?? lhs.createdAt
            let rhsDate = localEventDate(for: rhs) ?? rhs.createdAt

            if lhsDate == rhsDate {
                if lhs.sortIndex == rhs.sortIndex {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortIndex < rhs.sortIndex
            }

            return lhsDate < rhsDate
        }
    }

    init(request: PDFExportRequest, caseTitle: String) {
        self.request = request
        self.caseFile = request.caseFile
        self.caseTitleValue = caseTitle
    }

    static func caseTitle(for caseFile: CaseFile) -> String {
        let title = caseFile.userTitle.trimmedForPDF
        return title.isEmpty ? "Proofly Proof Packet" : "\(title) Proof Packet"
    }

    func render(to destinationURL: URL) throws {
        let format = UIGraphicsPDFRendererFormat()
        var documentInfo: [String: Any] = [
            kCGPDFContextTitle as String: caseTitleValue,
            kCGPDFContextCreator as String: "Proofly",
            kCGPDFContextAuthor as String: "Proofly"
        ]
        if let signatureStamp = request.signatureStamp {
            documentInfo[kCGPDFContextSubject as String] = "Signed with Proofly token \(signatureStamp.validationToken)"
            documentInfo[kCGPDFContextKeywords as String] = "Proofly signed PDF, signature token \(signatureStamp.validationToken)"
        }
        format.documentInfo = documentInfo

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        try renderer.writePDF(to: destinationURL) { context in
            switch request.exportMode {
            case .cleanPacket:
                drawRenderedAttachmentPages(context)
            case .fullArchive:
                drawCoverPage(context)
                drawCaseSummaryAndTimelinePages(context)
                drawEvidenceIndexPages(context)
                drawEvidenceItemPages(context)
                drawRenderedAttachmentPages(context)
            }

            if request.includeStatementPlaceholder {
                drawStatementPlaceholderPage(context)
            }

            if pageNumber == 0 {
                drawBlankRenderedFilePage(context)
            }

            finishOpenPageIfNeeded(isFinalPage: true)
        }
    }

    private func drawCoverPage(_ context: UIGraphicsPDFRendererContext) {
        beginCoverPage(context)

        let x = margin
        var y: CGFloat = 58

        drawText(
            "Proofly",
            in: CGRect(x: x, y: y, width: contentWidth, height: 28),
            font: .systemFont(ofSize: 18, weight: .semibold),
            color: .pdfInk
        )
        y += 58

        drawText(
            "Proof Packet",
            in: CGRect(x: x, y: y, width: contentWidth, height: 22),
            font: .systemFont(ofSize: 14, weight: .semibold),
            color: .pdfSecondary
        )
        y += 34

        let titleHeight = drawText(
            caseFile.userTitle.trimmedForPDF.isEmpty ? "Untitled Case" : caseFile.userTitle.trimmedForPDF,
            in: CGRect(x: x, y: y, width: contentWidth, height: 110),
            font: .systemFont(ofSize: 34, weight: .semibold),
            color: .pdfInk,
            lineSpacing: 4
        )
        y += titleHeight + 12

        let proofItemText = evidenceItems.count == 1 ? "1 proof item" : "\(evidenceItems.count) proof items"
        drawText(
            "Prepared \(Self.shortDateFormatter.string(from: request.generatedAt)) • \(proofItemText)",
            in: CGRect(x: x, y: y, width: contentWidth, height: 18),
            font: .systemFont(ofSize: 11.5, weight: .regular),
            color: .pdfSecondary
        )
        y += 28

        drawRule(y: y, color: .pdfInk, alpha: 0.42, lineWidth: 1)
        y += 30

        let metadata = [
            ("Case type", caseFile.caseType.displayName),
            ("Status", caseFile.status.displayName),
            ("Prepared", Self.longDateTimeFormatter.string(from: request.generatedAt)),
            ("Proof items", "\(evidenceItems.count)"),
            ("Attachments", "\(attachmentCount)"),
            ("Date range", dateRangeText)
        ]
        let metadataHeight = drawMetadataGrid(metadata, x: x, y: y, columns: 2)
        y += metadataHeight + 24

        let summary = caseFile.userSummary.trimmedForPDF
        if !summary.isEmpty {
            let bodyHeight = min(
                104,
                heightForText(
                    summary.limitedForPDF(to: 540),
                    width: contentWidth - 32,
                    font: .systemFont(ofSize: 11.5, weight: .regular),
                    lineSpacing: 3
                ) + 4
            )
            let rect = CGRect(x: x, y: y, width: contentWidth, height: bodyHeight + 48)
            drawRoundedRect(rect, fill: .white, stroke: .pdfDivider, strokeAlpha: 0.42, cornerRadius: 8)
            drawText(
                "Summary",
                in: CGRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 32, height: 16),
                font: .systemFont(ofSize: 10.5, weight: .semibold),
                color: .pdfInk
            )
            drawText(
                summary.limitedForPDF(to: 540),
                in: CGRect(x: rect.minX + 16, y: rect.minY + 36, width: rect.width - 32, height: bodyHeight),
                font: .systemFont(ofSize: 11.5, weight: .regular),
                color: .pdfSecondary,
                lineSpacing: 3
            )
        }
    }

    private func drawCaseSummaryAndTimelinePages(_ context: UIGraphicsPDFRendererContext) {
        beginContentPage(
            context,
            title: "Case Summary"
        )

        drawSectionTitle("Overview")
        let overviewGridHeight = drawMetadataGrid(
            [
                ("Case title", caseTitleValue),
                ("Case type", caseFile.caseType.displayName),
                ("Status", caseFile.status.displayName),
                ("Proof items", "\(evidenceItems.count)"),
                ("Created", Self.shortDateFormatter.string(from: caseFile.createdAt)),
                ("Last updated", Self.shortDateTimeFormatter.string(from: caseFile.updatedAt))
            ],
            x: margin,
            y: cursorY,
            columns: 2
        )
        cursorY += overviewGridHeight + 16

        if !caseFile.userSummary.trimmedForPDF.isEmpty {
            drawTextBlock(
                context,
                title: "Summary",
                text: caseFile.userSummary.trimmedForPDF,
                emptyText: "",
                maxCharacters: 900
            )
        }

        if !caseFile.userNotes.trimmedForPDF.isEmpty {
            drawTextBlock(
                context,
                title: "Notes",
                text: caseFile.userNotes.trimmedForPDF,
                emptyText: "",
                maxCharacters: 700
            )
        }

        drawSectionTitle("Readiness")
        let importantCount = evidenceItems.filter(\.userMarkedImportant).count
        let reviewedCount = evidenceItems.filter(\.isReviewed).count
        let evidenceOverviewGridHeight = drawMetadataGrid(
            [
                ("Reviewed", "\(reviewedCount)"),
                ("Important", "\(importantCount)"),
                ("Attachments", "\(attachmentCount)"),
                ("Detected text", textSourceSummary)
            ],
            x: margin,
            y: cursorY,
            columns: 2
        )
        cursorY += evidenceOverviewGridHeight + 16

        drawCategorySummary(context)
        drawTimelineSection(context)
    }

    private func drawTimelineSection(_ context: UIGraphicsPDFRendererContext) {
        currentPageTitle = "Timeline"
        currentPageSubtitle = "Proof items in date order"

        if cursorY > headerBottom + 28 {
            cursorY += 8
        }
        ensureSpace(58, context: context)
        drawSectionTitle("Timeline")

        guard !evidenceItems.isEmpty else {
            drawEmptyMessage("No proof items have been added yet.")
            return
        }

        var lastDayKey: String?
        for (index, evidenceItem) in evidenceItems.enumerated() {
            let date = localEventDate(for: evidenceItem)
            let dayKey = date.map { Self.dayKeyFormatter.string(from: $0) } ?? "No date"
            if dayKey != lastDayKey {
                if lastDayKey != nil {
                    cursorY += 8
                }

                ensureSpace(52, context: context)
                drawRule(y: cursorY, color: .pdfDivider, alpha: 0.5, lineWidth: 0.5)
                cursorY += 12
                drawText(
                    date.map { Self.timelineSectionFormatter.string(from: $0) } ?? "Date not set",
                    in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 20),
                    font: .systemFont(ofSize: 12.5, weight: .semibold),
                    color: .pdfInk,
                    letterSpacing: 0.1
                )
                cursorY += 24
                lastDayKey = dayKey
            }

            drawTimelineEntry(context, evidenceItem: evidenceItem, itemNumber: index + 1)
        }
    }

    private func drawEvidenceIndexPages(_ context: UIGraphicsPDFRendererContext) {
        beginContentPage(
            context,
            title: "Proof Item Index",
            subtitle: "Reference list for the full archive pages that follow."
        )

        guard !evidenceItems.isEmpty else {
            drawEmptyMessage("No proof items have been added yet.")
            return
        }

        drawIndexHeader()
        for (index, evidenceItem) in evidenceItems.enumerated() {
            drawIndexRow(context, evidenceItem: evidenceItem, itemNumber: index + 1)
        }
    }

    private func drawEvidenceItemPages(_ context: UIGraphicsPDFRendererContext) {
        for (index, evidenceItem) in evidenceItems.enumerated() {
            beginContentPage(
                context,
                title: "Exhibit \(evidenceLabel(for: index + 1))",
                subtitle: displayTitle(for: evidenceItem)
            )

            drawEvidenceItemDetails(context, evidenceItem: evidenceItem, itemNumber: index + 1)
        }
    }

    private func drawStatementPlaceholderPage(_ context: UIGraphicsPDFRendererContext) {
        beginContentPage(
            context,
            title: "Statement Page",
            subtitle: "A blank page for a user-prepared statement if needed."
        )

        drawTextBlock(
            context,
            title: "Statement page",
            text: "This page is intentionally left as a placeholder for a statement or cover note prepared outside of Proofly. Proofly does not provide legal advice or generate this statement.",
            emptyText: "",
            maxCharacters: 800
        )

        cursorY += 12
        drawLabeledLine(label: "Prepared by", y: cursorY)
        cursorY += 48
        drawLabeledLine(label: "Date", y: cursorY)
        cursorY += 58

        drawText(
            "Statement",
            in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 18),
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: .pdfInk
        )
        cursorY += 28

        for _ in 0..<9 {
            drawRule(y: cursorY, color: .pdfDivider, alpha: 0.65, lineWidth: 0.8)
            cursorY += 42
        }
    }

    private func drawEvidenceItemDetails(
        _ context: UIGraphicsPDFRendererContext,
        evidenceItem: EvidenceItem,
        itemNumber: Int
    ) {
        let label = evidenceLabel(for: itemNumber)
        let title = displayTitle(for: evidenceItem)
        let dateText = localEventDate(for: evidenceItem).map(Self.shortDateFormatter.string(from:)) ?? "Date not set"
        let sourceText = pdfDateSourceText(for: localDateSource(for: evidenceItem))

        let heroHeight: CGFloat = 84
        ensureSpace(heroHeight + 18, context: context)

        let heroRect = CGRect(x: margin, y: cursorY, width: contentWidth, height: heroHeight)
        drawRoundedRect(heroRect, fill: .white, stroke: .pdfDivider, strokeAlpha: 0.5, cornerRadius: 8)

        let badgeRect = CGRect(x: heroRect.minX + 14, y: heroRect.minY + 16, width: 84, height: 52)
        drawExhibitBadge(label, in: badgeRect, emphasized: true)

        let titleX = badgeRect.maxX + 18
        let titleWidth = heroRect.maxX - titleX - 16
        let exhibitTitleHeight = heightForText(
            title,
            width: titleWidth,
            font: .systemFont(ofSize: 17, weight: .semibold),
            lineSpacing: 1
        )
        drawText(
            title,
            in: CGRect(x: titleX, y: heroRect.minY + 17, width: titleWidth, height: min(40, exhibitTitleHeight + 4)),
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: .pdfInk,
            lineSpacing: 1
        )

        drawText(
            "\(evidenceItem.category.displayName) • \(dateText) • \(sourceText)",
            in: CGRect(x: titleX, y: heroRect.minY + 59, width: titleWidth, height: 14),
            font: .systemFont(ofSize: 9.5, weight: .regular),
            color: .pdfSecondary
        )
        cursorY += heroHeight + 18

        let attachmentText = evidenceItem.attachments.count == 1 ? "1 attachment" : "\(evidenceItem.attachments.count) attachments"
        let itemGridHeight = drawMetadataGrid(
            [
                ("Event date", dateText),
                ("Date source", sourceText),
                ("Category", evidenceItem.category.displayName),
                ("Attachments", attachmentText),
                ("Imported", Self.shortDateTimeFormatter.string(from: evidenceItem.createdAt)),
                ("Important", evidenceItem.userMarkedImportant ? "Yes" : "No")
            ],
            x: margin,
            y: cursorY,
            columns: 2
        )
        cursorY += itemGridHeight + 22

        drawTextBlock(
            context,
            title: "User note",
            text: evidenceItem.userNotes.trimmedForPDF,
            emptyText: "No user note entered.",
            maxCharacters: 1_400
        )

        if !evidenceItem.userCleanedNote.trimmedForPDF.isEmpty {
            drawTextBlock(
                context,
                title: "Cleaned note",
                text: evidenceItem.userCleanedNote.trimmedForPDF,
                emptyText: "",
                maxCharacters: 1_400
            )
        }

        if !evidenceItem.userWhyThisMatters.trimmedForPDF.isEmpty {
            drawTextBlock(
                context,
                title: "Why this matters",
                text: evidenceItem.userWhyThisMatters.trimmedForPDF,
                emptyText: "",
                maxCharacters: 1_100
            )
        }

        if !evidenceItem.originalOCRText.trimmedForPDF.isEmpty {
            drawTextBlock(
                context,
                title: "Detected text",
                text: evidenceItem.originalOCRText.trimmedForPDF,
                emptyText: "",
                maxCharacters: 1_200,
                footnote: "Detected text was extracted locally on-device and is kept separate from user-edited notes."
            )
        }

        drawAttachments(context, attachments: evidenceItem.sortedAttachments)
    }

    private func drawAttachments(_ context: UIGraphicsPDFRendererContext, attachments: [Attachment]) {
        drawSectionTitle("Attachments")

        guard !attachments.isEmpty else {
            drawEmptyMessage("No attachments linked to this proof item.")
            return
        }

        for (index, attachment) in attachments.enumerated() {
            drawAttachmentCard(context, attachment: attachment, attachmentNumber: index + 1)
        }
    }

    private func drawRenderedAttachmentPages(_ context: UIGraphicsPDFRendererContext) {
        for (evidenceIndex, evidenceItem) in evidenceItems.enumerated() {
            for (attachmentIndex, attachment) in evidenceItem.sortedAttachments.enumerated() {
                drawRenderedAttachment(
                    context,
                    attachment: attachment,
                    evidenceNumber: evidenceIndex + 1,
                    attachmentNumber: attachmentIndex + 1
                )
            }
        }
    }

    private func drawRenderedAttachment(
        _ context: UIGraphicsPDFRendererContext,
        attachment: Attachment,
        evidenceNumber: Int,
        attachmentNumber: Int
    ) {
        if let document = renderablePDFDocument(for: attachment) {
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                drawRenderedPDFPage(
                    context,
                    page: page,
                    attachment: attachment,
                    evidenceNumber: evidenceNumber,
                    attachmentNumber: attachmentNumber,
                    pageNumberInFile: pageIndex + 1,
                    filePageCount: document.pageCount
                )
            }
            return
        }

        beginRenderedFilePage(
            context,
            attachment: attachment,
            evidenceNumber: evidenceNumber,
            attachmentNumber: attachmentNumber
        )

        guard let image = renderableImage(for: attachment) else {
            drawUnrenderableAttachmentPlaceholder(attachment)
            return
        }

        drawRenderableImage(image, sourceSize: image.size)
    }

    private func drawRenderedPDFPage(
        _ context: UIGraphicsPDFRendererContext,
        page: PDFPage,
        attachment: Attachment,
        evidenceNumber: Int,
        attachmentNumber: Int,
        pageNumberInFile: Int,
        filePageCount: Int
    ) {
        beginRenderedFilePage(
            context,
            attachment: attachment,
            evidenceNumber: evidenceNumber,
            attachmentNumber: attachmentNumber,
            pageNumberInFile: filePageCount > 1 ? pageNumberInFile : nil,
            filePageCount: filePageCount > 1 ? filePageCount : nil
        )

        let pageBounds = page.bounds(for: .mediaBox)
        let canvasRect = renderedFileCanvasRect(for: pageBounds.size)
        let contentRect = aspectFitRect(imageSize: pageBounds.size, in: canvasRect)

        drawCanvasBorder(canvasRect)

        guard pageBounds.width > 0,
              pageBounds.height > 0,
              let graphicsContext = UIGraphicsGetCurrentContext() else {
            return
        }

        let scale = min(contentRect.width / pageBounds.width, contentRect.height / pageBounds.height)
        guard scale.isFinite, scale > 0 else { return }

        graphicsContext.saveGState()
        UIBezierPath(rect: canvasRect).addClip()
        graphicsContext.translateBy(x: contentRect.minX, y: contentRect.maxY)
        graphicsContext.scaleBy(x: scale, y: -scale)
        graphicsContext.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        page.draw(with: .mediaBox, to: graphicsContext)
        graphicsContext.restoreGState()
    }

    private func beginRenderedFilePage(
        _ context: UIGraphicsPDFRendererContext,
        attachment: Attachment,
        evidenceNumber: Int,
        attachmentNumber: Int,
        pageNumberInFile: Int? = nil,
        filePageCount: Int? = nil
    ) {
        finishOpenPageIfNeeded()
        context.beginPage()
        pageNumber += 1
        hasOpenPage = true
        currentPageTitle = "Rendered File"
        currentPageSubtitle = attachment.originalFilename.trimmedForPDF

        UIColor.white.setFill()
        UIRectFill(pageRect)

        if request.exportMode == .fullArchive {
            let label = renderedFileLabel(
                evidenceNumber: evidenceNumber,
                attachmentNumber: attachmentNumber,
                pageNumberInFile: pageNumberInFile,
                filePageCount: filePageCount
            )
            drawText(
                label,
                in: CGRect(x: margin, y: 30, width: contentWidth * 0.38, height: 14),
                font: .systemFont(ofSize: 8.4, weight: .semibold),
                color: .pdfTertiary
            )

            let filename = attachment.originalFilename.trimmedForPDF.singleLineLimitedForPDF(to: 72)
            if !filename.isEmpty {
                drawText(
                    filename,
                    in: CGRect(x: margin + contentWidth * 0.38, y: 30, width: contentWidth * 0.62, height: 14),
                    font: .systemFont(ofSize: 8.4, weight: .regular),
                    color: .pdfTertiary,
                    alignment: .right
                )
            }
        }
    }

    private func drawBlankRenderedFilePage(_ context: UIGraphicsPDFRendererContext) {
        finishOpenPageIfNeeded()
        context.beginPage()
        pageNumber += 1
        hasOpenPage = true
        currentPageTitle = "Rendered File"
        currentPageSubtitle = nil

        UIColor.white.setFill()
        UIRectFill(pageRect)
    }

    private func renderedFileLabel(
        evidenceNumber: Int,
        attachmentNumber: Int,
        pageNumberInFile: Int?,
        filePageCount: Int?
    ) -> String {
        let baseLabel = "\(evidenceLabel(for: evidenceNumber)) · File \(attachmentNumber)"
        guard let pageNumberInFile, let filePageCount else {
            return baseLabel
        }

        return "\(baseLabel) · Page \(pageNumberInFile) of \(filePageCount)"
    }

    private func drawRenderableImage(_ image: UIImage, sourceSize: CGSize) {
        guard let graphicsContext = UIGraphicsGetCurrentContext() else { return }

        let canvasRect = renderedFileCanvasRect(for: sourceSize)
        let imageRect = aspectFitRect(imageSize: image.size, in: canvasRect)

        drawCanvasBorder(canvasRect)

        graphicsContext.saveGState()
        UIBezierPath(rect: canvasRect).addClip()
        image.draw(in: imageRect)
        graphicsContext.restoreGState()
    }

    private func drawCanvasBorder(_ canvasRect: CGRect) {
        drawLine(
            from: CGPoint(x: canvasRect.minX, y: canvasRect.minY),
            to: CGPoint(x: canvasRect.maxX, y: canvasRect.minY),
            color: .pdfDivider,
            alpha: 0.26,
            lineWidth: 0.5
        )
        drawLine(
            from: CGPoint(x: canvasRect.maxX, y: canvasRect.minY),
            to: CGPoint(x: canvasRect.maxX, y: canvasRect.maxY),
            color: .pdfDivider,
            alpha: 0.26,
            lineWidth: 0.5
        )
        drawLine(
            from: CGPoint(x: canvasRect.maxX, y: canvasRect.maxY),
            to: CGPoint(x: canvasRect.minX, y: canvasRect.maxY),
            color: .pdfDivider,
            alpha: 0.26,
            lineWidth: 0.5
        )
        drawLine(
            from: CGPoint(x: canvasRect.minX, y: canvasRect.maxY),
            to: CGPoint(x: canvasRect.minX, y: canvasRect.minY),
            color: .pdfDivider,
            alpha: 0.26,
            lineWidth: 0.5
        )
    }

    private func drawUnrenderableAttachmentPlaceholder(_ attachment: Attachment) {
        let canvasRect = renderedFileCanvasRect(for: CGSize(width: 1, height: 1))
        drawRoundedRect(canvasRect, fill: .white, stroke: .pdfDivider, strokeAlpha: 0.5, cornerRadius: 0)

        let filename = attachment.originalFilename.trimmedForPDF
        let message = filename.isEmpty
            ? "This file type cannot be rendered inside the PDF."
            : "\(filename)\n\nThis file type cannot be rendered inside the PDF."
        drawText(
            message,
            in: canvasRect.insetBy(dx: 28, dy: 28),
            font: .systemFont(ofSize: 12, weight: .regular),
            color: .pdfSecondary,
            alignment: .center,
            lineSpacing: 4
        )
    }

    private func drawAttachmentCard(
        _ context: UIGraphicsPDFRendererContext,
        attachment: Attachment,
        attachmentNumber: Int
    ) {
        let height: CGFloat = 148
        ensureSpace(height + 12, context: context)

        let cardRect = CGRect(x: margin, y: cursorY, width: contentWidth, height: height)
        drawRoundedRect(cardRect, fill: .white, stroke: .pdfDivider, strokeAlpha: 0.48)

        drawText(
            "Attachment \(attachmentNumber)",
            in: CGRect(x: cardRect.minX + 14, y: cardRect.minY + 13, width: 118, height: 12),
            font: .systemFont(ofSize: 8, weight: .semibold),
            color: .pdfTertiary
        )

        let filename = attachment.originalFilename.trimmedForPDF.isEmpty ? "Attachment" : attachment.originalFilename.trimmedForPDF
        drawText(
            filename,
            in: CGRect(x: cardRect.minX + 14, y: cardRect.minY + 29, width: cardRect.width - 28, height: 22),
            font: .systemFont(ofSize: 12.5, weight: .semibold),
            color: .pdfInk,
            lineSpacing: 1
        )

        drawLine(
            from: CGPoint(x: cardRect.minX + 14, y: cardRect.minY + 57),
            to: CGPoint(x: cardRect.maxX - 14, y: cardRect.minY + 57),
            color: .pdfDivider,
            alpha: 0.38,
            lineWidth: 0.5
        )

        let thumbnailRect = CGRect(x: cardRect.minX + 14, y: cardRect.minY + 70, width: 94, height: 60)
        drawAttachmentThumbnail(attachment, in: thumbnailRect)

        let textX = thumbnailRect.maxX + 18
        let textWidth = cardRect.maxX - textX - 14
        var y = cardRect.minY + 69
        drawText(
            "Type",
            in: CGRect(x: textX, y: y, width: 74, height: 12),
            font: .systemFont(ofSize: 8, weight: .semibold),
            color: .pdfTertiary
        )
        drawText(
            attachment.attachmentType.displayName,
            in: CGRect(x: textX + 84, y: y - 1, width: textWidth - 84, height: 14),
            font: .systemFont(ofSize: 10.2, weight: .medium),
            color: .pdfInk
        )
        y += 22

        let fileSizeText = attachment.fileSizeBytes.map { Self.fileSizeFormatter.string(fromByteCount: $0) } ?? "File size unavailable"
        let importedText = Self.shortDateTimeFormatter.string(from: attachment.createdAt)
        drawText(
            "Size",
            in: CGRect(x: textX, y: y, width: 74, height: 12),
            font: .systemFont(ofSize: 8, weight: .semibold),
            color: .pdfTertiary
        )
        drawText(
            fileSizeText,
            in: CGRect(x: textX + 84, y: y - 1, width: textWidth - 84, height: 14),
            font: .systemFont(ofSize: 10.2, weight: .medium),
            color: .pdfInk
        )
        y += 22

        drawText(
            "Imported",
            in: CGRect(x: textX, y: y, width: 74, height: 12),
            font: .systemFont(ofSize: 8, weight: .semibold),
            color: .pdfTertiary
        )
        drawText(
            importedText,
            in: CGRect(x: textX + 84, y: y - 1, width: textWidth - 84, height: 14),
            font: .systemFont(ofSize: 10.2, weight: .medium),
            color: .pdfInk
        )

        cursorY += height + 12
    }

    private func drawTimelineEntry(
        _ context: UIGraphicsPDFRendererContext,
        evidenceItem: EvidenceItem,
        itemNumber: Int
    ) {
        let note = timelineNote(for: evidenceItem)
        let why = evidenceItem.userWhyThisMatters.trimmedForPDF
        let noteText = note.isEmpty ? "" : note.limitedForPDF(to: 280)
        let whyText = why.isEmpty ? "" : "Why this matters: \(why.limitedForPDF(to: 220))"
        let detectedText = timelineDetectedText(for: evidenceItem)
        let dateText = localEventDate(for: evidenceItem).map(Self.shortDateFormatter.string(from:)) ?? "Date not set"
        let sourceText = pdfDateSourceText(for: localDateSource(for: evidenceItem))
        let metaText = "\(dateText) · \(evidenceItem.category.displayName) · \(sourceText)"
        let body = [noteText, whyText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let previewAttachment = primaryPreviewAttachment(for: evidenceItem)
        let leftRailWidth: CGFloat = 96
        let textWidth = contentWidth - 32 - leftRailWidth - 18

        let bodyHeight = heightForText(
            body.isEmpty ? "No note added." : body,
            width: textWidth,
            font: .systemFont(ofSize: 10.5, weight: .regular),
            lineSpacing: 2
        )
        let detectedHeight = detectedText.isEmpty ? 0 : heightForText(
            "Detected text: \(detectedText)",
            width: textWidth,
            font: .systemFont(ofSize: 9.5, weight: .regular),
            lineSpacing: 1.5
        ) + 10
        let titleHeight = heightForText(
            displayTitle(for: evidenceItem),
            width: textWidth,
            font: .systemFont(ofSize: 12, weight: .semibold),
            lineSpacing: 1
        )
        let textHeight = titleHeight + bodyHeight + detectedHeight + 44
        let leftRailHeight: CGFloat = previewAttachment == nil ? 108 : 180
        let cardHeight = max(leftRailHeight, textHeight)

        ensureSpace(cardHeight + 10, context: context)

        let cardRect = CGRect(x: margin, y: cursorY, width: contentWidth, height: cardHeight)
        drawRoundedRect(cardRect, fill: .white, stroke: .pdfDivider, strokeAlpha: 0.5)

        let labelRect = CGRect(x: cardRect.minX + 12, y: cardRect.minY + 14, width: 82, height: 38)
        drawExhibitBadge(evidenceLabel(for: itemNumber), in: labelRect)

        drawPill(
            evidenceItem.needsReview ? "Needs review" : "Reviewed",
            x: cardRect.minX + 12,
            y: labelRect.maxY + 8,
            width: 82
        )

        if evidenceItem.userMarkedImportant {
            drawPill("Important", x: cardRect.minX + 12, y: labelRect.maxY + 32, width: 82)
        }

        if let previewAttachment {
            let thumbnailRect = CGRect(x: cardRect.minX + 12, y: labelRect.maxY + 58, width: 82, height: 58)
            drawAttachmentThumbnail(previewAttachment, in: thumbnailRect)

            let attachmentText = evidenceItem.attachments.count == 1 ? "1 file" : "\(evidenceItem.attachments.count) files"
            drawText(
                attachmentText,
                in: CGRect(x: thumbnailRect.minX, y: thumbnailRect.maxY + 5, width: thumbnailRect.width, height: 12),
                font: .systemFont(ofSize: 8, weight: .regular),
                color: .pdfTertiary,
                alignment: .center
            )
        }

        let textX = cardRect.minX + 16 + leftRailWidth + 18
        var textY = cardRect.minY + 14
        drawText(
            displayTitle(for: evidenceItem),
            in: CGRect(x: textX, y: textY, width: textWidth, height: titleHeight + 4),
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: .pdfInk,
            lineSpacing: 1
        )
        textY += titleHeight + 5
        drawText(
            metaText,
            in: CGRect(x: textX, y: textY, width: textWidth, height: 14),
            font: .systemFont(ofSize: 9.2, weight: .regular),
            color: .pdfTertiary
        )
        textY += 18
        drawText(
            body.isEmpty ? "No note added." : body,
            in: CGRect(x: textX, y: textY, width: textWidth, height: bodyHeight + 6),
            font: .systemFont(ofSize: 10.5, weight: .regular),
            color: .pdfSecondary,
            lineSpacing: 2
        )
        textY += bodyHeight + 8

        if !detectedText.isEmpty {
            drawText(
                "Detected text: \(detectedText)",
                in: CGRect(x: textX, y: textY, width: textWidth, height: detectedHeight),
                font: .systemFont(ofSize: 9.5, weight: .regular),
                color: .pdfTertiary,
                lineSpacing: 1.5
            )
        }

        cursorY += cardHeight + 10
    }

    private func drawIndexHeader() {
        let headerRect = CGRect(x: margin, y: cursorY, width: contentWidth, height: 26)
        drawRoundedRect(headerRect, fill: .pdfPanel, stroke: .pdfDivider, strokeAlpha: 0.45, cornerRadius: 6)

        let y = headerRect.minY + 8
        let headerFont = UIFont.systemFont(ofSize: 7.7, weight: .semibold)
        drawText("Exhibit", in: CGRect(x: margin + 10, y: y, width: 62, height: 12), font: headerFont, color: .pdfTertiary)
        drawText("Date", in: CGRect(x: margin + 76, y: y, width: 82, height: 12), font: headerFont, color: .pdfTertiary)
        drawText("Title", in: CGRect(x: margin + 166, y: y, width: 190, height: 12), font: headerFont, color: .pdfTertiary)
        drawText("Category", in: CGRect(x: margin + 364, y: y, width: 82, height: 12), font: headerFont, color: .pdfTertiary)
        drawText("Files", in: CGRect(x: margin + 454, y: y, width: 40, height: 12), font: headerFont, color: .pdfTertiary, alignment: .right)
        cursorY += 34
        drawRule(y: cursorY, color: .pdfDivider, alpha: 0.55, lineWidth: 0.5)
        cursorY += 8
    }

    private func drawIndexRow(
        _ context: UIGraphicsPDFRendererContext,
        evidenceItem: EvidenceItem,
        itemNumber: Int
    ) {
        ensureSpace(44, context: context)
        if cursorY < headerBottom + 24 {
            drawIndexHeader()
        }

        let rowY = cursorY
        let dateText = localEventDate(for: evidenceItem).map(Self.compactDateFormatter.string(from:)) ?? "—"
        let title = displayTitle(for: evidenceItem).limitedForPDF(to: 74)
        let category = evidenceItem.category.displayName
        let attachments = "\(evidenceItem.attachments.count)"

        drawText(evidenceLabel(for: itemNumber), in: CGRect(x: margin + 10, y: rowY, width: 62, height: 30), font: .monospacedSystemFont(ofSize: 10.2, weight: .semibold), color: .pdfInk)
        drawText(dateText, in: CGRect(x: margin + 76, y: rowY, width: 82, height: 30), font: .systemFont(ofSize: 9.6, weight: .regular), color: .pdfInk)
        drawText(title, in: CGRect(x: margin + 166, y: rowY, width: 190, height: 30), font: .systemFont(ofSize: 9.6, weight: .regular), color: .pdfInk, lineSpacing: 1)
        drawText(category, in: CGRect(x: margin + 364, y: rowY, width: 82, height: 30), font: .systemFont(ofSize: 9.4, weight: .regular), color: .pdfSecondary)
        drawText(attachments, in: CGRect(x: margin + 454, y: rowY, width: 40, height: 30), font: .systemFont(ofSize: 9.6, weight: .medium), color: .pdfInk, alignment: .right)

        cursorY += 34
        drawRule(y: cursorY, color: .pdfDivider, alpha: 0.35, lineWidth: 0.5)
        cursorY += 8
    }

    private func drawTextBlock(
        _ context: UIGraphicsPDFRendererContext,
        title: String,
        text: String,
        emptyText: String,
        maxCharacters: Int,
        footnote: String? = nil
    ) {
        let body = text.isEmpty ? emptyText : text.limitedForPDF(to: maxCharacters)
        let footnoteText = footnote?.trimmedForPDF ?? ""
        let bodyHeight = heightForText(
            body,
            width: contentWidth - 32,
            font: .systemFont(ofSize: 11, weight: .regular),
            lineSpacing: 3
        )
        let footnoteHeight = footnoteText.isEmpty ? 0 : heightForText(
            footnoteText,
            width: contentWidth - 32,
            font: .systemFont(ofSize: 9.5, weight: .regular),
            lineSpacing: 2
        ) + 12
        let blockHeight = bodyHeight + footnoteHeight + 48

        ensureSpace(blockHeight + 12, context: context)

        let rect = CGRect(x: margin, y: cursorY, width: contentWidth, height: blockHeight)
        drawRoundedRect(rect, fill: .white, stroke: .pdfDivider, strokeAlpha: 0.42)

        drawText(
            title,
            in: CGRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 14),
            font: .systemFont(ofSize: 10.5, weight: .semibold),
            color: .pdfInk
        )
        drawLine(
            from: CGPoint(x: rect.minX + 16, y: rect.minY + 32),
            to: CGPoint(x: rect.maxX - 16, y: rect.minY + 32),
            color: .pdfDivider,
            alpha: 0.32,
            lineWidth: 0.5
        )
        drawText(
            body,
            in: CGRect(x: rect.minX + 16, y: rect.minY + 40, width: rect.width - 32, height: bodyHeight + 4),
            font: .systemFont(ofSize: 11, weight: .regular),
            color: text.isEmpty ? .pdfTertiary : .pdfSecondary,
            lineSpacing: 3
        )

        if !footnoteText.isEmpty {
            drawText(
                footnoteText,
                in: CGRect(x: rect.minX + 16, y: rect.minY + 46 + bodyHeight, width: rect.width - 32, height: footnoteHeight),
                font: .systemFont(ofSize: 9.5, weight: .regular),
                color: .pdfTertiary,
                lineSpacing: 2
            )
        }

        cursorY += blockHeight + 12
    }

    private func drawCategorySummary(_ context: UIGraphicsPDFRendererContext) {
        let categoryPairs = categorySummaryPairs()
        guard !categoryPairs.isEmpty else { return }

        ensureSpace(96, context: context)
        drawSectionTitle("Categories")
        let gridHeight = drawMetadataGrid(
            categoryPairs,
            x: margin,
            y: cursorY,
            columns: min(3, max(1, categoryPairs.count))
        )
        cursorY += gridHeight + 16
    }

    @discardableResult
    private func drawMetadataGrid(
        _ metadata: [(String, String)],
        x: CGFloat,
        y: CGFloat,
        columns: Int
    ) -> CGFloat {
        let columnCount = max(1, columns)
        let columnWidth = contentWidth / CGFloat(columnCount)
        let rowHeight: CGFloat = 44
        let rowCount = Int(ceil(Double(metadata.count) / Double(columnCount)))
        guard rowCount > 0 else { return 0 }

        let panelHeight = CGFloat(rowCount) * rowHeight
        let panelRect = CGRect(x: x, y: y, width: contentWidth, height: panelHeight)
        drawRoundedRect(panelRect, fill: .pdfPanel, stroke: .pdfDivider, strokeAlpha: 0.55, cornerRadius: 7)

        if rowCount > 1 {
            for row in 1..<rowCount {
                let lineY = y + (CGFloat(row) * rowHeight)
                drawLine(
                    from: CGPoint(x: x, y: lineY),
                    to: CGPoint(x: x + contentWidth, y: lineY),
                    color: .pdfDivider,
                    alpha: 0.38,
                    lineWidth: 0.5
                )
            }
        }

        if columnCount > 1 {
            for column in 1..<columnCount {
                let lineX = x + (CGFloat(column) * columnWidth)
                drawLine(
                    from: CGPoint(x: lineX, y: y),
                    to: CGPoint(x: lineX, y: y + panelHeight),
                    color: .pdfDivider,
                    alpha: 0.32,
                    lineWidth: 0.5
                )
            }
        }

        for (index, item) in metadata.enumerated() {
            let column = index % columnCount
            let row = index / columnCount
            let rect = CGRect(
                x: x + (CGFloat(column) * columnWidth),
                y: y + (CGFloat(row) * rowHeight),
                width: columnWidth,
                height: rowHeight
            )
            drawText(
                item.0,
                in: CGRect(x: rect.minX + 12, y: rect.minY + 8, width: rect.width - 24, height: 12),
                font: .systemFont(ofSize: 8.2, weight: .semibold),
                color: .pdfTertiary
            )
            drawText(
                item.1,
                in: CGRect(x: rect.minX + 12, y: rect.minY + 23, width: rect.width - 24, height: 17),
                font: .systemFont(ofSize: 10.6, weight: .medium),
                color: .pdfInk
            )
        }

        return panelHeight
    }

    private func drawAttachmentThumbnail(_ attachment: Attachment, in rect: CGRect) {
        drawRoundedRect(rect, fill: .pdfPanelAlt, stroke: .pdfDivider, strokeAlpha: 0.35)

        if let image = previewImage(for: attachment),
           let graphicsContext = UIGraphicsGetCurrentContext() {
            let imageRect = aspectFitRect(imageSize: image.size, in: rect.insetBy(dx: 4, dy: 4))
            graphicsContext.saveGState()
            UIBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 6).addClip()
            image.draw(in: imageRect)
            graphicsContext.restoreGState()
            return
        }

        let badge = attachment.attachmentType == .pdf ? "PDF" : attachment.attachmentType.displayName
        drawText(
            String(badge),
            in: CGRect(x: rect.minX + 8, y: rect.midY - 10, width: rect.width - 16, height: 20),
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: .pdfSecondary,
            alignment: .center
        )
    }

    private func previewImage(for attachment: Attachment) -> UIImage? {
        let candidateURLs = [
            resolvedLocalFileURL(for: attachment.thumbnailLocalFilePath),
            resolvedLocalFileURL(for: attachment.localFilePath)
        ]
            .compactMap { $0 }

        for url in candidateURLs {
            if let image = image(at: url) {
                return image
            }
        }

        if let document = renderablePDFDocument(for: attachment),
           let page = document.page(at: 0) {
            return page.thumbnail(of: CGSize(width: 480, height: 480), for: .mediaBox)
        }

        return nil
    }

    private func renderablePDFDocument(for attachment: Attachment) -> PDFDocument? {
        guard attachmentCanBePDF(attachment),
              let documentURL = resolvedLocalFileURL(for: attachment.localFilePath),
              let document = PDFDocument(url: documentURL),
              document.pageCount > 0 else {
            return nil
        }

        return document
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

    private func renderableImage(for attachment: Attachment) -> UIImage? {
        let candidateURLs = [
            resolvedLocalFileURL(for: attachment.localFilePath),
            resolvedLocalFileURL(for: attachment.thumbnailLocalFilePath)
        ]
        .compactMap { $0 }

        for url in candidateURLs {
            if let image = image(at: url) {
                return image
            }
        }

        return nil
    }

    private func image(at url: URL) -> UIImage? {
        let path = url.path(percentEncoded: false)
        if let image = UIImage(contentsOfFile: path),
           image.size.width > 0,
           image.size.height > 0 {
            return image
        }

        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data),
           image.size.width > 0,
           image.size.height > 0 {
            return image
        }

        let options = [kCGImageSourceShouldCache: true] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, options) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
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

    private func renderedFileCanvasRect(for sourceSize: CGSize) -> CGRect {
        let topInset: CGFloat = request.exportMode == .cleanPacket ? margin : 54
        let bottomInset: CGFloat = request.exportMode == .cleanPacket ? 60 : 74
        let canvasBounds = CGRect(
            x: margin,
            y: topInset,
            width: contentWidth,
            height: pageRect.height - topInset - bottomInset
        )
        let targetAspectRatio = renderedFileCanvasAspectRatio(for: sourceSize)
        let targetSize = CGSize(width: targetAspectRatio, height: 1)
        return aspectFitRect(imageSize: targetSize, in: canvasBounds)
    }

    private func renderedFileCanvasAspectRatio(for sourceSize: CGSize) -> CGFloat {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return 1
        }

        let sourceAspectRatio = sourceSize.width / sourceSize.height
        return sourceAspectRatio < 0.9 ? (1 / 1.4) : 1
    }

    private func beginCoverPage(_ context: UIGraphicsPDFRendererContext) {
        finishOpenPageIfNeeded()
        context.beginPage()
        pageNumber += 1
        hasOpenPage = true
        currentPageTitle = "Cover"
        currentPageSubtitle = nil
    }

    private func beginContentPage(
        _ context: UIGraphicsPDFRendererContext,
        title: String,
        subtitle: String? = nil
    ) {
        finishOpenPageIfNeeded()
        context.beginPage()
        pageNumber += 1
        hasOpenPage = true
        currentPageTitle = title
        currentPageSubtitle = subtitle

        drawPageHeader(title: title, subtitle: subtitle)
        cursorY = headerBottom + 20
    }

    private func finishOpenPageIfNeeded(isFinalPage: Bool = false) {
        guard hasOpenPage else { return }
        drawSignatureIfNeeded(isFinalPage: isFinalPage)
        drawTopWatermark()
        drawPageFooter()
        hasOpenPage = false
    }

    private func drawSignatureIfNeeded(isFinalPage: Bool) {
        guard let signatureStamp = request.signatureStamp,
              shouldDrawSignature(signatureStamp, isFinalPage: isFinalPage) else {
            return
        }

        let signatureRect = signatureRect(for: signatureStamp)
        let imageBounds = signatureRect.insetBy(dx: 0, dy: 0)
            .divided(atDistance: 58, from: .minYEdge)
            .slice
        let imageRect = aspectFitRect(imageSize: signatureStamp.image.size, in: imageBounds)
        guard imageRect.width > 0, imageRect.height > 0 else { return }

        signatureStamp.image.draw(in: imageRect, blendMode: .normal, alpha: 0.96)
        drawText(
            "Proofly signature token: \(signatureStamp.validationToken)",
            in: CGRect(x: signatureRect.minX, y: imageBounds.maxY + 3, width: signatureRect.width, height: 18),
            font: .monospacedSystemFont(ofSize: 5.6, weight: .medium),
            color: UIColor.pdfSecondary.withAlphaComponent(0.82),
            alignment: .center
        )
    }

    private func shouldDrawSignature(_ signatureStamp: PDFSignatureStamp, isFinalPage: Bool) -> Bool {
        switch signatureStamp.page {
        case .firstPage:
            pageNumber == 1
        case .lastPage:
            isFinalPage
        case .everyPage:
            true
        }
    }

    private func signatureRect(for signatureStamp: PDFSignatureStamp) -> CGRect {
        let maxSize = CGSize(width: 176, height: 80)
        let horizontalInset = margin + 10
        let upperY = headerBottom + 22
        let lowerY = pageRect.height - 126
        let centerY = (pageRect.height - maxSize.height) / 2
        let centerX = (pageRect.width - maxSize.width) / 2

        switch signatureStamp.placement {
        case .upperLeft:
            return CGRect(x: horizontalInset, y: upperY, width: maxSize.width, height: maxSize.height)
        case .upperRight:
            return CGRect(x: pageRect.maxX - horizontalInset - maxSize.width, y: upperY, width: maxSize.width, height: maxSize.height)
        case .center:
            return CGRect(x: centerX, y: centerY, width: maxSize.width, height: maxSize.height)
        case .lowerLeft:
            return CGRect(x: horizontalInset, y: lowerY, width: maxSize.width, height: maxSize.height)
        case .lowerRight:
            return CGRect(x: pageRect.maxX - horizontalInset - maxSize.width, y: lowerY, width: maxSize.width, height: maxSize.height)
        }
    }

    private func ensureSpace(_ neededHeight: CGFloat, context: UIGraphicsPDFRendererContext) {
        guard cursorY + neededHeight > contentBottom else { return }
        beginContentPage(context, title: currentPageTitle, subtitle: currentPageSubtitle)
    }

    private func drawPageHeader(title: String, subtitle: String?) {
        drawText(
            "\(coverTitle) · Proofly packet",
            in: CGRect(x: margin, y: headerTop, width: contentWidth * 0.54, height: 16),
            font: .systemFont(ofSize: 8.8, weight: .regular),
            color: .pdfSecondary
        )

        drawText(
            title,
            in: CGRect(x: margin, y: headerTop + 18, width: contentWidth * 0.62, height: 24),
            font: .systemFont(ofSize: 15.8, weight: .semibold),
            color: .pdfInk
        )

        if let subtitle, !subtitle.isEmpty {
            drawText(
                subtitle,
                in: CGRect(x: margin + contentWidth * 0.54, y: headerTop + 19, width: contentWidth * 0.46, height: 28),
                font: .systemFont(ofSize: 9, weight: .regular),
                color: .pdfSecondary,
                alignment: .right,
                lineSpacing: 1
            )
        }

        drawRule(y: headerBottom, color: .pdfDivider, alpha: 0.75, lineWidth: 0.6)
    }

    private func drawTopWatermark() {
        guard request.includeProofKitWatermark else { return }

        drawText(
            "proofly",
            in: CGRect(x: margin, y: 16, width: contentWidth, height: 14),
            font: .systemFont(ofSize: 9.2, weight: .semibold),
            color: UIColor.pdfTertiary.withAlphaComponent(0.42),
            alignment: .center
        )
    }

    private func drawPageFooter() {
        let footerY = pageRect.height - 44
        if currentPageTitle == "Cover" {
            drawText(
                "Proofly organizes user-provided records and does not provide legal advice.",
                in: CGRect(x: margin, y: footerY, width: contentWidth, height: 16),
                font: .systemFont(ofSize: 8.5, weight: .regular),
                color: .pdfTertiary
            )
            return
        }

        if request.exportMode == .cleanPacket && currentPageTitle == "Rendered File" {
            guard request.includeProofKitWatermark else { return }
            drawText(
                "Generated with Proofly",
                in: CGRect(x: margin, y: footerY, width: contentWidth, height: 16),
                font: .systemFont(ofSize: 7.8, weight: .regular),
                color: UIColor.pdfTertiary.withAlphaComponent(0.62),
                alignment: .center
            )
            return
        }

        drawRule(y: footerY - 10, color: .pdfDivider, alpha: 0.45, lineWidth: 0.5)

        let footerTextColor = request.includeProofKitWatermark
            ? UIColor.pdfTertiary.withAlphaComponent(0.62)
            : .pdfTertiary
        let footerFont = UIFont.systemFont(
            ofSize: request.includeProofKitWatermark ? 7.8 : 8.5,
            weight: .regular
        )

        if !footerGeneratedText.isEmpty {
            drawText(
                footerGeneratedText,
                in: CGRect(x: margin, y: footerY, width: contentWidth * 0.72, height: 16),
                font: footerFont,
                color: footerTextColor
            )
        }
        drawText(
            "Page \(pageNumber)",
            in: CGRect(x: margin + contentWidth * 0.72, y: footerY, width: contentWidth * 0.28, height: 16),
            font: .systemFont(ofSize: 8.5, weight: .regular),
            color: .pdfTertiary,
            alignment: .right
        )
    }

    private var footerGeneratedText: String {
        if request.includeProofKitWatermark {
            return "Generated with Proofly"
        }

        return ""
    }

    private func drawSectionTitle(_ title: String) {
        if cursorY > headerBottom + 24 {
            cursorY += 4
        }

        drawText(
            title,
            in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 15),
            font: .systemFont(ofSize: 11.2, weight: .semibold),
            color: .pdfInk
        )
        cursorY += 20
        drawRule(y: cursorY, color: .pdfDivider, alpha: 0.58, lineWidth: 0.5)
        cursorY += 12
    }

    private func drawEmptyMessage(_ message: String) {
        let rect = CGRect(x: margin, y: cursorY, width: contentWidth, height: 70)
        drawRoundedRect(rect, fill: .pdfPanel, stroke: .pdfDivider, strokeAlpha: 0.35)
        drawText(
            message,
            in: rect.insetBy(dx: 16, dy: 20),
            font: .systemFont(ofSize: 11, weight: .regular),
            color: .pdfSecondary,
            lineSpacing: 2
        )
        cursorY += 84
    }

    private func drawLabeledLine(label: String, y: CGFloat) {
        drawText(
            label,
            in: CGRect(x: margin, y: y, width: 100, height: 18),
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: .pdfInk
        )
        drawRule(y: y + 22, color: .pdfDivider, alpha: 0.75, lineWidth: 0.8)
    }

    private func drawPill(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) {
        let rect = CGRect(x: x, y: y, width: width, height: 20)
        drawRoundedRect(rect, fill: .pdfPanelAlt, stroke: .pdfDivider, strokeAlpha: 0.15, cornerRadius: 10)
        drawText(
            text,
            in: CGRect(x: rect.minX + 8, y: rect.minY + 4, width: rect.width - 16, height: 12),
            font: .systemFont(ofSize: 8.5, weight: .semibold),
            color: .pdfSecondary,
            alignment: .center
        )
    }

    private func drawExhibitBadge(_ label: String, in rect: CGRect, emphasized: Bool = false) {
        drawRoundedRect(
            rect,
            fill: emphasized ? .pdfPanelAlt : .pdfPanel,
            stroke: .pdfDivider,
            strokeAlpha: emphasized ? 0.52 : 0.42,
            cornerRadius: 6
        )

        drawText(
            "Exhibit",
            in: CGRect(x: rect.minX + 4, y: rect.minY + (emphasized ? 9 : 7), width: rect.width - 8, height: 9),
            font: .systemFont(ofSize: emphasized ? 7.4 : 6.7, weight: .semibold),
            color: .pdfTertiary,
            alignment: .center
        )

        drawText(
            label,
            in: CGRect(x: rect.minX + 4, y: rect.minY + (emphasized ? 25 : 20), width: rect.width - 8, height: emphasized ? 17 : 13),
            font: .monospacedSystemFont(ofSize: emphasized ? 14 : 10.5, weight: .semibold),
            color: .pdfInk,
            alignment: .center
        )
    }

    private func drawRoundedRect(
        _ rect: CGRect,
        fill: UIColor,
        stroke: UIColor,
        strokeAlpha: CGFloat,
        cornerRadius: CGFloat = 8
    ) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        fill.setFill()
        path.fill()
        stroke.withAlphaComponent(strokeAlpha).setStroke()
        path.lineWidth = 0.6
        path.stroke()
    }

    private func drawRule(y: CGFloat, color: UIColor, alpha: CGFloat, lineWidth: CGFloat) {
        drawLine(
            from: CGPoint(x: margin, y: y),
            to: CGPoint(x: pageRect.maxX - margin, y: y),
            color: color,
            alpha: alpha,
            lineWidth: lineWidth
        )
    }

    private func drawLine(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        color: UIColor,
        alpha: CGFloat,
        lineWidth: CGFloat
    ) {
        let path = UIBezierPath()
        path.move(to: startPoint)
        path.addLine(to: endPoint)
        color.withAlphaComponent(alpha).setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    @discardableResult
    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left,
        lineSpacing: CGFloat = 0,
        letterSpacing: CGFloat = 0
    ) -> CGFloat {
        let attributed = attributedString(
            text,
            font: font,
            color: color,
            alignment: alignment,
            lineSpacing: lineSpacing,
            letterSpacing: letterSpacing
        )
        let height = attributed.boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral.height
        attributed.draw(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height, height + 2)))
        return min(rect.height, height + 2)
    }

    private func heightForText(
        _ text: String,
        width: CGFloat,
        font: UIFont,
        lineSpacing: CGFloat = 0
    ) -> CGFloat {
        let attributed = attributedString(
            text,
            font: font,
            color: .pdfInk,
            alignment: .left,
            lineSpacing: lineSpacing,
            letterSpacing: 0
        )
        return ceil(
            attributed.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height
        )
    }

    private func attributedString(
        _ text: String,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment,
        lineSpacing: CGFloat,
        letterSpacing: CGFloat
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = lineSpacing

        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
                .kern: letterSpacing
            ]
        )
    }

    private func aspectFitRect(imageSize: CGSize, in boundingRect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return boundingRect }
        let scale = min(boundingRect.width / imageSize.width, boundingRect.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: boundingRect.midX - (width / 2),
            y: boundingRect.midY - (height / 2),
            width: width,
            height: height
        )
    }

    private func evidenceLabel(for itemNumber: Int) -> String {
        "E-\(String(format: "%03d", itemNumber))"
    }

    private func displayTitle(for evidenceItem: EvidenceItem) -> String {
        let title = evidenceItem.userTitle.trimmedForPDF
        if !title.isEmpty { return title }

        if let filename = evidenceItem.sortedAttachments.first?.originalFilename.trimmedForPDF,
           !filename.isEmpty {
            return filename
        }

        return "Untitled proof item"
    }

    private func timelineNote(for evidenceItem: EvidenceItem) -> String {
        if !evidenceItem.userCleanedNote.trimmedForPDF.isEmpty {
            return evidenceItem.userCleanedNote.trimmedForPDF
        }

        if !evidenceItem.userNotes.trimmedForPDF.isEmpty {
            return evidenceItem.userNotes.trimmedForPDF
        }

        return ""
    }

    private func timelineDetectedText(for evidenceItem: EvidenceItem) -> String {
        let itemText = evidenceItem.originalOCRText.trimmedForPDF
        if !itemText.isEmpty {
            return itemText.prefixLinesForPDF(maxLines: 4, maxCharacters: 360)
        }

        let attachmentText = evidenceItem.sortedAttachments
            .map(\.originalOCRText)
            .first { !$0.trimmedForPDF.isEmpty }?
            .trimmedForPDF ?? ""
        return attachmentText.prefixLinesForPDF(maxLines: 4, maxCharacters: 360)
    }

    private func primaryPreviewAttachment(for evidenceItem: EvidenceItem) -> Attachment? {
        evidenceItem.sortedAttachments.first { attachment in
            switch attachment.attachmentType {
            case .photo, .screenshot, .pdf:
                true
            case .document, .textNote, .other:
                false
            }
        } ?? evidenceItem.sortedAttachments.first
    }

    private func localEventDate(for evidenceItem: EvidenceItem) -> Date? {
        evidenceItem.userProvidedEventDate ?? evidenceItem.detectedEventDate
    }

    private func localDateSource(for evidenceItem: EvidenceItem) -> DateSource {
        if evidenceItem.userProvidedEventDate != nil {
            return evidenceItem.userDateSource
        }

        if evidenceItem.detectedEventDate != nil {
            return evidenceItem.detectedDateSource ?? .notSpecified
        }

        return .notSpecified
    }

    private func pdfDateSourceText(for source: DateSource) -> String {
        switch source {
        case .notSpecified:
            "date source not set"
        case .userEntered:
            "user-entered date"
        case .fileMetadata:
            "date from file details"
        case .filename:
            "date from filename"
        case .visionOCR:
            "date found in text"
        case .importedMetadata:
            "date from import details"
        case .aiSuggested:
            "suggested date"
        }
    }

    private var coverTitle: String {
        let title = caseFile.userTitle.trimmedForPDF
        return title.isEmpty ? "Untitled case" : title.singleLineLimitedForPDF(to: 54)
    }

    private var attachmentCount: Int {
        evidenceItems.reduce(0) { $0 + $1.attachments.count }
    }

    private var textSourceSummary: String {
        let count = evidenceItems.filter { evidenceItem in
            !evidenceItem.originalOCRText.trimmedForPDF.isEmpty ||
                evidenceItem.sortedAttachments.contains { !$0.originalOCRText.trimmedForPDF.isEmpty }
        }.count

        guard count > 0 else { return "No detected text" }
        return count == 1 ? "1 item with detected text" : "\(count) items with detected text"
    }

    private var dateRangeText: String {
        let dates = evidenceItems.compactMap(localEventDate(for:))
        guard let firstDate = dates.min(), let lastDate = dates.max() else {
            return "Date not set"
        }

        if Self.dayKeyFormatter.string(from: firstDate) == Self.dayKeyFormatter.string(from: lastDate) {
            return Self.shortDateFormatter.string(from: firstDate)
        }

        return "\(Self.shortDateFormatter.string(from: firstDate)) - \(Self.shortDateFormatter.string(from: lastDate))"
    }

    private func categorySummaryPairs() -> [(String, String)] {
        let grouped = Dictionary(grouping: evidenceItems, by: { $0.category })
        return grouped.keys.sorted { $0.displayName < $1.displayName }.map { category in
            let count = grouped[category]?.count ?? 0
            return (category.displayName, "\(count)")
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let compactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let timelineSectionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let longDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
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

private extension String {
    var trimmedForPDF: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    }

    func limitedForPDF(to maxCharacters: Int) -> String {
        let value = trimmedForPDF
        guard value.count > maxCharacters else { return value }
        let endIndex = value.index(value.startIndex, offsetBy: maxCharacters)
        return "\(value[..<endIndex])…\n\n[Additional text remains in the original Proofly record.]"
    }

    func singleLineLimitedForPDF(to maxCharacters: Int) -> String {
        let value = trimmedForPDF.replacingOccurrences(of: "\n", with: " ")
        guard value.count > maxCharacters else { return value }
        let endIndex = value.index(value.startIndex, offsetBy: maxCharacters)
        return "\(value[..<endIndex])..."
    }

    func prefixLinesForPDF(maxLines: Int, maxCharacters: Int) -> String {
        let value = trimmedForPDF
        guard !value.isEmpty else { return "" }

        let lines = value
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(maxLines)
            .joined(separator: " ")
        let compacted = lines.trimmingCharacters(in: .whitespacesAndNewlines)

        guard compacted.count > maxCharacters else { return compacted }
        let endIndex = compacted.index(compacted.startIndex, offsetBy: maxCharacters)
        return "\(compacted[..<endIndex])..."
    }
}
