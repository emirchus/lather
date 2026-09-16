import SwiftUI
import AppKit

/// The Layer 2 editor: the actual SOAP envelope XML that gets sent. Backed by
/// `NSTextView` — SwiftUI's `TextEditor` can't drive live syntax-color
/// changes without resetting the cursor, and can't intercept keystrokes for
/// tag/quote auto-closing. Both need direct `NSTextStorage`/`NSTextView`
/// control, which this bridges.
struct XMLCodeEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var validationIssue: EditorIssue?
    var isEditable: Bool = true
    /// Names offered when the user presses Control+Space: element names from
    /// the request's WSDL schema (Layer 1), plus the active environment's
    /// `{{variable}}` names. Empty candidates just means nothing to suggest.
    var completionCandidates: [String] = []

    func makeNSView(context: Context) -> NSScrollView {
        // `usingTextLayoutManager: false` opts into the classic TextKit 1
        // stack up front. `LineNumberRulerView` needs direct `NSLayoutManager`
        // access; grabbing `.layoutManager` off a default (TextKit 2) text
        // view forces a runtime compatibility migration that left this view
        // rendering no text at all (line numbers still drew fine, since those
        // come from the layout manager, not the text view's own rendering).
        let textView = CompletionTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.string = text
        XMLSyntaxHighlighter.colorize(textView.textStorage ?? NSTextStorage())

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView = LineNumberRulerView(scrollView: scrollView, textView: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        context.coordinator.completionCandidates = completionCandidates
        if textView.string != text {
            textView.string = text
            XMLSyntaxHighlighter.colorize(textView.textStorage ?? NSTextStorage())
            scrollView.verticalRulerView?.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, validationIssue: $validationIssue, completionCandidates: completionCandidates)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private let validationIssue: Binding<EditorIssue?>
        var completionCandidates: [String]

        init(text: Binding<String>, validationIssue: Binding<EditorIssue?>, completionCandidates: [String]) {
            self.text = text
            self.validationIssue = validationIssue
            self.completionCandidates = completionCandidates
        }

        /// Backs Control+Space completion (`CompletionTextView.keyDown`
        /// calls `complete(nil)`, which triggers this). Matches candidates
        /// from the WSDL schema against the partial word at the cursor.
        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            guard !completionCandidates.isEmpty else { return words }
            let partial = (textView.string as NSString).substring(with: charRange)
            guard !partial.isEmpty else { return completionCandidates.sorted() }
            let matches = completionCandidates.filter { $0.lowercased().hasPrefix(partial.lowercased()) }
            return matches.sorted()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            XMLSyntaxHighlighter.colorize(textView.textStorage ?? NSTextStorage())
            validationIssue.wrappedValue = XMLValidator.validate(textView.string)
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacementString else { return true }

            if replacementString == "\n" {
                insertNewlineWithIndent(in: textView, at: affectedCharRange)
                return false
            }

            guard replacementString.count == 1, let typed = replacementString.first else { return true }

            if typed == ">", autoCloseTag(in: textView, at: affectedCharRange) { return false }
            if skipOverExistingClosingQuote(typed, in: textView, at: affectedCharRange) { return false }
            if skipOverExistingClosingBrace(typed, in: textView, at: affectedCharRange) { return false }
            if autoCloseQuote(typed, in: textView, at: affectedCharRange) { return false }
            if autoCloseBrace(typed, in: textView, at: affectedCharRange) { return false }

            return true
        }

        /// Typing `{` auto-closes to `{}` with the cursor in between — same
        /// idea as the quote pairing below, so typing `{{` for a `{{variable}}`
        /// placeholder lands on `{{|}}`, ready for `token` to be typed or
        /// completed straight into place.
        private func autoCloseBrace(_ typed: Character, in textView: NSTextView, at range: NSRange) -> Bool {
            guard typed == "{", range.length == 0 else { return false }
            replaceText(in: textView, range: range, with: "{}", selectionOffset: 1)
            return true
        }

        /// Typing a closing brace right before the one auto-close already
        /// inserted just moves past it, instead of inserting a duplicate.
        private func skipOverExistingClosingBrace(_ typed: Character, in textView: NSTextView, at range: NSRange) -> Bool {
            guard typed == "}", range.length == 0 else { return false }
            let current = textView.string as NSString
            guard range.location >= 0, range.location < current.length,
                  current.character(at: range.location) == 125 // '}'
            else { return false }
            textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            return true
        }

        /// Completing an opening tag (typing its `>`) inserts the matching
        /// `</tagName>` right after, with the cursor left between them.
        /// Closing tags (`</...`), self-closing tags (`.../>`), comments, and
        /// processing instructions are left alone.
        private func autoCloseTag(in textView: NSTextView, at range: NSRange) -> Bool {
            guard range.length == 0 else { return false }
            let current = textView.string as NSString
            let cursor = min(max(range.location, 0), current.length)

            guard let openIndex = lastUnclosedTagStart(in: current, before: cursor) else { return false }
            let tagContent = current.substring(with: NSRange(location: openIndex + 1, length: cursor - openIndex - 1))

            guard !tagContent.hasPrefix("/"), !tagContent.hasSuffix("/"),
                  !tagContent.hasPrefix("!"), !tagContent.hasPrefix("?"),
                  let tagName = tagContent.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first,
                  !tagName.isEmpty
            else { return false }

            replaceText(in: textView, range: range, with: ">" + "</\(tagName)>", selectionOffset: 1)
            return true
        }

        private func lastUnclosedTagStart(in text: NSString, before location: Int) -> Int? {
            var i = location - 1
            while i >= 0 {
                let c = text.character(at: i)
                if c == 62 { return nil } // '>' found first: not inside a tag
                if c == 60 { return i }   // '<' found first: inside a tag starting here
                i -= 1
            }
            return nil
        }

        /// Typing a closing quote right before the one auto-close already
        /// inserted just moves past it, instead of inserting a duplicate.
        private func skipOverExistingClosingQuote(_ typed: Character, in textView: NSTextView, at range: NSRange) -> Bool {
            guard typed == "\"", range.length == 0 else { return false }
            let current = textView.string as NSString
            guard range.location >= 0, range.location < current.length,
                  current.character(at: range.location) == 34
            else { return false }
            textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            return true
        }

        private func autoCloseQuote(_ typed: Character, in textView: NSTextView, at range: NSRange) -> Bool {
            guard typed == "\"", range.length == 0 else { return false }
            replaceText(in: textView, range: range, with: "\"\"", selectionOffset: 1)
            return true
        }

        /// Matches the current line's indentation, adding one level after an
        /// opening tag so nested elements stay readable as you type.
        private func insertNewlineWithIndent(in textView: NSTextView, at range: NSRange) {
            let current = textView.string as NSString
            let cursor = min(max(range.location, 0), current.length)

            let lineRange = current.lineRange(for: NSRange(location: cursor, length: 0))
            let currentLine = current.substring(with: lineRange)
            let leadingWhitespace = String(currentLine.prefix { $0 == " " || $0 == "\t" })

            let textBeforeCursor = current.substring(to: cursor)
            let opensNewLevel = textBeforeCursor.hasSuffix(">") && !textBeforeCursor.hasSuffix("/>") && !endsWithClosingTag(textBeforeCursor)
            let indent = opensNewLevel ? leadingWhitespace + "  " : leadingWhitespace
            let insertion = "\n" + indent

            replaceText(in: textView, range: range, with: insertion, selectionOffset: (insertion as NSString).length)
        }

        private func endsWithClosingTag(_ text: String) -> Bool {
            guard let lastOpenAngle = text.lastIndex(of: "<") else { return false }
            let tagContent = text[text.index(after: lastOpenAngle)...]
            return tagContent.hasPrefix("/")
        }

        /// Mutates the text storage directly instead of calling
        /// `NSTextView.insertText`, which re-enters `shouldChangeTextIn` for
        /// its own replacement text — and can recurse infinitely when that
        /// text matches the same condition being handled here.
        private func replaceText(in textView: NSTextView, range: NSRange, with replacement: String, selectionOffset: Int) {
            guard let textStorage = textView.textStorage else { return }
            textStorage.beginEditing()
            textStorage.replaceCharacters(in: range, with: replacement)
            textStorage.endEditing()
            textView.setSelectedRange(NSRange(location: range.location + selectionOffset, length: 0))
            textView.didChangeText()
        }
    }
}
