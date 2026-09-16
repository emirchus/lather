import SwiftUI

struct WorkspaceView: View {
    var viewModel: WorkspaceViewModel
    var environmentViewModel: EnvironmentViewModel

    var body: some View {
        VSplitView {
            RequestEditorView(viewModel: viewModel, environmentViewModel: environmentViewModel)
                .frame(minHeight: 200)

            ResponseViewerView(viewModel: viewModel)
                .frame(minHeight: 200)
        }
    }
}

#Preview {
    WorkspaceView(viewModel: WorkspaceViewModel(), environmentViewModel: EnvironmentViewModel())
}
