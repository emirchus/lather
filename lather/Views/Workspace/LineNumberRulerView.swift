import AppKit

/// A real line-number gutter attached to the code editors' `NSScrollView` as
/// a ruler accessory — the correct way to do this on AppKit (it's what
/// Xcode/BBEdit use), and the only way that stays in sync with scrolling.
/// A previous version faked the gutter with a separate, non-scrolling
/// SwiftUI `VStack` next to the editor; the two fell out of sync as soon as
/// a document was tall enough to actually scroll, since nothing kept them
/// scrolling together.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 36
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // Fill `self.bounds`, never the `rect` parameter: `rect` can be
        // (and in practice was) wider than the ruler's own bounds — filling
        // it painted over the adjacent text view with the gutter background,
        // hiding all of its text.
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        guard let textView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView
        else { return }

        let visibleRect = scrollView.documentVisibleRect
        let inset = textView.textContainerInset
        let content = textView.string as NSString

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 || content.length == 0 else { return }

        let firstVisibleCharIndex = content.length == 0 ? 0 : layoutManager.characterIndexForGlyph(at: glyphRange.location)
        var lineNumber = content.substring(to: firstVisibleCharIndex).components(separatedBy: "\n").count

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            let y = usedRect.minY + inset.height - visibleRect.minY
            let numberString = "\(lineNumber)" as NSString
            let size = numberString.size(withAttributes: attributes)
            numberString.draw(
                at: NSPoint(x: self.ruleThickness - size.width - 8, y: y + (usedRect.height - size.height) / 2),
                withAttributes: attributes
            )
            lineNumber += 1
        }
    }
}
