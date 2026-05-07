import SwiftUI

@main
struct ProofKitApp: App {
    private let services = ServiceContainer.live

    var body: some Scene {
        WindowGroup {
            ProofKitRootView(services: services)
        }
    }
}
