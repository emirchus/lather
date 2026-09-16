import SwiftUI
import AppKit

/// Placeholder for future security/certificate settings (client certificate
/// management for mTLS, e.g. AFIP WSAA / electronic invoicing use cases).
struct SettingsView: View {
    var vaultManager: VaultManager
    var environmentViewModel: EnvironmentViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var environmentPendingDeletion: APIEnvironment?

    var body: some View {
        NavigationStack {
            Form {
                Section("Vault") {
                    if case .ready(let folderURL) = vaultManager.state {
                        LabeledContent("Location", value: folderURL.path)
                            .textSelection(.enabled)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                    } else {
                        Text("No vault is currently open.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Environments") {
                    if environmentViewModel.environments.isEmpty {
                        Text("No environments yet. Add one to define {{variables}} your requests can reference.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(environmentViewModel.environments) { environment in
                        DisclosureGroup {
                            variablesEditor(for: environment)
                        } label: {
                            environmentHeader(for: environment)
                        }
                    }

                    Button {
                        environmentViewModel.createEnvironment(named: "New Environment")
                    } label: {
                        Label("Add Environment…", systemImage: "plus")
                    }
                }

                Section("Client Certificates") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No certificates added yet.")
                            .foregroundStyle(.secondary)
                        Text("Certificates are attached to individual requests from the lock icon in the request editor.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Button {
                        // TODO: present a file importer for .pem/.crt/.key files.
                    } label: {
                        Label("Add Certificate…", systemImage: "plus")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .confirmationDialog(
            "Delete “\(environmentPendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { environmentPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { environmentPendingDeletion = nil }
                }
            ),
            presenting: environmentPendingDeletion
        ) { environment in
            Button("Delete", role: .destructive) {
                environmentViewModel.deleteEnvironment(environment.id)
            }
        } message: { environment in
            Text("This deletes all \(environment.variables.count) variable(s) in “\(environment.name)”. This can't be undone.")
        }
    }

    /// The `DisclosureGroup`'s label: the environment's name plus its
    /// active/delete controls, all independently tappable without expanding
    /// the group (only tapping blank space in the row toggles it).
    @ViewBuilder
    private func environmentHeader(for environment: APIEnvironment) -> some View {
        let isActive = environmentViewModel.activeEnvironmentID == environment.id

        HStack(spacing: 10) {
            TextField(
                "Environment name",
                text: Binding(
                    get: { environment.name },
                    set: { environmentViewModel.renameEnvironment(environment.id, to: $0) }
                ),
                prompt: Text("Environment name")
            )
            .textFieldStyle(.plain)
            .labelsHidden()
            .fontWeight(.medium)

            Spacer(minLength: 8)

            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Button("Make Active") {
                    environmentViewModel.setActiveEnvironment(environment.id)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Button {
                environmentPendingDeletion = environment
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete environment")
        }
    }

    @ViewBuilder
    private func variablesEditor(for environment: APIEnvironment) -> some View {
        if environment.variables.isEmpty {
            Text("No variables yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("KEY")
                    Text("VALUE")
                    Color.clear.gridCellUnsizedAxes(.horizontal)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(environment.variables) { variable in
                    GridRow {
                        TextField(
                            "Key",
                            text: Binding(
                                get: { variable.key },
                                set: { environmentViewModel.updateVariable(variable.id, in: environment.id, key: $0, value: variable.value) }
                            ),
                            prompt: Text("key")
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        TextField(
                            "Value",
                            text: Binding(
                                get: { variable.value },
                                set: { environmentViewModel.updateVariable(variable.id, in: environment.id, key: variable.key, value: $0) }
                            ),
                            prompt: Text("value")
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        Button {
                            environmentViewModel.removeVariable(variable.id, from: environment.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }

        Button {
            environmentViewModel.addVariable(to: environment.id)
        } label: {
            Label("Add Variable", systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .padding(.top, environment.variables.isEmpty ? 0 : 4)
    }
}

#Preview {
    SettingsView(vaultManager: VaultManager(), environmentViewModel: EnvironmentViewModel())
}
