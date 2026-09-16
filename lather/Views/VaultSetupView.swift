import SwiftUI
import AppKit

/// Shown at launch until a vault is configured — asks where to store
/// collections and requests. Also doubles as the retry screen if reopening
/// a previously-chosen vault failed (`VaultManager.state == .failed`).
struct VaultSetupView: View {
    var vaultManager: VaultManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.rectangle.stack")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Choose a Vault")
                    .font(.title2.bold())
                Text("Pick a folder where Lather will store your collections and requests. You can find it again from Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if case .failed(let message) = vaultManager.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            VStack(spacing: 10) {
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder…", systemImage: "folder")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Use Default Location") {
                    useDefaultLocation()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
            }
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 420)
        .background(.background)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder where Lather will store your data."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        vaultManager.chooseVault(at: url)
    }

    private func useDefaultLocation() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let vaultURL = base.appendingPathComponent("Lather", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
            vaultManager.chooseVault(at: vaultURL)
        } catch {
            // VaultManager has no way to surface this on its own since we
            // never got as far as calling chooseVault — the folder itself
            // couldn't be created. Fall back to letting the user pick one.
            chooseFolder()
        }
    }
}

#Preview {
    VaultSetupView(vaultManager: VaultManager())
}
