import PDFKit
import PencilKit
import SwiftUI
import UIKit

struct SignatureCaptureView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var drawing = PKDrawing()
    @State private var page: PDFSignaturePage
    @State private var placement: PDFSignaturePlacement
    /// Normalized page-relative center (x, y in 0...1, origin top-left) for free placement.
    /// Mirrors the selected preset until the user drags the signature in the preview.
    @State private var customOffset: CGPoint
    /// Rendered image of the document page the signature will land on, shown behind the
    /// draggable signature so custom placement can target real content. Nil until loaded
    /// (or when no source document is available).
    @State private var pagePreviewImage: UIImage?
    /// Point size of the previewed page's media box, used to map the fixed 176×80 signature
    /// box and normalized offset onto the rendered page accurately.
    @State private var previewPageSize = CGSize(width: 612, height: 792)

    /// Source PDF (pre-signature) used to render the placement preview background.
    let documentURL: URL?
    let onComplete: (UIImage, PDFSignaturePage, PDFSignaturePlacement, CGPoint?) -> Void

    init(
        initialPage: PDFSignaturePage,
        initialPlacement: PDFSignaturePlacement,
        initialCustomOffset: CGPoint? = nil,
        documentURL: URL? = nil,
        onComplete: @escaping (UIImage, PDFSignaturePage, PDFSignaturePlacement, CGPoint?) -> Void
    ) {
        _page = State(initialValue: initialPage)
        _placement = State(initialValue: initialPlacement)
        _customOffset = State(
            initialValue: initialCustomOffset ?? initialPlacement.normalizedCenter
        )
        self.documentURL = documentURL
        self.onComplete = onComplete
    }

    private var canApplySignature: Bool {
        signatureImage != nil
    }

    private var signatureImage: UIImage? {
        guard !drawing.bounds.isNull, !drawing.bounds.isEmpty else { return nil }
        let renderBounds = drawing.bounds.insetBy(dx: -18, dy: -18)
        return drawing.image(from: renderBounds, scale: 3)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Draw signature")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Your signature stays on this device and is applied only to the PDF you generate.")
                            .font(.subheadline)
                            .foregroundStyle(ProofKitVisual.helperText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SignatureCanvas(drawing: $drawing)
                        .frame(height: 220)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
                        }
                        .shadow(color: ProofKitVisual.elevatedShadow.opacity(0.55), radius: 12, x: 0, y: 6)

                    Button {
                        withAnimation(ProofKitMotion.standard) {
                            drawing = PKDrawing()
                        }
                    } label: {
                        Label("Clear", systemImage: "eraser")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canApplySignature)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Placement")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Picker("Page", selection: $page) {
                            ForEach(PDFSignaturePage.allCases) { page in
                                Text(page.displayName).tag(page)
                            }
                        }
                        .pickerStyle(.segmented)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                            ForEach(PDFSignaturePlacement.presets) { option in
                                let isSelected = placement == option
                                let selectedColor = ProofKitVisual.accentSecondary
                                Button {
                                    withAnimation(ProofKitMotion.standard) {
                                        placement = option
                                        customOffset = option.normalizedCenter
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(isSelected ? selectedColor : ProofKitVisual.helperText)

                                        Text(option.displayName)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.82)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 11)
                                    .background {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(isSelected ? selectedColor.opacity(0.12) : ProofKitVisual.fieldBackground)
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(isSelected ? selectedColor.opacity(0.44) : ProofKitVisual.cardBorder, lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        placementPreview
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Sign PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard let signatureImage else { return }
                        let offset = placement == .custom ? customOffset : nil
                        onComplete(signatureImage, page, placement, offset)
                    }
                    .disabled(!canApplySignature)
                }
            }
            .task(id: page) {
                loadPagePreview()
            }
        }
    }

    private var placementPreview: some View {
        let pageHeight: CGFloat = 300
        let previewAspect = previewPageSize.height > 0 ? previewPageSize.width / previewPageSize.height : 612 / 792
        let pageWidth = pageHeight * previewAspect
        let sigWidth = pageWidth * (176 / max(previewPageSize.width, 1))
        let sigHeight = pageHeight * (80 / max(previewPageSize.height, 1))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fine-tune position")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if placement == .custom {
                    Text("Custom")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ProofKitVisual.accentSecondary)
                }
            }

            Text(pagePreviewImage == nil
                ? "Drag the signature to place it anywhere on the page."
                : "Drag the signature over the document to place it on an exact spot.")
                .font(.caption)
                .foregroundStyle(ProofKitVisual.helperText)

            Group {
                if let pagePreviewImage {
                    Image(uiImage: pagePreviewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white
                }
            }
            .frame(width: pageWidth, height: pageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
            }
            .overlay {
                signaturePreviewThumbnail(width: sigWidth, height: sigHeight)
                    .position(
                        x: customOffset.x * pageWidth,
                        y: customOffset.y * pageHeight
                    )
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateCustomOffset(
                            location: value.location,
                            pageSize: CGSize(width: pageWidth, height: pageHeight),
                            signatureSize: CGSize(width: sigWidth, height: sigHeight)
                        )
                    }
            )
            .frame(maxWidth: .infinity)
            .shadow(color: ProofKitVisual.elevatedShadow.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .padding(.top, 4)
    }

    /// Renders the page the signature will land on (first, last, or a representative page
    /// for "every page") from the source PDF, sizing the preview to its real dimensions.
    private func loadPagePreview() {
        guard let documentURL,
              let document = PDFDocument(url: documentURL),
              document.pageCount > 0 else {
            pagePreviewImage = nil
            return
        }

        let index: Int
        switch page {
        case .firstPage, .everyPage:
            index = 0
        case .lastPage:
            index = document.pageCount - 1
        }

        guard let pdfPage = document.page(at: index) else {
            pagePreviewImage = nil
            return
        }

        let bounds = pdfPage.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else {
            pagePreviewImage = nil
            return
        }

        // Render at ~2x the on-screen height for crisp text.
        let renderHeight: CGFloat = 600
        let renderSize = CGSize(width: renderHeight * bounds.width / bounds.height, height: renderHeight)
        previewPageSize = bounds.size
        pagePreviewImage = pdfPage.thumbnail(of: renderSize, for: .mediaBox)
    }

    private func signaturePreviewThumbnail(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let signatureImage {
                Image(uiImage: signatureImage)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Text("Signature")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ProofKitVisual.helperText)
            }
        }
        .frame(width: width, height: height)
        .background {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(ProofKitVisual.accentSecondary.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(ProofKitVisual.accentSecondary.opacity(0.55), lineWidth: 1)
        }
    }

    private func updateCustomOffset(location: CGPoint, pageSize: CGSize, signatureSize: CGSize) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }

        let halfWidth = signatureSize.width / 2
        let halfHeight = signatureSize.height / 2
        let clampedX = min(max(location.x, halfWidth), pageSize.width - halfWidth)
        let clampedY = min(max(location.y, halfHeight), pageSize.height - halfHeight)

        // Keep the signature inside the page's content band (away from header/footer),
        // matching the clamp applied when the signature is stamped onto the PDF.
        let normalizedY = min(max(clampedY / pageSize.height, 0.12), 0.9)

        if placement != .custom {
            placement = .custom
        }
        customOffset = CGPoint(x: clampedX / pageSize.width, y: normalizedY)
    }
}

private struct SignatureCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        if canvasView.drawing.dataRepresentation() != drawing.dataRepresentation() {
            canvasView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let parent: SignatureCanvas

        init(_ parent: SignatureCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
