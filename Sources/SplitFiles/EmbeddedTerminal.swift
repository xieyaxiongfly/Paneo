import AppKit
import GhosttyTerminal

final class PaneTerminalView: AppTerminalView {
    weak var pane: FilePane?
    override func mouseDown(with event: NSEvent) { pane?.activate(); super.mouseDown(with: event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, window?.attachedSheet == nil else { return false }
        if handlePaneShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if handlePaneShortcut(event) { return }
        super.keyDown(with: event)
    }
    private func handlePaneShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased(), let direction = PaneDirection.from(key) {
            pane?.workspace?.focusPane(direction); return true
        }
        if flags == .control, PaneDirection.arrow(event.keyCode) != nil {
            pane?.workspace?.splitTowardKey(event.keyCode); return true
        }
        return false
    }
}

final class EmbeddedTerminal: NSView, TerminalSurfaceCloseDelegate, TerminalSurfaceTitleDelegate {
    let terminal = PaneTerminalView(frame: .zero)
    weak var pane: FilePane?
    private let titleLabel = NSTextField(labelWithString: "Ghostty")
    init(pane: FilePane, directory: URL) {
        self.pane = pane
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let header = ChromeStack(); header.spacing = 8; header.distribution = .fill
        header.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        let back = ActionButton("", symbol: "folder", help: "Return to Files (Keep Terminal Running)") { [weak pane] in pane?.hideTerminal() }
        let close = ActionButton("", symbol: "xmark", help: "End Terminal Session and Return to Files") { [weak pane] in pane?.closeTerminal() }
        for button in [back, close] { button.compact = true; button.isBordered = false; button.image = button.image?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) }
        titleLabel.font = InterfaceStyle.label; titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.stringValue = "Ghostty · \(directory.lastPathComponent)"
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(back); header.addArrangedSubview(titleLabel); header.addArrangedSubview(close)
        back.widthAnchor.constraint(equalToConstant: 26).isActive = true
        close.widthAnchor.constraint(equalToConstant: 26).isActive = true
        terminal.pane = pane; terminal.delegate = self
        terminal.configuration = TerminalSurfaceOptions(fontSize: 14, workingDirectory: directory.path)
        terminal.controller = TerminalController.shared
        for child in [header, terminal] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor), header.trailingAnchor.constraint(equalTo: trailingAnchor), header.heightAnchor.constraint(equalToConstant: InterfaceStyle.paneHeaderHeight),
            terminal.topAnchor.constraint(equalTo: header.bottomAnchor), terminal.leadingAnchor.constraint(equalTo: leadingAnchor), terminal.trailingAnchor.constraint(equalTo: trailingAnchor), terminal.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        terminal.setAccessibilityLabel("Ghostty Terminal: \(directory.path)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func terminalDidChangeTitle(_ title: String) { titleLabel.stringValue = "Ghostty · \(title)" }
    func terminalDidClose(processAlive: Bool) {
        DispatchQueue.main.async { [weak self] in
            if processAlive { self?.pane?.closeTerminal() } else { self?.pane?.stopTerminal() }
        }
    }
    func stop() { terminal.delegate = nil; terminal.controller = nil; removeFromSuperview() }
}
