import UIKit

// The terminal responder needs to conform to `UITextInput` so iOS will deliver
// the spacebar long-press floating-cursor gesture (`beginFloatingCursor` /
// `updateFloatingCursor` / `endFloatingCursor`). The terminal has no editable
// document, so this file provides safe stubs over a virtual one-character
// document. Everything here exists solely to keep UIKit's protocol-required
// calls happy without surfacing autocorrect, marked text, an edit menu, or
// other text-input behaviors. UIKit may still deliver committed software
// keyboard input through `replace(_:withText:)`, so committed replacement text
// is forwarded to the same terminal path as `insertText`.

/// Stub UITextPosition backed by an integer offset in a virtual document of
/// length 1.
final class GhosttyVirtualTextPosition: UITextPosition {
    let offset: Int
    init(offset: Int) {
        self.offset = offset
        super.init()
    }
}

final class GhosttyVirtualTextRange: UITextRange {
    let from: GhosttyVirtualTextPosition
    let to: GhosttyVirtualTextPosition

    init(from: GhosttyVirtualTextPosition, to: GhosttyVirtualTextPosition) {
        self.from = from
        self.to = to
        super.init()
    }

    override var start: UITextPosition { from }
    override var end: UITextPosition { to }
    override var isEmpty: Bool { from.offset == to.offset }
}

extension GhosttyTerminalResponderUIView: UITextInput {
    var selectedTextRange: UITextRange? {
        get {
            guard markedTextStorage != nil else {
                let end = GhosttyVirtualTextPosition(offset: virtualDocumentLength)
                return GhosttyVirtualTextRange(from: end, to: end)
            }
            let startOffset = min(markedTextSelection.location, virtualDocumentLength)
            let endOffset = min(
                startOffset + markedTextSelection.length,
                virtualDocumentLength
            )
            return GhosttyVirtualTextRange(
                from: GhosttyVirtualTextPosition(offset: startOffset),
                to: GhosttyVirtualTextPosition(offset: endOffset)
            )
        }
        set { _ = newValue }
    }

    var markedTextRange: UITextRange? {
        guard markedTextStorage != nil else { return nil }
        return GhosttyVirtualTextRange(
            from: GhosttyVirtualTextPosition(offset: 0),
            to: GhosttyVirtualTextPosition(offset: virtualDocumentLength)
        )
    }
    var markedTextStyle: [NSAttributedString.Key: Any]? {
        get { nil }
        set { _ = newValue }
    }

    var beginningOfDocument: UITextPosition { GhosttyVirtualTextPosition(offset: 0) }
    var endOfDocument: UITextPosition {
        GhosttyVirtualTextPosition(offset: virtualDocumentLength)
    }
    var tokenizer: UITextInputTokenizer { floatingCursorTokenizer }
    var selectionAffinity: UITextStorageDirection {
        get { .forward }
        set { _ = newValue }
    }

    func text(in range: UITextRange) -> String? {
        guard
            let range = range as? GhosttyVirtualTextRange,
            range.from.offset >= 0,
            range.from.offset <= range.to.offset,
            range.to.offset <= virtualDocumentLength
        else {
            return nil
        }

        if let markedTextStorage {
            return (markedTextStorage as NSString).substring(
                with: NSRange(
                    location: range.from.offset,
                    length: range.to.offset - range.from.offset
                )
            )
        }

        // Keep the virtual document coherent so UIKit sees one deletable
        // character and drives its native Backspace repeat behavior.
        return range.isEmpty ? "" : " "
    }

    func replace(_ range: UITextRange, withText text: String) {
        _ = range
        clearMarkedText()
        submitTextInput(text, source: "replaceText")
    }

    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        guard let markedText else {
            unmarkText()
            return
        }

        inputDelegate?.textWillChange(self)
        inputDelegate?.selectionWillChange(self)
        markedTextStorage = markedText
        let length = markedText.utf16.count
        let location = max(0, min(selectedRange.location, length))
        self.markedTextSelection = NSRange(
            location: location,
            length: max(0, min(selectedRange.length, length - location))
        )
        inputDelegate?.textDidChange(self)
        inputDelegate?.selectionDidChange(self)
    }

    func unmarkText() {
        guard let markedTextStorage else { return }
        inputDelegate?.textWillChange(self)
        inputDelegate?.selectionWillChange(self)
        clearMarkedText()
        inputDelegate?.textDidChange(self)
        inputDelegate?.selectionDidChange(self)
        submitTextInput(markedTextStorage, source: "unmarkText")
    }

    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard
            let from = fromPosition as? GhosttyVirtualTextPosition,
            let to = toPosition as? GhosttyVirtualTextPosition
        else {
            return nil
        }
        return GhosttyVirtualTextRange(from: from, to: to)
    }

    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let position = position as? GhosttyVirtualTextPosition else { return nil }
        let next = max(0, min(virtualDocumentLength, position.offset + offset))
        return GhosttyVirtualTextPosition(offset: next)
    }

    func position(
        from position: UITextPosition,
        in direction: UITextLayoutDirection,
        offset: Int
    ) -> UITextPosition? {
        // Direction is meaningless against a single-character virtual document;
        // delegate to the linear offset variant so UIKit's tokenizer keeps
        // receiving non-nil positions.
        self.position(from: position, offset: offset)
    }

    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        guard
            let lhs = position as? GhosttyVirtualTextPosition,
            let rhs = other as? GhosttyVirtualTextPosition
        else {
            return .orderedSame
        }
        if lhs.offset < rhs.offset { return .orderedAscending }
        if lhs.offset > rhs.offset { return .orderedDescending }
        return .orderedSame
    }

    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        guard
            let lhs = from as? GhosttyVirtualTextPosition,
            let rhs = toPosition as? GhosttyVirtualTextPosition
        else {
            return 0
        }
        return rhs.offset - lhs.offset
    }

    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        _ = direction
        return range.end
    }

    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        _ = direction
        guard let position = position as? GhosttyVirtualTextPosition else { return nil }
        return GhosttyVirtualTextRange(from: position, to: position)
    }

    func baseWritingDirection(
        for position: UITextPosition,
        in direction: UITextStorageDirection
    ) -> NSWritingDirection {
        _ = (position, direction)
        return .natural
    }

    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {
        _ = (writingDirection, range)
    }

    func firstRect(for range: UITextRange) -> CGRect {
        _ = range
        return .zero
    }

    func caretRect(for position: UITextPosition) -> CGRect {
        _ = position
        return .zero
    }

    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        _ = range
        return []
    }

    func closestPosition(to point: CGPoint) -> UITextPosition? {
        _ = point
        return GhosttyVirtualTextPosition(offset: virtualDocumentLength)
    }

    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        _ = (point, range)
        return GhosttyVirtualTextPosition(offset: 0)
    }

    private var virtualDocumentLength: Int {
        max(1, markedTextStorage?.utf16.count ?? 0)
    }

    func characterRange(at point: CGPoint) -> UITextRange? {
        _ = point
        let zero = GhosttyVirtualTextPosition(offset: 0)
        return GhosttyVirtualTextRange(from: zero, to: zero)
    }
}
