import SwiftUI

/// Log of every "Send" for the current request — what went out (URL,
/// headers, body) and what came back (status, headers, body), newest first.
struct TimelineView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var expandedEntryID: RequestTimelineEntry.ID?

    var body: some View {
        Group {
            if viewModel.timeline.isEmpty {
                ContentUnavailableView(
                    "No Requests Sent Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Send this request to see a log of what was sent and what came back.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.timeline) { entry in
                            TimelineEntryRow(
                                entry: entry,
                                isExpanded: expandedEntryID == entry.id,
                                toggle: {
                                    expandedEntryID = expandedEntryID == entry.id ? nil : entry.id
                                }
                            )
                        }
                    }
                    .padding(10)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Text("\(viewModel.timeline.count) send\(viewModel.timeline.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear", role: .destructive) { viewModel.clearTimeline() }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.regularMaterial)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.timeline.count) { _, _ in
            // Auto-expand the newest attempt so the result is visible right away.
            expandedEntryID = viewModel.timeline.first?.id
        }
    }
}

private struct TimelineEntryRow: View {
    let entry: RequestTimelineEntry
    let isExpanded: Bool
    let toggle: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(width: 10)

                    statusBadge

                    Text(Self.timeFormatter.string(from: entry.timestamp))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text(entry.endpointURL.isEmpty ? "(no URL)" : entry.endpointURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if entry.errorMessage == nil {
                        Text(String(format: "%.0f ms", entry.duration * 1000))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)

            if isExpanded {
                Divider()
                expandedContent
                    .padding(10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1))
    }

    @ViewBuilder
    private var statusBadge: some View {
        if entry.errorMessage != nil {
            Text("Error")
                .font(.caption.bold())
                .foregroundStyle(.red)
        } else {
            Text("\(entry.statusCode ?? 0)")
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(entry.isSuccess ? .green : .red)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = entry.errorMessage {
                labeledSection(title: "Error") {
                    Text(message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }

            labeledSection(title: "Request") {
                VStack(alignment: .leading, spacing: 6) {
                    if !entry.soapAction.isEmpty {
                        labeledLine("SOAPAction", entry.soapAction)
                    }
                    headerList(entry.requestHeaders)
                    codeBlock(entry.requestBody)
                }
            }

            if entry.errorMessage == nil {
                labeledSection(title: "Response") {
                    VStack(alignment: .leading, spacing: 6) {
                        headerList(entry.responseHeaders)
                        codeBlock(entry.responseBody)
                    }
                }
            }
        }
    }

    private func labeledSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func labeledLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(label):")
                .font(.caption.bold())
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func headerList(_ headers: [String: String]) -> some View {
        if !headers.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(headers.sorted(by: { $0.key < $1.key })), id: \.key) { header in
                    Text("\(header.key): \(header.value)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func codeBlock(_ text: String) -> some View {
        Text(text.isEmpty ? "—" : text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

#Preview {
    TimelineView(viewModel: WorkspaceViewModel())
}
