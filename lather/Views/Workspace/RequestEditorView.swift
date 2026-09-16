import SwiftUI

struct RequestEditorView: View {
    @Bindable var viewModel: WorkspaceViewModel
    var environmentViewModel: EnvironmentViewModel
    @State private var showingCertificateManager = false
    @State private var payloadTab: PayloadTab = .xml

    @State private var xmlValidationIssue: EditorIssue?

    @State private var jsonText: String = ""
    @State private var jsonValidationIssue: EditorIssue?
    /// Suppresses `onChange(of: jsonText)` for assignments we make ourselves
    /// (re-deriving JSON from the XML) — only actual edits from the JSON
    /// editor should be pushed back into the XML, or clicking the JSON tab
    /// would silently rewrite the XML's root element to `request.name`.
    @State private var isSyncingJSONFromXML = false

    /// The three payload layers: Schema (Layer 1, read-only reference from
    /// the WSDL), XML (Layer 2, the payload that actually gets sent), and
    /// JSON (Layer 3, a translation of Layer 2 that's also editable — edits
    /// get pushed back into the XML, which stays the source of truth).
    private enum PayloadTab: String, CaseIterable, Identifiable {
        case schema = "Schema"
        case xml = "XML"
        case json = "JSON"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField("https://example.com/service", text: $viewModel.request.endpointURL)
                    .textFieldStyle(.roundedBorder)

                TextField("SOAPAction", text: $viewModel.request.soapAction)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Button {
                    showingCertificateManager = true
                } label: {
                    Image(systemName: "lock.shield")
                }
                .buttonStyle(.bordered)
                .help("Manage client certificates & WSAA tickets")

                Button {
                    viewModel.send(activeVariables: environmentViewModel.activeVariables)
                } label: {
                    if viewModel.isSending {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16)
                    } else {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSending)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (⌘Return)")
            }

            HStack {
                Text("Body")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let issue = payloadTab == .xml ? xmlValidationIssue : (payloadTab == .json ? jsonValidationIssue : nil) {
                    Label("Line \(issue.line): \(issue.message)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                Spacer()

                Picker("", selection: $payloadTab) {
                    ForEach(PayloadTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
            }

            switch payloadTab {
            case .schema:
                readOnlyPane(schemaText)
            case .xml:
                codeEditorPane(isValid: xmlValidationIssue == nil) {
                    XMLCodeEditor(
                        text: $viewModel.request.xmlBody,
                        validationIssue: $xmlValidationIssue,
                        isEditable: !viewModel.isSending,
                        completionCandidates: editorCompletionCandidates
                    )
                }
            case .json:
                codeEditorPane(isValid: jsonValidationIssue == nil) {
                    JSONCodeEditor(
                        text: $jsonText,
                        validationIssue: $jsonValidationIssue,
                        isEditable: !viewModel.isSending,
                        completionCandidates: editorCompletionCandidates
                    )
                }
            }
        }
        .padding()
        .background(.background)
        .disabled(viewModel.isSending)
        .background {
            // Cmd+1/2/3 tab switching — background buttons so the shortcut
            // works window-wide without a visible control.
            Group {
                Button("") { payloadTab = .schema }.keyboardShortcut("1", modifiers: .command)
                Button("") { payloadTab = .xml }.keyboardShortcut("2", modifiers: .command)
                Button("") { payloadTab = .json }.keyboardShortcut("3", modifiers: .command)
            }
            .opacity(0)
        }
        .onAppear { refreshFromXML() }
        .onChange(of: viewModel.request.id) { _, _ in refreshFromXML() }
        .onChange(of: payloadTab) { _, newTab in
            if newTab == .json {
                setJSONFromXML()
            }
        }
        .onChange(of: jsonText) { _, newValue in
            if isSyncingJSONFromXML {
                isSyncingJSONFromXML = false
                return
            }
            viewModel.applyEditedJSON(newValue)
        }
        .sheet(isPresented: $showingCertificateManager) {
            CertificateManagerView(viewModel: viewModel)
        }
    }

    private func refreshFromXML() {
        xmlValidationIssue = XMLValidator.validate(viewModel.request.xmlBody)
        setJSONFromXML()
    }

    private func setJSONFromXML() {
        let derivedJSON = viewModel.jsonPreview()
        jsonValidationIssue = JSONValidator.validate(derivedJSON)
        // Only touch `jsonText` — and only arm the suppression flag — when the
        // value is actually about to change, otherwise `onChange(of: jsonText)`
        // never fires to consume the flag and it would wrongly stay armed for
        // the next real edit.
        guard derivedJSON != jsonText else { return }
        isSyncingJSONFromXML = true
        jsonText = derivedJSON
    }

    private var schemaText: String {
        viewModel.request.officialSchemaXML ?? "No schema available.\n\nImport this request from a WSDL to see the official envelope structure here."
    }

    /// Element/key names Control+Space can suggest, pulled from the WSDL
    /// schema (Layer 1). Empty for requests without one (Postman/Insomnia
    /// imports, manually created requests) — completion just offers nothing.
    private var schemaCompletionCandidates: [String] {
        guard let schema = viewModel.request.officialSchemaXML else { return [] }
        let names = XMLLexer.tokenize(schema).compactMap { token -> String? in
            guard token.kind == .tagName else { return nil }
            let name = (schema as NSString).substring(with: token.range)
            // Skip namespaced elements (soapenv:Envelope/Header/Body) — those
            // are envelope structure, not data fields worth completing.
            return name.contains(":") ? nil : name
        }
        return Array(Set(names))
    }

    /// The active environment's variable names, offered for `{{variable}}`
    /// completion — typing `{{` auto-closes to `{{|}}` (existing
    /// bracket-pairing behavior), so completing a bare name here drops
    /// straight into place between the braces.
    private var variableCompletionCandidates: [String] {
        Array(environmentViewModel.activeVariables.keys)
    }

    /// Everything Control+Space can suggest in the XML/JSON editors: WSDL
    /// schema field names plus the active environment's variable names.
    private var editorCompletionCandidates: [String] {
        schemaCompletionCandidates + variableCompletionCandidates
    }

    /// Line numbers are drawn by each editor's own `LineNumberRulerView`,
    /// attached directly to its `NSScrollView` — that's what keeps them in
    /// sync with scrolling for long documents. (An earlier version faked the
    /// gutter with a separate, non-scrolling SwiftUI `VStack` next to the
    /// editor; it visibly desynced on any document tall enough to scroll.)
    @ViewBuilder
    private func codeEditorPane(isValid: Bool, @ViewBuilder editor: () -> some View) -> some View {
        editor()
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isValid ? Color(.separatorColor) : .red.opacity(0.7), lineWidth: 1)
            )
    }

    private func readOnlyPane(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1))
    }
}

#Preview {
    RequestEditorView(viewModel: WorkspaceViewModel(), environmentViewModel: EnvironmentViewModel())
}
