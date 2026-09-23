import AppKit

/// A temporary field drawn over a filename; filesystem failures stay beside it.
final class InlineRename: NSObject, NSTextFieldDelegate {
    let field = NSTextField()
    private let errorLabel = NSTextField(labelWithString: "")
    private let commit: (String) throws -> Void
    private let finished: (Bool) -> Void
    private var ending = false
    init(name: String, frame: NSRect, in view: NSView, commit: @escaping (String) throws -> Void, finished: @escaping (Bool) -> Void) {
        self.commit = commit; self.finished = finished
        super.init()
        field.frame = frame; field.stringValue = name; field.font = InterfaceStyle.body
        field.isEditable = true; field.isSelectable = true; field.isBezeled = true
        field.drawsBackground = true; field.backgroundColor = .textBackgroundColor
        field.focusRingType = .default; field.delegate = self
        field.setAccessibilityLabel("Rename File")
        field.toolTip = "Return to save · Escape to cancel"
        errorLabel.font = InterfaceStyle.caption; errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.frame = NSRect(x: frame.minX, y: view.isFlipped ? frame.maxY + 2 : frame.minY - 20, width: frame.width, height: 18)
        view.addSubview(field); view.addSubview(errorLabel)
    }
    func begin() { field.selectText(nil) }
    func cancel() { end(restoreFocus: true) }
    private func end(restoreFocus: Bool = false) {
        guard !ending else { return }; ending = true
        field.delegate = nil; field.removeFromSuperview(); errorLabel.removeFromSuperview()
        finished(restoreFocus)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { end(restoreFocus: true); return true }
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.insertTab(_:)) {
            do { try commit(field.stringValue); end(restoreFocus: true) }
            catch {
                errorLabel.stringValue = error.localizedDescription; errorLabel.toolTip = error.localizedDescription
                field.toolTip = error.localizedDescription; NSSound.beep()
            }
            return true
        }
        return false
    }
    func controlTextDidEndEditing(_ obj: Notification) { end() }
}
