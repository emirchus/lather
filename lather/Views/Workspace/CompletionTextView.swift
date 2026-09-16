import AppKit

/// An `NSTextView` that treats Control+Space as "show completions", same as
/// Xcode. AppKit's own default key bindings don't reliably map that chord to
/// `complete(_:)`, so this handles it explicitly. (Control+Space is also
/// macOS's default Spotlight shortcut — if that's still bound systemwide,
/// the keystroke may never reach the app at all. Nothing to fix on our side
/// for that case; it's a system-level shortcut conflict.)
class CompletionTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), event.charactersIgnoringModifiers == " " {
            complete(nil)
            return
        }
        super.keyDown(with: event)
    }
}
