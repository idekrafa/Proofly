import SwiftUI
import SwiftData

@main
struct ProofKitApp: App {
    private let services = ServiceContainer.live

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CaseFile.self,
            EvidenceItem.self,
            Attachment.self,
            ExportPacket.self,
            AIResultCache.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.proofKitServices, services)
                .onOpenURL { url in
                    services.account.handleAuthCallback(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
