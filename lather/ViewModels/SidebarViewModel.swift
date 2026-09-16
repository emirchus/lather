import Foundation
import Observation

@Observable
final class SidebarViewModel {
    var collections: [Collection]
    var selectedRequestID: SOAPRequest.ID?
    var importErrorMessage: String?

    private let importer: CollectionImporting
    private let vault: VaultManager?

    /// `vault` is optional so previews/tests can keep constructing this
    /// in-memory-only, with no persistence.
    init(importer: CollectionImporting = CollectionImporter(), vault: VaultManager? = nil) {
        self.importer = importer
        self.vault = vault
        if let saved = vault?.loadCollections() {
            self.collections = saved
        } else if vault != nil {
            // A brand-new vault (no data file yet) starts seeded with a
            // couple of examples instead of a blank sidebar.
            self.collections = Collection.sampleData
            vault?.saveCollections(Collection.sampleData)
        } else {
            self.collections = []
        }
    }

    private var persistTask: Task<Void, Never>?

    /// Debounced so rapid edits (typing in the body editor fires this on
    /// every keystroke) collapse into a single disk write shortly after
    /// things go quiet, instead of rewriting the vault file constantly.
    private func persist() {
        persistTask?.cancel()
        guard let vault else { return }
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            vault.saveCollections(self.collections)
        }
    }

    /// Writes immediately, bypassing the debounce — call before anything
    /// that could end the session (switching away from a request, the app
    /// losing focus/quitting) so the last edit isn't lost mid-debounce.
    func flushPendingChanges() {
        persistTask?.cancel()
        vault?.saveCollections(collections)
    }

    /// Writes an edited request (from the workspace editor) back into
    /// whichever collection holds it — the workspace only holds its own
    /// copy of the request it's editing, so without this, edits would never
    /// make it back here to be found again or persisted.
    func updateRequest(_ updated: SOAPRequest) {
        for collectionIndex in collections.indices {
            if let requestIndex = collections[collectionIndex].requests.firstIndex(where: { $0.id == updated.id }) {
                guard collections[collectionIndex].requests[requestIndex] != updated else { return }
                collections[collectionIndex].requests[requestIndex] = updated
                persist()
                return
            }
        }
    }

    func createCollection(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        collections.append(Collection(name: trimmedName, requests: []))
        persist()
    }

    func renameCollection(_ id: Collection.ID, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = trimmedName
        persist()
    }

    func deleteCollection(_ id: Collection.ID) {
        collections.removeAll { $0.id == id }
        persist()
    }

    func createRequest(named name: String, in collectionID: Collection.ID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = SOAPRequest(name: trimmedName.isEmpty ? "Untitled Request" : trimmedName)
        collections[index].requests.append(request)
        selectedRequestID = request.id
        persist()
    }

    /// Creates a new request in the first collection, creating one first if
    /// there isn't one yet. Backs both the empty-state "New Request" button
    /// and the ⌘⇧N hotkey, which have no specific collection to target.
    func createRequestInFirstAvailableCollection() {
        let targetCollectionID: Collection.ID
        if let firstCollection = collections.first {
            targetCollectionID = firstCollection.id
        } else {
            createCollection(named: "My Collection")
            guard let newCollection = collections.first else { return }
            targetCollectionID = newCollection.id
        }
        createRequest(named: "Untitled Request", in: targetCollectionID)
    }

    func renameRequest(_ requestID: SOAPRequest.ID, in collectionID: Collection.ID, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let collectionIndex = collections.firstIndex(where: { $0.id == collectionID }),
              let requestIndex = collections[collectionIndex].requests.firstIndex(where: { $0.id == requestID })
        else { return }
        collections[collectionIndex].requests[requestIndex].name = trimmedName
        persist()
    }

    func deleteRequest(_ requestID: SOAPRequest.ID, from collectionID: Collection.ID) {
        guard let collectionIndex = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[collectionIndex].requests.removeAll { $0.id == requestID }
        if selectedRequestID == requestID {
            selectedRequestID = nil
        }
        persist()
    }

    func request(withID id: SOAPRequest.ID?) -> SOAPRequest? {
        guard let id else { return nil }
        return collections.flatMap(\.requests).first { $0.id == id }
    }

    func importCollection(from url: URL, format: ImportFormat) {
        do {
            let collection = try importer.importCollection(from: url, format: format)
            collections.append(collection)
            persist()
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}
