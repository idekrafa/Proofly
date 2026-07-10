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
    @State private var isShowingAppStatus = false
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

        return cases.isEmpty ? String(localized: "Welcome to Proofly") : String(localized: "Welcome back")
    }

    private var headerSubtitle: String {
        cases.isEmpty ? String(localized: "A calm place for proof, timelines, and packets.") : String(localized: "Your calm proof workspace.")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HomeStatusPillHost(
                        healthMonitor: services.serviceHealth
                    ) {
                        isShowingAppStatus = true
                    }

                    header

                    if cases.isEmpty {
                        EmptyHomeWorkspaceCard {
                            Task { await addCase() }
                        }
                        .transition(ProofKitMotion.cardInsertion)
                        .proofKitAppear(delay: 0.04)
                    } else if let featuredCase {
                        FeaturedCaseCard(
                            caseFile: featuredCase,
                            onAddProof: { caseFile in
                                Task { await showAddProofOptions(for: caseFile) }
                            }
                        )
                            .transition(ProofKitMotion.cardInsertion)
                            .proofKitAppear(delay: 0.04)

                        NextBestStepCard(caseFile: featuredCase)
                            .transition(ProofKitMotion.cardInsertion)
                            .proofKitAppear(delay: 0.08)
                    }

                    if !cases.isEmpty {
                        MyCasesSection(
                            cases: cases,
                            onAddProof: { caseFile in
                                Task { await showAddProofOptions(for: caseFile) }
                            },
                            onNewCase: {
                                Task { await addCase() }
                            }
                        )
                        .proofKitAppear(delay: 0.12)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 132)
            }
            .background(HomePalette.background.ignoresSafeArea())
            .animation(ProofKitMotion.standard, value: cases.map(\.id))
            .toolbar(.hidden, for: .navigationBar)
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
            .sheet(isPresented: $isShowingCreateCaseFlow) {
                CreateCaseFlowView { draft in
                    let caseFile = viewModel.createCase(
                        in: modelContext,
                        title: draft.title,
                        caseType: draft.caseType,
                        summary: draft.summary,
                        notes: draft.notes
                    )
                    services.analytics.trackCaseCreated(caseFile, sourceScreen: .home)
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
            .sheet(isPresented: $isShowingAppStatus) {
                AppStatusView(
                    healthMonitor: services.serviceHealth
                )
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

            Button {
                Task { await addCase() }
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomePalette.primaryActionForeground)
                    .frame(width: 46, height: 46)
                    .background {
                        Circle()
                            .fill(HomePalette.primaryActionBackground)
                    }
            }
            .buttonStyle(HomeIconButtonStyle())
            .accessibilityLabel(String(localized: "New Case"))

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

        services.analytics.trackCaseCreateStarted(sourceScreen: .home)
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
    let onAddProof: (CaseFile) -> Void

    private var readiness: CaseReadinessResult { CaseReadinessCalculator.calculate(for: caseFile) }
    private var progress: Double { readiness.progress }
    private var nextAction: HomeNextAction { HomeNextAction(readiness: readiness) }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 11) {
                    Text("Active proof timeline")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomePalette.accent)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Text(caseFile.homeDisplayTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .kerning(-0.35)
                        .lineLimit(3)
                        .minimumScaleFactor(0.88)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        HomeMetadataPill(text: readiness.category.displayName)
                        HomeMetadataPill(text: String(localized: "\(readiness.score)% ready"))
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                HomeRookOrb(assetName: caseFile.homeRookAssetName, size: 62)
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Readiness")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HomePalette.secondaryText)

                    Spacer(minLength: 12)

                    Text("\(readiness.score)%")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(HomePalette.accent)
                }

                ProgressTrack(progress: progress)
                    .frame(height: 7)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: nextAction.systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HomePalette.accent)
                    .frame(width: 22, height: 22)
                    .background {
                        Circle()
                            .fill(HomePalette.accent.opacity(0.12))
                    }

                Text(nextAction.line)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            primaryCTA
        }
        .homeCard(padding: 20, cornerRadius: 26)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var primaryCTA: some View {
        if nextAction == .addProof {
            Button {
                onAddProof(caseFile)
            } label: {
                HomePrimaryActionLabel(title: nextAction.ctaTitle, systemImage: nextAction.ctaSystemImage)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(nextAction.ctaTitle)
        } else {
            NavigationLink {
                CaseDetailView(caseFile: caseFile)
            } label: {
                HomePrimaryActionLabel(title: nextAction.ctaTitle, systemImage: nextAction.ctaSystemImage)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(nextAction.ctaTitle)
        }
    }
}

private struct NextBestStepCard: View {
    let caseFile: CaseFile

    private var readiness: CaseReadinessResult { CaseReadinessCalculator.calculate(for: caseFile) }
    private var nextAction: HomeNextAction { HomeNextAction(readiness: readiness) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: nextAction.helperSystemImage)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HomePalette.accent)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(HomePalette.accent.opacity(0.10))
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Next best step")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HomePalette.accent)

                Text(nextAction.helperCopy)
                    .font(.subheadline)
                    .foregroundStyle(HomePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
        }
        .homeCard(padding: 14, cornerRadius: 22)
    }
}

private struct HomePrimaryActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.86)
        }
        .foregroundStyle(HomePalette.primaryActionForeground)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(HomePalette.primaryActionBackground)
        }
    }
}

private struct HomeRookOrb: View {
    let assetName: String
    let size: CGFloat

    var body: some View {
        HomeRookImage(assetName: assetName, size: size)
            .padding(6)
            .background {
                Circle()
                    .fill(HomePalette.rookHalo)
            }
            .overlay {
                Circle()
                    .stroke(HomePalette.hairline, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct HomeRookImage: View {
    let assetName: String
    let size: CGFloat

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
        .accessibilityLabel(String(localized: "Case progress"))
        .accessibilityValue(String(localized: "\(Int((progress * 100).rounded())) percent complete"))
        .animation(ProofKitMotion.slowEase, value: progress)
    }
}

private struct MyCasesSection: View {
    let cases: [CaseFile]
    let onAddProof: (CaseFile) -> Void
    let onNewCase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent cases")
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

//                    Button(action: onNewCase) {
//                        Text("+ New case")
//                            .font(.headline.weight(.semibold))
//                            .foregroundStyle(HomePalette.primaryActionForeground)
//                            .frame(maxWidth: .infinity)
//                            .padding(.vertical, 16)
//                            .background {
//                                RoundedRectangle(cornerRadius: 19, style: .continuous)
//                                    .fill(HomePalette.primaryActionBackground)
//                            }
//                    }
//                    .buttonStyle(.plain)
//                    .accessibilityLabel("New case")
//                    .proofKitAppear(delay: 0.06)
                }
            }
        }
    }

    private var noCasesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No proof timelines yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Your recent work will appear here once you create a timeline.")
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
    private var nextAction: HomeNextAction { HomeNextAction(readiness: readiness) }

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

                    Text("\(readiness.score)% ready · \(nextAction.line)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(HomePalette.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button(action: onAddProof) {
                    Text("Add proof")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HomePillButtonStyle())

                NavigationLink {
                    CaseDetailView(caseFile: caseFile)
                } label: {
                    Text("Open timeline")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HomePillButtonStyle())
            }
        }
        .padding(16)
    }
}

private struct EmptyHomeWorkspaceCard: View {
    let onNewCase: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            HomeRookImage(assetName: "RookCasesEmpty", size: 96)
                .frame(maxWidth: .infinity)

            VStack(alignment: .center, spacing: 9) {
                Text("Ready to build your first proof timeline?")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .kerning(-0.2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Start with a situation, then add screenshots, notes, photos, or documents.")
                    .font(.subheadline)
                    .foregroundStyle(HomePalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HomePalette.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Next best step")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HomePalette.accent)

                    Text("Create your first proof timeline.")
                        .font(.footnote)
                        .foregroundStyle(HomePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(HomePalette.controlFill)
            }

            Button(action: onNewCase) {
                HomePrimaryActionLabel(title: String(localized: "Create first case"), systemImage: "plus")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Create first case"))
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

private struct HomeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(ProofKitMotion.quick, value: configuration.isPressed)
    }
}

private enum HomeNextAction: Equatable {
    case addProof
    case reviewInbox
    case checkTimeline
    case exportPacket

    init(readiness: CaseReadinessResult) {
        if !readiness.signals.hasAtLeastOneProofItem {
            self = .addProof
        } else if readiness.counts.unreviewedItemCount > 0 {
            self = .reviewInbox
        } else if !readiness.signals.hasTimelineDate || !readiness.signals.hasTimelineDepthOrStrongItem {
            self = .checkTimeline
        } else {
            self = .exportPacket
        }
    }

    var line: String {
        switch self {
        case .addProof:
            String(localized: "Next: Add proof")
        case .reviewInbox:
            String(localized: "Next: Review inbox")
        case .checkTimeline:
            String(localized: "Next: Check timeline")
        case .exportPacket:
            String(localized: "Next: Export packet")
        }
    }

    var ctaTitle: String {
        switch self {
        case .addProof:
            String(localized: "Add proof")
        case .reviewInbox:
            String(localized: "Review inbox")
        case .checkTimeline:
            String(localized: "View timeline")
        case .exportPacket:
            String(localized: "Export packet")
        }
    }

    var systemImage: String {
        switch self {
        case .addProof:
            "plus.circle.fill"
        case .reviewInbox:
            "tray.full.fill"
        case .checkTimeline:
            "calendar.badge.clock"
        case .exportPacket:
            "doc.text.fill"
        }
    }

    var ctaSystemImage: String {
        switch self {
        case .addProof:
            "plus"
        case .reviewInbox:
            "tray.full"
        case .checkTimeline:
            "calendar"
        case .exportPacket:
            "square.and.arrow.up"
        }
    }

    var helperSystemImage: String {
        switch self {
        case .addProof:
            "sparkles"
        case .reviewInbox:
            "checklist"
        case .checkTimeline:
            "calendar"
        case .exportPacket:
            "checklist"
        }
    }

    var helperCopy: String {
        switch self {
        case .addProof:
            String(localized: "Start with one screenshot, receipt, note, or document.")
        case .reviewInbox:
            String(localized: "Review new proof so it can be added to your timeline.")
        case .checkTimeline:
            String(localized: "Check dates so your timeline tells the story clearly.")
        case .exportPacket:
            String(localized: "Your packet is ready when you are.")
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
    static let rookHalo = dynamicColor(
        light: UIColor(red: 0.91, green: 0.96, blue: 1.00, alpha: 1),
        dark: UIColor(red: 0.105, green: 0.150, blue: 0.198, alpha: 1)
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
        CaseFile.displayTitle(forTrimmedTitle: userTitle.homeTrimmedText)
    }

    var homeUpdatedText: String {
        Calendar.current.isDateInToday(updatedAt)
            ? String(localized: "Updated today")
            : String(localized: "Updated \(ProofKitDateFormatting.shortDate(updatedAt))")
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
        let trimmedTitle = userTitle.homeTrimmedText
        let source = CaseFile.isUntitledTitle(trimmedTitle) ? caseReadinessCategory.displayName : trimmedTitle
        let words = source
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        let initials = String(words).uppercased()
        return initials.isEmpty ? "PK" : initials
    }

    var homeRookAssetName: String {
        switch caseReadinessCategory.analyticsValue {
        case "apartment":
            "RookPurposeRental"
        case "refund":
            "RookPurposeRefund"
        case "school":
            "RookPurposeCollege"
        default:
            "RookPurposeOther"
        }
    }
}

private extension CaseType {
    var homeFallbackColors: [Color] {
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

private extension String {
    var homeTrimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    HomePreview()
        .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self], inMemory: true)
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
