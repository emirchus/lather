import Foundation

/// A validation problem surfaced by a code editor (currently `XMLValidator`),
/// with the line/column to point the user at.
struct EditorIssue: Equatable {
    let message: String
    let line: Int
    let column: Int
}
