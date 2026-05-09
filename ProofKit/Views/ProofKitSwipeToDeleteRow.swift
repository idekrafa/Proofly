import SwiftUI

struct ProofKitSwipeToDeleteRow<Content: View>: View {
    private let deleteButtonWidth: CGFloat = 96
    private let revealThreshold: CGFloat = 42

    let deleteAccessibilityLabel: String
    let cornerRadius: CGFloat
    let onOpen: (() -> Void)?
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @GestureState private var dragTranslation: CGFloat = 0
    @State private var restingOffset: CGFloat = 0
    @State private var isSuppressingTap = false
    @State private var rowHeight: CGFloat = 0

    init(
        deleteAccessibilityLabel: String,
        cornerRadius: CGFloat = ProofKitVisual.cardCornerRadius,
        onOpen: (() -> Void)? = nil,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.deleteAccessibilityLabel = deleteAccessibilityLabel
        self.cornerRadius = cornerRadius
        self.onOpen = onOpen
        self.onDelete = onDelete
        self.content = content
    }

    private var visibleOffset: CGFloat {
        max(-deleteButtonWidth, min(0, restingOffset + dragTranslation))
    }

    private var isDeleteRevealed: Bool {
        restingOffset < 0
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteButton
                .frame(width: deleteButtonWidth, height: rowHeight)
                .opacity(visibleOffset < 0 && rowHeight > 0 ? 1 : 0)
                .allowsHitTesting(isDeleteRevealed)
                .zIndex(2)

            swipableContent
                .zIndex(1)
        }
        .clipped()
        .onPreferenceChange(ProofKitSwipeRowHeightPreferenceKey.self) { height in
            guard abs(rowHeight - height) > 0.5 else { return }
            rowHeight = height
        }
        .proofKitSwipeOpenAccessibilityAction(onOpen)
        .accessibilityAction(named: isDeleteRevealed ? "Hide Delete" : "Reveal Delete") {
            withAnimation(ProofKitMotion.standard) {
                restingOffset = isDeleteRevealed ? 0 : -deleteButtonWidth
            }
        }
    }

    @ViewBuilder
    private var swipableContent: some View {
        if onOpen == nil {
            contentBase
                .simultaneousGesture(revealGesture)
        } else {
            contentBase
                .onTapGesture(perform: handleTap)
                .simultaneousGesture(revealGesture)
        }
    }

    private var contentBase: some View {
        content()
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ProofKitSwipeRowHeightPreferenceKey.self, value: proxy.size.height)
                }
            }
            .offset(x: visibleOffset)
            .contentShape(Rectangle())
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            performDelete()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))

                Text("Delete")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(width: deleteButtonWidth)
            .frame(maxHeight: .infinity)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityLabel(deleteAccessibilityLabel)
        }
        .buttonStyle(.plain)
    }

    private func performDelete() {
        isSuppressingTap = true
        onDelete()
        resetTapSuppressionSoon()
    }

    private var revealGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                isSuppressingTap = true
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    resetTapSuppressionSoon()
                    return
                }

                let projectedOffset = restingOffset + value.predictedEndTranslation.width
                let shouldReveal = projectedOffset < -deleteButtonWidth / 2 || value.translation.width < -revealThreshold

                withAnimation(ProofKitMotion.standard) {
                    restingOffset = shouldReveal ? -deleteButtonWidth : 0
                }

                resetTapSuppressionSoon()
            }
    }

    private func handleTap() {
        guard !isSuppressingTap else { return }

        if isDeleteRevealed {
            withAnimation(ProofKitMotion.standard) {
                restingOffset = 0
            }
        } else {
            onOpen?()
        }
    }

    private func resetTapSuppressionSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isSuppressingTap = false
        }
    }
}

private struct ProofKitSwipeRowHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    @ViewBuilder
    func proofKitSwipeOpenAccessibilityAction(_ action: (() -> Void)?) -> some View {
        if let action {
            accessibilityAction(named: "Open") {
                action()
            }
        } else {
            self
        }
    }
}
