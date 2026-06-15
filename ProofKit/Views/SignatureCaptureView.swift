import PencilKit
import SwiftUI
import UIKit

struct SignatureCaptureView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var drawing = PKDrawing()
    @State private var page: PDFSignaturePage
    @State private var placement: PDFSignaturePlacement

    let onComplete: (UIImage, PDFSignaturePage, PDFSignaturePlacement) -> Void

    init(
        initialPage: PDFSignaturePage,
        initialPlacement: PDFSignaturePlacement,
        onComplete: @escaping (UIImage, PDFSignaturePage, PDFSignaturePlacement) -> Void
    ) {
        _page = State(initialValue: initialPage)
        _placement = State(initialValue: initialPlacement)
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
                            ForEach(PDFSignaturePlacement.allCases) { option in
                                let isSelected = placement == option
                                let selectedColor = ProofKitVisual.accentSecondary
                                Button {
                                    withAnimation(ProofKitMotion.standard) {
                                        placement = option
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
                        onComplete(signatureImage, page, placement)
                    }
                    .disabled(!canApplySignature)
                }
            }
        }
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
