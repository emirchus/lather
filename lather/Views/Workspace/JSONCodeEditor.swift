import SwiftUI
import AppKit

/// The Layer 3 editor: a JSON view of the payload that's also directly
/// editable — edits get translated back into Layer 2's XML. Backed by
/// `NSTextView` for the same reasons as `XMLCodeEditor`: live syntax colors
/// and keystroke interception (bracket/quote auto-close) both need direct
/// `NSTextStorage`/`NSTextView` control that SwiftUI's `TextEditor` doesn't
/// expose.
struct JSONCodeEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var validationIssue: EditorIssue?
    var isEditable: Bool = true
    /// Names offered when the user presses Control+Space: key names from the
    /// request's WSDL schema (Layer 1), plus the active environment's
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
        JSONSyntaxHighlighter.colorize(textView.textStorage ?? NSTextStorage())

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
            JSONSyntaxHighlighter.colorize(textView.textStorage ?? NSTextStorage())
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
            JSONSyntaxHighlighter.colorize(textView.textStorage ?? NSTextStorage())
            validationIssue.wrappedValue = JSONValidator.validate(textView.string)
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacementString else { return true }

            if replacementString == "\n" {
                insertNewlineWithIndent(in: textView, at: affectedCharRange)
                return false
            }

            guard replacementString.count == 1, let typed = replacementString.first else { return true }

            if skipOverExistingClosingCharacter(typed, in: textView, at: affectedCharRange) { return false }
            if autoCloseBracketOrQuote(typed, in: textView, at: affectedCharRange) { return false }

            return true
        }

        /// Typing a closing bracket/quote right before the same character
        /// that auto-close already inserted just moves past it, instead of
        /// inserting a duplicate.
        private func skipOverExistingClosingCharacter(_ typed: Character, in textView: NSTextView, at range: NSRange) -> Bool {
            guard ["}", "]", "\""].contains(typed), range.length == 0 else { return false }
            // `textView.string`, not `textView.textStorage?.string`: the latter can back onto
            // the live mutable storage and crash if read mid-edit (inside this delegate call).
            let current = textView.string as NSString
            guard range.location >= 0, range.location < current.length,
                  current.character(at: range.location) == typed.utf16.first
            else { return false }
            textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            return true
        }

        private func autoCloseBracketOrQuote(_ typed: Character, in textView: NSTextView, at range: NSRange) -> Bool {
            let pairs: [Character: Character] = ["{": "}", "[": "]", "\"": "\""]
            guard let closer = pairs[typed], range.length == 0 else { return false }
            replaceText(in: textView, range: range, with: "\(typed)\(closer)", selectionOffset: 1)
            return true
        }

        /// Matches the current line's indentation, adding one level after an
        /// open bracket so nested objects/arrays stay readable as you type.
        private func insertNewlineWithIndent(in textView: NSTextView, at range: NSRange) {
            // `textView.string`, not `textView.textStorage?.string`: the latter can back onto
            // the live mutable storage and crash if read mid-edit (inside this delegate call).
            let current = textView.string as NSString
            let cursor = min(max(range.location, 0), current.length)

            let lineRange = current.lineRange(for: NSRange(location: cursor, length: 0))
            let currentLine = current.substring(with: lineRange)
            let leadingWhitespace = String(currentLine.prefix { $0 == " " || $0 == "\t" })

            let textBeforeCursor = current.substring(to: cursor)
            let indent = (textBeforeCursor.last == "{" || textBeforeCursor.last == "[") ? leadingWhitespace + "  " : leadingWhitespace
            let insertion = "\n" + indent

            replaceText(in: textView, range: range, with: insertion, selectionOffset: (insertion as NSString).length)
        }

        /// Mutates the text storage directly instead of calling
        /// `NSTextView.insertText`, which re-enters `shouldChangeTextIn` for
        /// its own replacement text — and recurses infinitely when that text
        /// matches the same condition being handled here (inserting "\n"
        /// while already handling a typed "\n" caused a stack overflow).
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
