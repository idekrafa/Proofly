import SwiftData
import SwiftUI

struct ContentView: View {
    let accountSession: ProofKitAccountSession?
    let firstCaseSeed: ProofKitOnboardingFirstCaseSeed?
    let onSignOut: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: ProofKitRootTab = .overview
    @State private var hasHandledFirstCaseSeed = false
    @State private var firstCaseCreationRoute: ProofKitFirstCaseCreationRoute?
    @State private var firstCaseImportRoute: ProofKitFirstCaseImportRoute?
    @State private var firstCaseManualEntryRoute: ProofKitFirstCaseManualEntryRoute?
    @State private var pendingFirstCaseImportRoute: ProofKitFirstCaseImportRoute?
    @State private var pendingFirstCaseManualEntryRoute: ProofKitFirstCaseManualEntryRoute?
    @State private var pendingFirstCaseAhaRoute: ProofKitFirstCaseAhaRoute?
    @State private var firstCaseAhaRoute: ProofKitFirstCaseAhaRoute?
    @State private var firstCaseNotice: ProofKitFirstCaseNotice?
    @AppStorage(ProofKitSettingsStorageKeys.appearance) private var appearanceRawValue = ProofKitAppearancePreference.system.rawValue

    init(
        accountSession: ProofKitAccountSession? = nil,
        firstCaseSeed: ProofKitOnboardingFirstCaseSeed? = nil,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.accountSession = accountSession
        self.firstCaseSeed = firstCaseSeed
        self.onSignOut = onSignOut
    }

    private var preferredColorScheme: ColorScheme? {
        (ProofKitAppearancePreference(rawValue: appearanceRawValue) ?? .system).colorScheme
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(accountSession: accountSession) {
                selectedTab = .settings
            }
                .tabItem {
                    Label("Overview", systemImage: selectedTab == .overview ? "rectangle.grid.3x2.fill" : "rectangle.grid.3x2")
                }
                .tag(ProofKitRootTab.overview)

            CasesView()
            .tabItem {
                Label("Cases", systemImage: selectedTab == .cases ? "folder.fill" : "folder")
            }
            .tag(ProofKitRootTab.cases)

            VaultView()
            .tabItem {
                Label("Vault", systemImage: selectedTab == .vault ? "shippingbox.fill" : "shippingbox")
            }
            .tag(ProofKitRootTab.vault)

            GlobalSettingsView(onSignedOut: onSignOut)
            .tabItem {
                Label("Settings", systemImage: selectedTab == .settings ? "gearshape.fill" : "gearshape")
            }
            .tag(ProofKitRootTab.settings)
        }
        .tint(Color(red: 0.02, green: 0.47, blue: 0.92))
        .preferredColorScheme(preferredColorScheme)
        .animation(ProofKitMotion.standard, value: selectedTab)
        .task(id: firstCaseSeed?.id) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            presentFirstCaseCreationIfNeeded()
        }
        .sheet(item: $firstCaseCreationRoute) { route in
            ProofKitFirstCaseCreationSheet(seed: route.seed) { details in
                createFirstCase(details: details, seed: route.seed)
            }
        }
        .sheet(item: $firstCaseImportRoute, onDismiss: presentPendingFirstCaseAha) { route in
            AddProofImportView(
                caseFile: route.caseFile,
                onManualEntryRequested: {
                    queueFirstCaseManualEntry(ProofKitFirstCaseManualEntryRoute(caseFile: route.caseFile, seed: route.seed))
                },
                onImportComplete: { importedItems in
                    pendingFirstCaseAhaRoute = ProofKitFirstCaseAhaRoute(
                        caseFile: route.caseFile,
                        seed: route.seed,
                        proofCount: importedItems.count
                    )
                    firstCaseImportRoute = nil
                }
            )
        }
        .sheet(item: $firstCaseManualEntryRoute, onDismiss: presentPendingFirstCaseAha) { route in
            ManualEvidenceEntryView(caseFile: route.caseFile) { _ in
                pendingFirstCaseAhaRoute = ProofKitFirstCaseAhaRoute(
                    caseFile: route.caseFile,
                    seed: route.seed,
                    proofCount: 1
                )
                firstCaseManualEntryRoute = nil
            }
        }
        .sheet(item: $firstCaseAhaRoute) { route in
            ProofKitFirstCaseAhaSheet(route: route) {
                firstCaseAhaRoute = nil
                selectedTab = .cases
            }
        }
        .alert(item: $firstCaseNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @MainActor
    private func presentFirstCaseCreationIfNeeded() {
        guard !hasHandledFirstCaseSeed, let firstCaseSeed else { return }

        hasHandledFirstCaseSeed = true
        firstCaseCreationRoute = ProofKitFirstCaseCreationRoute(seed: firstCaseSeed)
        ProofKitPendingOnboardingSeedStore.clear()
    }

    @MainActor
    private func createFirstCase(
        details: ProofKitFirstCaseDetails,
        seed: ProofKitOnboardingFirstCaseSeed
    ) -> Bool {
        let cleanTitle = details.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }

        let now = Date()
        let caseFile = CaseFile(
            caseType: seed.caseType,
            status: .draft,
            userTitle: cleanTitle,
            userSummary: seed.summary,
            userNotes: seed.notesText(details: details.details),
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(caseFile)

        do {
            try modelContext.save()
            selectedTab = .cases
            firstCaseCreationRoute = nil
            queueFirstCaseImport(ProofKitFirstCaseImportRoute(caseFile: caseFile, seed: seed))
            return true
        } catch {
            firstCaseNotice = ProofKitFirstCaseNotice(
                title: "First Case Not Created",
                message: "ProofKit could not create the starter case. Please try again."
            )
            return false
        }
    }

    @MainActor
    private func queueFirstCaseImport(_ route: ProofKitFirstCaseImportRoute) {
        pendingFirstCaseImportRoute = route

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let pendingFirstCaseImportRoute = self.pendingFirstCaseImportRoute else { return }
            self.pendingFirstCaseImportRoute = nil
            self.firstCaseImportRoute = pendingFirstCaseImportRoute
        }
    }

    @MainActor
    private func queueFirstCaseManualEntry(_ route: ProofKitFirstCaseManualEntryRoute) {
        pendingFirstCaseManualEntryRoute = route
        firstCaseImportRoute = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let pendingFirstCaseManualEntryRoute = self.pendingFirstCaseManualEntryRoute else { return }
            self.pendingFirstCaseManualEntryRoute = nil
            self.firstCaseManualEntryRoute = pendingFirstCaseManualEntryRoute
        }
    }

    @MainActor
    private func presentPendingFirstCaseAha() {
        guard let pendingFirstCaseAhaRoute else { return }

        self.pendingFirstCaseAhaRoute = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.firstCaseAhaRoute = pendingFirstCaseAhaRoute
        }
    }
}

private enum ProofKitRootTab: Hashable {
    case overview
    case cases
    case vault
    case settings
}

private struct ProofKitFirstCaseCreationRoute: Identifiable {
    let seed: ProofKitOnboardingFirstCaseSeed

    var id: String { seed.id }
}

private struct ProofKitFirstCaseImportRoute: Identifiable {
    let caseFile: CaseFile
    let seed: ProofKitOnboardingFirstCaseSeed

    var id: String { "import-\(caseFile.id.uuidString)" }
}

private struct ProofKitFirstCaseManualEntryRoute: Identifiable {
    let caseFile: CaseFile
    let seed: ProofKitOnboardingFirstCaseSeed

    var id: String { "manual-\(caseFile.id.uuidString)" }
}

private struct ProofKitFirstCaseAhaRoute: Identifiable {
    let caseFile: CaseFile
    let seed: ProofKitOnboardingFirstCaseSeed
    let proofCount: Int

    var id: String { "aha-\(caseFile.id.uuidString)-\(proofCount)" }
}

private struct ProofKitFirstCaseNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ProofKitFirstCaseDetails {
    let title: String
    let details: String
}

private struct ProofKitFirstCaseCreationSheet: View {
    let seed: ProofKitOnboardingFirstCaseSeed
    let onCreate: (ProofKitFirstCaseDetails) -> Bool

    @State private var title: String
    @State private var details = ""
    @State private var saveErrorMessage: String?
    @FocusState private var focusedField: ProofKitFirstCaseFocusedField?

    init(
        seed: ProofKitOnboardingFirstCaseSeed,
        onCreate: @escaping (ProofKitFirstCaseDetails) -> Bool
    ) {
        self.seed = seed
        self.onCreate = onCreate
        _title = State(initialValue: seed.title)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    intro
                    preselectedCaseCard
                    titleAndDetailsCard
                    suggestedEvidenceCard

                    if let saveErrorMessage {
                        Text(saveErrorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(ProofKitMotion.compactInsertion)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 114)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ProofKitVisual.screenBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .navigationTitle("First Case")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .onAppear {
                focusedField = .title
            }
            .animation(ProofKitMotion.standard, value: saveErrorMessage)
        }
        .presentationDetents([.large])
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background {
                    Circle()
                        .fill(ProofKitVisual.accentGradient)
                }

            VStack(alignment: .leading, spacing: 8) {
                Text("Let’s build your first case")
                    .font(.system(size: 30, weight: .bold))
                    .kerning(-0.6)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("We’ll start with your selected situation. You can change it anytime.")
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .proofKitAppear()
    }

    private var preselectedCaseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preselected case")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ProofKitVisual.helperText)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ProofKitVisual.accent)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(seed.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(seed.caseTypeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ProofKitVisual.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            Capsule(style: .continuous)
                                .fill(ProofKitVisual.accent.opacity(0.12))
                        }

                    Text(seed.summary)
                        .font(.subheadline)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .proofKitFirstCaseCard()
        .proofKitAppear(delay: 0.04)
    }

    private var titleAndDetailsCard: some View {
        VStack(alignment: .leading, spacing: ProofKitVisual.sectionSpacing) {
            VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                Text("Case title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.helperText)

                TextField("Case title", text: $title)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .title)
                    .font(.title3.weight(.semibold))
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(ProofKitVisual.fieldBackground)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
                    }
                    .onSubmit {
                        focusedField = .details
                    }
            }

            VStack(alignment: .leading, spacing: ProofKitVisual.fieldSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What happened?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ProofKitVisual.helperText)

                    Text("Add a few details now, or leave this blank and import proof first.")
                        .font(.footnote)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextEditor(text: $details)
                    .focused($focusedField, equals: .details)
                    .frame(minHeight: 104)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(ProofKitVisual.fieldBackground)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
                    }
            }
        }
        .proofKitFirstCaseCard()
        .proofKitAppear(delay: 0.08)
    }

    private var suggestedEvidenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested evidence")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Next, ProofKit will help you import the proof that fits this case.")
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(seed.suggestedEvidence, id: \.self) { evidence in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ProofKitVisual.accent)
                            .padding(.top, 1)

                        Text(evidence)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .proofKitFirstCaseCard()
        .proofKitAppear(delay: 0.12)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                createCase()
            } label: {
                Text("Create Case")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(trimmedTitle.isEmpty)

            Text("Then we’ll help you add your first proof.")
                .font(.footnote)
                .foregroundStyle(ProofKitVisual.helperText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(.regularMaterial)
    }

    private func createCase() {
        let cleanTitle = trimmedTitle
        guard !cleanTitle.isEmpty else { return }

        let didCreate = onCreate(
            ProofKitFirstCaseDetails(
                title: cleanTitle,
                details: details.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )

        if didCreate {
            focusedField = nil
        } else {
            saveErrorMessage = "Your first case could not be created. Please try again."
        }
    }
}

private enum ProofKitFirstCaseFocusedField: Hashable {
    case title
    case details
}

private struct ProofKitFirstCaseAhaSheet: View {
    let route: ProofKitFirstCaseAhaRoute
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    ProofKitFirstCaseAhaHero()
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 9) {
                        Text(ahaTitle)
                            .font(.system(size: 30, weight: .bold))
                            .kerning(-0.6)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(ahaBody)
                            .font(.subheadline)
                            .foregroundStyle(ProofKitVisual.helperText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ProofKitFirstCaseMetadataRow(
                            systemImage: "folder.fill",
                            label: "Case title",
                            value: route.caseFile.userTitle
                        )
                        ProofKitFirstCaseMetadataRow(
                            systemImage: "tag.fill",
                            label: "Case category",
                            value: route.seed.caseTypeLabel
                        )
                        ProofKitFirstCaseMetadataRow(
                            systemImage: "lock.fill",
                            label: "Proof storage",
                            value: "Local to this device"
                        )
                    }
                    .proofKitFirstCaseCard()
                }
                .padding(20)
                .padding(.bottom, 92)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(ProofKitVisual.screenBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button {
                    onContinue()
                } label: {
                    Text("Continue Case")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .background(.regularMaterial)
            }
            .navigationTitle("Proof Added")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var proofCount: Int {
        max(1, route.proofCount)
    }

    private var ahaTitle: String {
        "\(proofCount) \(proofCount == 1 ? "proof item" : "proof items") added"
    }

    private var ahaBody: String {
        "ProofKit started “\(route.caseFile.userTitle)” and kept your proof local to this device. You can keep adding proof or manage the case anytime."
    }
}

private struct ProofKitFirstCaseAhaHero: View {
    var body: some View {
        Image("RookProofSuccess")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: 184, height: 136)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
            }
            .shadow(color: ProofKitVisual.accentSecondary.opacity(0.16), radius: 18, x: 0, y: 10)
            .accessibilityHidden(true)
    }
}

private struct ProofKitFirstCaseMetadataRow: View {
    let systemImage: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ProofKitVisual.accentSecondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.helperText)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private extension View {
    func proofKitFirstCaseCard() -> some View {
        self
            .padding(ProofKitVisual.compactCardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous)
                    .fill(ProofKitVisual.cardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: ProofKitVisual.cardCornerRadius, style: .continuous)
                    .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
            }
    }
}

private struct RootPlaceholderView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(red: 0.02, green: 0.47, blue: 0.92))
                    .frame(width: 72, height: 72)
                    .background {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.systemBackground))
                    }

                VStack(spacing: 7) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .proofKitAppear()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self, AIResultCache.self], inMemory: true)
}
