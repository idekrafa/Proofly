import SwiftUI

struct CaseSettingsView: View {
    let caseFile: CaseFile

    var body: some View {
        VStack(alignment: .leading, spacing: ProofKitVisual.sectionSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Case details")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Basic information for this case.")
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ReadOnlySettingsRow(label: "Type", value: caseFile.caseType.displayName)
                    SettingsDivider()
                    ReadOnlySettingsRow(label: "Status", value: caseFile.status.displayName)
                    SettingsDivider()
                    ReadOnlySettingsRow(label: "Created", value: ProofKitDateFormatting.shortDate(caseFile.createdAt))
                    SettingsDivider()
                    ReadOnlySettingsRow(label: "Updated", value: ProofKitDateFormatting.shortDate(caseFile.updatedAt))
                }
                .settingsCard()
                .padding(.top, 4)
            }

            AICreditStatusCard()
        }
        .proofKitAppear()
    }
}

private struct ReadOnlySettingsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(ProofKitVisual.helperText)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
            .background(ProofKitVisual.divider)
    }
}

private extension View {
    func settingsCard() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: ProofKitVisual.panelCornerRadius, style: .continuous)
                    .fill(ProofKitVisual.cardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: ProofKitVisual.panelCornerRadius, style: .continuous)
                    .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
            }
    }
}

#Preview {
    CaseSettingsView(caseFile: CaseFile(caseType: .workplaceIssue, userTitle: "Sample Case"))
}
