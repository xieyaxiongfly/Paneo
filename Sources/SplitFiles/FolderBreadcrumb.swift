import AppKit

private final class BreadcrumbButton: ActionButton {
    var onDoubleClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let onDoubleClick { onDoubleClick(); return }
        super.mouseDown(with: event)
    }
}

enum BreadcrumbAction: String, CaseIterable {
    case rename = "Rename…", copyPath = "Copy Path", reveal = "Show in Finder", pin = "Pin to Sidebar"
}

/// Ancestors remain clickable; narrow panes fold them into a single menu.
final class FolderBreadcrumb: NSView {
    var onAction: ((BreadcrumbAction, URL) -> Void)?
    var onNavigate: ((URL) -> Void)?
    var url: URL? { didSet { signature = ""; needsLayout = true } }
    private var signature = ""
    override var intrinsicContentSize: NSSize { NSSize(width: 240, height: 28) }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityLabel("Folder Path")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func ancestors(_ url: URL) -> [URL] {
        var result = [url.standardizedFileURL]
        while let first = result.first, first.path != "/" { result.insert(first.deletingLastPathComponent(), at: 0) }
        if let cloud = result.firstIndex(where: { $0.deletingLastPathComponent().lastPathComponent == "CloudStorage" }) {
            return Array(result[cloud...])
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if let index = result.firstIndex(where: { $0.path == home }) { return Array(result[index...]) }
        return result
    }
    private func title(_ url: URL) -> String {
        if url.lastPathComponent.hasPrefix("GoogleDrive-") { return "Google Drive" }
        return url.path == "/" ? FileManager.default.displayName(atPath: "/") : url.lastPathComponent
    }
    override func layout() {
        super.layout()
        guard let url else { return }
        let next = url.path + ":" + String(Int(bounds.width))
        guard signature != next else { return }; signature = next
        subviews.forEach { $0.removeFromSuperview() }
        let paths = ancestors(url)
        let widths = paths.enumerated().map { index, path -> CGFloat in
            let font = NSFont.systemFont(ofSize: 14, weight: .medium)
            return min(240, (title(path) as NSString).size(withAttributes: [.font: font]).width + 60)
        }
        let available = max(0, bounds.width)
        var start = paths.count - 1
        var used = min(widths[start], max(0, available - (start > 0 ? 44 : 0)))
        while start > 0 {
            let proposed = used + 18 + widths[start - 1]
            if proposed + (start > 1 ? 44 : 0) > available { break }
            start -= 1; used = proposed
        }
        var x: CGFloat = 0
        if start > 0 {
            let collapsed = Array(paths.prefix(start))
            let menuButton = ActionButton("", symbol: "ellipsis", help: "Show Parent Folders") { [weak self] in
                guard let self else { return }
                let menu = NSMenu()
                for path in collapsed {
                    let item = NSMenuItem(title: self.title(path), action: #selector(self.chooseAncestor(_:)), keyEquivalent: "")
                    item.target = self; item.representedObject = path
                    item.image = FolderIcons.image(for: path)
                    menu.addItem(item)
                }
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: self.bounds.minY), in: self)
            }
            menuButton.compact = true; menuButton.frame = NSRect(x: 0, y: (bounds.height - 28) / 2, width: min(26, available), height: 28)
            addSubview(menuButton); x = 26
            addChevron(at: x); x += 18
        }
        for index in start..<paths.count {
            let path = paths[index], current = index == paths.count - 1
            let button = BreadcrumbButton(title(path), symbol: nil, help: path.path) { [weak self] in
                self?.onNavigate?(path)
            }
            if current && path.path != "/" {
                button.onDoubleClick = { [weak self] in self?.onAction?(.rename, path) }
                button.toolTip = path.path + "\nDouble-click to rename. Right-click for more actions."
            }
            let menu = NSMenu(); menu.autoenablesItems = false
            for action in BreadcrumbAction.allCases {
                let item = NSMenuItem(title: action.rawValue, action: #selector(performFolderAction(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = (action, path)
                item.isEnabled = action != .rename || path.path != "/"
                menu.addItem(item)
            }
            button.menu = menu
            button.compact = true
            button.showsCapsuleBackground = true
            button.contentHorizontalInset = 14
            button.font = .systemFont(ofSize: 14, weight: .medium)
            button.contentTintColor = nil
            button.attributedTitle = NSAttributedString(string: title(path), attributes: [
                .font: button.font!, .foregroundColor: current ? NSColor.labelColor : NSColor.secondaryLabelColor
            ])
            button.image = FolderIcons.image(for: path)
            button.imagePosition = .imageLeading
            button.cell?.lineBreakMode = .byTruncatingMiddle
            button.state = current ? .on : .off
            button.frame = NSRect(x: x, y: (bounds.height - 28) / 2, width: max(0, min(widths[index], available - x)), height: 28)
            addSubview(button); x += button.frame.width
            if !current { addChevron(at: x); x += 18 }
        }
    }
    @objc private func performFolderAction(_ sender: NSMenuItem) {
        guard let (action, path) = sender.representedObject as? (BreadcrumbAction, URL) else { return }
        onAction?(action, path)
    }
    private func addChevron(at x: CGFloat) {
        let separator = NSImageView(frame: NSRect(x: x + 4, y: (bounds.height - 12) / 2, width: 10, height: 12))
        separator.image = NSImage(systemSymbolName: "arrowtriangle.right.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 9, weight: .medium))
        separator.contentTintColor = .secondaryLabelColor; addSubview(separator)
    }
    @objc private func chooseAncestor(_ sender: NSMenuItem) { if let url = sender.representedObject as? URL { onNavigate?(url) } }
}
