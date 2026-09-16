import Foundation

enum CommandCenterAction {
    case newCollection
    case newRequest
    case openSettings
}

enum CommandCenterResultKind {
    case request(SOAPRequest.ID)
    case action(CommandCenterAction)
}

struct CommandCenterResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let kind: CommandCenterResultKind
}

/// Search behind the Command Center: matches requests by name (across every
/// collection) and a small set of built-in commands, by title.
enum CommandCenterSearch {
    private static let actions: [(CommandCenterAction, title: String, systemImage: String)] = [
        (.newCollection, "New Collection", "folder.badge.plus"),
        (.newRequest, "New Request", "doc.badge.plus"),
        (.openSettings, "Settings", "gearshape")
    ]

    static func results(for query: String, collections: [Collection], limit: Int = 8) -> [CommandCenterResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lowerQuery = trimmed.lowercased()

        let requestResults = collections.flatMap { collection in
            collection.requests
                .filter { $0.name.lowercased().contains(lowerQuery) }
                .map { request in
                    CommandCenterResult(
                        title: request.name,
                        subtitle: collection.name,
                        systemImage: "envelope",
                        kind: .request(request.id)
                    )
                }
        }

        let actionResults = actions
            .filter { $0.title.lowercased().contains(lowerQuery) }
            .map { action in
                CommandCenterResult(title: action.title, subtitle: "Command", systemImage: action.systemImage, kind: .action(action.0))
            }

        return Array((requestResults + actionResults).prefix(limit))
    }
}
