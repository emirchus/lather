import SwiftUI

/// The idle, always-visible trigger in the toolbar's `.principal` slot: a
/// quiet pill that just opens the real command palette (`CommandCenterPaletteView`).
/// It intentionally isn't a live text field — typing happens in the palette
/// itself, which renders as a single window-level overlay so the input and
/// its results read as one continuous card, Cursor/Raycast-style.
struct CommandCenterView: View {
    var onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        // No Spacer/`.frame(maxWidth: .infinity)` anywhere in here: either
        // one, inside a `ToolbarItem(placement: .principal)`, makes NSToolbar
        // collapse the item to zero width, so the whole trigger silently
        // disappears. Keep every element intrinsically sized.
        //
        // Not a `Button`, either: NSToolbar draws its own hover/pressed
        // capsule behind any Button placed in a toolbar item, regardless of
        // buttonStyle — it shows up as a second, larger outline around our
        // own pill. A plain tappable view sidesteps that entirely.
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Search requests, or type a command…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("⌘K")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onOpen)
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }
}

/// The command palette itself — a single floating card containing the search
/// field and its results, rendered by the host view (`ContentView`) as a
/// window-level overlay near the top of the window. Not a `.popover`: one
/// anchored to a view hosted inside an `NSToolbarItem` is unreliable on
/// macOS (especially with `.windowStyle(.hiddenTitleBar)`) and can simply
/// fail to appear.
struct CommandCenterPaletteView: View {
    @Binding var text: String
    @Binding var selectedIndex: Int
    var results: [CommandCenterResult]
    var isFocused: FocusState<Bool>.Binding
    var onExecuteSelected: () -> Void
    var onSelect: (CommandCenterResult) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search requests, or type a command…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
                    // Without this, macOS's native text-completion candidate
                    // bubble floats above the field and clips into our
                    // rounded card — jarring against the custom chrome.
                    .focused(isFocused)
                    .onKeyPress(.downArrow) {
                        guard !results.isEmpty else { return .ignored }
                        selectedIndex = min(selectedIndex + 1, results.count - 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard !results.isEmpty else { return .ignored }
                        selectedIndex = max(selectedIndex - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        guard results.indices.contains(selectedIndex) else { return .ignored }
                        onExecuteSelected()
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        onDismiss()
                        return .handled
                    }

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .onChange(of: text) { _, _ in selectedIndex = 0 }

            if !results.isEmpty {
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                resultRow(result, isSelected: index == selectedIndex)
                                    .id(result.id)
                                    .onTapGesture { onSelect(result) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: min(CGFloat(results.count) * 40 + 12, 320))
                    .onChange(of: selectedIndex) { _, newValue in
                        guard results.indices.contains(newValue) else { return }
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(results[newValue].id)
                        }
                    }
                }
            }
        }
        .frame(width: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
    }

    private func resultRow(_ result: CommandCenterResult, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)

            Text(result.title)
                .foregroundStyle(.primary)

            Text(result.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isSelected ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

#Preview {
    CommandCenterView(onOpen: {})
        .padding()
}
