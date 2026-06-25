import SwiftUI

enum CaseCategoryPickerCardStyle: Equatable {
    case standard
    case onboardingPurpose
}

struct CaseCategoryPickerView: View {
    let categories: [CaseCategory]
    @Binding var selection: CaseCategory?
    let showsRookArtwork: Bool
    let cardSpacing: CGFloat
    let cardStyle: CaseCategoryPickerCardStyle

    init(
        categories: [CaseCategory] = CaseCategory.sharedOptions,
        selection: Binding<CaseCategory?>,
        showsRookArtwork: Bool = false,
        cardSpacing: CGFloat = ProofKitVisual.cardSpacing,
        cardStyle: CaseCategoryPickerCardStyle = .standard
    ) {
        self.categories = categories
        _selection = selection
        self.showsRookArtwork = showsRookArtwork
        self.cardSpacing = cardSpacing
        self.cardStyle = cardStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: cardSpacing) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                Button {
                    withAnimation(ProofKitMotion.standard) {
                        selection = category
                    }
                } label: {
                    card(for: category)
                }
                .buttonStyle(ProofKitCardButtonStyle())
                .proofKitAppear(delay: min(Double(index) * 0.02, 0.12))
                .accessibilityHint(selection == category ? String(localized: "Selected") : String(localized: "Double tap to select this category."))
            }
        }
    }

    @ViewBuilder
    private func card(for category: CaseCategory) -> some View {
        switch cardStyle {
        case .standard:
            CaseCategoryCard(
                category: category,
                isSelected: selection == category,
                showsRookArtwork: showsRookArtwork
            )
        case .onboardingPurpose:
            CaseCategoryPurposeCard(
                category: category,
                isSelected: selection == category,
                height: 142,
                imageSize: 134,
                imageColumnWidth: 136,
                accessory: .selection
            )
        }
    }
}

struct CaseCategoryPurposeCard: View {
    enum Accessory: Equatable {
        case chevron
        case selection
    }

    let category: CaseCategory
    let isSelected: Bool
    let height: CGFloat
    let imageSize: CGFloat
    let imageColumnWidth: CGFloat
    let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let imageName = category.rookAssetName {
                    Image(imageName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: imageSize, height: imageSize)
                        .shadow(color: Color.black.opacity(0.30), radius: 14, x: 0, y: 9)
                } else {
                    Image(systemName: category.iconName)
                        .font(.system(size: 34, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ProofKitAuthPalette.secondaryText)
                }
            }
            .frame(width: imageColumnWidth, height: height, alignment: .center)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(category.onboardingPurposeTitle)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .tracking(-0.18)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)

                Text(category.onboardingPurposeOutcome)
                    .font(.system(size: 14.5, weight: .regular, design: .rounded))
                    .tracking(-0.08)
                    .foregroundStyle(ProofKitAuthPalette.secondaryText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.86)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessoryView
        }
        .padding(.leading, 2)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            CaseCategoryPurposeCardPalette.fieldBackgroundTop,
                            CaseCategoryPurposeCardPalette.fieldBackgroundBottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(ProofKitVisual.accentGradient, lineWidth: 2)
            } else {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(CaseCategoryPurposeCardPalette.fieldStroke, lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(category.onboardingPurposeTitle). \(category.onboardingPurposeOutcome)"))
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.36))
                .accessibilityHidden(true)
        case .selection:
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? ProofKitVisual.accentSecondary : .white.opacity(0.30))
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityValue: String {
        switch accessory {
        case .chevron:
            ""
        case .selection:
            isSelected ? String(localized: "Selected") : String(localized: "Not selected")
        }
    }
}

private enum CaseCategoryPurposeCardPalette {
    static let fieldBackgroundTop = Color(red: 0.125, green: 0.157, blue: 0.204).opacity(0.96)
    static let fieldBackgroundBottom = Color(red: 0.086, green: 0.108, blue: 0.140).opacity(0.98)
    static let fieldStroke = Color.white.opacity(0.11)
}

struct CaseCategoryCard: View {
    let category: CaseCategory
    let isSelected: Bool
    let showsRookArtwork: Bool

    init(
        category: CaseCategory,
        isSelected: Bool,
        showsRookArtwork: Bool = false
    ) {
        self.category = category
        self.isSelected = isSelected
        self.showsRookArtwork = showsRookArtwork
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            leadingVisual

            VStack(alignment: .leading, spacing: 6) {
                Text(category.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(category.description)
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            selectionIndicator
        }
        .padding(ProofKitVisual.compactCardPadding)
        .frame(maxWidth: .infinity, minHeight: showsRookArtwork ? 112 : 88, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous)
                .fill(ProofKitVisual.cardBackground)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous)
                    .stroke(ProofKitVisual.accentGradient, lineWidth: 2)
            } else {
                RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous)
                    .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous))
        .animation(ProofKitMotion.standard, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(category.title). \(category.description)"))
        .accessibilityValue(isSelected ? String(localized: "Selected") : String(localized: "Not selected"))
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if showsRookArtwork, let rookAssetName = category.rookAssetName {
            Image(rookAssetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 82, height: 82)
                .shadow(color: Color.black.opacity(0.24), radius: 10, x: 0, y: 7)
                .frame(width: 86, height: 86)
                .accessibilityHidden(true)
        } else {
            ZStack {
                Circle()
                    .fill(isSelected ? ProofKitVisual.accent.opacity(0.16) : ProofKitVisual.quietFill)

                Image(systemName: category.iconName)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? ProofKitVisual.accent : ProofKitVisual.helperText)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)
        }
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isSelected ? ProofKitVisual.accentSecondary : ProofKitVisual.subduedText)
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
    }
}
