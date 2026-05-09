import SwiftData
import SwiftUI

enum ProofKitSettingsStorageKeys {
    static let appearance = "proofkit.settings.appearance"
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

struct GlobalSettingsView: View {
    private let initialAccountSession: ProofKitAccountSession?
    private let onAccountSessionUpdated: (ProofKitAccountSession) -> Void
    let onSignedOut: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.proofKitServices) private var services

    @Query(sort: \CaseFile.updatedAt, order: .reverse) private var caseFiles: [CaseFile]

    @State private var entitlement = ProofKitEntitlementSnapshot.placeholder()
    @State private var accountSession: ProofKitAccountSession?
    @State private var accountProfile = SettingsEditableAccountProfile.empty
    @State private var aiCreditsText = "Checking…"
    @State private var settingsNotice: SettingsNotice?
    @State private var confirmation: SettingsConfirmation?
    @State private var exportFile: SettingsExportFile?
    @State private var infoSheet: SettingsInfoPresentation?
    @State private var isPreparingExport = false
    @State private var isDeletingLocalData = false
    @State private var showingNameEditor = false
    @State private var showingEmailEditor = false
    @State private var showingPaywall = false
    @State private var didTrackSettingsOpened = false
    @AppStorage(AnalyticsService.optOutStorageKey) private var analyticsOptOut = false

    init(
        accountSession: ProofKitAccountSession? = nil,
        onAccountSessionUpdated: @escaping (ProofKitAccountSession) -> Void = { _ in },
        onSignedOut: @escaping () -> Void = {}
    ) {
        self.initialAccountSession = accountSession
        self.onAccountSessionUpdated = onAccountSessionUpdated
        self.onSignedOut = onSignedOut
        _accountSession = State(initialValue: accountSession)
    }

    private var editableNameValue: String {
        accountProfile.name ?? accountSession?.profileDisplayName ?? ""
    }

    private var editableEmailValue: String {
        accountProfile.email ?? accountSession?.email ?? ""
    }

    private var displayNameText: String {
        let value = editableNameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Add name" : value
    }

    private var displayEmailText: String {
        let value = editableEmailValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Add email" : value
    }

    private var planStatusText: String {
        entitlement.plan == .pro ? "Pro" : "Free"
    }

    private var analyticsEnabledBinding: Binding<Bool> {
        Binding(
            get: { !analyticsOptOut },
            set: { isEnabled in
                analyticsOptOut = !isEnabled
                services.analytics.setOptedOut(!isEnabled)
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                    header

                    accountSection
                    planSection
                    privacySection
                    supportSection
                    aboutSection
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, SettingsLayout.safeBottomPadding)
            }
            .background(ProofKitVisual.screenBackground.ignoresSafeArea())
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                trackSettingsOpenedIfNeeded()
                await loadSettings()
            }
            .onChange(of: initialAccountSession) { _, updatedSession in
                accountSession = updatedSession
                accountProfile = services.account.isConfigured ? .empty : SettingsAccountProfileStore.load(for: updatedSession)
            }
            .sheet(isPresented: $showingNameEditor) {
                SettingsEditNameSheet(initialName: editableNameValue) { newName in
                    saveAccountName(newName)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingEmailEditor) {
                SettingsEditEmailSheet(initialEmail: editableEmailValue) { newEmail in
                    saveAccountEmail(newEmail)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingPaywall, onDismiss: {
                Task { await loadSettings() }
            }) {
                PaywallView {
                    await loadSettings()
                }
            }
            .sheet(item: $infoSheet) { sheet in
                SettingsInfoSheetView(sheet: sheet)
                    .presentationDetents([.medium, .large])
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
                    primaryButton: .destructive(Text(confirmation.confirmTitle)) {
                        perform(confirmation)
                    },
                    secondaryButton: .cancel(Text("Cancel"))
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Settings")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .kerning(-0.8)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text("Manage your account, plan, privacy, and app preferences.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
        .proofKitAppear()
    }

    private var accountSection: some View {
        settingsSection(
            title: "Account",
            copy: "Used for your ProofKit account and exported packets.",
            delay: 0.03
        ) {
            SettingsGroup {
                SettingsValueButtonRow(
                    icon: "person.crop.circle.fill",
                    iconColor: ProofKitVisual.accentSecondary,
                    title: "Name",
                    value: displayNameText,
                    valueColor: editableNameValue.isEmpty ? ProofKitVisual.subduedText : ProofKitVisual.helperText
                ) {
                    showingNameEditor = true
                }

                SettingsDivider()

                SettingsValueButtonRow(
                    icon: "envelope.fill",
                    iconColor: ProofKitVisual.accent,
                    title: "Email",
                    value: displayEmailText,
                    valueColor: editableEmailValue.isEmpty ? ProofKitVisual.subduedText : ProofKitVisual.helperText
                ) {
                    showingEmailEditor = true
                }
            }
        }
    }

    private var planSection: some View {
        settingsSection(
            title: "Plan",
            copy: "AI tools will use credits once they launch. Your core proof timeline stays usable without AI.",
            delay: 0.06
        ) {
            SettingsGroup {
                SettingsValueRow(
                    icon: "crown.fill",
                    iconColor: .yellow,
                    title: "Current plan",
                    value: planStatusText
                )

                SettingsDivider()

                SettingsValueRow(
                    icon: "sparkles",
                    iconColor: ProofKitVisual.accentSecondary,
                    title: "AI credits",
                    value: aiCreditsText
                )

                SettingsDivider()

                SettingsButtonRow(
                    icon: "creditcard.fill",
                    iconColor: ProofKitVisual.accent,
                    title: "Manage subscription",
                    titleColor: ProofKitVisual.accent,
                    showsChevron: true
                ) {
                    showingPaywall = true
                }
            }
        }
    }

    private var privacySection: some View {
        settingsSection(title: "Privacy & data", delay: 0.09) {
            SettingsGroup {
                SettingsButtonRow(
                    icon: "lock.fill",
                    iconColor: ProofKitVisual.accentSecondary,
                    title: "Local-first storage",
                    showsChevron: true
                ) {
                    infoSheet = .localFirst
                }

                SettingsDivider()

                SettingsToggleRow(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: ProofKitVisual.accent,
                    title: "Product analytics",
                    subtitle: "Only privacy-safe funnel events. Never proof content.",
                    isOn: analyticsEnabledBinding
                )

                SettingsDivider()

                SettingsButtonRow(
                    icon: "square.and.arrow.up.fill",
                    iconColor: ProofKitVisual.accent,
                    title: isPreparingExport ? "Preparing export…" : "Export my data",
                    titleColor: ProofKitVisual.accent,
                    isLoading: isPreparingExport
                ) {
                    Task { await prepareDataExport() }
                }
                .disabled(isPreparingExport)

                SettingsDivider()

                SettingsButtonRow(
                    icon: "trash.fill",
                    iconColor: .red,
                    title: isDeletingLocalData ? "Deleting local data…" : "Delete local data",
                    titleColor: .red,
                    isLoading: isDeletingLocalData
                ) {
                    confirmation = .deleteLocalData
                }
                .disabled(isDeletingLocalData)
            }
        }
    }

    private var supportSection: some View {
        settingsSection(title: "Support", delay: 0.12) {
            SettingsGroup {
                SettingsButtonRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    iconColor: ProofKitVisual.accentSecondary,
                    title: "Send feedback",
                    showsChevron: true
                ) {
                    services.analytics.trackFeedbackStarted()
                    openMail(subject: "ProofKit Feedback")
                }

                SettingsDivider()

                SettingsButtonRow(
                    icon: "envelope.badge.fill",
                    iconColor: ProofKitVisual.accent,
                    title: "Contact support",
                    showsChevron: true
                ) {
                    services.analytics.trackSupportOpened()
                    openMail(subject: "ProofKit Support")
                }

                SettingsDivider()

                SettingsButtonRow(
                    icon: "ladybug.fill",
                    iconColor: .orange,
                    title: "Report a bug",
                    showsChevron: true
                ) {
                    services.analytics.trackSupportOpened()
                    openMail(subject: "ProofKit Bug Report")
                }
            }
        }
    }

    private var aboutSection: some View {
        settingsSection(title: "About", delay: 0.15) {
            SettingsGroup {
                SettingsButtonRow(
                    icon: "checkmark.seal.fill",
                    iconColor: ProofKitVisual.accent,
                    title: "About ProofKit",
                    showsChevron: true
                ) {
                    infoSheet = .aboutProofKit
                }

                SettingsDivider()

                SettingsButtonRow(
                    icon: "bird.fill",
                    iconColor: ProofKitVisual.accentSecondary,
                    title: "About Rook",
                    showsChevron: true
                ) {
                    infoSheet = .aboutRook
                }

                SettingsDivider()

                SettingsValueRow(
                    icon: "info.circle.fill",
                    iconColor: ProofKitVisual.helperText,
                    title: "Version",
                    value: SettingsAppVersionText.current
                )
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        copy: String? = nil,
        delay: Double,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.helperText)
                    .textCase(.uppercase)
                    .tracking(0.5)

                if let copy {
                    Text(copy)
                        .font(.footnote)
                        .foregroundStyle(ProofKitVisual.subduedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)

            content()
        }
        .proofKitAppear(delay: delay)
    }

    private func trackSettingsOpenedIfNeeded() {
        guard !didTrackSettingsOpened else { return }
        didTrackSettingsOpened = true
        services.analytics.trackSettingsOpened()
    }

    @MainActor
    private func loadSettings() async {
        entitlement = await services.paywall.currentEntitlement()
        aiCreditsText = await currentAICreditsText(for: entitlement)

        guard services.account.isConfigured else {
            accountSession = nil
            accountProfile = SettingsAccountProfileStore.load(for: nil)
            return
        }

        let authResult = try? await services.account.currentSession(
            onboardingCategory: nil,
            onboardingDisplayName: nil
        )
        accountSession = authResult?.session
        accountProfile = .empty
        if let session = authResult?.session {
            SettingsAccountProfileStore.clear(for: session)
        }
    }

    @MainActor
    private func currentAICreditsText(for entitlement: ProofKitEntitlementSnapshot) async -> String {
        guard services.account.isConfigured else {
            return Self.includedCreditsText(for: entitlement)
        }

        do {
            let balance = try await services.aiCredits.fetchAICreditBalance()
            return "\(balance.availableCredits) available"
        } catch {
            return Self.includedCreditsText(for: entitlement)
        }
    }

    private static func includedCreditsText(for entitlement: ProofKitEntitlementSnapshot) -> String {
        let credits = entitlement.limits.monthlyAICredits
        if credits <= 0 {
            return "Not included"
        }

        return entitlement.limits.aiCreditsRenewMonthly ? "\(credits)/month included" : "\(credits) included"
    }

    @MainActor
    private func saveAccountName(_ name: String) {
        Task { await saveAccountNameToSupabase(name) }
    }

    @MainActor
    private func saveAccountEmail(_ email: String) {
        Task { await requestSupabaseEmailChange(email) }
    }

    @MainActor
    private func saveAccountNameToSupabase(_ name: String) async {
        guard let normalized = Self.normalizedName(name) else {
            settingsNotice = SettingsNotice(
                title: "Name Required",
                message: "Enter a name before saving."
            )
            return
        }

        guard services.account.isConfigured else {
            accountProfile.name = normalized
            SettingsAccountProfileStore.saveName(normalized, for: accountSession)
            settingsNotice = SettingsNotice(
                title: "Saved on This Device",
                message: "Supabase account services are not configured in this build, so the name was saved locally only."
            )
            return
        }

        do {
            let updatedSession = try await services.account.updateProfileDisplayName(normalized)
            accountSession = updatedSession
            accountProfile = .empty
            SettingsAccountProfileStore.clear(for: updatedSession)
            onAccountSessionUpdated(updatedSession)
            settingsNotice = SettingsNotice(
                title: "Name Updated",
                message: "Your ProofKit profile name was updated in Supabase."
            )
        } catch {
            settingsNotice = SettingsNotice(
                title: "Couldn’t Update Name",
                message: Self.message(for: error)
            )
        }
    }

    @MainActor
    private func requestSupabaseEmailChange(_ email: String) async {
        guard let normalized = Self.normalizedEmail(email),
              SettingsEmailValidator.isValid(normalized) else {
            settingsNotice = SettingsNotice(
                title: "Invalid Email",
                message: "Enter a valid email address before saving."
            )
            return
        }

        if normalized == accountSession?.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            settingsNotice = SettingsNotice(
                title: "Email Unchanged",
                message: "That is already the email address for this ProofKit account."
            )
            return
        }

        guard services.account.isConfigured else {
            settingsNotice = SettingsNotice(
                title: "Email Not Updated",
                message: "Supabase account services are not configured in this build, so email changes can’t be requested."
            )
            return
        }

        do {
            try await services.account.requestEmailChange(to: normalized)
            SettingsAccountProfileStore.clearEmail(for: accountSession)
            settingsNotice = SettingsNotice(
                title: "Confirm Your New Email",
                message: "Supabase sent a confirmation email to \(normalized). Your ProofKit account email will update after you confirm it."
            )
        } catch {
            settingsNotice = SettingsNotice(
                title: "Couldn’t Request Email Change",
                message: Self.message(for: error)
            )
        }
    }

    private func perform(_ confirmation: SettingsConfirmation) {
        switch confirmation {
        case .deleteLocalData:
            Task { await deleteLocalData() }
        }
    }

    @MainActor
    private func prepareDataExport() async {
        guard !isPreparingExport else { return }
        isPreparingExport = true
        defer { isPreparingExport = false }

        do {
            let file = try Self.writeDataExport(
                for: caseFiles,
                accountName: editableNameValue,
                accountEmail: editableEmailValue,
                plan: planStatusText,
                aiCreditsText: aiCreditsText
            )
            exportFile = file
        } catch {
            settingsNotice = SettingsNotice(
                title: "Couldn’t Export Data",
                message: Self.message(for: error)
            )
        }
    }

    @MainActor
    private func deleteLocalData() async {
        guard !isDeletingLocalData else { return }
        isDeletingLocalData = true
        defer { isDeletingLocalData = false }

        let snapshot = SettingsLocalDataSnapshot(caseFiles: caseFiles)

        do {
            for caseFile in caseFiles {
                modelContext.delete(caseFile)
            }

            try modelContext.save()
            let removalResult = Self.removeLocalFiles(at: snapshot.fileURLs)
            SettingsAccountProfileStore.clear(for: accountSession)
            accountProfile = .empty
            settingsNotice = Self.localDataDeletionNotice(
                snapshot: snapshot,
                removalResult: removalResult
            )
        } catch {
            modelContext.rollback()
            settingsNotice = SettingsNotice(
                title: "Couldn’t Delete Local Data",
                message: Self.message(for: error)
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

    private static func writeDataExport(
        for caseFiles: [CaseFile],
        accountName: String,
        accountEmail: String,
        plan: String,
        aiCreditsText: String
    ) throws -> SettingsExportFile {
        let snapshot = ProofKitSettingsDataExport(
            exportedAt: .now,
            appVersion: SettingsAppVersionText.current,
            accountName: normalizedName(accountName),
            accountEmail: normalizedEmail(accountEmail),
            plan: plan,
            aiCreditsText: aiCreditsText,
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

    private static func removeLocalFiles(at urls: Set<URL>) -> SettingsFileRemovalResult {
        let fileManager = FileManager.default
        var removedCount = 0
        var failedCount = 0

        for url in urls {
            let path = url.path(percentEncoded: false)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            guard !isDirectory.boolValue else { continue }

            do {
                try fileManager.removeItem(at: url)
                removedCount += 1
            } catch {
                failedCount += 1
            }
        }

        return SettingsFileRemovalResult(removedCount: removedCount, failedCount: failedCount)
    }

    private static func localDataDeletionNotice(
        snapshot: SettingsLocalDataSnapshot,
        removalResult: SettingsFileRemovalResult
    ) -> SettingsNotice {
        if snapshot.caseCount == 0, snapshot.fileURLs.isEmpty {
            return SettingsNotice(
                title: "No Local Data Found",
                message: "ProofKit did not find local cases, proof files, OCR text, or packets to delete on this device."
            )
        }

        var message = "Removed \(snapshot.caseCount) case\(snapshot.caseCount == 1 ? "" : "s") and local proof records from this device."
        if removalResult.removedCount > 0 {
            message += " Removed \(removalResult.removedCount) stored file\(removalResult.removedCount == 1 ? "" : "s")."
        }
        if removalResult.failedCount > 0 {
            message += " \(removalResult.failedCount) file\(removalResult.failedCount == 1 ? "" : "s") could not be removed; try again or contact support."
        }

        return SettingsNotice(
            title: "Local Data Deleted",
            message: message
        )
    }

    private static func normalizedName(_ value: String) -> String? {
        let normalized = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedEmail(_ value: String) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
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
    static let groupCornerRadius: CGFloat = 20
    static let rowHorizontalPadding: CGFloat = 18
    static let rowVerticalPadding: CGFloat = 11
    static let rowSpacing: CGFloat = 12
    static let rowMinHeight: CGFloat = 56
    static let iconWidth: CGFloat = 28
    static let dividerIndent: CGFloat = 32
    static let safeBottomPadding: CGFloat = 132
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

private struct SettingsValueRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: SettingsLayout.rowSpacing) {
            SettingsIcon(systemImage: icon, color: iconColor)

            Text(title)
                .font(.body.weight(.regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
        .minSettingsRowHeight()
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsValueButtonRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    var valueColor: Color = ProofKitVisual.helperText
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsLayout.rowSpacing) {
                SettingsIcon(systemImage: icon, color: iconColor)

                Text(title)
                    .font(.body.weight(.regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(value)
                    .font(.body.weight(.regular))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(0.82)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ProofKitVisual.subduedText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
            .padding(.vertical, SettingsLayout.rowVerticalPadding)
            .minSettingsRowHeight()
        }
        .buttonStyle(ProofKitCardButtonStyle())
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: SettingsLayout.rowSpacing) {
                SettingsIcon(systemImage: icon, color: iconColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.regular))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(ProofKitVisual.accent)
        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
        .minSettingsRowHeight()
        .accessibilityElement(children: .combine)
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

private struct SettingsEditNameSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var attemptedSave = false
    let onSave: (String) -> Void

    init(initialName: String, onSave: @escaping (String) -> Void) {
        _name = State(initialValue: initialName)
        self.onSave = onSave
    }

    private var normalizedName: String {
        name
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !normalizedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("This updates your ProofKit profile name in Supabase and refreshes your home greeting.")
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .font(.body.weight(.semibold))
                    .padding(14)
                    .proofKitFieldBackground(cornerRadius: 16)
                    .onSubmit(save)

                if attemptedSave, !canSave {
                    Text("Enter a name before saving.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                        .transition(ProofKitMotion.compactInsertion)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProofKitVisual.screenBackground.ignoresSafeArea())
            .navigationTitle("Edit name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .animation(ProofKitMotion.standard, value: attemptedSave)
        }
    }

    private func save() {
        attemptedSave = true
        guard canSave else { return }

        onSave(normalizedName)
        dismiss()
    }
}

private struct SettingsEditEmailSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email: String
    @State private var attemptedSave = false
    let onSave: (String) -> Void

    init(initialEmail: String, onSave: @escaping (String) -> Void) {
        _email = State(initialValue: initialEmail)
        self.onSave = onSave
    }

    private var normalizedEmail: String {
        email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var canSave: Bool {
        SettingsEmailValidator.isValid(normalizedEmail)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Supabase will send a confirmation email. Your ProofKit account email changes only after you confirm the new address.")
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .font(.body.weight(.semibold))
                    .padding(14)
                    .proofKitFieldBackground(cornerRadius: 16)
                    .onSubmit(save)

                if attemptedSave, !canSave {
                    Text("Enter a valid email address.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                        .transition(ProofKitMotion.compactInsertion)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProofKitVisual.screenBackground.ignoresSafeArea())
            .navigationTitle("Edit email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .animation(ProofKitMotion.standard, value: attemptedSave)
        }
    }

    private func save() {
        attemptedSave = true
        guard canSave else { return }

        onSave(normalizedEmail)
        dismiss()
    }
}

private enum SettingsEmailValidator {
    static func isValid(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private struct SettingsInfoSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let sheet: SettingsInfoPresentation

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    icon

                    VStack(alignment: .leading, spacing: 10) {
                        Text(sheet.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(sheet.message)
                            .font(.body)
                            .foregroundStyle(ProofKitVisual.helperText)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .proofKitCard(cornerRadius: ProofKitVisual.panelCornerRadius)
                }
                .padding(20)
                .padding(.bottom, 28)
            }
            .background(ProofKitVisual.screenBackground.ignoresSafeArea())
            .navigationTitle(sheet.navigationTitle)
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

    @ViewBuilder
    private var icon: some View {
        if sheet == .aboutRook {
            Image("rook_image")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: 148)
                .frame(maxWidth: .infinity, alignment: .center)
                .shadow(color: ProofKitVisual.accentSecondary.opacity(0.14), radius: 14, x: 0, y: 9)
                .accessibilityLabel("Rook proof keeper")
        } else {
            Image(systemName: sheet.systemImage)
                .font(.system(size: 42, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(sheet.iconColor)
                .frame(width: 64, height: 64)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(ProofKitVisual.quietFill)
                }
                .accessibilityHidden(true)
        }
    }
}

private enum SettingsInfoPresentation: String, Identifiable {
    case localFirst
    case aboutProofKit
    case aboutRook

    var id: String { rawValue }

    var navigationTitle: String {
        switch self {
        case .localFirst:
            "Local-first storage"
        case .aboutProofKit:
            "About ProofKit"
        case .aboutRook:
            "About Rook"
        }
    }

    var title: String { navigationTitle }

    var systemImage: String {
        switch self {
        case .localFirst:
            "lock.fill"
        case .aboutProofKit:
            "checkmark.seal.fill"
        case .aboutRook:
            "bird.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .localFirst, .aboutRook:
            ProofKitVisual.accentSecondary
        case .aboutProofKit:
            ProofKitVisual.accent
        }
    }

    var message: String {
        switch self {
        case .localFirst:
            "ProofKit keeps your cases and proof private on this device unless you choose to export or share them."
        case .aboutProofKit:
            "ProofKit helps you organize screenshots, receipts, notes, and documents into a clear proof timeline. Your core proof records stay local-first on this device unless you choose to export or share them."
        case .aboutRook:
            "Rook is ProofKit’s little proof keeper — a calm guide for turning messy screenshots and receipts into a clear timeline."
        }
    }
}

private struct SettingsEditableAccountProfile: Equatable {
    var name: String?
    var email: String?

    static let empty = SettingsEditableAccountProfile(name: nil, email: nil)
}

private enum SettingsAccountProfileStore {
    static func load(for session: ProofKitAccountSession?) -> SettingsEditableAccountProfile {
        SettingsEditableAccountProfile(
            name: normalizedValue(forKey: key("name", session: session)),
            email: normalizedValue(forKey: key("email", session: session))
        )
    }

    static func saveName(_ name: String?, for session: ProofKitAccountSession?) {
        save(name, forKey: key("name", session: session))
    }

    static func saveEmail(_ email: String?, for session: ProofKitAccountSession?) {
        save(email, forKey: key("email", session: session))
    }

    static func clearEmail(for session: ProofKitAccountSession?) {
        UserDefaults.standard.removeObject(forKey: key("email", session: session))
    }

    static func clear(for session: ProofKitAccountSession?) {
        UserDefaults.standard.removeObject(forKey: key("name", session: session))
        UserDefaults.standard.removeObject(forKey: key("email", session: session))
    }

    private static func normalizedValue(forKey key: String) -> String? {
        guard let value = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func save(_ value: String?, forKey key: String) {
        if let value, !value.isEmpty {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func key(_ field: String, session: ProofKitAccountSession?) -> String {
        let scope = session?.userID.uuidString.lowercased() ?? "local"
        return "proofkit.settings.accountProfile.\(scope).\(field)"
    }
}

private struct SettingsLocalDataSnapshot {
    let caseCount: Int
    let fileURLs: Set<URL>

    @MainActor
    init(caseFiles: [CaseFile]) {
        caseCount = caseFiles.count
        var urls = Set<URL>()

        for caseFile in caseFiles {
            Self.insertFileURL(caseFile.thumbnailLocalFilePath, into: &urls)

            for evidenceItem in caseFile.evidenceItems {
                for attachment in evidenceItem.attachments {
                    Self.insertFileURL(attachment.localFilePath, into: &urls)
                    Self.insertFileURL(attachment.thumbnailLocalFilePath, into: &urls)
                }
            }

            for exportPacket in caseFile.exportPackets {
                Self.insertFileURL(exportPacket.localPDFFilePath, into: &urls)
            }
        }

        fileURLs = urls
    }

    private static func insertFileURL(_ path: String?, into urls: inout Set<URL>) {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return
        }

        urls.insert(URL(fileURLWithPath: path))
    }
}

private struct SettingsFileRemovalResult {
    let removedCount: Int
    let failedCount: Int
}

private enum SettingsAppVersionText {
    static var current: String {
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
    case deleteLocalData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deleteLocalData:
            "Delete local data?"
        }
    }

    var message: String {
        switch self {
        case .deleteLocalData:
            "This removes ProofKit data stored on this device. Export anything important first. This can’t be undone."
        }
    }

    var confirmTitle: String {
        switch self {
        case .deleteLocalData:
            "Delete local data"
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
    let accountName: String?
    let accountEmail: String?
    let plan: String
    let aiCreditsText: String
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
