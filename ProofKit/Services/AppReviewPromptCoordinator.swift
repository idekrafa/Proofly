import Foundation

final class AppReviewPromptCoordinator {
    static let shared = AppReviewPromptCoordinator()

    private let didRequestReviewKey = "proofly.didRequestTimelineProofReview"
    private var didRequestReviewThisSession = false

    private init() {}

    func shouldRequestTimelineProofReview() -> Bool {
        guard !didRequestReviewThisSession else { return false }
        // StoreKit does not report whether the user submitted stars, so treat
        // a successful app-side request as the point where Proofly should stop asking.
        guard !UserDefaults.standard.bool(forKey: didRequestReviewKey) else { return false }

        didRequestReviewThisSession = true
        UserDefaults.standard.set(true, forKey: didRequestReviewKey)
        return true
    }
}
