import AppKit
import SwiftUI

enum JSONTokenKind {
    case key
    case string
    case number
    case keyword
    case punctuation
    case invalid
}

struct JSONToken {
    let kind: JSONTokenKind
    let range: NSRange
}

/// A small hand-rolled JSON lexer — good enough to drive syntax highlighting,
/// not a validating parser (see `JSONValidator` for that).
enum JSONLexer {
    static func tokenize(_ text: String) -> [JSONToken] {
        let ns = text as NSString
        let length = ns.length
        var tokens: [JSONToken] = []
        var i = 0

        func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }
        func isWhitespace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
        func isLetter(_ c: unichar) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }

        while i < length {
            let c = ns.character(at: i)

            if c == 34 { // "
                let start = i
                i += 1
                while i < length {
                    let cc = ns.character(at: i)
                    if cc == 92 { i += 2; continue } // backslash escape
                    i += 1
                    if cc == 34 { break }
                }
                let range = NSRange(location: start, length: i - start)
                var j = i
                while j < length, isWhitespace(ns.character(at: j)) { j += 1 }
                let isKey = j < length && ns.character(at: j) == 58 // ':'
                tokens.append(JSONToken(kind: isKey ? .key : .string, range: range))
                continue
            }

            if c == 45 || isDigit(c) { // '-' or digit
                let start = i
                i += 1
                while i < length {
                    let cc = ns.character(at: i)
                    if isDigit(cc) || cc == 46 || cc == 101 || cc == 69 || cc == 43 || cc == 45 {
                        i += 1
                    } else {
                        break
                    }
                }
                tokens.append(JSONToken(kind: .number, range: NSRange(location: start, length: i - start)))
                continue
            }

            if isLetter(c) {
                let start = i
                i += 1
                while i < length, isLetter(ns.character(at: i)) { i += 1 }
                let range = NSRange(location: start, length: i - start)
                let word = ns.substring(with: range)
                tokens.append(JSONToken(kind: (word == "true" || word == "false" || word == "null") ? .keyword : .invalid, range: range))
                continue
            }

            if "{}[]:,".utf16.contains(c) {
                tokens.append(JSONToken(kind: .punctuation, range: NSRange(location: i, length: 1)))
                i += 1
                continue
            }

            i += 1
        }

        return tokens
    }
}

/// Colorizes an `NSTextStorage` in place (attribute-only changes) so the
/// text view's selection/cursor is preserved across edits.
enum JSONSyntaxHighlighter {
    static func colorize(_ textStorage: NSTextStorage) {
        let text = textStorage.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        textStorage.beginEditing()
        textStorage.removeAttribute(.foregroundColor, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        for token in JSONLexer.tokenize(text) {
            textStorage.addAttribute(.foregroundColor, value: color(for: token.kind), range: token.range)
        }
        textStorage.endEditing()
    }

    /// A colored, read-only rendering for `Text` — used for the response
    /// viewer's Pretty JSON tab, which is display-only and has no business
    /// pulling in the full `NSTextView`-backed editor (undo, autocomplete,
    /// etc.) that `JSONCodeEditor` needs for actually editing a body.
    static func attributedString(for text: String) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = .primary

        for token in JSONLexer.tokenize(text) {
            guard let range = Range(token.range, in: attributed) else { continue }
            attributed[range].foregroundColor = Color(nsColor: color(for: token.kind))
        }
        return attributed
    }

    private static func color(for kind: JSONTokenKind) -> NSColor {
        switch kind {
        case .key: .systemBlue
        case .string: .systemRed
        case .number: .systemOrange
        case .keyword: .systemPurple
        case .punctuation: .secondaryLabelColor
        case .invalid: .systemRed
        }
    }
}

/// Validates JSON structure. Delegates the authoritative valid/invalid call
/// to `JSONSerialization`, then does a best-effort bracket/string scan to
/// locate roughly where things went wrong, for a friendlier message.
enum JSONValidator {
    static func validate(_ text: String) -> EditorIssue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = text.data(using: .utf8) else {
            return EditorIssue(message: "Body isn't valid UTF-8 text.", line: 1, column: 1)
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return nil
        } catch {
            return locateStructuralProblem(in: text) ?? EditorIssue(message: "Invalid JSON.", line: 1, column: 1)
        }
    }

    private static func locateStructuralProblem(in text: String) -> EditorIssue? {
        var line = 1
        var column = 1
        var stack: [Character] = []
        var inString = false
        var escapeNext = false

        for char in text {
            defer {
                if char == "\n" {
                    line += 1
                    column = 1
                } else {
                    column += 1
                }
            }

            if escapeNext {
                escapeNext = false
                continue
            }

            if inString {
                if char == "\\" { escapeNext = true } else if char == "\"" { inString = false }
                continue
            }

            switch char {
            case "\"":
                inString = true
            case "{", "[":
                stack.append(char)
            case "}", "]":
                let expected: Character = char == "}" ? "{" : "["
                if stack.popLast() != expected {
                    return EditorIssue(message: "Unexpected '\(char)'", line: line, column: column)
                }
            default:
                break
            }
        }

        if inString {
            return EditorIssue(message: "Unterminated string", line: line, column: column)
        }
        if let unclosed = stack.last {
            return EditorIssue(message: "Missing closing '\(unclosed == "{" ? "}" : "]")'", line: line, column: column)
        }
        return nil
    }
}
