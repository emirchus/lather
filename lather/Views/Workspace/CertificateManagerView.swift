import SwiftUI

/// Per-request certificate & WSAA ticket manager, opened from the
/// `lock.shield` button in the request editor's header.
struct CertificateManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: WorkspaceViewModel

    @State private var showingCertificateImporter = false
    @State private var showingKeyImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Client Certificate", selection: $viewModel.request.selectedCertificateID) {
                        Text("None").tag(ClientCertificate.ID?.none)
                        ForEach(viewModel.certificateStore.allCertificates()) { certificate in
                            Text(certificate.name).tag(Optional(certificate.id))
                        }
                    }

                    Button {
                        showingCertificateImporter = true
                    } label: {
                        Label("Import Certificate (.pem / .crt)…", systemImage: "doc.badge.plus")
                    }

                    Button {
                        showingKeyImporter = true
                    } label: {
                        Label("Import Private Key (.key)…", systemImage: "key")
                    }
                } header: {
                    Text("OpenSSL Certificate")
                } footer: {
                    Text("Used for mTLS-authenticated SOAP endpoints.")
                }

                Section {
                    LabeledContent("Status") {
                        Text("No ticket requested")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        // TODO: sign a Login Ticket Request (LoginCms) with the selected
                        // certificate/key, POST it to WSAA, and store the resulting
                        // Token/Sign pair (and its expiration) for reuse.
                    } label: {
                        Label("Request WSAA Ticket", systemImage: "ticket")
                    }
                    .disabled(viewModel.request.selectedCertificateID == nil)
                } header: {
                    Text("WSAA Authentication")
                } footer: {
                    Text("Generates a signed Login Ticket Request and exchanges it for an AFIP WSAA access token (Token/Sign).")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Certificates & Security")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 420)
        .fileImporter(
            isPresented: $showingCertificateImporter,
            allowedContentTypes: [ClientCertificate.Kind.pem.contentType, ClientCertificate.Kind.crt.contentType]
        ) { result in
            guard case .success(let url) = result else { return }
            let kind: ClientCertificate.Kind = url.pathExtension.lowercased() == "crt" ? .crt : .pem
            try? viewModel.certificateStore.addCertificate(
                ClientCertificate(name: url.lastPathComponent, kind: kind, fileURL: url)
            )
        }
        .fileImporter(
            isPresented: $showingKeyImporter,
            allowedContentTypes: [ClientCertificate.Kind.key.contentType]
        ) { result in
            guard case .success(let url) = result else { return }
            try? viewModel.certificateStore.addCertificate(
                ClientCertificate(name: url.lastPathComponent, kind: .key, fileURL: url)
            )
        }
    }
}

#Preview {
    CertificateManagerView(viewModel: WorkspaceViewModel())
}
