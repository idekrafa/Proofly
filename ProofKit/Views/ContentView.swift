import SwiftData
import SwiftUI

struct ContentView: View {
    let onSignOut: () -> Void

    @State private var selectedTab: ProofKitRootTab = .overview
    @AppStorage(ProofKitSettingsStorageKeys.appearance) private var appearanceRawValue = ProofKitAppearancePreference.system.rawValue

    init(onSignOut: @escaping () -> Void = {}) {
        self.onSignOut = onSignOut
    }

    private var preferredColorScheme: ColorScheme? {
        (ProofKitAppearancePreference(rawValue: appearanceRawValue) ?? .system).colorScheme
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView {
                selectedTab = .settings
            }
                .tabItem {
                    Label("Overview", systemImage: selectedTab == .overview ? "rectangle.grid.3x2.fill" : "rectangle.grid.3x2")
                }
                .tag(ProofKitRootTab.overview)

            CasesView()
            .tabItem {
                Label("Cases", systemImage: selectedTab == .cases ? "folder.fill" : "folder")
            }
            .tag(ProofKitRootTab.cases)

            VaultView()
            .tabItem {
                Label("Vault", systemImage: selectedTab == .vault ? "shippingbox.fill" : "shippingbox")
            }
            .tag(ProofKitRootTab.vault)

            GlobalSettingsView(onSignedOut: onSignOut)
            .tabItem {
                Label("Settings", systemImage: selectedTab == .settings ? "gearshape.fill" : "gearshape")
            }
            .tag(ProofKitRootTab.settings)
        }
        .tint(Color(red: 0.02, green: 0.47, blue: 0.92))
        .preferredColorScheme(preferredColorScheme)
        .animation(ProofKitMotion.standard, value: selectedTab)
    }
}

private enum ProofKitRootTab: Hashable {
    case overview
    case cases
    case vault
    case settings
}

private struct RootPlaceholderView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(red: 0.02, green: 0.47, blue: 0.92))
                    .frame(width: 72, height: 72)
                    .background {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.systemBackground))
                    }

                VStack(spacing: 7) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .proofKitAppear()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [CaseFile.self, EvidenceItem.self, Attachment.self, ExportPacket.self, AIResultCache.self], inMemory: true)
}
