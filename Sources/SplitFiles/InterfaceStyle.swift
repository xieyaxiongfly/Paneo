import AppKit

/// Shared metrics keep file, workspace and terminal chrome consistent.
enum InterfaceStyle {
    static let body = NSFont.systemFont(ofSize: 14)
    static let label = NSFont.systemFont(ofSize: 13)
    static let caption = NSFont.systemFont(ofSize: 12)
    static let section = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let paneHeaderHeight: CGFloat = 34
}

final class ChromeStack: NSStackView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        super.draw(dirtyRect)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
}
