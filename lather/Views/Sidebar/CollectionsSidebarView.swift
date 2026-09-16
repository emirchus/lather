import SwiftUI
import UniformTypeIdentifiers

struct CollectionsSidebarView: View {
    @Bindable var sidebar: SidebarViewModel

    @State private var collapsedCollectionIDs: Set<Collection.ID> = []

    @State private var showingNewCollectionAlert = false
    @State private var newCollectionName = ""

    @State private var renamingCollectionID: Collection.ID?
    @State private var renameCollectionName = ""

    @State private var renamingRequest: (collectionID: Collection.ID, requestID: SOAPRequest.ID)?
    @State private var renameRequestName = ""

    @State private var pendingImportFormat: ImportFormat = .postman
    @State private var showingImporter = false

    var body: some View {
        List(selection: $sidebar.selectedRequestID) {
            ForEach(sidebar.collections) { collection in
                DisclosureGroup(isExpanded: expandedBinding(for: collection.id)) {
                    if collection.requests.isEmpty {
                        Text("No requests yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 4)
                    } else {
                        ForEach(collection.requests) { request in
                            Label(request.name, systemImage: "envelope")
                                .tag(request.id)
                                .contextMenu {
                                    Button("Rename…") {
                                        renamingRequest = (collection.id, request.id)
                                        renameRequestName = request.name
                                    }
                                    Button("Delete", role: .destructive) {
                                        sidebar.deleteRequest(request.id, from: collection.id)
                                    }
                                }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                        Text(collection.name)
                        Spacer()
                        if !collection.requests.isEmpty {
                            Text("\(collection.requests.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("New Request") {
                            collapsedCollectionIDs.remove(collection.id)
                            sidebar.createRequest(named: "Untitled Request", in: collection.id)
                        }
                        Divider()
                        Button("Rename Collection…") {
                            renamingCollectionID = collection.id
                            renameCollectionName = collection.name
                        }
                        Button("Delete Collection", role: .destructive) {
                            sidebar.deleteCollection(collection.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Lather")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    Button {
                        newCollectionName = ""
                        showingNewCollectionAlert = true
                    } label: {
                        Label("New Collection…", systemImage: "folder.badge.plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Divider()

                    Menu {
                        ForEach(ImportFormat.allCases) { format in
                            Button("\(format.displayName)…") {
                                pendingImportFormat = format
                                showingImporter = true
                            }
                        }
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
        }
        .alert("New Collection", isPresented: $showingNewCollectionAlert) {
            TextField("Name", text: $newCollectionName)
            Button("Create") { sidebar.createCollection(named: newCollectionName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Collection", isPresented: Binding(
            get: { renamingCollectionID != nil },
            set: { isPresented in if !isPresented { renamingCollectionID = nil } }
        )) {
            TextField("Name", text: $renameCollectionName)
            Button("Rename") {
                if let id = renamingCollectionID {
                    sidebar.renameCollection(id, to: renameCollectionName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Request", isPresented: Binding(
            get: { renamingRequest != nil },
            set: { isPresented in if !isPresented { renamingRequest = nil } }
        )) {
            TextField("Name", text: $renameRequestName)
            Button("Rename") {
                if let target = renamingRequest {
                    sidebar.renameRequest(target.requestID, in: target.collectionID, to: renameRequestName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Import Failed", isPresented: Binding(
            get: { sidebar.importErrorMessage != nil },
            set: { isPresented in if !isPresented { sidebar.importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sidebar.importErrorMessage ?? "")
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: pendingImportFormat.allowedContentTypes) { result in
            switch result {
            case .success(let url):
                sidebar.importCollection(from: url, format: pendingImportFormat)
            case .failure(let error):
                sidebar.importErrorMessage = error.localizedDescription
            }
        }
    }

    private func expandedBinding(for collectionID: Collection.ID) -> Binding<Bool> {
        Binding(
            get: { !collapsedCollectionIDs.contains(collectionID) },
            set: { isExpanded in
                if isExpanded {
                    collapsedCollectionIDs.remove(collectionID)
                } else {
                    collapsedCollectionIDs.insert(collectionID)
                }
            }
        )
    }
}

#Preview {
    NavigationSplitView {
        CollectionsSidebarView(sidebar: SidebarViewModel())
    } detail: {
        Text("Detail")
    }
}
