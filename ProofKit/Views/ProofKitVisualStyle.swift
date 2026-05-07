import SwiftUI
import UIKit

enum ProofKitVisual {
    static let cardPadding: CGFloat = 20
    static let compactCardPadding: CGFloat = 18
    static let cardCornerRadius: CGFloat = 18
    static let panelCornerRadius: CGFloat = 16
    static let fieldCornerRadius: CGFloat = 12
    static let sectionSpacing: CGFloat = 20
    static let cardSpacing: CGFloat = 14
    static let fieldSpacing: CGFloat = 10

    static let screenBackground = dynamicColor(
        light: .systemGroupedBackground,
        dark: UIColor(red: 0.047, green: 0.059, blue: 0.078, alpha: 1)
    )
    static let cardBackground = dynamicColor(
        light: .secondarySystemGroupedBackground,
        dark: UIColor(red: 0.082, green: 0.102, blue: 0.133, alpha: 1)
    )
    static let fieldBackground = dynamicColor(
        light: .tertiarySystemGroupedBackground,
        dark: UIColor(red: 0.125, green: 0.157, blue: 0.204, alpha: 1)
    )
    static let quietFill = dynamicColor(
        light: .tertiarySystemFill,
        dark: UIColor(red: 0.125, green: 0.157, blue: 0.204, alpha: 1)
    )
    static let helperText = dynamicColor(
        light: .secondaryLabel,
        dark: UIColor(red: 0.69, green: 0.74, blue: 0.80, alpha: 1)
    )
    static let subduedText = dynamicColor(
        light: .tertiaryLabel,
        dark: UIColor(red: 0.50, green: 0.56, blue: 0.63, alpha: 1)
    )
    static let cardBorder = dynamicColor(
        light: UIColor.separator.withAlphaComponent(0.18),
        dark: UIColor(white: 1, alpha: 0.10)
    )
    static let divider = dynamicColor(
        light: UIColor.separator.withAlphaComponent(0.14),
        dark: UIColor(white: 1, alpha: 0.08)
    )
    static let accent = dynamicColor(
        light: UIColor(red: 0.02, green: 0.47, blue: 0.92, alpha: 1),
        dark: UIColor(red: 0.26, green: 0.65, blue: 1.00, alpha: 1)
    )
    static let accentSecondary = dynamicColor(
        light: UIColor(red: 0.03, green: 0.58, blue: 0.58, alpha: 1),
        dark: UIColor(red: 0.15, green: 0.82, blue: 0.78, alpha: 1)
    )
    static let primaryActionBackground = dynamicColor(
        light: UIColor(red: 0.02, green: 0.47, blue: 0.92, alpha: 1),
        dark: UIColor(red: 0.16, green: 0.56, blue: 1.00, alpha: 1)
    )
    static let primaryActionForeground = Color.white
    static let elevatedShadow = dynamicColor(
        light: UIColor(white: 0, alpha: 0.045),
        dark: UIColor(white: 0, alpha: 0.32)
    )
    static let imageBadgeBackground = dynamicColor(
        light: UIColor(white: 0, alpha: 0.58),
        dark: UIColor(white: 0, alpha: 0.70)
    )
    static let pdfPreviewBackgroundUIColor = dynamicUIColor(
        light: .secondarySystemGroupedBackground,
        dark: UIColor(red: 0.047, green: 0.059, blue: 0.078, alpha: 1)
    )

    static let accentGradient = LinearGradient(
        colors: [accent, accentSecondary],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let surfaceGradient = LinearGradient(
        colors: [cardBackground, fieldBackground],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(dynamicUIColor(light: light, dark: dark))
    }

    private static func dynamicUIColor(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? dark : light
        }
    }
}

enum ProofKitMotion {
    static let quick = Animation.easeOut(duration: 0.16)
    static let standard = Animation.snappy(duration: 0.26, extraBounce: 0.015)
    static let horizontalCardSlide = Animation.spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.06)
    static let softSpring = Animation.spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.08)
    static let slowEase = Animation.easeInOut(duration: 0.30)

    static let cardInsertion = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 10)),
        removal: .opacity
    )

    static let compactInsertion = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 5)),
        removal: .opacity
    )

    static func horizontalCardTransition(forward: Bool) -> AnyTransition {
        let travel: CGFloat = 48

        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(x: forward ? travel : -travel))
                .combined(with: .scale(scale: 0.992, anchor: .center)),
            removal: .opacity
                .combined(with: .offset(x: forward ? -travel : travel))
                .combined(with: .scale(scale: 0.996, anchor: .center))
        )
    }
}

extension View {
    func proofKitCard(
        padding: CGFloat = ProofKitVisual.cardPadding,
        cornerRadius: CGFloat = ProofKitVisual.cardCornerRadius
    ) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ProofKitVisual.cardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
            }
    }

    func proofKitFieldBackground(
        cornerRadius: CGFloat = ProofKitVisual.fieldCornerRadius
    ) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ProofKitVisual.fieldBackground)
            }
    }

    func proofKitAppear(delay: Double = 0) -> some View {
        modifier(ProofKitAppearModifier(delay: delay))
    }
}

private struct ProofKitAppearModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (isVisible ? 0 : 8))
            .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.996), anchor: .center)
            .onAppear {
                guard !isVisible else { return }

                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(ProofKitMotion.softSpring.delay(delay)) {
                        isVisible = true
                    }
                }
            }
    }
}

struct ProofKitCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(ProofKitMotion.quick, value: configuration.isPressed)
    }
}
