import SwiftData
import SwiftUI

enum ProofKitSettingsStorageKeys {
    static let appearance = "proofkit.settings.appearance"
    static let automaticTimeZone = "proofkit.settings.automaticTimeZone"
    static let dictationLanguage = "proofkit.settings.dictationLanguage"
}

enum ProofKitAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum ProofKitDictationLanguagePreference: String, CaseIterable, Identifiable {
    case autoDetect
    case englishUS
    case portugueseBR
    case spanish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .autoDetect:
            "Auto-detect"
        case .englishUS:
            "English (US)"
        case .portugueseBR:
            "Português (BR)"
        case .spanish:
            "Spanish"
        }
    }
}

struct GlobalSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.proofKitServices) private var services

    @Query(sort: \CaseFile.updatedAt, order: .reverse) private var caseFiles: [CaseFile]

    @AppStorage(ProofKitSettingsStorageKeys.appearance) private var appearanceRawValue = ProofKitAppearancePreference.system.rawValue
    @AppStorage(ProofKitSettingsStorageKeys.automaticTimeZone) private var automaticTimeZone = true
    @AppStorage(ProofKitSettingsStorageKeys.dictationLanguage) private var dictationLanguageRawValue = ProofKitDictationLanguagePreference.autoDetect.rawValue

    @State private var entitlement = ProofKitEntitlementSnapshot.placeholder()
    @State private var accountSession: ProofKitAccountSession?
    @State private var settingsNotice: SettingsNotice?
    @State private var confirmation: SettingsConfirmation?
    @State private var exportFile: SettingsExportFile?
    @State private var isPreparingExport = false
    @State private var isSigningOut = false
    @State private var showingPlans = false
    @State private var showingAbout = false

    private var appearancePreference: ProofKitAppearancePreference {
        ProofKitAppearancePreference(rawValue: appearanceRawValue) ?? .system
    }

    private var dictationLanguagePreference: ProofKitDictationLanguagePreference {
        ProofKitDictationLanguagePreference(rawValue: dictationLanguageRawValue) ?? .autoDetect
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                    deviceSettingsSection
                    subscriptionSection
                    singleActionSections
                    dataAndAccountSection
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadAccountAndPlan()
            }
            .sheet(isPresented: $showingPlans) {
                SettingsPlansSheet(entitlement: entitlement)
            }
            .sheet(isPresented: $showingAbout) {
                SettingsAboutSheet()
            }
            .sheet(item: $exportFile) { file in
                SettingsExportReadySheet(exportFile: file)
            }
            .alert(item: $settingsNotice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(item: $confirmation) { confirmation in
                Alert(
                    title: Text(confirmation.title),
                    message: Text(confirmation.message),
                    primaryButton: confirmation.buttonRole == .destructive
                    ? .destructive(Text(confirmation.confirmTitle)) {
                        perform(confirmation)
                    }
                    : .default(Text(confirmation.confirmTitle)) {
                        perform(confirmation)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var deviceSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle("Device Settings")

            SettingsGroup {
                SettingsMenuRow(
                    icon: "circle.lefthalf.filled",
                    iconColor: .indigo,
                    title: "Appearance",
                    value: appearancePreference.displayName
                ) {
                    ForEach(ProofKitAppearancePreference.allCases) { preference in
                        Button {
                            withAnimation(ProofKitMotion.standard) {
                                appearanceRawValue = preference.rawValue
                            }
                        } label: {
                            if preference == appearancePreference {
                                Label(preference.displayName, systemImage: "checkmark")
                            } else {
                                Text(preference.displayName)
                            }
                        }
                    }
                }

                SettingsDivider()

                SettingsToggleRow(
                    icon: "globe",
                    iconColor: .purple,
                    title: "Automatic Time Zone",
                    isOn: $automaticTimeZone
                )

                SettingsDivider()

                SettingsMenuRow(
                    icon: "mic.fill",
                    iconColor: Color(red: 0.0, green: 0.52, blue: 1.0),
                    title: "Dictation Language",
                    value: dictationLanguagePreference.displayName,
                    showsInfo: true
                ) {
                    ForEach(ProofKitDictationLanguagePreference.allCases) { language in
                        Button {
                            dictationLanguageRawValue = language.rawValue
                        } label: {
                            if language == dictationLanguagePreference {
                                Label(language.displayName, systemImage: "checkmark")
                            } else {
                                Text(language.displayName)
                            }
                        }
                    }
                }
            }
        }
        .proofKitAppear()
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle("Subscription")

            SettingsGroup {
                SettingsDetailRow(
                    icon: "crown.fill",
                    iconColor: .yellow,
                    title: "\(entitlement.plan.displayName) Plan Active",
                    subtitle: subscriptionSubtitle,
                    titleColor: .primary
                )

                SettingsDivider()

                SettingsButtonRow(
                    icon: nil,
                    iconColor: Color(red: 0.0, green: 0.52, blue: 1.0),
                    title: "See Plans",
                    titleColor: Color(red: 0.0, green: 0.52, blue: 1.0),
                    showsChevron: true
                ) {
                    showingPlans = true
                }
            }
        }
        .proofKitAppear(delay: 0.03)
    }

    private var singleActionSections: some View {
        VStack(spacing: SettingsLayout.actionGroupSpacing) {
            SettingsGroup {
                SettingsButtonRow(
                    icon: "star.fill",
                    iconColor: Color(red: 0.0, green: 0.52, blue: 1.0),
                    title: "Give Feedback",
                    showsChevron: true
                ) {
                    openMail(subject: "ProofKit Feedback")
                }
            }

            SettingsGroup {
                SettingsButtonRow(
                    icon: "heart.fill",
                    iconColor: .pink,
                    title: "About the App",
                    showsChevron: true
                ) {
                    showingAbout = true
                }
            }
        }
        .proofKitAppear(delay: 0.06)
    }

    private var dataAndAccountSection: some View {
        SettingsGroup {
            SettingsButtonRow(
                icon: "envelope.fill",
                iconColor: Color(red: 0.0, green: 0.52, blue: 1.0),
                title: "Contact Support",
                titleColor: Color(red: 0.0, green: 0.52, blue: 1.0)
            ) {
                openMail(subject: "ProofKit Support")
            }

            SettingsDivider()

            SettingsButtonRow(
                icon: "trash",
                iconColor: .orange,
                title: "Clear Local Cache",
                titleColor: .orange
            ) {
                confirmation = .clearCache
            }

            SettingsDivider()

            SettingsButtonRow(
                icon: "square.and.arrow.up",
                iconColor: Color(red: 0.0, green: 0.52, blue: 1.0),
                title: isPreparingExport ? "Preparing Export…" : "Export Data",
                titleColor: Color(red: 0.0, green: 0.52, blue: 1.0),
                isLoading: isPreparingExport
            ) {
                Task { await prepareDataExport() }
            }
            .disabled(isPreparingExport)

            SettingsDivider()

            SettingsButtonRow(
                icon: "person.crop.circle.badge.xmark",
                iconColor: .red,
                title: "Delete Account",
                titleColor: .red
            ) {
                confirmation = .deleteAccount
            }

            SettingsDivider()

            SettingsButtonRow(
                icon: "rectangle.portrait.and.arrow.right",
                iconColor: .red,
                title: isSigningOut ? "Signing Out…" : "Sign Out",
                titleColor: .red,
                isLoading: isSigningOut
            ) {
                confirmation = .signOut
            }
            .disabled(isSigningOut)
        }
        .proofKitAppear(delay: 0.09)
    }

    private var subscriptionSubtitle: String {
        [
            entitlement.limits.aiCreditLimitText,
            entitlement.limits.exportLimitText,
            entitlement.source == .purchaseEntitlement ? nil : "Purchase data is placeholder-backed"
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    @MainActor
    private func loadAccountAndPlan() async {
        entitlement = await services.paywall.currentEntitlement()

        guard services.account.isConfigured else {
            accountSession = nil
            return
        }

        accountSession = try? await services.account.currentSession()
    }

    private func perform(_ confirmation: SettingsConfirmation) {
        switch confirmation {
        case .clearCache:
            Task { await clearLocalCache() }
        case .deleteAccount:
            showDeleteAccountResult()
        case .signOut:
            Task { await signOut() }
        }
    }

    @MainActor
    private func clearLocalCache() async {
        do {
            let clearedCount = try Self.clearCacheDirectories()
            settingsNotice = SettingsNotice(
                title: "Local Cache Cleared",
                message: clearedCount == 0
                ? "No temporary ProofKit cache files were found. Your saved cases, proof files, OCR text, and PDFs were not changed."
                : "Removed \(clearedCount) temporary ProofKit cache folder\(clearedCount == 1 ? "" : "s"). Your saved cases, proof files, OCR text, and PDFs were not changed."
            )
        } catch {
            settingsNotice = SettingsNotice(
                title: "Couldn’t Clear Cache",
                message: Self.message(for: error)
            )
        }
    }

    @MainActor
    private func prepareDataExport() async {
        guard !isPreparingExport else { return }
        isPreparingExport = true
        defer { isPreparingExport = false }

        do {
            let file = try Self.writeDataExport(for: caseFiles)
            exportFile = file
        } catch {
            settingsNotice = SettingsNotice(
                title: "Couldn’t Export Data",
                message: Self.message(for: error)
            )
        }
    }

    @MainActor
    private func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }

        guard services.account.isConfigured else {
            settingsNotice = SettingsNotice(
                title: "No Account Connected",
                message: "Supabase account services are not configured in this build. Local cases and proof files are still available on this device."
            )
            return
        }

        do {
            try await services.account.signOut()
            accountSession = nil
            settingsNotice = SettingsNotice(
                title: "Signed Out",
                message: "This device has been signed out. Local cases and proof files remain on this device."
            )
        } catch {
            settingsNotice = SettingsNotice(
                title: "Couldn’t Sign Out",
                message: Self.message(for: error)
            )
        }
    }

    private func showDeleteAccountResult() {
        if services.account.isConfigured, accountSession != nil {
            settingsNotice = SettingsNotice(
                title: "Account Deletion Not Yet Connected",
                message: "ProofKit can sign out on this device, but permanent account deletion still needs a backend endpoint. Contact support and we’ll help remove the account record."
            )
        } else {
            settingsNotice = SettingsNotice(
                title: "No Account to Delete",
                message: "There is no signed-in account on this device. This did not delete local cases, proof files, OCR text, or PDFs."
            )
        }
    }

    private func openMail(subject: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@proofkit.app"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject)
        ]

        if let url = components.url {
            openURL(url)
        }
    }

    private static func clearCacheDirectories() throws -> Int {
        let fileManager = FileManager.default
        let candidates = [
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "ProofKit"),
            URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "ProofKit"),
            URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "ProofKitSettingsExports")
        ].compactMap { $0 }

        var clearedCount = 0
        for url in candidates where fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.removeItem(at: url)
            clearedCount += 1
        }

        return clearedCount
    }

    @MainActor
    private static func writeDataExport(for caseFiles: [CaseFile]) throws -> SettingsExportFile {
        let snapshot = ProofKitSettingsDataExport(
            exportedAt: .now,
            appVersion: SettingsAboutSheet.appVersionText,
            caseCount: caseFiles.count,
            cases: caseFiles.map(ProofKitSettingsCaseExport.init(caseFile:))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(snapshot)
        let exportDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ProofKitSettingsExports")
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )

        let timestamp = Self.exportFilenameDateFormatter.string(from: .now)
        let url = exportDirectory.appending(path: "proofkit-data-\(timestamp).json")
        try data.write(to: url, options: [.atomic])

        return SettingsExportFile(url: url, caseCount: caseFiles.count)
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }

    private static let exportFilenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private enum SettingsLayout {
    static let sectionSpacing: CGFloat = 20
    static let actionGroupSpacing: CGFloat = 14
    static let groupCornerRadius: CGFloat = 20
    static let rowHorizontalPadding: CGFloat = 18
    static let rowVerticalPadding: CGFloat = 11
    static let rowSpacing: CGFloat = 12
    static let rowMinHeight: CGFloat = 56
    static let iconWidth: CGFloat = 28
    static let dividerIndent: CGFloat = 32
    static let sectionTitleHorizontalPadding: CGFloat = 30
}

private struct SettingsSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ProofKitVisual.helperText)
            .padding(.horizontal, SettingsLayout.sectionTitleHorizontalPadding)
    }
}

private struct SettingsGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background {
            RoundedRectangle(cornerRadius: SettingsLayout.groupCornerRadius, style: .continuous)
                .fill(ProofKitVisual.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: SettingsLayout.groupCornerRadius, style: .continuous)
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: SettingsLayout.groupCornerRadius, style: .continuous))
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .background(ProofKitVisual.divider)
            .padding(.leading, SettingsLayout.dividerIndent)
    }
}

private struct SettingsIcon: View {
    let systemImage: String?
    let color: Color

    var body: some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: SettingsLayout.iconWidth, alignment: .center)
                    .accessibilityHidden(true)
            } else {
                Color.clear
                    .frame(width: SettingsLayout.iconWidth)
            }
        }
    }
}

private struct SettingsDetailRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    var titleColor: Color = .primary

    var body: some View {
        HStack(alignment: .center, spacing: SettingsLayout.rowSpacing) {
            SettingsIcon(systemImage: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(2)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
        .minSettingsRowHeight()
    }
}

private struct SettingsMenuRow<MenuContent: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    var showsInfo = false
    let menuContent: MenuContent

    init(
        icon: String,
        iconColor: Color,
        title: String,
        value: String,
        showsInfo: Bool = false,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.value = value
        self.showsInfo = showsInfo
        self.menuContent = menuContent()
    }

    var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: SettingsLayout.rowSpacing) {
                SettingsIcon(systemImage: icon, color: iconColor)

                Text(title)
                    .font(.body.weight(.regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if showsInfo {
                    Image(systemName: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ProofKitVisual.helperText)
                }

                Spacer(minLength: 12)

                Text(value)
                    .font(.body.weight(.regular))
                    .foregroundStyle(ProofKitVisual.helperText)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.helperText)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
            .padding(.vertical, SettingsLayout.rowVerticalPadding)
            .minSettingsRowHeight()
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn.animation(ProofKitMotion.standard)) {
            HStack(spacing: SettingsLayout.rowSpacing) {
                SettingsIcon(systemImage: icon, color: iconColor)

                Text(title)
                    .font(.body.weight(.regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.switch)
        .tint(.green)
        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
        .padding(.vertical, 10)
        .minSettingsRowHeight()
    }
}

private struct SettingsButtonRow: View {
    let icon: String?
    let iconColor: Color
    let title: String
    var titleColor: Color = .primary
    var showsChevron = false
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsLayout.rowSpacing) {
                SettingsIcon(systemImage: icon, color: iconColor)

                Text(title)
                    .font(.body.weight(.regular))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)

                Spacer(minLength: 12)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ProofKitVisual.subduedText)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
            .padding(.vertical, SettingsLayout.rowVerticalPadding)
            .minSettingsRowHeight()
        }
        .buttonStyle(ProofKitCardButtonStyle())
    }
}

private extension View {
    func minSettingsRowHeight() -> some View {
        frame(minHeight: SettingsLayout.rowMinHeight, alignment: .center)
    }
}

private struct SettingsPlansSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entitlement: ProofKitEntitlementSnapshot

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Plan")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)

                        Text("\(entitlement.plan.displayName) is active. Plan records are placeholder-backed until StoreKit or RevenueCat purchase records are connected.")
                            .font(.subheadline)
                            .foregroundStyle(ProofKitVisual.helperText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .proofKitCard()

                    PaywallPlanCard()
                    AICreditStatusCard()
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct SettingsAboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(red: 0.0, green: 0.52, blue: 1.0))

                VStack(alignment: .leading, spacing: 8) {
                    Text("ProofKit")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.primary)

                    Text("A local-first place to organize proof, review OCR text, build a timeline, and create case PDFs from your own records.")
                        .font(.subheadline)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    AboutInfoRow(title: "Version", value: Self.appVersionText)
                    Divider().padding(.leading, 14)
                    AboutInfoRow(title: "Storage", value: "Local evidence files stay on this device")
                    Divider().padding(.leading, 14)
                    AboutInfoRow(title: "AI", value: "Text-only, user-triggered actions")
                }
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(ProofKitVisual.cardBackground)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    static var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return "Build \(build)"
        default:
            return "Development"
        }
    }
}

private struct AboutInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(ProofKitVisual.helperText)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
    }
}

private struct SettingsExportReadySheet: View {
    @Environment(\.dismiss) private var dismiss
    let exportFile: SettingsExportFile

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "doc.badge.arrow.up")
                    .font(.system(size: 42, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(red: 0.0, green: 0.52, blue: 1.0))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Data Export Ready")
                        .font(.title2.weight(.bold))

                    Text("Your JSON export includes case, evidence, attachment metadata, OCR text, notes, and export history for \(exportFile.caseCount) case\(exportFile.caseCount == 1 ? "" : "s"). It does not include raw image, PDF, or attachment bytes.")
                        .font(.subheadline)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ShareLink(item: exportFile.url) {
                    Label("Share Export", systemImage: "square.and.arrow.up")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum SettingsConfirmation: String, Identifiable {
    case clearCache
    case deleteAccount
    case signOut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clearCache:
            "Clear Local Cache?"
        case .deleteAccount:
            "Delete Account?"
        case .signOut:
            "Sign Out?"
        }
    }

    var message: String {
        switch self {
        case .clearCache:
            "This removes temporary ProofKit cache folders only. It does not delete cases, proof files, OCR text, notes, or exported PDFs."
        case .deleteAccount:
            "ProofKit will check account state. Local cases and proof files will not be deleted by this action."
        case .signOut:
            "This signs out the connected account on this device. Local cases and proof files remain on this device."
        }
    }

    var confirmTitle: String {
        switch self {
        case .clearCache:
            "Clear Cache"
        case .deleteAccount:
            "Continue"
        case .signOut:
            "Sign Out"
        }
    }

    var buttonRole: ButtonRole? {
        switch self {
        case .clearCache:
            nil
        case .deleteAccount, .signOut:
            .destructive
        }
    }
}

private struct SettingsExportFile: Identifiable {
    let id = UUID()
    let url: URL
    let caseCount: Int
}

private struct ProofKitSettingsDataExport: Encodable {
    let exportedAt: Date
    let appVersion: String
    let caseCount: Int
    let cases: [ProofKitSettingsCaseExport]
}

private struct ProofKitSettingsCaseExport: Encodable {
    let id: UUID
    let caseType: String
    let status: String
    let title: String
    let summary: String
    let notes: String
    let createdAt: Date
    let updatedAt: Date
    let archivedAt: Date?
    let evidenceCount: Int
    let exportCount: Int
    let evidenceItems: [ProofKitSettingsEvidenceExport]
    let exports: [ProofKitSettingsPDFExport]

    @MainActor
    init(caseFile: CaseFile) {
        id = caseFile.id
        caseType = caseFile.caseType.displayName
        status = caseFile.status.displayName
        title = caseFile.userTitle
        summary = caseFile.userSummary
        notes = caseFile.userNotes
        createdAt = caseFile.createdAt
        updatedAt = caseFile.updatedAt
        archivedAt = caseFile.archivedAt
        evidenceCount = caseFile.evidenceItems.count
        exportCount = caseFile.exportPackets.count
        evidenceItems = caseFile.sortedEvidenceItems.map(ProofKitSettingsEvidenceExport.init(evidenceItem:))
        exports = caseFile.sortedExportPackets.map(ProofKitSettingsPDFExport.init(exportPacket:))
    }
}

private struct ProofKitSettingsEvidenceExport: Encodable {
    let id: UUID
    let title: String
    let category: String
    let userNotes: String
    let userCleanedNote: String
    let whyThisMatters: String
    let userProvidedEventDate: Date?
    let detectedEventDate: Date?
    let eventDate: Date?
    let eventDateSource: String
    let isImportant: Bool
    let isReviewed: Bool
    let reviewedAt: Date?
    let originalOCRText: String
    let originalOCRConfidence: Double?
    let originalOCRCompletedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let attachments: [ProofKitSettingsAttachmentExport]

    @MainActor
    init(evidenceItem: EvidenceItem) {
        id = evidenceItem.id
        title = evidenceItem.userTitle
        category = evidenceItem.category.displayName
        userNotes = evidenceItem.userNotes
        userCleanedNote = evidenceItem.userCleanedNote
        whyThisMatters = evidenceItem.userWhyThisMatters
        userProvidedEventDate = evidenceItem.userProvidedEventDate
        detectedEventDate = evidenceItem.detectedEventDate
        eventDate = evidenceItem.eventDate
        eventDateSource = evidenceItem.eventDateSource.displayName
        isImportant = evidenceItem.userMarkedImportant
        isReviewed = evidenceItem.isReviewed
        reviewedAt = evidenceItem.reviewedAt
        originalOCRText = evidenceItem.originalOCRText
        originalOCRConfidence = evidenceItem.originalOCRConfidence
        originalOCRCompletedAt = evidenceItem.originalOCRCompletedAt
        createdAt = evidenceItem.createdAt
        updatedAt = evidenceItem.updatedAt
        attachments = evidenceItem.sortedAttachments.map(ProofKitSettingsAttachmentExport.init(attachment:))
    }
}

private struct ProofKitSettingsAttachmentExport: Encodable {
    let id: UUID
    let type: String
    let originalFilename: String
    let uniformTypeIdentifier: String?
    let fileSizeBytes: Int64?
    let contentHash: String?
    let fileCreatedAt: Date?
    let fileModifiedAt: Date?
    let originalOCRText: String
    let originalOCRConfidence: Double?
    let originalOCRCompletedAt: Date?
    let importedMetadataJSON: String
    let createdAt: Date
    let updatedAt: Date

    @MainActor
    init(attachment: Attachment) {
        id = attachment.id
        type = attachment.attachmentType.displayName
        originalFilename = attachment.originalFilename
        uniformTypeIdentifier = attachment.uniformTypeIdentifier
        fileSizeBytes = attachment.fileSizeBytes
        contentHash = attachment.contentHash
        fileCreatedAt = attachment.fileCreatedAt
        fileModifiedAt = attachment.fileModifiedAt
        originalOCRText = attachment.originalOCRText
        originalOCRConfidence = attachment.originalOCRConfidence
        originalOCRCompletedAt = attachment.originalOCRCompletedAt
        importedMetadataJSON = attachment.importedMetadataJSON
        createdAt = attachment.createdAt
        updatedAt = attachment.updatedAt
    }
}

private struct ProofKitSettingsPDFExport: Encodable {
    let id: UUID
    let title: String
    let notes: String
    let fileSizeBytes: Int64?
    let pageCount: Int?
    let includedEvidenceItemIDsJSON: String
    let exportOptionsJSON: String
    let createdAt: Date
    let exportedAt: Date?

    @MainActor
    init(exportPacket: ExportPacket) {
        id = exportPacket.id
        title = exportPacket.userPacketTitle.replacingOccurrences(of: "Packet", with: "Case")
        notes = exportPacket.userPacketNotes
        fileSizeBytes = exportPacket.fileSizeBytes
        pageCount = exportPacket.pageCount
        includedEvidenceItemIDsJSON = exportPacket.includedEvidenceItemIDsJSON
        exportOptionsJSON = exportPacket.exportOptionsJSON
        createdAt = exportPacket.createdAt
        exportedAt = exportPacket.exportedAt
    }
}

#Preview {
    GlobalSettingsView()
        .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self, AIResultCache.self], inMemory: true)
}
