import SwiftUI

/// Switches between the vault setup screen and the main app depending on
/// whether a vault folder is configured (and reachable) yet.
struct RootView: View {
    @State private var vaultManager = VaultManager()

    var body: some View {
        switch vaultManager.state {
        case .notConfigured, .failed:
            VaultSetupView(vaultManager: vaultManager)
        case .ready:
            ContentView(vaultManager: vaultManager)
        }
    }
}

#Preview {
    RootView()
}
