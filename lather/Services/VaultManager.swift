import Foundation
import Observation

/// Owns where Lather stores its data — a user-chosen folder (the "vault").
/// Sandboxed apps lose access to an arbitrary folder the moment the app
/// quits unless a security-scoped bookmark was saved for it, so that's what
/// this persists (in `UserDefaults`) and resolves again on every launch.
@Observable
final class VaultManager {
    enum State: Equatable {
        case notConfigured
        case ready(folderURL: URL)
        case failed(String)
    }

    private(set) var state: State = .notConfigured

    private static let bookmarkDefaultsKey = "vault.bookmarkData"

    /// The URL we currently hold security-scoped access to, so it can be
    /// released if the vault changes or the manager is torn down.
    private var accessedURL: URL?

    init() {
        restoreVaultIfPossible()
    }

    deinit {
        accessedURL?.stopAccessingSecurityScopedResource()
    }

    private func restoreVaultIfPossible() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: Self.bookmarkDefaultsKey) else {
            state = .notConfigured
            return
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                state = .failed("Lather couldn't get access to your vault folder (\(url.path)). Choose a folder again.")
                return
            }
            accessedURL = url
            if isStale {
                try? saveBookmark(for: url)
            }
            state = .ready(folderURL: url)
        } catch {
            state = .failed("Couldn't reopen your vault folder: \(error.localizedDescription)")
        }
    }

    /// Adopts `url` (already granted for this session, e.g. by `NSOpenPanel`
    /// or a freshly created folder) as the vault, saving a bookmark so it's
    /// remembered on the next launch.
    func chooseVault(at url: URL) {
        do {
            try saveBookmark(for: url)
            accessedURL?.stopAccessingSecurityScopedResource()
            _ = url.startAccessingSecurityScopedResource()
            accessedURL = url
            state = .ready(folderURL: url)
        } catch {
            state = .failed("Couldn't save that folder as your vault: \(error.localizedDescription)")
        }
    }

    private func saveBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmarkData, forKey: Self.bookmarkDefaultsKey)
    }

    // MARK: - Reading and writing the vault's data
    //
    // Laid out as a browsable folder tree, not one opaque file — the same
    // idea as a Bruno collection:
    //
    //   <vault>/Collections/
    //     My Collection/
    //       .collection.json     — {"id", "name"}, the source of truth for
    //                               identity/name (folder names are just for
    //                               Finder; they get sanitized and de-duped)
    //       Some Request.json    — the full SOAPRequest
    //       Another Request.json
    //     Another Collection/
    //       ...
    //
    // Everything under `Collections/` is fully owned by Lather: saving wipes
    // and rewrites it from scratch each time, so a rename or delete never
    // leaves an orphaned file behind. Nothing outside `Collections/` in the
    // vault folder is ever touched.

    private static let collectionsDirectoryName = "Collections"
    private static let collectionMetadataFileName = ".collection.json"
    private static let legacyDataFileName = "lather-data.json"

    private struct CollectionMetadata: Codable {
        var id: UUID
        var name: String
    }

    private struct LegacyVaultData: Codable {
        var collections: [Collection]
    }

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// `nil` means the vault has no saved data yet (a brand-new vault, or
    /// one from before the folder-based layout — see the legacy-file
    /// fallback below); `[]` means it does, and it's genuinely empty.
    func loadCollections() -> [Collection]? {
        guard case .ready(let folderURL) = state else { return nil }
        let collectionsRoot = folderURL.appendingPathComponent(Self.collectionsDirectoryName, isDirectory: true)

        guard FileManager.default.fileExists(atPath: collectionsRoot.path) else {
            return migrateLegacyDataFileIfPresent(in: folderURL)
        }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: collectionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var collections: [Collection] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            let metadataURL = entry.appendingPathComponent(Self.collectionMetadataFileName)
            guard let metadataData = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONDecoder().decode(CollectionMetadata.self, from: metadataData)
            else { continue } // not a folder Lather manages — leave it alone

            let requestFiles = (try? FileManager.default.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            let requests = requestFiles
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .filter { $0.pathExtension == "json" }
                .compactMap { try? Data(contentsOf: $0) }
                .compactMap { try? JSONDecoder().decode(SOAPRequest.self, from: $0) }

            collections.append(Collection(id: metadata.id, name: metadata.name, requests: requests))
        }
        return collections
    }

    func saveCollections(_ collections: [Collection]) {
        guard case .ready(let folderURL) = state else { return }
        let collectionsRoot = folderURL.appendingPathComponent(Self.collectionsDirectoryName, isDirectory: true)

        try? FileManager.default.removeItem(at: collectionsRoot)
        try? FileManager.default.createDirectory(at: collectionsRoot, withIntermediateDirectories: true)

        var usedFolderNames = Set<String>()
        for collection in collections {
            let folderName = uniqueName(for: collection.name, avoiding: &usedFolderNames)
            let collectionFolder = collectionsRoot.appendingPathComponent(folderName, isDirectory: true)
            guard (try? FileManager.default.createDirectory(at: collectionFolder, withIntermediateDirectories: true)) != nil else { continue }

            let metadata = CollectionMetadata(id: collection.id, name: collection.name)
            if let metadataData = try? Self.jsonEncoder.encode(metadata) {
                try? metadataData.write(to: collectionFolder.appendingPathComponent(Self.collectionMetadataFileName), options: .atomic)
            }

            var usedFileNames = Set<String>()
            for request in collection.requests {
                let fileName = uniqueName(for: request.name, avoiding: &usedFileNames) + ".json"
                if let requestData = try? Self.jsonEncoder.encode(request) {
                    try? requestData.write(to: collectionFolder.appendingPathComponent(fileName), options: .atomic)
                }
            }
        }
    }

    /// One-time upgrade from the very first vault format (a single
    /// `lather-data.json`) to the folder layout, for any vault chosen before
    /// this existed. Re-saves in the new layout and removes the old file.
    private func migrateLegacyDataFileIfPresent(in folderURL: URL) -> [Collection]? {
        let legacyURL = folderURL.appendingPathComponent(Self.legacyDataFileName)
        guard let data = try? Data(contentsOf: legacyURL),
              let legacy = try? JSONDecoder().decode(LegacyVaultData.self, from: data)
        else { return nil }

        saveCollections(legacy.collections)
        try? FileManager.default.removeItem(at: legacyURL)
        return legacy.collections
    }

    /// A filesystem-safe, de-duplicated name for a collection/request's
    /// display name. Uniqueness is tracked (and updated) via `used`, scoped
    /// to wherever the caller is currently writing siblings.
    private func uniqueName(for rawName: String, avoiding used: inout Set<String>) -> String {
        let sanitized = sanitizeFileName(rawName)
        var candidate = sanitized
        var suffix = 2
        while used.contains(candidate.lowercased()) {
            candidate = "\(sanitized) (\(suffix))"
            suffix += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalidCharacters).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = String(trimmed.prefix(100))
        return truncated.isEmpty ? "Untitled" : truncated
    }

    // MARK: - Environments
    //
    // Unlike collections, environments are few and don't need to be
    // Finder-browsable, so they're a single flat file rather than a folder
    // per item.

    private static let environmentsFileName = "environments.json"

    struct EnvironmentsFile: Codable {
        var environments: [APIEnvironment]
        var activeEnvironmentID: APIEnvironment.ID?
    }

    /// `nil` means the vault has no environments file yet (a brand-new
    /// vault, or one from before this feature existed).
    func loadEnvironmentsFile() -> EnvironmentsFile? {
        guard case .ready(let folderURL) = state else { return nil }
        let url = folderURL.appendingPathComponent(Self.environmentsFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(EnvironmentsFile.self, from: data)
    }

    func saveEnvironmentsFile(_ file: EnvironmentsFile) {
        guard case .ready(let folderURL) = state else { return }
        let url = folderURL.appendingPathComponent(Self.environmentsFileName)
        guard let data = try? Self.jsonEncoder.encode(file) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
