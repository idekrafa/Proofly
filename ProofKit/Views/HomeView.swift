import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.proofKitServices) private var services
    @Query(sort: \CaseFile.updatedAt, order: .reverse) private var cases: [CaseFile]
    @StateObject private var viewModel = CaseListViewModel()
    @State private var isShowingCreateCaseFlow = false
    @State private var pendingCreatedCase: CaseFile?
    @State private var createdCaseToOpen: CaseFile?
    @State private var isOpeningCreatedCase = false
    @State private var paywallNotice: PaywallAccessDecision?
    @State private var activeAddProofSheet: HomeAddProofSheet?
    private let accountSession: ProofKitAccountSession?
    private let onSettingsTapped: () -> Void

    init(
        accountSession: ProofKitAccountSession? = nil,
        onSettingsTapped: @escaping () -> Void = {}
    ) {
        self.accountSession = accountSession
        self.onSettingsTapped = onSettingsTapped
    }

    private var featuredCase: CaseFile? {
        cases.first { $0.status == .active } ?? cases.first { $0.status != .archived }
    }

    private var headerGreeting: String {
        if let accountSession {
            return accountSession.welcomeBackGreeting
        }

        return cases.isEmpty ? "Welcome to ProofKit" : "Welcome back"
    }

    private var headerSubtitle: String {
        cases.isEmpty ? "Let’s build your first proof case." : "Here’s what you’re working on."
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if cases.isEmpty {
                        CreateFirstCaseCard {
                            Task { await addCase() }
                        }
                        .transition(ProofKitMotion.cardInsertion)
                        .proofKitAppear(delay: 0.04)
                    } else if let featuredCase {
                        FeaturedCaseCard(caseFile: featuredCase)
                            .transition(ProofKitMotion.cardInsertion)
                            .proofKitAppear(delay: 0.04)
                    }

                    MyCasesSection(
                        cases: cases,
                        onAddProof: { caseFile in
                            Task { await showAddProofOptions(for: caseFile) }
                        },
                        onNewCase: {
                            Task { await addCase() }
                        }
                    )
                    .proofKitAppear(delay: 0.10)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .background(HomePalette.background.ignoresSafeArea())
            .animation(ProofKitMotion.standard, value: cases.map(\.id))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $isOpeningCreatedCase) {
                if let createdCaseToOpen {
                    CaseDetailView(caseFile: createdCaseToOpen)
                } else {
                    EmptyStateView(
                        title: "Case created",
                        message: "Your case was created locally.",
                        systemImage: "checkmark.circle"
                    )
                }
            }
            .sheet(isPresented: $isShowingCreateCaseFlow) {
                CreateCaseFlowView { draft in
                    pendingCreatedCase = viewModel.createCase(
                        in: modelContext,
                        title: draft.title,
                        caseType: draft.caseType
                    )
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
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(headerGreeting)
                    .font(.system(size: 28, design: .default))
                    .foregroundStyle(.primary)
                    .kerning(-0.45)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .fixedSize(horizontal: false, vertical: true)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(HomePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

//  This was the Settings redirection button, not being used for now
//            Button(action: onSettingsTapped) {
//                Image(systemName: "person.crop.circle")
//                    .font(.system(size: 21, weight: .semibold))
//                    .symbolRenderingMode(.hierarchical)
//                    .foregroundStyle(.primary)
//                    .frame(width: 46, height: 46)
//                    .background {
//                        Circle()
//                            .fill(HomePalette.card)
//                    }
//                    .overlay {
//                        Circle()
//                            .stroke(HomePalette.hairline, lineWidth: 1)
//                    }
//                    .homeSoftShadow(radius: 12, y: 6)
//            }
//            .buttonStyle(.plain)
//            .accessibilityLabel("Profile and settings")
        }
        .padding(.top, 6)
        .proofKitAppear()
    }

    @MainActor
    private func addCase() async {
        let decision = await services.paywall.canCreateCase(existingCases: cases)
        guard decision.isAllowed else {
            paywallNotice = decision
            return
        }

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
}

private enum HomeAddProofSheet: Identifiable {
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

private struct FeaturedCaseCard: View {
    let caseFile: CaseFile

    private var readiness: CaseReadinessResult { CaseReadinessCalculator.calculate(for: caseFile) }
    private var progress: Double { readiness.progress }
    private var currentStep: HomeCaseStep { HomeCaseStep(readiness: readiness) }
    private var missingItems: [String] { readiness.blockers }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(headline)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .kerning(-0.25)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(caseFile.homeDisplayTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            HomeMetadataPill(text: readiness.category.displayName)
                            HomeMetadataPill(text: caseFile.status.displayName)
                        }
                    }
                }

                Spacer(minLength: 8)

                CaseThumbnail(caseFile: caseFile, width: 82, height: 82, cornerRadius: 20)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(readiness.score)% ready")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 12)

                    Text(readiness.nextStepLabel)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(HomePalette.secondaryText)
                }

                ProgressTrack(progress: progress)
                    .frame(height: 7)

                HStack(spacing: 7) {
                    ForEach(HomeCaseStep.allCases) { step in
                        StepChip(
                            step: step,
                            isCurrent: step == currentStep,
                            isComplete: step.order < currentStep.order || progress >= 1
                        )
                    }
                }
            }

            HStack(alignment: .center, spacing: 12) {
                missingItemsLabel

                Spacer(minLength: 8)

                NavigationLink {
                    CaseDetailView(caseFile: caseFile)
                } label: {
                    HStack(spacing: 6) {
                        Text(readiness.signals.hasExportablePDF ? "Export case" : "Continue case")
                            .font(.footnote.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(HomePalette.primaryActionForeground)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background {
                        Capsule(style: .continuous)
                            .fill(HomePalette.primaryActionBackground)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .homeCard(padding: 20, cornerRadius: 26)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        if readiness.signals.hasGeneratedExport {
            return "Your packet is saved"
        }

        if readiness.signals.hasExportablePDF {
            return "Your case is ready to export"
        }

        if readiness.score >= 75 {
            return "Your case is almost ready"
        }

        if readiness.score >= 25 {
            return "Your case is in progress"
        }

        return "Start building your case"
    }

    @ViewBuilder
    private var missingItemsLabel: some View {
        if readiness.counts.generatedExportCount > 0 {
            Label(
                readiness.counts.generatedExportCount == 1 ? "1 packet saved" : "\(readiness.counts.generatedExportCount) packets saved",
                systemImage: "doc.text.fill"
            )
            .font(.footnote.weight(.medium))
            .foregroundStyle(HomePalette.secondaryText)
            .lineLimit(2)
        } else if missingItems.isEmpty {
            Label(readiness.nextStepLabel, systemImage: readiness.signals.hasExportablePDF ? "checkmark.circle" : "list.bullet.clipboard")
                .font(.footnote.weight(.medium))
                .foregroundStyle(HomePalette.secondaryText)
                .lineLimit(2)
        } else {
            Label("Missing: \(missingItems.joined(separator: ", "))", systemImage: "exclamationmark.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(HomePalette.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ProgressTrack: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clampedProgress = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(HomePalette.progressTrack)

                Capsule(style: .continuous)
                    .fill(HomePalette.accentGradient)
                    .frame(width: width * clampedProgress)
            }
        }
        .accessibilityLabel("Case progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent complete")
        .animation(ProofKitMotion.slowEase, value: progress)
    }
}

private struct StepChip: View {
    let step: HomeCaseStep
    let isCurrent: Bool
    let isComplete: Bool

    var body: some View {
        Text(step.title)
            .font(.caption.weight(isCurrent ? .semibold : .medium))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(isCurrent ? HomePalette.accent.opacity(0.12) : Color.clear)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(isCurrent ? HomePalette.accent.opacity(0.18) : Color.clear, lineWidth: 1)
            }
    }

    private var textColor: Color {
        if isCurrent {
            return HomePalette.accent
        }

        if isComplete {
            return Color(.label)
        }

        return HomePalette.tertiaryText
    }
}

private struct MyCasesSection: View {
    let cases: [CaseFile]
    let onAddProof: (CaseFile) -> Void
    let onNewCase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("My Cases")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .kerning(-0.2)

            if cases.isEmpty {
                noCasesCard
            } else {
                VStack(spacing: 14) {
                    VStack(spacing: 0) {
                        ForEach(Array(cases.enumerated()), id: \.element.id) { index, caseFile in
                            CaseRow(caseFile: caseFile, onAddProof: {
                                onAddProof(caseFile)
                            })
                            .proofKitAppear(delay: min(Double(index) * 0.025, 0.12))

                            if caseFile.id != cases.last?.id {
                                Divider()
                                    .padding(.leading, 82)
                            }
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(HomePalette.card)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(HomePalette.hairline, lineWidth: 1)
                    }
                    .homeSoftShadow(radius: 18, y: 9)

                    Button(action: onNewCase) {
                        Text("+ New Case")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(HomePalette.primaryActionForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background {
                                RoundedRectangle(cornerRadius: 19, style: .continuous)
                                    .fill(HomePalette.primaryActionBackground)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New Case")
                    .proofKitAppear(delay: 0.06)
                }
            }
        }
    }

    private var noCasesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No cases yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Your cases will appear here once you create one.")
                .font(.subheadline)
                .foregroundStyle(HomePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .homeCard(padding: 18, cornerRadius: 24)
    }
}

private struct CaseRow: View {
    let caseFile: CaseFile
    let onAddProof: () -> Void
    private var readiness: CaseReadinessResult { CaseReadinessCalculator.calculate(for: caseFile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 13) {
                CaseThumbnail(caseFile: caseFile, width: 56, height: 56, cornerRadius: 15)

                VStack(alignment: .leading, spacing: 5) {
                    Text(caseFile.homeDisplayTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text("\(readiness.category.displayName) · \(readiness.counts.proofItemCount.evidenceItemCountText) · \(caseFile.homeUpdatedText)")
                        .font(.subheadline)
                        .foregroundStyle(HomePalette.secondaryText)
                        .lineLimit(1)

                    Text("\(readiness.score)% ready · \(readiness.nextStepLabel)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(HomePalette.tertiaryText)
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
                .buttonStyle(HomePillButtonStyle())

                NavigationLink {
                    CaseDetailView(caseFile: caseFile)
                } label: {
                    Text("Manage Case")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HomePillButtonStyle())
            }
        }
        .padding(16)
    }
}

private struct CreateFirstCaseCard: View {
    let onNewCase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create your first case")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .kerning(-0.2)

                Text("Start organizing photos, screenshots, PDFs, and notes into a clean case file.")
                    .font(.subheadline)
                    .foregroundStyle(HomePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onNewCase) {
                Text("+ New Case")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HomeSoftPrimaryButtonStyle())
            .accessibilityLabel("New Case")
        }
        .homeCard(padding: 20, cornerRadius: 26)
    }
}

private struct CaseThumbnail: View {
    let caseFile: CaseFile
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if
                let imagePath = caseFile.homeThumbnailPath,
                let image = UIImage(contentsOfFile: imagePath)
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                CaseTypeFallbackThumbnail(caseFile: caseFile)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(HomePalette.thumbnailStroke, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct CaseTypeFallbackThumbnail: View {
    let caseFile: CaseFile

    var body: some View {
        ZStack {
            LinearGradient(
                colors: caseFile.caseType.homeFallbackColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .padding(8)

            Text(caseFile.homeThumbnailInitials)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .tracking(0.4)
        }
    }
}

private struct HomeMetadataPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(HomePalette.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(HomePalette.controlFill)
            }
    }
}

private struct HomePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? HomePalette.controlFillPressed : HomePalette.controlFill)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

private struct HomeSoftPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(HomePalette.accent)
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(HomePalette.accent.opacity(configuration.isPressed ? 0.16 : 0.10))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(HomePalette.accent.opacity(0.14), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

private enum HomeCaseStep: CaseIterable, Identifiable {
    case `case`
    case proof
    case timeline
    case export

    var id: String { title }

    init(readiness: CaseReadinessResult) {
        if !readiness.signals.hasTitle || !readiness.signals.hasSelectedCategory {
            self = .case
        } else if !readiness.signals.hasAtLeastOneProofItem || !readiness.signals.allProofItemsHandled {
            self = .proof
        } else if !readiness.signals.hasTimelineDate || !readiness.signals.hasTimelineDepthOrStrongItem {
            self = .timeline
        } else {
            self = .export
        }
    }

    var title: String {
        switch self {
        case .case:
            "Case"
        case .proof:
            "Proof"
        case .timeline:
            "Timeline"
        case .export:
            "Export"
        }
    }

    var order: Int {
        switch self {
        case .case:
            0
        case .proof:
            1
        case .timeline:
            2
        case .export:
            3
        }
    }
}

private enum HomePalette {
    static let background = dynamicColor(
        light: UIColor(red: 0.972, green: 0.968, blue: 0.958, alpha: 1),
        dark: UIColor(red: 0.047, green: 0.059, blue: 0.078, alpha: 1)
    )
    static let card = dynamicColor(
        light: .systemBackground,
        dark: UIColor(red: 0.082, green: 0.102, blue: 0.133, alpha: 1)
    )
    static let accent = dynamicColor(
        light: UIColor(red: 0.02, green: 0.47, blue: 0.92, alpha: 1),
        dark: UIColor(red: 0.26, green: 0.65, blue: 1.00, alpha: 1)
    )
    static let accentSecondary = dynamicColor(
        light: UIColor(red: 0.03, green: 0.58, blue: 0.58, alpha: 1),
        dark: UIColor(red: 0.15, green: 0.82, blue: 0.78, alpha: 1)
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
    static let progressTrack = dynamicColor(
        light: .systemGray5,
        dark: UIColor(red: 0.180, green: 0.224, blue: 0.290, alpha: 1)
    )
    static let primaryActionBackground = dynamicColor(
        light: .black,
        dark: UIColor(red: 0.16, green: 0.56, blue: 1.00, alpha: 1)
    )
    static let primaryActionForeground = Color.white
    static let thumbnailStroke = dynamicColor(
        light: UIColor(white: 1, alpha: 0.72),
        dark: UIColor(white: 1, alpha: 0.18)
    )
    static let shadow = dynamicColor(
        light: UIColor(white: 0, alpha: 0.052),
        dark: UIColor(white: 0, alpha: 0.32)
    )

    static let accentGradient = LinearGradient(
        colors: [accent, accentSecondary],
        startPoint: .leading,
        endPoint: .trailing
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
    func homeCard(padding: CGFloat, cornerRadius: CGFloat) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(HomePalette.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(HomePalette.hairline, lineWidth: 1)
            }
            .homeSoftShadow(radius: 20, y: 10)
    }

    func homeSoftShadow(radius: CGFloat, y: CGFloat) -> some View {
        shadow(color: HomePalette.shadow, radius: radius, x: 0, y: y)
    }
}

private extension CaseFile {
    var homeDisplayTitle: String {
        let trimmedTitle = userTitle.homeTrimmedText
        return trimmedTitle.isEmpty ? "Untitled Case" : trimmedTitle
    }

    var homeUpdatedText: String {
        Calendar.current.isDateInToday(updatedAt)
            ? "Updated today"
            : "Updated \(ProofKitDateFormatting.shortDate(updatedAt))"
    }

    var homeThumbnailPath: String? {
        if let thumbnailLocalFilePath, !thumbnailLocalFilePath.homeTrimmedText.isEmpty {
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

    var homeThumbnailInitials: String {
        let source = homeDisplayTitle == "Untitled Case" ? caseReadinessCategory.displayName : homeDisplayTitle
        let words = source
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        let initials = String(words).uppercased()
        return initials.isEmpty ? "PK" : initials
    }

}

private extension CaseType {
    var homeFallbackColors: [Color] {
        switch self {
        case .apartmentIssue, .tenantLandlord:
            [Color(red: 0.32, green: 0.55, blue: 0.58), Color(red: 0.17, green: 0.28, blue: 0.31)]
        case .refundWarrantyIssue, .consumer:
            [Color(red: 0.27, green: 0.47, blue: 0.78), Color(red: 0.15, green: 0.25, blue: 0.43)]
        case .workplaceIssue, .employment, .unpaidFreelanceWork:
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

private extension String {
    var homeTrimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    HomePreview()
        .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self, AIResultCache.self], inMemory: true)
}

private struct HomePreview: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var cases: [CaseFile]

    var body: some View {
        HomeView()
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
            ),
            EvidenceItem(
                category: .receipt,
                userTitle: "Temporary supplies receipt",
                userNotes: "Buckets and plastic sheeting purchased to protect furniture.",
                detectedEventDate: Date().addingTimeInterval(-86400 * 2),
                detectedDateSource: .fileMetadata,
                createdAt: Date().addingTimeInterval(-86400 * 2),
                caseFile: ceilingLeakCase
            )
        ]

        modelContext.insert(ceilingLeakCase)
    }
}
