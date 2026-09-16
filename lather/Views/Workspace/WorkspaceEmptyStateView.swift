import SwiftUI

/// Shown in the detail column when no request is selected yet.
struct WorkspaceEmptyStateView: View {
    var sidebar: SidebarViewModel

    var body: some View {
        ContentUnavailableView {
            Label("No Request Selected", systemImage: "tray")
        } description: {
            Text("Select a request from the sidebar, or create a new one to get started.")
        } actions: {
            Button {
                sidebar.createRequestInFirstAvailableCollection()
            } label: {
                Label("New Request", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

#Preview {
    WorkspaceEmptyStateView(sidebar: SidebarViewModel())
}
