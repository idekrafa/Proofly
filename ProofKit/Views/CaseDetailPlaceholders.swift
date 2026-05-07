import SwiftUI

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PlaceholderPanel: View {
    let systemImage: String
    let title: String
    let message: String
    let steps: [PlaceholderStep]
    let footnote: String?

    init(
        systemImage: String,
        title: String,
        message: String,
        steps: [PlaceholderStep] = [],
        footnote: String? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.steps = steps
        self.footnote = footnote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.helperText)
                    .frame(width: 44, height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(ProofKitVisual.quietFill)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !steps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(steps) { step in
                        PlaceholderStepRow(step: step)

                        if step.id != steps.last?.id {
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }
                .padding(.top, 2)
            }

            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.subduedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .proofKitCard(cornerRadius: ProofKitVisual.panelCornerRadius)
    }
}

struct PlaceholderStep: Identifiable {
    let systemImage: String
    let title: String
    let detail: String

    var id: String { "\(systemImage)-\(title)" }
}

private struct PlaceholderStepRow: View {
    let step: PlaceholderStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ProofKitVisual.helperText)
                .frame(width: 22, height: 22)
                .background {
                    Circle()
                        .fill(ProofKitVisual.fieldBackground)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }
}
