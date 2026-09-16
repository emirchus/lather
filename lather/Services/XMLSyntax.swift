import AppKit

enum XMLTokenKind {
    case tagBracket
    case tagName
    case attributeName
    case attributeValue
    case comment
    case text
}

struct XMLToken {
    let kind: XMLTokenKind
    let range: NSRange
}

/// A small hand-rolled XML lexer — good enough to drive syntax highlighting,
/// not a validating parser (see `XMLValidator` for that).
enum XMLLexer {
    static func tokenize(_ text: String) -> [XMLToken] {
        let ns = text as NSString
        let length = ns.length
        var tokens: [XMLToken] = []
        var i = 0

        func isWhitespace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
        func isNameChar(_ c: unichar) -> Bool {
            guard let scalar = Unicode.Scalar(c) else { return false }
            let ch = Character(scalar)
            return ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == ":" || ch == "."
        }

        while i < length {
            let c = ns.character(at: i)

            guard c == 60 else { // not '<' -> plain text run
                let start = i
                while i < length, ns.character(at: i) != 60 { i += 1 }
                tokens.append(XMLToken(kind: .text, range: NSRange(location: start, length: i - start)))
                continue
            }

            if ns.length - i >= 4, ns.substring(with: NSRange(location: i, length: 4)) == "<!--" {
                let start = i
                let closing = ns.range(of: "-->", options: [], range: NSRange(location: i, length: length - i))
                i = closing.location != NSNotFound ? closing.location + closing.length : length
                tokens.append(XMLToken(kind: .comment, range: NSRange(location: start, length: i - start)))
                continue
            }

            tokens.append(XMLToken(kind: .tagBracket, range: NSRange(location: i, length: 1)))
            i += 1
            if i < length, ns.character(at: i) == 47 { // '/'
                tokens.append(XMLToken(kind: .tagBracket, range: NSRange(location: i, length: 1)))
                i += 1
            }

            let nameStart = i
            while i < length, isNameChar(ns.character(at: i)) { i += 1 }
            if i > nameStart {
                tokens.append(XMLToken(kind: .tagName, range: NSRange(location: nameStart, length: i - nameStart)))
            }

            while i < length, ns.character(at: i) != 62 { // until '>'
                let cc = ns.character(at: i)
                if cc == 47 {
                    tokens.append(XMLToken(kind: .tagBracket, range: NSRange(location: i, length: 1)))
                    i += 1
                } else if isWhitespace(cc) || cc == 61 { // whitespace or '='
                    i += 1
                } else if cc == 34 || cc == 39 { // quote
                    let quote = cc
                    let valueStart = i
                    i += 1
                    while i < length, ns.character(at: i) != quote { i += 1 }
                    if i < length { i += 1 }
                    tokens.append(XMLToken(kind: .attributeValue, range: NSRange(location: valueStart, length: i - valueStart)))
                } else if isNameChar(cc) {
                    let attrStart = i
                    while i < length, isNameChar(ns.character(at: i)) { i += 1 }
                    tokens.append(XMLToken(kind: .attributeName, range: NSRange(location: attrStart, length: i - attrStart)))
                } else {
                    i += 1
                }
            }
            if i < length, ns.character(at: i) == 62 {
                tokens.append(XMLToken(kind: .tagBracket, range: NSRange(location: i, length: 1)))
                i += 1
            }
        }

        return tokens
    }
}

/// Colorizes an `NSTextStorage` in place (attribute-only changes) so the
/// text view's selection/cursor is preserved across edits.
enum XMLSyntaxHighlighter {
    static func colorize(_ textStorage: NSTextStorage) {
        let text = textStorage.string
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        textStorage.beginEditing()
        textStorage.removeAttribute(.foregroundColor, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        for token in XMLLexer.tokenize(text) {
            let color: NSColor
            switch token.kind {
            case .tagBracket: color = .secondaryLabelColor
            case .tagName: color = .systemBlue
            case .attributeName: color = .systemOrange
            case .attributeValue: color = .systemRed
            case .comment: color = .systemGreen
            case .text: color = .labelColor
            }
            textStorage.addAttribute(.foregroundColor, value: color, range: token.range)
        }
        textStorage.endEditing()
    }
}

/// Validates well-formedness via `XMLParser` itself, which reports the exact
/// line/column of the first problem.
enum XMLValidator {
    static func validate(_ text: String) -> EditorIssue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = text.data(using: .utf8) else {
            return EditorIssue(message: "Body isn't valid UTF-8 text.", line: 1, column: 1)
        }

        let parser = XMLParser(data: data)
        guard !parser.parse() else { return nil }

        let message = parser.parserError?.localizedDescription ?? "Invalid XML."
        return EditorIssue(message: message, line: parser.lineNumber, column: parser.columnNumber)
    }
}
