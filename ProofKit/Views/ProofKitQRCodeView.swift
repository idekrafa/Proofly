import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum ProofKitQRCodeGenerator {
    /// Renders `content` as a QR code image. `scale` multiplies the native
    /// module size so the output stays sharp at display size.
    static func image(for content: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }

        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// A scannable QR code on a white card. The white backdrop is intentional:
/// scanners need contrast, so the code never adopts dark-mode colors.
struct ProofKitQRCodeView: View {
    let content: String
    var size: CGFloat = 190

    @State private var qrImage: UIImage?

    var body: some View {
        Group {
            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
        .task(id: content) {
            qrImage = ProofKitQRCodeGenerator.image(for: content)
        }
        .accessibilityLabel("QR code for the signing link")
    }
}
