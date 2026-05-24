import StoreKit
import SwiftData
import SwiftUI

struct ManualEvidenceEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.proofKitServices) private var services
    @Environment(\.requestReview) private var requestReview

    @Bindable var caseFile: CaseFile
    let onSave: (EvidenceItem) -> Void

    @State private var eventDate = Date()
    @State private var title = ""
    @State private var category: EvidenceCategory = .note
    @State private var userNote = ""
    @State private var whyThisMatters = ""
    @State private var userMarkedImportant = false
    @State private var saveErrorMessage: String?
    @State private var entitlementSnapshot = ProofKitEntitlementSnapshot.placeholder()
    @State private var isSaving = false

    private var canSave: Bool {
        !title.proofKitTrimmedInput.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ProofKitVisual.sectionSpacing) {
                    intro
                        .proofKitAppear()
                    limitStatus
                        .proofKitAppear(delay: 0.04)
                    eventDetails
                        .proofKitAppear(delay: 0.08)
                    notes
                        .proofKitAppear(delay: 0.12)
                    importance
                        .proofKitAppear(delay: 0.16)

                    if let saveErrorMessage {
                        Text(saveErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(ProofKitMotion.compactInsertion)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, ProofKitVisual.sectionSpacing)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add Proof")
            .navigationBarTitleDisplayMode(.inline)
            .animation(ProofKitMotion.standard, value: isSaving)
            .animation(ProofKitMotion.standard, value: saveErrorMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveEvidence() }
                    } label: {
                        HStack(spacing: 6) {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                                    .transition(.opacity)
                            }

                            Text(isSaving ? "Saving…" : "Save")
                                .contentTransition(.opacity)
                        }
                    }
                    .disabled(!canSave || isSaving)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSaving)
        .task {
            entitlementSnapshot = await services.paywall.currentEntitlement()
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a manual record")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Capture what happened in your own words. This stays local and does not use OCR or AI.")
                .font(.subheadline)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var limitStatus: some View {
        if let evidenceItemLimit = entitlementSnapshot.limits.evidenceItemLimit {
            let currentCount = caseFile.evidenceItems.count
            let remainingCount = max(0, evidenceItemLimit - currentCount)

            Text(remainingCount == 0 ? "\(entitlementSnapshot.plan.displayName) has reached \(currentCount)/\(evidenceItemLimit) proof items for this case. Upgrade to add more proof." : "\(currentCount)/\(evidenceItemLimit) proof items used. This manual record will stay local and does not use AI credits.")
                .font(.footnote)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ProofKitVisual.cardBackground)
                }
        }
    }

    private var eventDetails: some View {
        EvidenceFormCard {
            VStack(alignment: .leading, spacing: ProofKitVisual.sectionSpacing) {
                VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                    EvidenceFieldHeader(
                        title: "Event date",
                        subtitle: "Use the date this happened, or the date this record refers to."
                    )

                    DatePicker(
                        "Event date",
                        selection: $eventDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                    EvidenceFieldHeader(title: "Title")

                    TextField("Example: Email about repair request", text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: ProofKitVisual.fieldCornerRadius, style: .continuous)
                                .fill(ProofKitVisual.fieldBackground)
                        }
                }

                VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                    EvidenceFieldHeader(title: "Category")

                    Picker("Category", selection: $category) {
                        ForEach(EvidenceCategory.allCases) { category in
                            Text(category.displayName)
                                .tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(ProofKitVisual.fieldBackground)
                    }
                }
            }
        }
    }

    private var notes: some View {
        EvidenceFormCard {
            VStack(alignment: .leading, spacing: ProofKitVisual.sectionSpacing) {
                VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                    EvidenceFieldHeader(
                        title: "User note",
                        subtitle: "Add the context you want to remember."
                    )

                    CalmTextEditor(
                        text: $userNote,
                        minHeight: 120,
                        accessibilityLabel: "User note"
                    )
                }

                VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                    EvidenceFieldHeader(
                        title: "Why this matters",
                        subtitle: "Keep this practical: what this record helps show or explain."
                    )

                    CalmTextEditor(
                        text: $whyThisMatters,
                        minHeight: 96,
                        accessibilityLabel: "Why this matters"
                    )
                }
            }
        }
    }

    private var importance: some View {
        EvidenceFormCard {
            Toggle(isOn: $userMarkedImportant) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mark as important")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Use this for records you want to review first when building the case.")
                        .font(.footnote)
                        .foregroundStyle(ProofKitVisual.helperText)
                }
            }
        }
    }

    @MainActor
    private func saveEvidence() async {
        let trimmedTitle = title.proofKitTrimmedInput
        guard !trimmedTitle.isEmpty else { return }

        withAnimation(ProofKitMotion.standard) {
            isSaving = true
            saveErrorMessage = nil
        }
        defer {
            withAnimation(ProofKitMotion.standard) {
                isSaving = false
            }
        }

        let decision = await services.paywall.canAddEvidence(to: caseFile, adding: 1)
        guard decision.isAllowed else {
            withAnimation(ProofKitMotion.standard) {
                saveErrorMessage = decision.message
            }
            return
        }

        let now = Date()
        let evidenceItem = EvidenceItem(
            category: category,
            userDateSource: .userEntered,
            userTitle: trimmedTitle,
            userNotes: userNote.proofKitTrimmedInput,
            userWhyThisMatters: whyThisMatters.proofKitTrimmedInput,
            userProvidedEventDate: eventDate,
            userMarkedImportant: userMarkedImportant,
            isReviewed: true,
            reviewedAt: now,
            createdAt: now,
            updatedAt: now,
            sortIndex: caseFile.evidenceItems.count
        )

        modelContext.insert(evidenceItem)
        caseFile.evidenceItems.append(evidenceItem)
        caseFile.updatedAt = now

        if caseFile.status == .draft {
            caseFile.status = .active
        }

        do {
            try modelContext.save()
            services.analytics.trackProofAdded(evidenceItem, caseFile: caseFile)
            services.analytics.trackTimelineItemCreated(evidenceItem)
            services.analytics.trackProofAddedToTimeline(evidenceItem)
            if AppReviewPromptCoordinator.shared.shouldRequestTimelineProofReview() {
                requestReview()
            }
            onSave(evidenceItem)
            dismiss()
        } catch {
            withAnimation(ProofKitMotion.standard) {
                saveErrorMessage = "Proof could not be saved. Please try again."
            }
        }
    }
}

private struct EvidenceFormCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .proofKitCard()
    }
}

private struct EvidenceFieldHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CalmTextEditor: View {
    @Binding var text: String
    let minHeight: CGFloat
    let accessibilityLabel: String

    var body: some View {
        TextEditor(text: $text)
            .frame(minHeight: minHeight)
            .padding(10)
            .scrollContentBackground(.hidden)
            .background {
                RoundedRectangle(cornerRadius: ProofKitVisual.fieldCornerRadius, style: .continuous)
                    .fill(ProofKitVisual.fieldBackground)
            }
            .accessibilityLabel(accessibilityLabel)
    }
}

private extension String {
    var proofKitTrimmedInput: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    NavigationStack {
        ManualEvidenceEntryView(
            caseFile: CaseFile(
                caseType: .apartmentIssue,
                userTitle: "Housing lease timeline"
            )
        ) { _ in }
    }
    .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self, AIResultCache.self], inMemory: true)
}
