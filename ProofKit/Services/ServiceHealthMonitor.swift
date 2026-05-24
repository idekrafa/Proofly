import Combine
import Foundation
import Network

enum ServiceHealthState: String, CaseIterable, Equatable {
    case healthy
    case offline
    case supabaseDown
    case aiProviderDown
    case degraded
    case checking

    var isHealthy: Bool { self == .healthy }
    var isDegraded: Bool { self != .healthy && self != .checking }

    var statusTitle: String {
        switch self {
        case .healthy:
            "All good"
        case .offline:
            "Proofly is offline"
        case .supabaseDown:
            "Supabase connection issue"
        case .aiProviderDown:
            "AI provider unavailable"
        case .degraded:
            "Services degraded"
        case .checking:
            "Checking services"
        }
    }

    var shortPillTitle: String? {
        switch self {
        case .healthy:
            nil
        case .offline:
            "Offline"
        case .supabaseDown:
            "Server issues"
        case .aiProviderDown:
            "AI delayed"
        case .degraded:
            "Server issues"
        case .checking:
            nil
        }
    }
}

struct ServiceHealthSnapshot: Equatable {
    var state: ServiceHealthState
    var message: String
    var lastCheckedAt: Date?
    var nextRecheckAt: Date?

    static let checking = ServiceHealthSnapshot(
        state: .checking,
        message: "Checking Proofly services...",
        lastCheckedAt: nil,
        nextRecheckAt: nil
    )

    static let healthy = ServiceHealthSnapshot(
        state: .healthy,
        message: "Proofly services are reachable.",
        lastCheckedAt: .now,
        nextRecheckAt: nil
    )
}

enum ServiceHealthIssueContext {
    case supabaseEdgeFunction
    case aiProvider
    case auth
    case credits
}

@MainActor
final class ServiceHealthMonitor: ObservableObject {
    @Published private(set) var snapshot: ServiceHealthSnapshot = .checking

    private let aiCredits: any AICreditTrackingServicing
    private let account: any AccountServicing
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "proofly.service-health.network")
    private var didStartNetworkMonitoring = false

    init(
        aiCredits: any AICreditTrackingServicing,
        account: any AccountServicing
    ) {
        self.aiCredits = aiCredits
        self.account = account
    }

    func start() {
        guard !didStartNetworkMonitoring else { return }
        didStartNetworkMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            let pathStatus = path.status
            Task { @MainActor [weak self] in
                self?.handleNetworkPathStatus(pathStatus)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func handleNetworkPathStatus(_ status: NWPath.Status) {
        if status == .satisfied {
            if snapshot.state == .offline || snapshot.state == .checking {
                snapshot = ServiceHealthSnapshot(
                    state: .healthy,
                    message: "Network is reachable. Proofly will recheck services as needed.",
                    lastCheckedAt: .now,
                    nextRecheckAt: nil
                )
            }
        } else {
            snapshot = ServiceHealthSnapshot(
                state: .offline,
                message: "No network connection is available. Local proof, OCR, notes, and exports remain on this device.",
                lastCheckedAt: .now,
                nextRecheckAt: nil
            )
        }
    }

    func recheck() async {
        start()

        guard monitor.currentPath.status == .satisfied else {
            snapshot = ServiceHealthSnapshot(
                state: .offline,
                message: "No network connection is available. Local proof, OCR, notes, and exports remain on this device.",
                lastCheckedAt: .now,
                nextRecheckAt: nil
            )
            return
        }

        guard account.isConfigured else {
            snapshot = ServiceHealthSnapshot(
                state: .degraded,
                message: "Server features are not configured in this build. Local-first features still work.",
                lastCheckedAt: .now,
                nextRecheckAt: nil
            )
            return
        }

        snapshot = ServiceHealthSnapshot(
            state: .checking,
            message: "Checking Proofly services...",
            lastCheckedAt: snapshot.lastCheckedAt,
            nextRecheckAt: nil
        )

        do {
            _ = try await aiCredits.fetchAICreditBalance()
            snapshot = .healthy
        } catch {
            record(error, context: .supabaseEdgeFunction)
        }
    }

    func record(_ error: Error, context: ServiceHealthIssueContext) {
        let state = Self.state(for: error, context: context, networkIsOffline: monitor.currentPath.status != .satisfied)
        snapshot = ServiceHealthSnapshot(
            state: state,
            message: Self.message(for: state, error: error, context: context),
            lastCheckedAt: .now,
            nextRecheckAt: Date().addingTimeInterval(30)
        )
    }

    func markHealthy(message: String = "Proofly services are reachable.") {
        guard monitor.currentPath.status == .satisfied else { return }
        snapshot = ServiceHealthSnapshot(
            state: .healthy,
            message: message,
            lastCheckedAt: .now,
            nextRecheckAt: nil
        )
    }

    static func isServiceAvailabilityError(_ error: Error) -> Bool {
        switch error {
        case ProofKitError.supabaseNotConfigured, ProofKitError.supabaseSDKUnavailable:
            return true
        default:
            break
        }

        let text = errorText(error)
        return text.contains("network") ||
            text.contains("offline") ||
            text.contains("timed out") ||
            text.contains("timeout") ||
            text.contains("could not connect") ||
            text.contains("connection") ||
            text.contains("unavailable") ||
            text.contains("function") ||
            text.contains("supabase") ||
            text.contains("anthropic") ||
            text.contains("claude") ||
            text.contains("rate limit") ||
            text.contains("429") ||
            text.contains("503") ||
            text.contains("502") ||
            text.contains("500")
    }

    private static func state(
        for error: Error,
        context: ServiceHealthIssueContext,
        networkIsOffline: Bool
    ) -> ServiceHealthState {
        if networkIsOffline {
            return .offline
        }

        let text = errorText(error)
        if context == .aiProvider ||
            text.contains("anthropic") ||
            text.contains("claude") ||
            text.contains("rate limit") ||
            text.contains("429") {
            return .aiProviderDown
        }

        if context == .auth || text.contains("auth") || text.contains("jwt") || text.contains("session") {
            return .degraded
        }

        if text.contains("supabase") ||
            text.contains("function") ||
            text.contains("edge") ||
            text.contains("503") ||
            text.contains("502") ||
            text.contains("500") {
            return .supabaseDown
        }

        return .degraded
    }

    private static func message(
        for state: ServiceHealthState,
        error: Error,
        context: ServiceHealthIssueContext
    ) -> String {
        switch state {
        case .offline:
            "No network connection is available. Local proof, OCR, notes, and exports remain on this device."
        case .supabaseDown:
            "Proofly could not reach its server functions. AI and credit refreshes are queued or paused until services return."
        case .aiProviderDown:
            "The AI provider is temporarily unavailable or rate limited. AI requests will wait and retry."
        case .degraded:
            context == .auth
                ? "Your server session may need a refresh. Local proof remains usable."
                : "Some server-backed features are temporarily limited. Local proof remains usable."
        case .checking:
            "Checking Proofly services..."
        case .healthy:
            "Proofly services are reachable."
        }
    }

    private static func errorText(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description.lowercased()
        }

        return error.localizedDescription.lowercased()
    }
}
