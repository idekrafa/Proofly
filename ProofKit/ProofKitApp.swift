import SwiftUI

@main
struct ProofKitApp: App {
    private let services: ServiceContainer

    init() {
        let services = ServiceContainer.live
        services.analytics.configure()
        services.analytics.trackAppOpened()
        services.subscriptions.configure()
        self.services = services
    }

    var body: some Scene {
        WindowGroup {
            ProofKitRootView(services: services)
        }
    }
}
