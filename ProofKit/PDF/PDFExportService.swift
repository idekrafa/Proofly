import Foundation
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
    let includeStatementPlaceholder: Bool
    let includeProofKitWatermark: Bool
    let generatedAt: Date

    init(
        caseFile: CaseFile,
        destinationDirectory: URL,
        includeStatementPlaceholder: Bool = true,
        includeProofKitWatermark: Bool = true,
        generatedAt: Date = .now
    ) {
        self.caseFile = caseFile
        self.destinationDirectory = destinationDirectory
        self.includeStatementPlaceholder = includeStatementPlaceholder
        self.includeProofKitWatermark = includeProofKitWatermark
        self.generatedAt = generatedAt
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
        let fallback = "ProofKit-Evidence-Case"
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
    private let margin: CGFloat = 54
    private let contentBottom: CGFloat = 712
    private let headerTop: CGFloat = 36
    private let headerBottom: CGFloat = 86
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
        return title.isEmpty ? "ProofKit Evidence Case" : "\(title) Evidence Case"
    }

    func render(to destinationURL: URL) throws {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: caseTitleValue,
            kCGPDFContextCreator as String: "ProofKit",
            kCGPDFContextAuthor as String: "ProofKit"
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        try renderer.writePDF(to: destinationURL) { context in
            drawCoverPage(context)
            drawCaseSummaryPage(context)
            drawTimelinePages(context)
            drawEvidenceIndexPages(context)
            drawEvidenceItemPages(context)

            if request.includeStatementPlaceholder {
                drawStatementPlaceholderPage(context)
            }

            finishOpenPageIfNeeded()
        }
    }

    private func drawCoverPage(_ context: UIGraphicsPDFRendererContext) {
        beginCoverPage(context)

        let x = margin
        var y: CGFloat = 134

        drawText(
            "EVIDENCE CASE",
            in: CGRect(x: x, y: y, width: contentWidth, height: 24),
            font: .systemFont(ofSize: 10, weight: .semibold),
            color: .pdfSecondary,
            letterSpacing: 1.3
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

        let exhibitText = evidenceItems.count == 1 ? "1 exhibit" : "\(evidenceItems.count) exhibits"
        drawText(
            "Prepared \(Self.shortDateFormatter.string(from: request.generatedAt)) • \(exhibitText)",
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
            ("Evidence records", "\(evidenceItems.count)"),
            ("Prepared", Self.longDateTimeFormatter.string(from: request.generatedAt))
        ]
        _ = drawMetadataGrid(metadata, x: x, y: y, columns: 2)

        let note = "Generated locally from records stored on this device. No AI-generated text or remote image processing was used for this case. ProofKit does not provide legal advice."
        drawText(
            note,
            in: CGRect(x: x, y: 620, width: contentWidth * 0.78, height: 70),
            font: .systemFont(ofSize: 12, weight: .regular),
            color: .pdfSecondary,
            lineSpacing: 2
        )
    }

    private func drawCaseSummaryPage(_ context: UIGraphicsPDFRendererContext) {
        beginContentPage(
            context,
            title: "Case Summary",
            subtitle: "Deterministic case details from local case records."
        )

        drawSectionTitle("Overview")
        let overviewGridHeight = drawMetadataGrid(
            [
                ("Case title", caseTitleValue),
                ("Case type", caseFile.caseType.displayName),
                ("Status", caseFile.status.displayName),
                ("Evidence records", "\(evidenceItems.count)"),
                ("Created", Self.shortDateFormatter.string(from: caseFile.createdAt)),
                ("Last updated", Self.shortDateTimeFormatter.string(from: caseFile.updatedAt))
            ],
            x: margin,
            y: cursorY,
            columns: 2
        )
        cursorY += overviewGridHeight + 22

        drawTextBlock(
            context,
            title: "User summary",
            text: caseFile.userSummary.trimmedForPDF,
            emptyText: "No case summary has been entered yet.",
            maxCharacters: 1_400
        )

        drawTextBlock(
            context,
            title: "User notes",
            text: caseFile.userNotes.trimmedForPDF,
            emptyText: "No additional case notes have been entered yet.",
            maxCharacters: 1_400
        )

        drawSectionTitle("Evidence overview")
        let importantCount = evidenceItems.filter(\.userMarkedImportant).count
        let reviewedCount = evidenceItems.filter(\.isReviewed).count
        let attachmentCount = evidenceItems.reduce(0) { $0 + $1.attachments.count }
        let evidenceOverviewGridHeight = drawMetadataGrid(
            [
                ("Important records", "\(importantCount)"),
                ("Reviewed records", "\(reviewedCount)"),
                ("Attachments", "\(attachmentCount)"),
                ("OCR source", "Local Apple Vision OCR")
            ],
            x: margin,
            y: cursorY,
            columns: 2
        )
        cursorY += evidenceOverviewGridHeight + 22

        let categoryLines = categorySummaryLines()
        drawTextBlock(
            context,
            title: "Category counts",
            text: categoryLines.isEmpty ? "" : categoryLines.joined(separator: "\n"),
            emptyText: "No evidence categories yet.",
            maxCharacters: 1_200
        )
    }

    private func drawTimelinePages(_ context: UIGraphicsPDFRendererContext) {
        beginContentPage(
            context,
            title: "Chronological Timeline",
            subtitle: "Sorted by user-entered date first, then locally detected date, then import date."
        )

        guard !evidenceItems.isEmpty else {
            drawEmptyMessage("No evidence records have been added yet.")
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
            title: "Evidence Index",
            subtitle: "Reference list for the proof item pages that follow."
        )

        guard !evidenceItems.isEmpty else {
            drawEmptyMessage("No evidence records have been added yet.")
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
            title: "Optional Statement Placeholder",
            subtitle: "A blank page for a user-prepared statement if needed."
        )

        drawTextBlock(
            context,
            title: "Statement page",
            text: "This page is intentionally left as a placeholder for a statement or cover note prepared outside of ProofKit. ProofKit does not provide legal advice or generate this statement.",
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
        let sourceText = localDateSource(for: evidenceItem).displayName

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
                title: "Original OCR excerpt",
                text: evidenceItem.originalOCRText.trimmedForPDF,
                emptyText: "",
                maxCharacters: 1_200,
                footnote: "OCR text was extracted locally on-device and is kept separate from user-edited notes."
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
            "ATTACHMENT \(attachmentNumber)",
            in: CGRect(x: cardRect.minX + 14, y: cardRect.minY + 13, width: 118, height: 12),
            font: .systemFont(ofSize: 7.6, weight: .semibold),
            color: .pdfTertiary,
            letterSpacing: 0.7
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
            "TYPE",
            in: CGRect(x: textX, y: y, width: 74, height: 12),
            font: .systemFont(ofSize: 7.5, weight: .semibold),
            color: .pdfTertiary,
            letterSpacing: 0.6
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
            "SIZE",
            in: CGRect(x: textX, y: y, width: 74, height: 12),
            font: .systemFont(ofSize: 7.5, weight: .semibold),
            color: .pdfTertiary,
            letterSpacing: 0.6
        )
        drawText(
            fileSizeText,
            in: CGRect(x: textX + 84, y: y - 1, width: textWidth - 84, height: 14),
            font: .systemFont(ofSize: 10.2, weight: .medium),
            color: .pdfInk
        )
        y += 22

        drawText(
            "IMPORTED",
            in: CGRect(x: textX, y: y, width: 74, height: 12),
            font: .systemFont(ofSize: 7.5, weight: .semibold),
            color: .pdfTertiary,
            letterSpacing: 0.6
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
        let noteText = note.isEmpty ? "No note entered." : note
        let whyText = why.isEmpty ? "" : "Why this matters: \(why.limitedForPDF(to: 220))"
        let body = [
            "\(evidenceItem.category.displayName) • \(localDateSource(for: evidenceItem).displayName)",
            noteText.limitedForPDF(to: 260),
            whyText
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        let bodyHeight = heightForText(
            body,
            width: contentWidth - 124,
            font: .systemFont(ofSize: 10.5, weight: .regular),
            lineSpacing: 2
        )
        let titleHeight = heightForText(
            displayTitle(for: evidenceItem),
            width: contentWidth - 124,
            font: .systemFont(ofSize: 12, weight: .semibold),
            lineSpacing: 1
        )
        let cardHeight = max(92, titleHeight + bodyHeight + 40)

        ensureSpace(cardHeight + 10, context: context)

        let cardRect = CGRect(x: margin, y: cursorY, width: contentWidth, height: cardHeight)
        drawRoundedRect(cardRect, fill: .white, stroke: .pdfDivider, strokeAlpha: 0.5)

        let labelRect = CGRect(x: cardRect.minX + 12, y: cardRect.minY + 14, width: 68, height: 38)
        drawExhibitBadge(evidenceLabel(for: itemNumber), in: labelRect)

        if evidenceItem.userMarkedImportant {
            drawPill("Important", x: cardRect.minX + 12, y: labelRect.maxY + 8, width: 68)
        }

        let textX = cardRect.minX + 100
        var textY = cardRect.minY + 14
        drawText(
            displayTitle(for: evidenceItem),
            in: CGRect(x: textX, y: textY, width: contentWidth - 124, height: titleHeight + 4),
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: .pdfInk,
            lineSpacing: 1
        )
        textY += titleHeight + 8
        drawText(
            body,
            in: CGRect(x: textX, y: textY, width: contentWidth - 124, height: bodyHeight + 6),
            font: .systemFont(ofSize: 10.5, weight: .regular),
            color: .pdfSecondary,
            lineSpacing: 2
        )

        cursorY += cardHeight + 10
    }

    private func drawIndexHeader() {
        let headerRect = CGRect(x: margin, y: cursorY, width: contentWidth, height: 26)
        drawRoundedRect(headerRect, fill: .pdfPanel, stroke: .pdfDivider, strokeAlpha: 0.45, cornerRadius: 6)

        let y = headerRect.minY + 8
        let headerFont = UIFont.systemFont(ofSize: 7.7, weight: .semibold)
        drawText("EXHIBIT", in: CGRect(x: margin + 10, y: y, width: 62, height: 12), font: headerFont, color: .pdfTertiary, letterSpacing: 0.6)
        drawText("DATE", in: CGRect(x: margin + 76, y: y, width: 82, height: 12), font: headerFont, color: .pdfTertiary, letterSpacing: 0.6)
        drawText("TITLE", in: CGRect(x: margin + 166, y: y, width: 190, height: 12), font: headerFont, color: .pdfTertiary, letterSpacing: 0.6)
        drawText("CATEGORY", in: CGRect(x: margin + 364, y: y, width: 82, height: 12), font: headerFont, color: .pdfTertiary, letterSpacing: 0.6)
        drawText("FILES", in: CGRect(x: margin + 454, y: y, width: 40, height: 12), font: headerFont, color: .pdfTertiary, alignment: .right, letterSpacing: 0.6)
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
        let blockHeight = bodyHeight + footnoteHeight + 60

        ensureSpace(blockHeight + 14, context: context)

        let rect = CGRect(x: margin, y: cursorY, width: contentWidth, height: blockHeight)
        drawRoundedRect(rect, fill: .white, stroke: .pdfDivider, strokeAlpha: 0.42)

        drawText(
            title.uppercased(),
            in: CGRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 32, height: 12),
            font: .systemFont(ofSize: 8.2, weight: .semibold),
            color: .pdfSecondary,
            letterSpacing: 0.7
        )
        drawLine(
            from: CGPoint(x: rect.minX + 16, y: rect.minY + 36),
            to: CGPoint(x: rect.maxX - 16, y: rect.minY + 36),
            color: .pdfDivider,
            alpha: 0.32,
            lineWidth: 0.5
        )
        drawText(
            body,
            in: CGRect(x: rect.minX + 16, y: rect.minY + 45, width: rect.width - 32, height: bodyHeight + 4),
            font: .systemFont(ofSize: 11, weight: .regular),
            color: text.isEmpty ? .pdfTertiary : .pdfSecondary,
            lineSpacing: 3
        )

        if !footnoteText.isEmpty {
            drawText(
                footnoteText,
                in: CGRect(x: rect.minX + 16, y: rect.minY + 51 + bodyHeight, width: rect.width - 32, height: footnoteHeight),
                font: .systemFont(ofSize: 9.5, weight: .regular),
                color: .pdfTertiary,
                lineSpacing: 2
            )
        }

        cursorY += blockHeight + 14
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
        let rowHeight: CGFloat = 50
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
                item.0.uppercased(),
                in: CGRect(x: rect.minX + 12, y: rect.minY + 9, width: rect.width - 24, height: 12),
                font: .systemFont(ofSize: 7.6, weight: .semibold),
                color: .pdfTertiary,
                letterSpacing: 0.6
            )
            drawText(
                item.1,
                in: CGRect(x: rect.minX + 12, y: rect.minY + 25, width: rect.width - 24, height: 18),
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

        let badge = attachment.attachmentType == .pdf ? "PDF" : attachment.attachmentType.displayName.prefix(3).uppercased()
        drawText(
            String(badge),
            in: CGRect(x: rect.minX + 8, y: rect.midY - 10, width: rect.width - 16, height: 20),
            font: .systemFont(ofSize: 14, weight: .semibold),
            color: .pdfSecondary,
            alignment: .center
        )
    }

    private func previewImage(for attachment: Attachment) -> UIImage? {
        let candidatePaths = [attachment.thumbnailLocalFilePath, attachment.localFilePath]
            .compactMap { $0 }

        for path in candidatePaths {
            if let image = UIImage(contentsOfFile: path) {
                return image
            }
        }

        if attachment.attachmentType == .pdf,
           let document = PDFDocument(url: URL(filePath: attachment.localFilePath)),
           let page = document.page(at: 0) {
            return page.thumbnail(of: CGSize(width: 480, height: 480), for: .mediaBox)
        }

        return nil
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

    private func finishOpenPageIfNeeded() {
        guard hasOpenPage else { return }
        drawPageFooter()
        hasOpenPage = false
    }

    private func ensureSpace(_ neededHeight: CGFloat, context: UIGraphicsPDFRendererContext) {
        guard cursorY + neededHeight > contentBottom else { return }
        beginContentPage(context, title: currentPageTitle, subtitle: currentPageSubtitle)
    }

    private func drawPageHeader(title: String, subtitle: String?) {
        drawText(
            "EVIDENCE PACKET",
            in: CGRect(x: margin, y: headerTop, width: 180, height: 16),
            font: .systemFont(ofSize: 8.5, weight: .semibold),
            color: .pdfSecondary,
            letterSpacing: 1.1
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

    private func drawPageFooter() {
        let footerY = pageRect.height - 44
        drawRule(y: footerY - 10, color: .pdfDivider, alpha: 0.45, lineWidth: 0.5)

        let footerTextColor = request.includeProofKitWatermark
            ? UIColor.pdfTertiary.withAlphaComponent(0.62)
            : .pdfTertiary
        let footerFont = UIFont.systemFont(
            ofSize: request.includeProofKitWatermark ? 7.8 : 8.5,
            weight: .regular
        )

        drawText(
            footerGeneratedText,
            in: CGRect(x: margin, y: footerY, width: contentWidth * 0.72, height: 16),
            font: footerFont,
            color: footerTextColor
        )
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
            return "Free export • Generated with ProofKit • \(Self.shortDateTimeFormatter.string(from: request.generatedAt))"
        }

        return "Created \(Self.shortDateTimeFormatter.string(from: request.generatedAt))"
    }

    private func drawSectionTitle(_ title: String) {
        if cursorY > headerBottom + 24 {
            cursorY += 4
        }

        drawText(
            title.uppercased(),
            in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 12),
            font: .systemFont(ofSize: 8.8, weight: .semibold),
            color: .pdfSecondary,
            letterSpacing: 0.8
        )
        cursorY += 18
        drawRule(y: cursorY, color: .pdfDivider, alpha: 0.58, lineWidth: 0.5)
        cursorY += 13
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
            "EXHIBIT",
            in: CGRect(x: rect.minX + 4, y: rect.minY + (emphasized ? 9 : 7), width: rect.width - 8, height: 9),
            font: .systemFont(ofSize: emphasized ? 7.4 : 6.7, weight: .semibold),
            color: .pdfTertiary,
            alignment: .center,
            letterSpacing: 0.7
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

        return "Untitled evidence"
    }

    private func timelineNote(for evidenceItem: EvidenceItem) -> String {
        if !evidenceItem.userCleanedNote.trimmedForPDF.isEmpty {
            return evidenceItem.userCleanedNote.trimmedForPDF
        }

        if !evidenceItem.userNotes.trimmedForPDF.isEmpty {
            return evidenceItem.userNotes.trimmedForPDF
        }

        if !evidenceItem.originalOCRText.trimmedForPDF.isEmpty {
            return "OCR excerpt: \(evidenceItem.originalOCRText.trimmedForPDF)"
        }

        return ""
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

    private func categorySummaryLines() -> [String] {
        let grouped = Dictionary(grouping: evidenceItems, by: { $0.category })
        return grouped.keys.sorted { $0.displayName < $1.displayName }.map { category in
            let count = grouped[category]?.count ?? 0
            return "\(category.displayName): \(count)"
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
        return "\(value[..<endIndex])…\n\n[Additional text remains in the original ProofKit record.]"
    }
}
