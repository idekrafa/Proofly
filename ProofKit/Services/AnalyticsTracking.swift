import CryptoKit
import Foundation

#if canImport(PostHog)
import PostHog
#endif

protocol AnalyticsTracking {
    var currentUserIDHash: String { get }

    func configure()
    func scoped(to session: ProofKitAccountSession) -> any AnalyticsTracking
    func setOptedOut(_ optedOut: Bool)

    func trackAppOpened()
    func trackSettingsOpened()
    func trackSupportOpened()
    func trackFeedbackStarted()

    func trackOnboardingStarted()
    func trackOnboardingCategorySelected(_ category: CaseCategory)
    func trackOnboardingCompleted(category: CaseCategory?)

    func trackCaseCreateStarted(sourceScreen: AnalyticsScreen)
    func trackCaseCreated(_ caseFile: CaseFile, sourceScreen: AnalyticsScreen)
    func trackCaseOpened(_ caseFile: CaseFile, sourceScreen: AnalyticsScreen)
    func trackCaseManageOpened(_ caseFile: CaseFile)
    func trackCaseDeleted(_ caseFile: CaseFile)

    func trackProofAddStarted(caseFile: CaseFile, proofType: AnalyticsProofType?, sourceScreen: AnalyticsScreen)
    func trackProofAdded(_ evidenceItem: EvidenceItem, caseFile: CaseFile)
    func trackProofImportFailed(proofType: AnalyticsProofType?, errorType: AnalyticsErrorType)
    func trackOCRReviewOpened(caseFile: CaseFile)
    func trackProofReviewed(_ evidenceItem: EvidenceItem)
    func trackProofSkipped(_ evidenceItem: EvidenceItem)
    func trackProofAddedToTimeline(_ evidenceItem: EvidenceItem)

    func trackTimelineOpened(caseFile: CaseFile)
    func trackTimelineItemCreated(_ evidenceItem: EvidenceItem)
    func trackTimelineItemEdited(_ evidenceItem: EvidenceItem)
    func trackTimelineReadyStateChanged(caseFile: CaseFile, readiness: CaseReadinessResult)

    func trackPDFExportStarted(caseFile: CaseFile)
    func trackPDFExportCompleted(caseFile: CaseFile, durationMS: Int)
    func trackPDFExportFailed(caseFile: CaseFile, durationMS: Int, errorType: AnalyticsErrorType)

    func trackPaywallViewed(sourceScreen: AnalyticsScreen)
    func trackPaywallDismissed(sourceScreen: AnalyticsScreen)
    func trackSubscriptionStarted(sourceScreen: AnalyticsScreen)
    func trackSubscriptionCompleted(sourceScreen: AnalyticsScreen)
    func trackSubscriptionFailed(sourceScreen: AnalyticsScreen, errorType: AnalyticsErrorType)

    func trackAIActionStarted(actionType: AnalyticsAIActionType)
    func trackAIActionCompleted(actionType: AnalyticsAIActionType, creditsSpent: Int?, creditsRemaining: Int?, durationMS: Int)
    func trackAIActionFailed(actionType: AnalyticsAIActionType, durationMS: Int, errorType: AnalyticsErrorType)
    func trackAICreditsSpent(actionType: AnalyticsAIActionType, creditsSpent: Int, creditsRemaining: Int?)
}

struct PostHogAnalyticsConfiguration: Equatable {
    static let projectTokenInfoPlistKey = "PROOFKIT_POSTHOG_PROJECT_TOKEN"
    static let hostInfoPlistKey = "PROOFKIT_POSTHOG_HOST"

    let projectToken: String
    let host: String

    var isConfigured: Bool {
        !projectToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PostHogAnalyticsConfiguration? {
        guard let projectToken = firstNonEmptyString(
            keys: [
                projectTokenInfoPlistKey,
                "POSTHOG_PROJECT_TOKEN",
                "POSTHOG_API_KEY"
            ],
            bundle: bundle,
            environment: environment
        ) else {
            return nil
        }

        let host = firstValidHostString(
            keys: [
                hostInfoPlistKey,
                "POSTHOG_HOST",
                "POSTHOG_API_HOST"
            ],
            bundle: bundle,
            environment: environment
        ) ?? "https://us.i.posthog.com"

        return PostHogAnalyticsConfiguration(projectToken: projectToken, host: host)
    }

    private static func firstValidHostString(
        keys: [String],
        bundle: Bundle,
        environment: [String: String]
    ) -> String? {
        firstNonEmptyString(keys: keys, bundle: bundle, environment: environment).flatMap { value in
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false else {
                return nil
            }
            return value
        }
    }

    private static func firstNonEmptyString(
        keys: [String],
        bundle: Bundle,
        environment: [String: String]
    ) -> String? {
        for key in keys {
            if let value = environment[key]?.proofKitAnalyticsConfigurationValue {
                return value
            }

            if let value = bundle.object(forInfoDictionaryKey: key) as? String,
               let cleaned = value.proofKitAnalyticsConfigurationValue {
                return cleaned
            }
        }

        return nil
    }
}

final class AnalyticsService: AnalyticsTracking {
    static let optOutStorageKey = "proofkit.analytics.optOut"

    private static var didConfigurePostHog = false
    private static var didLogMissingConfiguration = false
    private static let configurationLock = NSLock()

    private let configuration: PostHogAnalyticsConfiguration?
    private let userID: UUID?
    private let userDefaults: UserDefaults

    static func live() -> AnalyticsService {
        AnalyticsService(configuration: .load())
    }

    init(
        configuration: PostHogAnalyticsConfiguration?,
        userID: UUID? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        self.userID = userID
        self.userDefaults = userDefaults
    }

    var currentUserIDHash: String {
        AnalyticsHashing.sha256(userID?.uuidString ?? "anonymous")
    }

    func configure() {
        guard configuration?.isConfigured == true else {
            logMissingConfigurationOnce()
            return
        }

        #if canImport(PostHog)
        Self.configurationLock.lock()
        defer { Self.configurationLock.unlock() }

        guard !Self.didConfigurePostHog, let configuration else { return }

        let config = PostHogConfig(projectToken: configuration.projectToken, host: configuration.host)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.enableSwizzling = false
        config.sendFeatureFlagEvent = false
        config.preloadFeatureFlags = false
        config.setDefaultPersonProperties = false
        config.optOut = isOptedOut
        #if DEBUG
        // Product funnel events are sparse, and PostHog's default threshold waits
        // for a larger batch. In debug builds, flush the first event immediately so
        // integration validation does not sit on "waiting for events".
        config.flushAt = 1
        config.flushIntervalSeconds = 5
        #endif

        #if os(iOS) || targetEnvironment(macCatalyst)
        config.captureElementInteractions = false
        config.rageClickConfig.enabled = false
        #endif

        #if os(iOS)
        config.sessionReplay = false
        #endif

        if #available(iOS 15.0, *) {
            config.surveys = false
        }

        config.setBeforeSend { event in
            AnalyticsService.filteredPostHogEvent(event)
        }

        PostHogSDK.shared.setup(config)
        Self.didConfigurePostHog = true
        applyIdentityIfAvailable()
        #endif
    }

    func scoped(to session: ProofKitAccountSession) -> any AnalyticsTracking {
        let service = AnalyticsService(
            configuration: configuration,
            userID: session.userID,
            userDefaults: userDefaults
        )
        service.configure()
        service.applyIdentityIfAvailable()
        return service
    }

    func setOptedOut(_ optedOut: Bool) {
        userDefaults.set(optedOut, forKey: Self.optOutStorageKey)
        userDefaults.synchronize()

        #if canImport(PostHog)
        guard Self.didConfigurePostHog else { return }
        if optedOut {
            PostHogSDK.shared.optOut()
        } else {
            PostHogSDK.shared.optIn()
            applyIdentityIfAvailable()
        }
        #endif
    }

    func trackAppOpened() {
        capture(.appOpened)
    }

    func trackSettingsOpened() {
        capture(.settingsOpened, screenProperties(source: .settings))
    }

    func trackSupportOpened() {
        capture(.supportOpened, screenProperties(source: .settings, destination: .support))
    }

    func trackFeedbackStarted() {
        capture(.feedbackStarted, screenProperties(source: .settings, destination: .feedback))
    }

    func trackOnboardingStarted() {
        capture(.onboardingStarted, screenProperties(source: .welcome, destination: .onboarding))
    }

    func trackOnboardingCategorySelected(_ category: CaseCategory) {
        capture(
            .onboardingCategorySelected,
            AnalyticsProperties(caseCategory: AnalyticsCaseCategory(category))
        )
    }

    func trackOnboardingCompleted(category: CaseCategory?) {
        capture(
            .onboardingCompleted,
            AnalyticsProperties(caseCategory: category.map(AnalyticsCaseCategory.init))
        )
    }

    func trackCaseCreateStarted(sourceScreen: AnalyticsScreen) {
        capture(.caseCreateStarted, screenProperties(source: sourceScreen, destination: .caseCreate))
    }

    func trackCaseCreated(_ caseFile: CaseFile, sourceScreen: AnalyticsScreen) {
        capture(.caseCreated, caseProperties(caseFile, source: sourceScreen, destination: .caseDetail))
    }

    func trackCaseOpened(_ caseFile: CaseFile, sourceScreen: AnalyticsScreen) {
        capture(.caseOpened, caseProperties(caseFile, source: sourceScreen, destination: .caseDetail))
    }

    func trackCaseManageOpened(_ caseFile: CaseFile) {
        capture(.caseManageOpened, caseProperties(caseFile, source: .caseDetail, destination: .caseManage))
    }

    func trackCaseDeleted(_ caseFile: CaseFile) {
        capture(.caseDeleted, caseProperties(caseFile, source: .caseManage))
    }

    func trackProofAddStarted(caseFile: CaseFile, proofType: AnalyticsProofType?, sourceScreen: AnalyticsScreen) {
        var properties = caseProperties(caseFile, source: sourceScreen, destination: .addProof)
        properties.proofType = proofType
        capture(.proofAddStarted, properties)
    }

    func trackProofAdded(_ evidenceItem: EvidenceItem, caseFile: CaseFile) {
        var properties = caseProperties(caseFile, source: .addProof, destination: .proofReview)
        properties.proofType = AnalyticsProofType(evidenceItem)
        properties.proofCountBucket = AnalyticsCountBucket(count: caseFile.evidenceItems.count)
        capture(.proofAdded, properties)
    }

    func trackProofImportFailed(proofType: AnalyticsProofType?, errorType: AnalyticsErrorType = .importFailed) {
        capture(.proofImportFailed, AnalyticsProperties(proofType: proofType, errorType: errorType))
    }

    func trackOCRReviewOpened(caseFile: CaseFile) {
        capture(.ocrReviewOpened, caseProperties(caseFile, source: .caseInbox, destination: .proofReview))
    }

    func trackProofReviewed(_ evidenceItem: EvidenceItem) {
        capture(.proofReviewed, proofProperties(evidenceItem, source: .caseInbox, destination: .caseTimeline))
    }

    func trackProofSkipped(_ evidenceItem: EvidenceItem) {
        capture(.proofSkipped, proofProperties(evidenceItem, source: .caseInbox))
    }

    func trackProofAddedToTimeline(_ evidenceItem: EvidenceItem) {
        capture(.proofAddedToTimeline, proofProperties(evidenceItem, source: .caseInbox, destination: .caseTimeline))
    }

    func trackTimelineOpened(caseFile: CaseFile) {
        capture(.timelineOpened, caseProperties(caseFile, source: .caseDetail, destination: .caseTimeline))
    }

    func trackTimelineItemCreated(_ evidenceItem: EvidenceItem) {
        capture(.timelineItemCreated, proofProperties(evidenceItem, source: .manualProof, destination: .caseTimeline))
    }

    func trackTimelineItemEdited(_ evidenceItem: EvidenceItem) {
        capture(.timelineItemEdited, proofProperties(evidenceItem, source: .proofReview, destination: .caseTimeline))
    }

    func trackTimelineReadyStateChanged(caseFile: CaseFile, readiness: CaseReadinessResult) {
        var properties = caseProperties(caseFile, source: .caseDetail, destination: .caseTimeline)
        properties.readinessPercent = readiness.score
        properties.readinessBucket = AnalyticsReadinessBucket(percent: readiness.score)
        properties.proofCountBucket = AnalyticsCountBucket(count: readiness.counts.proofItemCount)
        properties.timelineItemCountBucket = AnalyticsCountBucket(count: readiness.counts.timelineItemCount)
        capture(.timelineReadyStateChanged, properties)
    }

    func trackPDFExportStarted(caseFile: CaseFile) {
        capture(.pdfExportStarted, caseProperties(caseFile, source: .caseExport))
    }

    func trackPDFExportCompleted(caseFile: CaseFile, durationMS: Int) {
        var properties = caseProperties(caseFile, source: .caseExport)
        properties.durationMS = max(0, durationMS)
        properties.success = true
        capture(.pdfExportCompleted, properties)
    }

    func trackPDFExportFailed(caseFile: CaseFile, durationMS: Int, errorType: AnalyticsErrorType = .exportFailed) {
        var properties = caseProperties(caseFile, source: .caseExport)
        properties.durationMS = max(0, durationMS)
        properties.success = false
        properties.errorType = errorType
        capture(.pdfExportFailed, properties)
    }

    func trackPaywallViewed(sourceScreen: AnalyticsScreen) {
        capture(.paywallViewed, screenProperties(source: sourceScreen, destination: .paywall))
    }

    func trackPaywallDismissed(sourceScreen: AnalyticsScreen) {
        capture(.paywallDismissed, screenProperties(source: .paywall, destination: sourceScreen))
    }

    func trackSubscriptionStarted(sourceScreen: AnalyticsScreen) {
        capture(.subscriptionStarted, screenProperties(source: sourceScreen, destination: .paywall))
    }

    func trackSubscriptionCompleted(sourceScreen: AnalyticsScreen) {
        var properties = screenProperties(source: .paywall, destination: sourceScreen)
        properties.success = true
        capture(.subscriptionCompleted, properties)
    }

    func trackSubscriptionFailed(sourceScreen: AnalyticsScreen, errorType: AnalyticsErrorType = .subscriptionFailed) {
        var properties = screenProperties(source: .paywall, destination: sourceScreen)
        properties.success = false
        properties.errorType = errorType
        capture(.subscriptionFailed, properties)
    }

    func trackAIActionStarted(actionType: AnalyticsAIActionType) {
        capture(.aiActionStarted, AnalyticsProperties(aiActionType: actionType))
    }

    func trackAIActionCompleted(actionType: AnalyticsAIActionType, creditsSpent: Int?, creditsRemaining: Int?, durationMS: Int) {
        var properties = AnalyticsProperties(
            aiActionType: actionType,
            creditsSpent: creditsSpent.map { max(0, $0) },
            creditsRemainingBucket: creditsRemaining.map(AnalyticsCreditBucket.init(remainingCredits:)),
            durationMS: max(0, durationMS),
            success: true
        )
        if properties.creditsSpent == 0 {
            properties.creditsSpent = nil
        }
        capture(.aiActionCompleted, properties)
    }

    func trackAIActionFailed(actionType: AnalyticsAIActionType, durationMS: Int, errorType: AnalyticsErrorType = .unknown) {
        capture(
            .aiActionFailed,
            AnalyticsProperties(
                aiActionType: actionType,
                durationMS: max(0, durationMS),
                success: false,
                errorType: errorType
            )
        )
    }

    func trackAICreditsSpent(actionType: AnalyticsAIActionType, creditsSpent: Int, creditsRemaining: Int?) {
        guard creditsSpent > 0 else { return }
        capture(
            .aiCreditsSpent,
            AnalyticsProperties(
                aiActionType: actionType,
                creditsSpent: creditsSpent,
                creditsRemainingBucket: creditsRemaining.map(AnalyticsCreditBucket.init(remainingCredits:))
            )
        )
    }

    private var isOptedOut: Bool {
        userDefaults.bool(forKey: Self.optOutStorageKey)
    }

    private func capture(_ event: AnalyticsEvent, _ properties: AnalyticsProperties = AnalyticsProperties()) {
        guard configuration?.isConfigured == true else { return }
        guard !isOptedOut else { return }

        configure()

        #if canImport(PostHog)
        guard Self.didConfigurePostHog else { return }
        PostHogSDK.shared.capture(event.rawValue, properties: properties.dictionary)
        #if DEBUG
        PostHogSDK.shared.flush()
        #endif
        #endif
    }

    private func applyIdentityIfAvailable() {
        #if canImport(PostHog)
        guard Self.didConfigurePostHog, !isOptedOut, userID != nil else { return }
        PostHogSDK.shared.identify(currentUserIDHash)
        #endif
    }

    private func caseProperties(
        _ caseFile: CaseFile,
        source: AnalyticsScreen? = nil,
        destination: AnalyticsScreen? = nil
    ) -> AnalyticsProperties {
        var properties = screenProperties(source: source, destination: destination)
        properties.caseCategory = AnalyticsCaseCategory(caseFile)
        properties.proofCountBucket = AnalyticsCountBucket(count: caseFile.evidenceItems.count)
        properties.timelineItemCountBucket = AnalyticsCountBucket(count: caseFile.evidenceItems.count)
        return properties
    }

    private func proofProperties(
        _ evidenceItem: EvidenceItem,
        source: AnalyticsScreen? = nil,
        destination: AnalyticsScreen? = nil
    ) -> AnalyticsProperties {
        var properties = screenProperties(source: source, destination: destination)
        properties.proofType = AnalyticsProofType(evidenceItem)
        if let caseFile = evidenceItem.caseFile {
            properties.caseCategory = AnalyticsCaseCategory(caseFile)
            properties.proofCountBucket = AnalyticsCountBucket(count: caseFile.evidenceItems.count)
            properties.timelineItemCountBucket = AnalyticsCountBucket(count: caseFile.evidenceItems.count)
        }
        return properties
    }

    private func screenProperties(source: AnalyticsScreen? = nil, destination: AnalyticsScreen? = nil) -> AnalyticsProperties {
        AnalyticsProperties(sourceScreen: source, destinationScreen: destination)
    }

    private func logMissingConfigurationOnce() {
        #if DEBUG
        Self.configurationLock.lock()
        defer { Self.configurationLock.unlock() }

        guard !Self.didLogMissingConfiguration else { return }
        Self.didLogMissingConfiguration = true
        print("[Analytics] PostHog is not configured. Set PROOFKIT_POSTHOG_PROJECT_TOKEN and PROOFKIT_POSTHOG_HOST in Config/ProofKit.local.xcconfig or CI build settings.")
        #endif
    }

    #if canImport(PostHog)
    private static func filteredPostHogEvent(_ event: PostHogEvent) -> PostHogEvent? {
        guard AnalyticsEvent(rawValue: event.event) != nil else {
            return nil
        }

        let filteredProperties = event.properties.reduce(into: [String: Any]()) { partialResult, entry in
            guard AnalyticsPropertyKey(rawValue: entry.key) != nil else { return }
            guard let sanitizedValue = sanitizedPropertyValue(entry.value) else { return }
            partialResult[entry.key] = sanitizedValue
        }

        event.properties = filteredProperties
        return event
    }

    private static func sanitizedPropertyValue(_ value: Any) -> Any? {
        switch value {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return trimmed
        case let value as Bool:
            return value
        case let value as Int:
            return value
        case let value as Int64:
            return value
        case let value as Double:
            guard value.isFinite else { return nil }
            return value
        default:
            return nil
        }
    }
    #endif
}

enum AnalyticsEvent: String, CaseIterable {
    case onboardingStarted = "onboarding_started"
    case onboardingCategorySelected = "onboarding_category_selected"
    case onboardingCompleted = "onboarding_completed"
    case caseCreateStarted = "case_create_started"
    case caseCreated = "case_created"
    case caseOpened = "case_opened"
    case caseManageOpened = "case_manage_opened"
    case caseDeleted = "case_deleted"
    case proofAddStarted = "proof_add_started"
    case proofAdded = "proof_added"
    case proofImportFailed = "proof_import_failed"
    case ocrReviewOpened = "ocr_review_opened"
    case proofReviewed = "proof_reviewed"
    case proofSkipped = "proof_skipped"
    case proofAddedToTimeline = "proof_added_to_timeline"
    case timelineOpened = "timeline_opened"
    case timelineItemCreated = "timeline_item_created"
    case timelineItemEdited = "timeline_item_edited"
    case timelineReadyStateChanged = "timeline_ready_state_changed"
    case pdfExportStarted = "pdf_export_started"
    case pdfExportCompleted = "pdf_export_completed"
    case pdfExportFailed = "pdf_export_failed"
    case paywallViewed = "paywall_viewed"
    case paywallDismissed = "paywall_dismissed"
    case subscriptionStarted = "subscription_started"
    case subscriptionCompleted = "subscription_completed"
    case subscriptionFailed = "subscription_failed"
    case aiActionStarted = "ai_action_started"
    case aiActionCompleted = "ai_action_completed"
    case aiActionFailed = "ai_action_failed"
    case aiCreditsSpent = "ai_credits_spent"
    case appOpened = "app_opened"
    case settingsOpened = "settings_opened"
    case supportOpened = "support_opened"
    case feedbackStarted = "feedback_started"
}

enum AnalyticsPropertyKey: String, CaseIterable {
    case caseCategory = "case_category"
    case proofType = "proof_type"
    case sourceScreen = "source_screen"
    case destinationScreen = "destination_screen"
    case readinessPercent = "readiness_percent"
    case readinessBucket = "readiness_bucket"
    case proofCountBucket = "proof_count_bucket"
    case timelineItemCountBucket = "timeline_item_count_bucket"
    case aiActionType = "ai_action_type"
    case creditsSpent = "credits_spent"
    case creditsRemainingBucket = "credits_remaining_bucket"
    case durationMS = "duration_ms"
    case success
    case errorType = "error_type"
}

struct AnalyticsProperties {
    var caseCategory: AnalyticsCaseCategory?
    var proofType: AnalyticsProofType?
    var sourceScreen: AnalyticsScreen?
    var destinationScreen: AnalyticsScreen?
    var readinessPercent: Int?
    var readinessBucket: AnalyticsReadinessBucket?
    var proofCountBucket: AnalyticsCountBucket?
    var timelineItemCountBucket: AnalyticsCountBucket?
    var aiActionType: AnalyticsAIActionType?
    var creditsSpent: Int?
    var creditsRemainingBucket: AnalyticsCreditBucket?
    var durationMS: Int?
    var success: Bool?
    var errorType: AnalyticsErrorType?

    var dictionary: [String: Any] {
        var values: [String: Any] = [:]
        values[AnalyticsPropertyKey.caseCategory.rawValue] = caseCategory?.rawValue
        values[AnalyticsPropertyKey.proofType.rawValue] = proofType?.rawValue
        values[AnalyticsPropertyKey.sourceScreen.rawValue] = sourceScreen?.rawValue
        values[AnalyticsPropertyKey.destinationScreen.rawValue] = destinationScreen?.rawValue
        values[AnalyticsPropertyKey.readinessPercent.rawValue] = readinessPercent.map { min(max($0, 0), 100) }
        values[AnalyticsPropertyKey.readinessBucket.rawValue] = readinessBucket?.rawValue
        values[AnalyticsPropertyKey.proofCountBucket.rawValue] = proofCountBucket?.rawValue
        values[AnalyticsPropertyKey.timelineItemCountBucket.rawValue] = timelineItemCountBucket?.rawValue
        values[AnalyticsPropertyKey.aiActionType.rawValue] = aiActionType?.rawValue
        values[AnalyticsPropertyKey.creditsSpent.rawValue] = creditsSpent.map { max(0, $0) }
        values[AnalyticsPropertyKey.creditsRemainingBucket.rawValue] = creditsRemainingBucket?.rawValue
        values[AnalyticsPropertyKey.durationMS.rawValue] = durationMS.map { max(0, $0) }
        values[AnalyticsPropertyKey.success.rawValue] = success
        values[AnalyticsPropertyKey.errorType.rawValue] = errorType?.rawValue
        return values.compactMapValues { $0 }
    }
}

enum AnalyticsScreen: String {
    case welcome
    case onboarding
    case home
    case cases
    case vault
    case settings
    case caseCreate = "case_create"
    case caseDetail = "case_detail"
    case caseTimeline = "case_timeline"
    case caseInbox = "case_inbox"
    case caseManage = "case_manage"
    case caseExport = "case_export"
    case addProof = "add_proof"
    case manualProof = "manual_proof"
    case proofReview = "proof_review"
    case paywall
    case support
    case feedback
}

enum AnalyticsCaseCategory: String {
    case apartment
    case refund
    case school
    case work
    case other

    nonisolated init(_ category: CaseCategory) {
        switch category {
        case .apartmentIssue:
            self = .apartment
        case .refundWarrantyIssue:
            self = .refund
        case .schoolCollegeIssue:
            self = .school
        case .other:
            self = .other
        }
    }

    init(_ caseFile: CaseFile) {
        self.init(caseFile.caseReadinessCategory)
    }

    nonisolated init(_ category: CaseReadinessCategory) {
        switch category.analyticsValue {
        case "apartment":
            self = .apartment
        case "refund":
            self = .refund
        case "school":
            self = .school
        case "work":
            self = .work
        default:
            self = .other
        }
    }
}

enum AnalyticsProofType: String {
    case screenshot
    case photo
    case pdf
    case note
    case receipt
    case message
    case other

    init(_ evidenceItem: EvidenceItem) {
        if let attachmentType = evidenceItem.sortedAttachments.first?.attachmentType {
            self.init(attachmentType)
            return
        }

        self.init(evidenceItem.category)
    }

    nonisolated init(_ category: EvidenceCategory) {
        switch category {
        case .screenshot:
            self = .screenshot
        case .photo:
            self = .photo
        case .receipt:
            self = .receipt
        case .message, .email:
            self = .message
        case .note:
            self = .note
        case .document, .contract, .uncategorized, .other:
            self = .other
        }
    }

    nonisolated init(_ attachmentType: AttachmentType) {
        switch attachmentType {
        case .screenshot:
            self = .screenshot
        case .photo:
            self = .photo
        case .pdf:
            self = .pdf
        case .textNote:
            self = .note
        case .document, .other:
            self = .other
        }
    }
}

enum AnalyticsReadinessBucket: String {
    case zeroToTwentyFive = "0_25"
    case twentySixToFifty = "26_50"
    case fiftyOneToSeventyFive = "51_75"
    case seventySixToNinetyNine = "76_99"
    case oneHundred = "100"

    nonisolated init(percent: Int) {
        switch min(max(percent, 0), 100) {
        case 0...25:
            self = .zeroToTwentyFive
        case 26...50:
            self = .twentySixToFifty
        case 51...75:
            self = .fiftyOneToSeventyFive
        case 76...99:
            self = .seventySixToNinetyNine
        default:
            self = .oneHundred
        }
    }
}

enum AnalyticsCountBucket: String {
    case zero = "0"
    case one = "1"
    case twoToFive = "2_5"
    case sixToTen = "6_10"
    case elevenPlus = "11_plus"

    nonisolated init(count: Int) {
        switch max(0, count) {
        case 0:
            self = .zero
        case 1:
            self = .one
        case 2...5:
            self = .twoToFive
        case 6...10:
            self = .sixToTen
        default:
            self = .elevenPlus
        }
    }
}

enum AnalyticsCreditBucket: String {
    case zero = "0"
    case oneToFive = "1_5"
    case sixToTwenty = "6_20"
    case twentyOneToFifty = "21_50"
    case fiftyOnePlus = "51_plus"

    nonisolated init(remainingCredits: Int) {
        switch max(0, remainingCredits) {
        case 0:
            self = .zero
        case 1...5:
            self = .oneToFive
        case 6...20:
            self = .sixToTwenty
        case 21...50:
            self = .twentyOneToFifty
        default:
            self = .fiftyOnePlus
        }
    }
}

enum AnalyticsAIActionType: String {
    case askAI = "ask_ai"
    case timelineSummary = "timeline_summary"
    case packetPolish = "packet_polish"
    case deepReview = "deep_review"
    case other

    nonisolated init(_ taskType: AITaskType) {
        switch taskType {
        case .summarizeTimeline:
            self = .timelineSummary
        case .finalCaseNarrative:
            self = .packetPolish
        case .summarizeItem, .classifyEvidence:
            self = .deepReview
        case .rewriteNote, .suggestTitle:
            self = .other
        }
    }
}

enum AnalyticsErrorType: String {
    case importFailed = "import_failed"
    case ocrFailed = "ocr_failed"
    case exportFailed = "export_failed"
    case networkFailed = "network_failed"
    case subscriptionFailed = "subscription_failed"
    case unknown

    nonisolated init(_ error: Error) {
        if let proofKitError = error as? ProofKitError {
            switch proofKitError {
            case .supabaseNotConfigured, .supabaseSDKUnavailable, .revenueCatNotConfigured, .revenueCatSDKUnavailable:
                self = .networkFailed
            case .planLimitReached:
                self = .subscriptionFailed
            default:
                self = .unknown
            }
            return
        }

        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            self = .networkFailed
        default:
            self = .unknown
        }
    }
}

enum AnalyticsHashing {
    static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var proofKitAnalyticsConfigurationValue: String? {
        let cleaned = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.contains("$(") else { return nil }
        return cleaned
    }
}
