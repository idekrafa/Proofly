import SwiftUI

struct PaywallBenefitRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(ProofKitPaywallStyle.teal)
                .frame(width: 22, height: 22)
                .background {
                    Circle()
                        .fill(ProofKitPaywallStyle.teal.opacity(0.12))
                }
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ProofKitPaywallStyle.ink.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PaywallBenefitRow(text: "Raw files stay on your device. AI only uses selected text and details when you ask.")
        .padding()
        .background(ProofKitPaywallStyle.background)
}
