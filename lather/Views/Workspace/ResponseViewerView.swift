import SwiftUI

struct ResponseViewerView: View {
    @Bindable var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusBar

            if viewModel.isSending {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            HStack {
                Picker("", selection: $viewModel.selectedResponseTab) {
                    ForEach(WorkspaceViewModel.ResponseTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 460)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            Group {
                switch viewModel.selectedResponseTab {
                case .prettyJSON:
                    jsonCodeView(viewModel.response?.prettyJSON ?? "")
                case .rawXML:
                    codeView(viewModel.response?.rawXML ?? "")
                case .headers:
                    headersView
                case .timeline:
                    TimelineView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var statusBar: some View {
        if let response = viewModel.response {
            HStack {
                Text(response.statusCode == 0 ? "Error" : "\(response.statusCode)")
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle((200..<400).contains(response.statusCode) ? .green : .red)
                if response.statusCode != 0 {
                    Text(String(format: "%.0f ms", response.duration * 1000))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.regularMaterial)
        }
    }

    private func codeView(_ text: String) -> some View {
        ScrollView {
            Text(text.isEmpty ? "—" : text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    /// Same as `codeView`, but syntax-colored — read-only and selectable via
    /// `Text(AttributedString)`, not the `NSTextView`-backed `JSONCodeEditor`
    /// (this never needs editing, undo, or autocomplete).
    private func jsonCodeView(_ text: String) -> some View {
        ScrollView {
            Group {
                if text.isEmpty {
                    Text("—").foregroundStyle(.secondary)
                } else {
                    Text(JSONSyntaxHighlighter.attributedString(for: text))
                }
            }
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private var headersView: some View {
        List {
            ForEach(Array((viewModel.response?.headers ?? [:]).sorted(by: { $0.key < $1.key })), id: \.key) { header in
                LabeledContent(header.key, value: header.value)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    ResponseViewerView(viewModel: WorkspaceViewModel())
}
