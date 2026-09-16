import SwiftUI

struct ContentView: View {
    var vaultManager: VaultManager
    @State private var sidebarViewModel: SidebarViewModel
    @State private var workspaceViewModel = WorkspaceViewModel()
    @State private var environmentViewModel: EnvironmentViewModel
    @State private var commandCenterText = ""
    @State private var commandCenterSelectedIndex = 0
    @State private var isCommandCenterOpen = false
    @State private var showSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var isCommandCenterFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(vaultManager: VaultManager) {
        self.vaultManager = vaultManager
        _sidebarViewModel = State(initialValue: SidebarViewModel(vault: vaultManager))
        _environmentViewModel = State(initialValue: EnvironmentViewModel(vault: vaultManager))
    }

    private var activeEnvironmentLabel: String {
        guard let activeEnvironmentID = environmentViewModel.activeEnvironmentID,
              let environment = environmentViewModel.environments.first(where: { $0.id == activeEnvironmentID })
        else {
            return "No Environment"
        }
        return environment.name
    }

    private var commandCenterResults: [CommandCenterResult] {
        CommandCenterSearch.results(for: commandCenterText, collections: sidebarViewModel.collections)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CollectionsSidebarView(sidebar: sidebarViewModel)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if sidebarViewModel.selectedRequestID != nil {
                WorkspaceView(viewModel: workspaceViewModel, environmentViewModel: environmentViewModel)
            } else {
                WorkspaceEmptyStateView(sidebar: sidebarViewModel)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                CommandCenterView(onOpen: openCommandCenter)
                    .frame(minWidth: 320, idealWidth: 480)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(environmentViewModel.environments) { environment in
                        Button {
                            environmentViewModel.setActiveEnvironment(environment.id)
                        } label: {
                            if environment.id == environmentViewModel.activeEnvironmentID {
                                Label(environment.name, systemImage: "checkmark")
                            } else {
                                Text(environment.name)
                            }
                        }
                    }
                    if !environmentViewModel.environments.isEmpty {
                        Divider()
                    }
                    Button("Manage Environments…") { showSettings = true }
                } label: {
                    Label(activeEnvironmentLabel, systemImage: "globe")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings (⌘,)")
            }
        }
        .overlay(alignment: .top) {
            if isCommandCenterOpen {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissCommandCenter() }
                    .overlay(alignment: .top) {
                        CommandCenterPaletteView(
                            text: $commandCenterText,
                            selectedIndex: $commandCenterSelectedIndex,
                            results: commandCenterResults,
                            isFocused: $isCommandCenterFocused,
                            onExecuteSelected: executeSelectedCommandCenterResult,
                            onSelect: executeCommandCenterResult,
                            onDismiss: dismissCommandCenter
                        )
                        .padding(.top, 12)
                        // The palette (and its TextField) only enters the view
                        // tree once `isCommandCenterOpen` flips to true, so
                        // focus can only be requested *after* that happens —
                        // setting the FocusState directly from the toolbar
                        // button would target a field that doesn't exist yet.
                        .onAppear { isCommandCenterFocused = true }
                    }
            }
        }
        .background {
            Group {
                // ⌘⇧N works regardless of what's currently selected/shown,
                // unlike the empty state's own "New Request" button.
                Button("") { sidebarViewModel.createRequestInFirstAvailableCollection() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("") { openCommandCenter() }
                    .keyboardShortcut("k", modifiers: .command)
            }
            .opacity(0)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(vaultManager: vaultManager, environmentViewModel: environmentViewModel)
        }
        .onChange(of: workspaceViewModel.request) { _, editedRequest in
            // The workspace only edits its own copy — write it back so it
            // can be found again (and persisted) from the sidebar's side.
            sidebarViewModel.updateRequest(editedRequest)
        }
        .onChange(of: sidebarViewModel.selectedRequestID) { _, newID in
            sidebarViewModel.flushPendingChanges()
            if let request = sidebarViewModel.request(withID: newID) {
                workspaceViewModel.load(request)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                sidebarViewModel.flushPendingChanges()
                environmentViewModel.flushPendingChanges()
            }
        }
    }

    private func openCommandCenter() {
        isCommandCenterOpen = true
    }

    private func dismissCommandCenter() {
        commandCenterText = ""
        commandCenterSelectedIndex = 0
        isCommandCenterFocused = false
        isCommandCenterOpen = false
    }

    private func executeSelectedCommandCenterResult() {
        guard commandCenterResults.indices.contains(commandCenterSelectedIndex) else { return }
        executeCommandCenterResult(commandCenterResults[commandCenterSelectedIndex])
    }

    private func executeCommandCenterResult(_ result: CommandCenterResult) {
        switch result.kind {
        case .request(let requestID):
            sidebarViewModel.selectedRequestID = requestID
        case .action(.openSettings):
            showSettings = true
        case .action(.newCollection):
            sidebarViewModel.createCollection(named: "New Collection")
        case .action(.newRequest):
            sidebarViewModel.createRequestInFirstAvailableCollection()
        }
        commandCenterText = ""
        commandCenterSelectedIndex = 0
        isCommandCenterFocused = false
        isCommandCenterOpen = false
    }
}

#Preview {
    ContentView(vaultManager: VaultManager())
}
