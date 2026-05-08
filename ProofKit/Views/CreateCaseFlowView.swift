import SwiftUI

struct CreateCaseDraft {
    let caseType: CaseType
    let title: String
}

struct CreateCaseFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let onCreate: (CreateCaseDraft) -> Void

    @State private var selectedOption: CreateCaseOption?
    @State private var title = ""
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
                    .padding(.bottom, 28)
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

            Text(step == .documentationType ? "Choose the closest fit. This only helps organize your records." : "Use a clear name you’ll recognize later. You can change it anytime.")
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
        VStack(alignment: .leading, spacing: ProofKitVisual.cardSpacing) {
            ForEach(Array(CreateCaseOption.allCases.enumerated()), id: \.element.id) { index, option in
                Button {
                    withAnimation(ProofKitMotion.standard) {
                        selectedOption = option
                    }
                } label: {
                    CreateCaseOptionRow(
                        option: option,
                        isSelected: selectedOption == option
                    )
                }
                .buttonStyle(ProofKitCardButtonStyle())
                .proofKitAppear(delay: min(Double(index) * 0.02, 0.12))
            }
        }
    }

    private var titleStep: some View {
        VStack(alignment: .leading, spacing: ProofKitVisual.sectionSpacing) {
            if let selectedOption {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Documenting")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ProofKitVisual.helperText)

                    Text(selectedOption.title)
                        .font(.headline.weight(.semibold))
                }
                .padding(ProofKitVisual.compactCardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(ProofKitVisual.cardBackground)
                }
                .transition(ProofKitMotion.compactInsertion)
            }

            VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                Text("Case title")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ProofKitVisual.helperText)

                TextField("Example: Kitchen repair records", text: $title)
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
            selectedOption == nil
        case .caseTitle:
            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func primaryAction() {
        switch step {
        case .documentationType:
            withAnimation(ProofKitMotion.standard) {
                step = .caseTitle
            }
        case .caseTitle:
            guard let selectedOption else { return }
            onCreate(
                CreateCaseDraft(
                    caseType: selectedOption.caseType,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }
    }

}

private struct CreateCaseOptionRow: View {
    let option: CreateCaseOption
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: option.systemImage)
                .font(.headline)
                .foregroundStyle(ProofKitVisual.helperText)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(option.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(option.description)
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : ProofKitVisual.subduedText)
        }
        .padding(ProofKitVisual.compactCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous)
                .fill(ProofKitVisual.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : ProofKitVisual.cardBorder, lineWidth: 1)
        }
        .animation(ProofKitMotion.standard, value: isSelected)
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

private enum CreateCaseOption: String, CaseIterable, Identifiable {
    case apartmentIssue
    case unpaidFreelanceWork
    case refundWarrantyIssue
    case workplaceIssue
    case insuranceIssue
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apartmentIssue:
            "Apartment issue"
        case .unpaidFreelanceWork:
            "Unpaid freelance work"
        case .refundWarrantyIssue:
            "Refund/warranty issue"
        case .workplaceIssue:
            "Workplace issue"
        case .insuranceIssue:
            "Insurance issue"
        case .other:
            "Something else"
        }
    }

    var description: String {
        switch self {
        case .apartmentIssue:
            "Repairs, messages, photos, rent records, or a move-out timeline."
        case .unpaidFreelanceWork:
            "Contracts, invoices, project records, messages, and payment timeline."
        case .refundWarrantyIssue:
            "Receipts, product photos, support messages, and warranty records."
        case .workplaceIssue:
            "Schedules, messages, notes, policy records, and workplace timeline."
        case .insuranceIssue:
            "Claim records, photos, receipts, messages, and adjuster updates."
        case .other:
            "Any situation where you want a clean set of records and a timeline."
        }
    }

    var systemImage: String {
        switch self {
        case .apartmentIssue:
            "house"
        case .unpaidFreelanceWork:
            "briefcase"
        case .refundWarrantyIssue:
            "cart"
        case .workplaceIssue:
            "person.text.rectangle"
        case .insuranceIssue:
            "shield"
        case .other:
            "folder"
        }
    }

    var caseType: CaseType {
        switch self {
        case .apartmentIssue:
            .apartmentIssue
        case .unpaidFreelanceWork:
            .unpaidFreelanceWork
        case .refundWarrantyIssue:
            .refundWarrantyIssue
        case .workplaceIssue:
            .workplaceIssue
        case .insuranceIssue:
            .insuranceIssue
        case .other:
            .other
        }
    }
}

#Preview {
    CreateCaseFlowView { _ in }
}
