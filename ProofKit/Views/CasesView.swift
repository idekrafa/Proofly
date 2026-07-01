import SwiftData
import SwiftUI
import UIKit

struct CasesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.proofKitServices) private var services
    @Query(sort: \CaseFile.updatedAt, order: .reverse) private var cases: [CaseFile]

    @StateObject private var viewModel = CaseListViewModel()
    @State private var searchText = ""
    @State private var isShowingCreateCaseFlow = false
    @State private var pendingCreatedCase: CaseFile?
    @State private var createdCaseToOpen: CaseFile?
    @State private var isOpeningCreatedCase = false
    @State private var paywallNotice: PaywallAccessDecision?
    @State private var activeAddProofSheet: CasesAddProofSheet?
    @State private var selectedCaseRoute: CasesCaseRoute?
    @State private var casePendingDeletion: CaseFile?
    @State private var isDeleteCaseConfirmationPresented = false
    @State private var caseDeletionNotice: CasesDeletionNotice?

    private var filteredCases: [CaseFile] {
        let queryTokens = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !queryTokens.isEmpty else { return cases }

        return cases.filter { caseFile in
            let searchableText = caseFile.casesSearchableText
            return queryTokens.allSatisfy { searchableText.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    CasesSearchField(text: $searchText)
                        .proofKitAppear(delay: 0.03)

                    content
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .background(CasesPalette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .animation(ProofKitMotion.standard, value: cases.map(\.id))
            .animation(ProofKitMotion.standard, value: filteredCases.map(\.id))
            .navigationDestination(isPresented: $isOpeningCreatedCase) {
                if let createdCaseToOpen {
                    CaseDetailView(caseFile: createdCaseToOpen)
                } else {
                    EmptyStateView(
                        title: String(localized: "Case created"),
                        message: String(localized: "Your case was created locally."),
                        systemImage: "checkmark.circle"
                    )
                }
            }
            .navigationDestination(item: $selectedCaseRoute) { route in
                CaseDetailView(caseFile: route.caseFile)
            }
            .sheet(isPresented: $isShowingCreateCaseFlow) {
                CreateCaseFlowView { draft in
                    let caseFile = viewModel.createCase(
                        in: modelContext,
                        title: draft.title,
                        caseType: draft.caseType,
                        summary: draft.summary,
                        notes: draft.notes
                    )
                    services.analytics.trackCaseCreated(caseFile, sourceScreen: .cases)
                    pendingCreatedCase = caseFile
                    isShowingCreateCaseFlow = false
                }
            }
            .sheet(item: $activeAddProofSheet) { sheet in
                switch sheet {
                case .importOptions(let caseFile):
                    AddProofImportView(
                        caseFile: caseFile,
                        onManualEntryRequested: {
                            withAnimation(ProofKitMotion.standard) {
                                activeAddProofSheet = .manualEntry(caseFile)
                            }
                        },
                        onImportComplete: { _ in
                            withAnimation(ProofKitMotion.standard) {
                                activeAddProofSheet = nil
                            }
                        }
                    )
                case .manualEntry(let caseFile):
                    ManualEvidenceEntryView(caseFile: caseFile) { _ in
                        withAnimation(ProofKitMotion.standard) {
                            activeAddProofSheet = nil
                        }
                    }
                }
            }
            .onChange(of: isShowingCreateCaseFlow) { _, isPresented in
                guard !isPresented, let pendingCreatedCase else { return }
                createdCaseToOpen = pendingCreatedCase
                self.pendingCreatedCase = nil
                isOpeningCreatedCase = true
            }
            .alert(item: $paywallNotice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(item: $caseDeletionNotice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .confirmationDialog(
                "Delete case?",
                isPresented: $isDeleteCaseConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Case", role: .destructive) {
                    deletePendingCase()
                }

                Button("Cancel", role: .cancel) {
                    casePendingDeletion = nil
                }
            } message: {
                Text(deleteCaseConfirmationMessage)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cases")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)
                    .kerning(-0.7)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(CasesPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                Task { await addCase() }
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CasesPalette.newCaseForeground)
                    .frame(width: 46, height: 46)
                    .background {
                        Circle()
                            .fill(CasesPalette.newCaseBackground)
                    }
            }
            .buttonStyle(CasesIconButtonStyle())
            .accessibilityLabel(String(localized: "New Case"))
        }
        .proofKitAppear()
    }

    private var headerSubtitle: String {
        if cases.isEmpty {
            return String(localized: "Create a case to start organizing proof.")
        }

        return String(localized: "\(cases.count) cases stored locally")
    }

    @ViewBuilder
    private var content: some View {
        if cases.isEmpty {
            CasesEmptyState(
                title: String(localized: "No cases yet"),
                message: String(localized: "Create your first case, then add photos, screenshots, PDFs, and notes as proof."),
                footnote: String(localized: "Cases stay local until you export them."),
                primaryActionTitle: String(localized: "+ New Case"),
                mascotImageName: "RookCasesEmpty",
                primaryAction: {
                    Task { await addCase() }
                }
            )
            .proofKitAppear(delay: 0.06)
        } else if filteredCases.isEmpty {
            CasesEmptyState(
                title: String(localized: "No matching cases"),
                message: String(localized: "Try searching by case title, status, type, notes, or evidence details."),
                primaryActionTitle: String(localized: "Clear Search"),
                primaryAction: {
                    withAnimation(ProofKitMotion.standard) {
                        searchText = ""
                    }
                }
            )
            .proofKitAppear(delay: 0.06)
        } else {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "All Cases") : String(localized: "Search Results"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .kerning(-0.25)

                    Spacer()

                    Text(filteredCases.count.caseCountText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CasesPalette.secondaryText)
                }

                LazyVStack(spacing: 14) {
                    ForEach(Array(filteredCases.enumerated()), id: \.element.id) { index, caseFile in
                        ProofKitSwipeToDeleteRow(
                            deleteAccessibilityLabel: String(localized: "Delete case"),
                            cornerRadius: 22,
                            onDelete: {
                                prepareDelete(for: caseFile)
                            }
                        ) {
                            CaseListCard(
                                caseFile: caseFile,
                                onAddProof: {
                                    Task { await showAddProofOptions(for: caseFile) }
                                },
                                onManageCase: {
                                    openCase(caseFile)
                                }
                            )
                        }
                        .proofKitAppear(delay: min(Double(index) * 0.025, 0.16))
                    }
                }
            }
            .transition(ProofKitMotion.cardInsertion)
        }
    }

    @MainActor
    private func addCase() async {
        let decision = await services.paywall.canCreateCase(existingCases: cases)
        guard decision.isAllowed else {
            paywallNotice = decision
            return
        }

        services.analytics.trackCaseCreateStarted(sourceScreen: .cases)
        isShowingCreateCaseFlow = true
    }

    @MainActor
    private func showAddProofOptions(for caseFile: CaseFile) async {
        let decision = await services.paywall.canAddEvidence(to: caseFile, adding: 1)
        guard decision.isAllowed else {
            paywallNotice = decision
            return
        }

        activeAddProofSheet = .importOptions(caseFile)
    }

    private func openCase(_ caseFile: CaseFile) {
        selectedCaseRoute = CasesCaseRoute(caseFile: caseFile)
    }

    private func prepareDelete(for caseFile: CaseFile) {
        casePendingDeletion = caseFile
        isDeleteCaseConfirmationPresented = true
    }

    private var deleteCaseConfirmationMessage: String {
        guard let casePendingDeletion else {
            return String(localized: "This removes the selected case from Proofly. Original proof files stay in the Vault and on this device.")
        }

        return String(localized: "This removes “\(casePendingDeletion.casesDisplayTitle)” and its timeline, notes, proof entries, and export records from Proofly. Original proof files stay in the Vault and on this device.")
    }

    private func deletePendingCase() {
        guard let caseFile = casePendingDeletion else { return }

        do {
            try CaseDeletionService.deleteCase(caseFile, modelContext: modelContext)
            services.analytics.trackCaseDeleted(caseFile)
        } catch {
            caseDeletionNotice = CasesDeletionNotice(
                title: String(localized: "Case not deleted"),
                message: String(localized: "This case could not be deleted. Please try again.")
            )
        }

        casePendingDeletion = nil
    }
}

private enum CasesAddProofSheet: Identifiable {
    case importOptions(CaseFile)
    case manualEntry(CaseFile)

    var id: String {
        switch self {
        case .importOptions(let caseFile):
            "importOptions-\(caseFile.id.uuidString)"
        case .manualEntry(let caseFile):
            "manualEntry-\(caseFile.id.uuidString)"
        }
    }
}

private struct CasesCaseRoute: Identifiable, Hashable {
    let id: UUID
    let caseFile: CaseFile

    init(caseFile: CaseFile) {
        id = caseFile.id
        self.caseFile = caseFile
    }

    static func == (lhs: CasesCaseRoute, rhs: CasesCaseRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct CasesDeletionNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct CasesSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CasesPalette.tertiaryText)

            TextField("Search cases", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    withAnimation(ProofKitMotion.quick) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(CasesPalette.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search"))
            }
        }
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CasesPalette.searchField)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CasesPalette.hairline, lineWidth: 1)
        }
        .casesSoftShadow(radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }
}

private struct CaseListCard: View {
    let caseFile: CaseFile
    let onAddProof: () -> Void
    let onManageCase: () -> Void
    private var readiness: CaseReadinessResult { CaseReadinessCalculator.calculate(for: caseFile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 13) {
                CasesThumbnail(caseFile: caseFile)

                VStack(alignment: .leading, spacing: 5) {
                    Text(caseFile.casesDisplayTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(readiness.category.displayName) · \(readiness.counts.proofItemCount.evidenceItemCountText) · \(caseFile.casesUpdatedText)")
                        .font(.subheadline)
                        .foregroundStyle(CasesPalette.secondaryText)
                        .lineLimit(1)

                    Text(String(localized: "\(readiness.score)% ready · \(readiness.nextStepLabel)"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CasesPalette.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button(action: onAddProof) {
                    Text("+ Add Proof")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CasesPillButtonStyle())

                Button(action: onManageCase) {
                    Text("Manage Case")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CasesPillButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CasesPalette.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CasesPalette.hairline, lineWidth: 1)
        }
        .casesSoftShadow(radius: 18, y: 9)
        .accessibilityElement(children: .combine)
    }
}

private struct CasesThumbnail: View {
    let caseFile: CaseFile

    var body: some View {
        Group {
            if
                let imagePath = caseFile.casesThumbnailPath,
                let image = UIImage(contentsOfFile: imagePath)
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                CasesFallbackThumbnail(caseFile: caseFile)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(CasesPalette.thumbnailStroke, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct CasesFallbackThumbnail: View {
    let caseFile: CaseFile

    var body: some View {
        ZStack {
            LinearGradient(
                colors: caseFile.caseType.casesFallbackColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .padding(8)

            Text(caseFile.casesThumbnailInitials)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .tracking(0.4)
        }
    }
}

private struct CasesEmptyState: View {
    let title: String
    let message: String
    var footnote: String? = nil
    let primaryActionTitle: String
    var mascotImageName: String? = nil
    let primaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ProofKitEmptyCardMetrics.contentSpacing) {
            if let mascotImageName {
                ProofKitEmptyMascotImage(
                    imageName: mascotImageName,
                    shadowColor: CasesPalette.mascotShadow
                )
            }

            VStack(alignment: .leading, spacing: ProofKitEmptyCardMetrics.textSpacing) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(CasesPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: primaryAction) {
                Text(primaryActionTitle)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CasesPrimaryButtonStyle())

            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(CasesPalette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ProofKitEmptyCardMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ProofKitEmptyCardMetrics.cornerRadius, style: .continuous)
                .fill(CasesPalette.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ProofKitEmptyCardMetrics.cornerRadius, style: .continuous)
                .stroke(CasesPalette.hairline, lineWidth: 1)
        }
        .casesSoftShadow(
            radius: ProofKitEmptyCardMetrics.shadowRadius,
            y: ProofKitEmptyCardMetrics.shadowY
        )
    }
}

private struct CasesPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? CasesPalette.controlFillPressed : CasesPalette.controlFill)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

private struct CasesPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(CasesPalette.newCaseForeground)
            .padding(.vertical, 15)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CasesPalette.newCaseBackground.opacity(configuration.isPressed ? 0.86 : 1))
            }
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

private struct CasesIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(ProofKitMotion.quick, value: configuration.isPressed)
    }
}

private enum CasesPalette {
    static let background = dynamicColor(
        light: UIColor(red: 0.972, green: 0.968, blue: 0.958, alpha: 1),
        dark: UIColor(red: 0.047, green: 0.059, blue: 0.078, alpha: 1)
    )
    static let card = dynamicColor(
        light: .systemBackground,
        dark: UIColor(red: 0.082, green: 0.102, blue: 0.133, alpha: 1)
    )
    static let searchField = dynamicColor(
        light: .systemBackground,
        dark: UIColor(red: 0.098, green: 0.122, blue: 0.157, alpha: 1)
    )
    static let secondaryText = dynamicColor(
        light: .secondaryLabel,
        dark: UIColor(red: 0.69, green: 0.74, blue: 0.80, alpha: 1)
    )
    static let tertiaryText = dynamicColor(
        light: .tertiaryLabel,
        dark: UIColor(red: 0.50, green: 0.56, blue: 0.63, alpha: 1)
    )
    static let hairline = dynamicColor(
        light: UIColor(red: 0.22, green: 0.24, blue: 0.27, alpha: 0.13),
        dark: UIColor(white: 1, alpha: 0.10)
    )
    static let controlFill = dynamicColor(
        light: .systemGray6,
        dark: UIColor(red: 0.125, green: 0.157, blue: 0.204, alpha: 1)
    )
    static let controlFillPressed = dynamicColor(
        light: .systemGray4,
        dark: UIColor(red: 0.176, green: 0.220, blue: 0.286, alpha: 1)
    )
    static let newCaseBackground = dynamicColor(
        light: .black,
        dark: UIColor(red: 0.16, green: 0.56, blue: 1.00, alpha: 1)
    )
    static let newCaseForeground = Color.white
    static let thumbnailStroke = dynamicColor(
        light: UIColor(white: 1, alpha: 0.72),
        dark: UIColor(white: 1, alpha: 0.18)
    )
    static let shadow = dynamicColor(
        light: UIColor(white: 0, alpha: 0.052),
        dark: UIColor(white: 0, alpha: 0.32)
    )
    static let mascotShadow = dynamicColor(
        light: UIColor(white: 0, alpha: 0.10),
        dark: UIColor(white: 0, alpha: 0.24)
    )

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(
            UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}

private extension View {
    func casesSoftShadow(radius: CGFloat, y: CGFloat) -> some View {
        shadow(color: CasesPalette.shadow, radius: radius, x: 0, y: y)
    }
}

private extension CaseFile {
    var casesDisplayTitle: String {
        CaseFile.displayTitle(forTrimmedTitle: userTitle.casesTrimmedText)
    }

    var casesUpdatedText: String {
        Calendar.current.isDateInToday(updatedAt)
            ? String(localized: "Updated today")
            : String(localized: "Updated \(ProofKitDateFormatting.shortDate(updatedAt))")
    }

    var casesThumbnailPath: String? {
        if let thumbnailLocalFilePath, !thumbnailLocalFilePath.casesTrimmedText.isEmpty {
            return thumbnailLocalFilePath
        }

        let attachments = evidenceItems
            .sorted { $0.updatedAt > $1.updatedAt }
            .flatMap { $0.sortedAttachments }

        if let thumbnailPath = attachments.compactMap(\.thumbnailLocalFilePath).first {
            return thumbnailPath
        }

        return attachments.first { attachment in
            attachment.attachmentType == .photo || attachment.attachmentType == .screenshot
        }?.localFilePath
    }

    var casesThumbnailInitials: String {
        let trimmedTitle = userTitle.casesTrimmedText
        let source = CaseFile.isUntitledTitle(trimmedTitle) ? caseReadinessCategory.displayName : trimmedTitle
        let words = source
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        let initials = String(words).uppercased()
        return initials.isEmpty ? "PK" : initials
    }

    var casesSearchableText: String {
        let evidenceText = evidenceItems
            .map(\.casesSearchableText)
            .joined(separator: " ")

        return [
            casesDisplayTitle,
            caseReadinessCategory.displayName,
            caseType.displayName,
            status.displayName,
            userSummary,
            userNotes,
            evidenceText
        ]
        .joined(separator: " ")
        .lowercased()
    }
}

private extension EvidenceItem {
    var casesSearchableText: String {
        [
            category.displayName,
            userTitle,
            userNotes,
            userCleanedNote,
            userWhyThisMatters,
            originalOCRText
        ]
        .joined(separator: " ")
        .lowercased()
    }
}

private extension CaseType {
    var casesFallbackColors: [Color] {
        switch self {
        case .apartmentIssue, .tenantLandlord:
            [Color(red: 0.32, green: 0.55, blue: 0.58), Color(red: 0.17, green: 0.28, blue: 0.31)]
        case .refundWarrantyIssue, .consumer:
            [Color(red: 0.27, green: 0.47, blue: 0.78), Color(red: 0.15, green: 0.25, blue: 0.43)]
        case .schoolCollegeIssue:
            [Color(red: 0.38, green: 0.45, blue: 0.72), Color(red: 0.20, green: 0.24, blue: 0.40)]
        case .workplaceIssue, .employment, .unpaidFreelanceWork, .workFreelanceIssue:
            [Color(red: 0.42, green: 0.42, blue: 0.52), Color(red: 0.22, green: 0.22, blue: 0.30)]
        case .insuranceIssue, .insurance:
            [Color(red: 0.25, green: 0.54, blue: 0.48), Color(red: 0.12, green: 0.31, blue: 0.29)]
        case .smallClaims:
            [Color(red: 0.36, green: 0.42, blue: 0.50), Color(red: 0.17, green: 0.22, blue: 0.28)]
        case .family, .immigration:
            [Color(red: 0.47, green: 0.41, blue: 0.56), Color(red: 0.27, green: 0.22, blue: 0.35)]
        case .general, .other:
            [Color(red: 0.39, green: 0.47, blue: 0.56), Color(red: 0.20, green: 0.27, blue: 0.34)]
        }
    }
}

private extension Int {
    var caseCountText: String {
        self == 1 ? String(localized: "1 case") : String(localized: "\(self) cases")
    }
}

private extension String {
    var casesTrimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    CasesPreview()
        .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self, AIResultCache.self], inMemory: true)
}

private struct CasesPreview: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var cases: [CaseFile]

    var body: some View {
        CasesView()
            .onAppear(perform: insertSampleDataIfNeeded)
    }

    private func insertSampleDataIfNeeded() {
        guard cases.isEmpty else { return }

        let ceilingLeakCase = CaseFile(
            caseType: .apartmentIssue,
            status: .active,
            userTitle: "Ceiling Leaking Main Bedroom",
            userSummary: "Water damage records for the main bedroom ceiling.",
            userNotes: "Track photos, requests, dates, and repair documentation for the case.",
            createdAt: Date().addingTimeInterval(-86400 * 9),
            updatedAt: .now
        )
        ceilingLeakCase.evidenceItems = [
            EvidenceItem(
                category: .photo,
                userTitle: "Ceiling leak stain",
                userNotes: "Water staining near the main bedroom light fixture.",
                detectedEventDate: Date().addingTimeInterval(-86400 * 7),
                detectedDateSource: .importedMetadata,
                createdAt: Date().addingTimeInterval(-86400 * 7),
                caseFile: ceilingLeakCase
            ),
            EvidenceItem(
                category: .message,
                userTitle: "Maintenance request sent",
                userNotes: "Initial request submitted after the leak worsened.",
                detectedEventDate: Date().addingTimeInterval(-86400 * 5),
                detectedDateSource: .visionOCR,
                createdAt: Date().addingTimeInterval(-86400 * 5),
                caseFile: ceilingLeakCase
            )
        ]

        let refundCase = CaseFile(
            caseType: .refundWarrantyIssue,
            status: .draft,
            userTitle: "Laptop Warranty Refund",
            createdAt: Date().addingTimeInterval(-86400 * 14),
            updatedAt: Date().addingTimeInterval(-86400 * 1)
        )

        modelContext.insert(ceilingLeakCase)
        modelContext.insert(refundCase)
    }
}
