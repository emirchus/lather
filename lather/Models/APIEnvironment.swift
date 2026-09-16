import Foundation

struct EnvironmentVariable: Identifiable, Codable, Hashable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

/// A named set of `{{key}}` variables (e.g. "Sandbox", "Production") that
/// requests can reference in their endpoint URL, headers, and XML body.
/// Named `APIEnvironment`, not `Environment` — the latter collides with
/// SwiftUI's `@Environment` property wrapper type in any file that uses both.
struct APIEnvironment: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var variables: [EnvironmentVariable]

    init(id: UUID = UUID(), name: String, variables: [EnvironmentVariable] = []) {
        self.id = id
        self.name = name
        self.variables = variables
    }
}
