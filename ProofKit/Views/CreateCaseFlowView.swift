import SwiftUI

struct CreateCaseDraft {
    let caseType: CaseType
    let title: String
    let summary: String
    let notes: String
}

struct CreateCaseFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let onCreate: (CreateCaseDraft) -> Void

    @State private var selectedCategory: CaseCategory?
    @State private var title = ""
    @State private var lastPrefilledTitle: String?
    @State private var step: Step = .documentationType
    @FocusState private var titleIsFocused: Bool

    private enum Step {
        case documentationType
        case caseTitle
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch step {
                        case .documentationType:
                            documentationTypeStep
                        case .caseTitle:
                            titleStep
                        }
                    }
                    .id(step)
                    .transition(ProofKitMotion.cardInsertion)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(.systemGroupedBackground))

                bottomBar
            }
            .navigationTitle("New Case")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: step) { _, newStep in
                if newStep == .caseTitle {
                    titleIsFocused = true
                }
            }
            .animation(ProofKitMotion.standard, value: step)
        }
        .presentationDetents([.large])
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(step == .documentationType ? "What are you documenting?" : "Name this case")
                .font(.title2.weight(.semibold))

            Text(step == .documentationType ? "Choose the closest fit. This only helps organize your records." : "ProofKit started with a suggested title. You can change it anytime.")
                .font(.subheadline)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ProgressCapsule(isActive: true)
                ProgressCapsule(isActive: step == .caseTitle)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .animation(ProofKitMotion.standard, value: step)
    }

    private var documentationTypeStep: some View {
        CaseCategoryPickerView(
            selection: $selectedCategory,
            cardSpacing: 13,
            cardStyle: .onboardingPurpose
        )
    }

    private var titleStep: some View {
        VStack(alignment: .leading, spacing: ProofKitVisual.sectionSpacing) {
            if let selectedCategory {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected category")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ProofKitVisual.helperText)

                    CaseCategoryPurposeCard(
                        category: selectedCategory,
                        isSelected: true,
                        height: 128,
                        imageSize: 116,
                        imageColumnWidth: 118,
                        accessory: .selection
                    )
                }
                .transition(ProofKitMotion.compactInsertion)
            }

            VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                Text("Case title")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ProofKitVisual.helperText)

                TextField(selectedCategory?.starterTitle ?? "Example: Kitchen repair records", text: $title)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($titleIsFocused)
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(ProofKitVisual.fieldBackground)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
                    }
            }

            if let selectedCategory {
                Text(selectedCategory.starterDescription)
                    .font(.footnote)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("ProofKit will create a local case file. You can add records, build a timeline, and export a case PDF later.")
                .font(.footnote)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step == .caseTitle {
                Button("Back") {
                    withAnimation(ProofKitMotion.standard) {
                        step = .documentationType
                    }
                }
                .buttonStyle(.bordered)
                .transition(ProofKitMotion.compactInsertion)
            }

            Spacer()

            Button(step == .documentationType ? "Continue" : "Create Case") {
                primaryAction()
            }
            .buttonStyle(.borderedProminent)
            .disabled(primaryActionIsDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
    }

    private var primaryActionIsDisabled: Bool {
        switch step {
        case .documentationType:
            selectedCategory == nil
        case .caseTitle:
            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func primaryAction() {
        switch step {
        case .documentationType:
            guard let selectedCategory else { return }
            prefillTitleIfNeeded(for: selectedCategory)
            withAnimation(ProofKitMotion.standard) {
                step = .caseTitle
            }
        case .caseTitle:
            guard let selectedCategory else { return }
            onCreate(
                CreateCaseDraft(
                    caseType: selectedCategory.caseType,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    summary: selectedCategory.starterDescription,
                    notes: selectedCategory.selectedCategoryNotesLine
                )
            )
        }
    }

    private func prefillTitleIfNeeded(for category: CaseCategory) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty || lastPrefilledTitle == title {
            title = category.starterTitle
            lastPrefilledTitle = category.starterTitle
        }
    }
}

private struct ProgressCapsule: View {
    let isActive: Bool

    var body: some View {
        Capsule(style: .continuous)
            .fill(isActive ? Color.accentColor : ProofKitVisual.quietFill)
            .frame(height: 4)
            .animation(ProofKitMotion.standard, value: isActive)
    }
}

#Preview {
    CreateCaseFlowView { _ in }
}
