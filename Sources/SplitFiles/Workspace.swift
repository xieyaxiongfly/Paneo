import AppKit

class ActionButton: NSButton {
    var actionBlock: (() -> Void)?
    private var hovered = false
    var contentHorizontalInset: CGFloat = 0 { didSet { needsDisplay = true } }
    var showsCapsuleBackground = false { didSet { needsDisplay = true } }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if showsCapsuleBackground || state == .on || (isEnabled && (hovered || isHighlighted)) {
            let color = state == .on ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.13 : (hovered ? 0.09 : 0.045))
            color.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: compact ? 12 : 15, yRadius: compact ? 12 : 15).fill()
        }
        if contentHorizontalInset > 0 {
            let inset = min(contentHorizontalInset, max(0, bounds.width / 2))
            cell?.drawInterior(withFrame: bounds.insetBy(dx: inset, dy: 0), in: self)
        } else {
            super.draw(dirtyRect)
        }
    }
    var compact = false { didSet { invalidateIntrinsicContentSize() } }
    override var intrinsicContentSize: NSSize {
        NSSize(width: title.isEmpty ? (compact ? 28 : 34) : max(58, super.intrinsicContentSize.width + 12), height: compact ? 28 : 34)
    }
    convenience init(_ title: String, symbol: String? = nil, help: String? = nil, action: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: help ?? title)?.withSymbolConfiguration(.init(pointSize: 18, weight: .medium)) }
        imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        bezelStyle = .regularSquare
        isBordered = false
        font = InterfaceStyle.label
        contentTintColor = .secondaryLabelColor
        (cell as? NSButtonCell)?.highlightsBy = []
        (cell as? NSButtonCell)?.showsStateBy = []
        controlSize = .regular
        imageScaling = .scaleProportionallyDown
        toolTip = help ?? title
        setAccessibilityLabel(help ?? title)
        target = self
        self.action = #selector(invoke)
        actionBlock = action
    }
    @objc private func invoke() { actionBlock?() }
}

final class WorkspaceTabButton: ActionButton {
    var contextMenu: (() -> NSMenu)?
    override var intrinsicContentSize: NSSize {
        NSSize(width: min(180, super.intrinsicContentSize.width), height: 34)
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

struct SavedNode: Codable {
    var path: String?
    var vertical: Bool?
    var fraction: Double?
    var children: [SavedNode]?
    var display: DisplaySettings?
}

final class PaneDivider: NSView {
    weak var split: PaneSplitView?
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: split?.isVertical == true ? .resizeLeftRight : .resizeUpDown)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        if split?.isVertical == true { NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill() }
        else { NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1).fill() }
    }
    override func mouseDown(with event: NSEvent) {
        guard let split, let window else { return }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let point = split.convert(next.locationInWindow, from: nil)
            let length = split.isVertical ? split.bounds.width : split.bounds.height
            let position = split.isVertical ? point.x : point.y
            split.fraction = min(0.88, max(0.12, position / max(1, length - 5)))
            split.arrangePanes()
            split.layoutSubtreeIfNeeded()
        }
    }
}

final class PaneSplitView: NSView {
    var isVertical = true
    var fraction: CGFloat = 0.5
    private var panes: [NSView] = []
    private var dimension: NSLayoutConstraint?
    private let divider = PaneDivider()
    override var isFlipped: Bool { true }
    func addArrangedSubview(_ pane: NSView) {
        pane.translatesAutoresizingMaskIntoConstraints = false
        panes.append(pane); addSubview(pane)
        guard panes.count == 2 else { return }
        divider.split = self; divider.translatesAutoresizingMaskIntoConstraints = false; addSubview(divider)
        let a = panes[0], b = panes[1]
        if isVertical {
            NSLayoutConstraint.activate([
                a.leadingAnchor.constraint(equalTo: leadingAnchor), a.topAnchor.constraint(equalTo: topAnchor), a.bottomAnchor.constraint(equalTo: bottomAnchor),
                divider.leadingAnchor.constraint(equalTo: a.trailingAnchor), divider.widthAnchor.constraint(equalToConstant: 5), divider.topAnchor.constraint(equalTo: topAnchor), divider.bottomAnchor.constraint(equalTo: bottomAnchor),
                b.leadingAnchor.constraint(equalTo: divider.trailingAnchor), b.trailingAnchor.constraint(equalTo: trailingAnchor), b.topAnchor.constraint(equalTo: topAnchor), b.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                a.topAnchor.constraint(equalTo: topAnchor), a.leadingAnchor.constraint(equalTo: leadingAnchor), a.trailingAnchor.constraint(equalTo: trailingAnchor),
                divider.topAnchor.constraint(equalTo: a.bottomAnchor), divider.heightAnchor.constraint(equalToConstant: 5), divider.leadingAnchor.constraint(equalTo: leadingAnchor), divider.trailingAnchor.constraint(equalTo: trailingAnchor),
                b.topAnchor.constraint(equalTo: divider.bottomAnchor), b.bottomAnchor.constraint(equalTo: bottomAnchor), b.leadingAnchor.constraint(equalTo: leadingAnchor), b.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }
        arrangePanes()
    }
    func arrangePanes() {
        guard panes.count == 2 else { return }
        dimension?.isActive = false
        dimension = isVertical ? panes[0].widthAnchor.constraint(equalTo: widthAnchor, multiplier: fraction, constant: -5 * fraction) : panes[0].heightAnchor.constraint(equalTo: heightAnchor, multiplier: fraction, constant: -5 * fraction)
        dimension?.isActive = true
    }
}

final class LayoutNode {
    var pane: FilePane?
    var children: [LayoutNode] = []
    var vertical = true
    var fraction: Double = 0.5
    var splitView: PaneSplitView?
    init(pane: FilePane) { self.pane = pane }
    init(_ first: LayoutNode, _ second: LayoutNode, vertical: Bool) {
        children = [first, second]; self.vertical = vertical
    }
    var panes: [FilePane] { pane.map { [$0] } ?? children.flatMap(\.panes) }
    func snapshot() -> SavedNode {
        if let pane { return SavedNode(path: pane.directory.path, display: pane.settings) }
        if let splitView { fraction = Double(splitView.fraction) }
        return SavedNode(vertical: vertical, fraction: fraction, children: children.map { $0.snapshot() })
    }
    func build(frame: NSRect) -> NSView {
        if let pane { pane.frame = frame; return pane }
        let split = PaneSplitView(frame: frame)
        split.isVertical = vertical
        split.fraction = CGFloat(fraction)
        split.autoresizingMask = [.width, .height]
        splitView = split
        for child in children { split.addArrangedSubview(child.build(frame: NSRect(origin: .zero, size: frame.size))) }
        split.arrangePanes()
        return split
    }
    func applyFractions() {
        guard let splitView else { return }
        splitView.fraction = CGFloat(fraction); splitView.arrangePanes()
        children.forEach { $0.applyFractions() }
    }
}

final class Workspace: NSViewController, NSMenuDelegate {
    var root: LayoutNode!
    weak var activePane: FilePane?
    private let canvas = NSView()
    private let paneLabel = NSTextField(labelWithString: "")
    private let sidebar = Sidebar()
    private var splitButtons: [ActionButton] = []
    private var closeButton: ActionButton!
    private let viewModes = NSSegmentedControl()
    private var sortButton: ActionButton!
    private var moreButton: ActionButton!
    private var shareButton: ActionButton!
    private var layoutButton: ActionButton!
    private var pinButton: ActionButton!
    private var previousLayout: SavedNode?
    private let workspaceTabs = NSStackView()
    private let workspaceScroll = NSScrollView()
    private var workspaceTabsWidth: NSLayoutConstraint?
    private var workspaceTabsSignature = ""
    private var sessions: [SavedWorkspace] = []
    private var currentSession = UUID()
    private var liveWorkspaces: [UUID: LayoutNode] = [:]
    private var restoringSession = false
    private let sessionsKey = "SplitFiles.workspaces.v1"

    let defaultsKey = "SplitFiles.layout.v1"

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1240, height: 780))
        let toolbar = ChromeStack()
        toolbar.orientation = .horizontal; toolbar.spacing = 6
        workspaceTabs.orientation = .horizontal; workspaceTabs.spacing = 5
        workspaceScroll.drawsBackground = false
        workspaceScroll.hasHorizontalScroller = false; workspaceScroll.hasVerticalScroller = false
        workspaceScroll.documentView = workspaceTabs
        workspaceScroll.setAccessibilityLabel("Workspace Switcher")
        workspaceScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        workspaceScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        workspaceScroll.heightAnchor.constraint(equalToConstant: 34).isActive = true
        workspaceTabsWidth = workspaceScroll.widthAnchor.constraint(equalToConstant: 36)
        workspaceTabsWidth?.priority = .defaultHigh; workspaceTabsWidth?.isActive = true
        toolbar.addArrangedSubview(workspaceScroll)
        toolbar.addArrangedSubview(ActionButton("", symbol: "plus", help: "New Workspace") { [weak self] in self?.newWorkspace() })
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(spacer)
        viewModes.segmentCount = FileViewMode.allCases.count
        viewModes.trackingMode = .selectOne
        viewModes.segmentStyle = .rounded
        viewModes.controlSize = .regular
        for (index, mode) in FileViewMode.allCases.enumerated() {
            viewModes.setImage(NSImage(systemSymbolName: mode.symbol, accessibilityDescription: mode.title)?.withSymbolConfiguration(.init(pointSize: 18, weight: .medium)), forSegment: index)
            viewModes.setWidth(36, forSegment: index)
            viewModes.setToolTip(mode.title + " View · ⌘" + String(index + 1), forSegment: index)
        }
        viewModes.target = self; viewModes.action = #selector(changeView(_:))
        viewModes.setAccessibilityLabel("Current Pane View")
        toolbar.addArrangedSubview(viewModes)
        func addToolbarDivider() {
            let divider = NSBox(); divider.boxType = .separator
            divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
            divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
            toolbar.addArrangedSubview(divider)
        }
        addToolbarDivider()
        sortButton = ActionButton("", symbol: "line.3.horizontal.decrease", help: "Sort & Group") { [weak self] in
            guard let self, let menu = self.activePane?.sortMenu() else { return }
            self.show(menu, from: self.sortButton)
        }
        moreButton = ActionButton("", symbol: "ellipsis.circle", help: "More Actions") { [weak self] in
            guard let self, let menu = self.activePane?.actionsMenu() else { return }
            self.show(menu, from: self.moreButton)
        }
        shareButton = ActionButton("", symbol: "square.and.arrow.up", help: "Share Selected Files") { [weak self] in
            guard let self else { return }; self.activePane?.share(from: self.shareButton)
        }
        toolbar.addArrangedSubview(sortButton); toolbar.addArrangedSubview(moreButton); toolbar.addArrangedSubview(shareButton)
        pinButton = ActionButton("", symbol: "pin", help: "Pin Current Folder to Sidebar") { [weak self] in
            guard let self, let pane = self.activePane else { return }
            self.sidebar.togglePin(pane.directory)
        }
        toolbar.addArrangedSubview(pinButton)
        addToolbarDivider()
        sidebar.onPinsChanged = { [weak self] in self?.updateControls() }
        layoutButton = ActionButton("Layout", symbol: "square.grid.2x2", help: "Split Layout Presets") { [weak self] in
            guard let self else { return }; self.show(self.layoutMenu(), from: self.layoutButton)
        }
        toolbar.addArrangedSubview(layoutButton)
        paneLabel.font = InterfaceStyle.caption; paneLabel.textColor = .secondaryLabelColor
        toolbar.addArrangedSubview(paneLabel)
        let horizontal = ActionButton("", symbol: "rectangle.split.2x1", help: "Split Right · ⌘D") { [weak self] in self?.split(vertical: true) }
        let vertical = ActionButton("", symbol: "rectangle.split.1x2", help: "Split Down · ⇧⌘D") { [weak self] in self?.split(vertical: false) }
        splitButtons = [horizontal, vertical]
        toolbar.addArrangedSubview(horizontal); toolbar.addArrangedSubview(vertical)
        closeButton = ActionButton("", symbol: "xmark.rectangle", help: "Close Current Pane · ⇧⌘W") { [weak self] in self?.closePane() }
        toolbar.addArrangedSubview(closeButton)
        let home = FileManager.default.homeDirectoryForCurrentUser
        sidebar.onNavigate = { [weak self] url in
            guard let self, let pane = self.activePane else { return }
            pane.navigate(to: url)
            self.activate(pane)
        }
        let separator = NSBox(); separator.boxType = .separator
        for item in [sidebar, toolbar, separator, canvas] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor, constant: 2), toolbar.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 6), toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8), toolbar.heightAnchor.constraint(equalToConstant: 42),
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor), sidebar.topAnchor.constraint(equalTo: view.topAnchor), sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 212),
            separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), separator.widthAnchor.constraint(equalToConstant: 1), separator.topAnchor.constraint(equalTo: view.topAnchor), separator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 458), view.widthAnchor.constraint(greaterThanOrEqualToConstant: 820),
            canvas.leadingAnchor.constraint(equalTo: separator.trailingAnchor), canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor), canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 2), canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if let data = UserDefaults.standard.data(forKey: defaultsKey), let saved = try? JSONDecoder().decode(SavedNode.self, from: data) {
            root = restore(saved, depth: 0)
        } else {
            root = LayoutNode(LayoutNode(pane: makePane(home)), LayoutNode(pane: makePane(home)), vertical: true)
        }
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let saved = try? JSONDecoder().decode(WorkspaceArchive.self, from: data), !saved.workspaces.isEmpty {
            sessions = saved.workspaces
            let selected = sessions.first { $0.id == saved.selectedID } ?? sessions[0]
            currentSession = selected.id
            restoringSession = true
            root = restore(selected.layout, depth: 0)
            restoringSession = false
        } else {
            sessions = [SavedWorkspace(id: currentSession, name: "Default", layout: root.snapshot())]
        }
        rebuild()
        activate(root.panes[0])
        save()
    }

    private func makePane(_ url: URL) -> FilePane { FilePane(directory: url, workspace: self) }
    private func restore(_ saved: SavedNode, depth: Int) -> LayoutNode {
        if let children = saved.children, children.count == 2, depth < 5 {
            let node = LayoutNode(restore(children[0], depth: depth + 1), restore(children[1], depth: depth + 1), vertical: saved.vertical ?? true)
            node.fraction = min(0.85, max(0.15, saved.fraction ?? 0.5)); return node
        }
        let pane = makePane(URL(fileURLWithPath: saved.path ?? FileManager.default.homeDirectoryForCurrentUser.path))
        if let display = saved.display { pane.restoreSettings(display) }
        return LayoutNode(pane: pane)
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        let hideCount = view.bounds.width < 1160
        if paneLabel.isHidden != hideCount { paneLabel.isHidden = hideCount }
    }
    private func rebuild() {
        root.panes.forEach { $0.removeFromSuperview() }
        canvas.subviews.forEach { $0.removeFromSuperview() }
        view.layoutSubtreeIfNeeded()
        let tree = root.build(frame: canvas.bounds)
        tree.translatesAutoresizingMaskIntoConstraints = false; canvas.addSubview(tree)
        NSLayoutConstraint.activate([tree.leadingAnchor.constraint(equalTo: canvas.leadingAnchor), tree.trailingAnchor.constraint(equalTo: canvas.trailingAnchor), tree.topAnchor.constraint(equalTo: canvas.topAnchor), tree.bottomAnchor.constraint(equalTo: canvas.bottomAnchor)])
        view.layoutSubtreeIfNeeded()
        root.applyFractions()
        paneLabel.stringValue = "\(root.panes.count) " + (root.panes.count == 1 ? "pane" : "panes")
        closeButton.isEnabled = root.panes.count > 1
        splitButtons.forEach { $0.isEnabled = root.panes.count < 8 }
    }
    func activate(_ pane: FilePane) {
        activePane = pane
        updateControls()
        sidebar.select(directory: pane.directory)
        root?.panes.forEach { $0.setActive($0 === pane) }
        if view.window?.attachedSheet == nil { view.window?.makeFirstResponder(pane.focusView) }
    }
    func focusNext() {
        let panes = root.panes
        let next = ((panes.firstIndex { $0 === activePane } ?? 0) + 1) % panes.count
        activate(panes[next]); view.window?.makeFirstResponder(panes[next].focusView)
    }
    func focusPane(_ direction: PaneDirection) {
        guard let activePane else { return }
        let panes = root.panes.filter { $0 !== activePane }
        let frames = panes.map { $0.convert($0.bounds, to: canvas) }
        let origin = activePane.convert(activePane.bounds, to: canvas)
        if let index = direction.neighbor(from: origin, among: frames) { activate(panes[index]) }
    }
    func split(vertical: Bool, before: Bool = false) {
        guard let activePane, root.panes.count < 8 else { NSSound.beep(); return }
        _ = root.snapshot()
        let newPane = makePane(activePane.directory)
        newPane.restoreSettings(activePane.settings)
        func replace(_ node: LayoutNode) {
            if node.pane === activePane {
                node.children = before ? [LayoutNode(pane: newPane), LayoutNode(pane: activePane)] : [LayoutNode(pane: activePane), LayoutNode(pane: newPane)]
                node.pane = nil; node.vertical = vertical; node.fraction = 0.5
            } else { node.children.forEach(replace) }
        }
        replace(root); rebuild(); activate(newPane); view.window?.makeFirstResponder(newPane.focusView); save()
    }
    func closePane() {
        guard let activePane, root.panes.count > 1 else { return }
        guard confirmClosingTerminals([activePane]) else { return }
        activePane.stopTerminal()
        _ = root.snapshot()
        func remove(_ node: LayoutNode) -> LayoutNode? {
            if node.pane === activePane { return nil }
            if node.pane != nil { return node }
            let remaining = node.children.compactMap(remove)
            if remaining.count == 1 { return remaining[0] }
            node.children = remaining; return node
        }
        root = remove(root); rebuild(); activate(root.panes[0]); view.window?.makeFirstResponder(root.panes[0].focusView); save()
    }
    func folderRenamed(from source: URL, to destination: URL) {
        func relocate(_ node: SavedNode) -> SavedNode {
            var node = node
            if let path = node.path { node.path = FolderRelocation.url(URL(fileURLWithPath: path), from: source, to: destination).path }
            node.children = node.children?.map(relocate)
            return node
        }
        for index in sessions.indices { sessions[index].layout = relocate(sessions[index].layout) }
        previousLayout = previousLayout.map(relocate)
        (root.panes + liveWorkspaces.values.flatMap { $0.panes }).forEach { $0.folderRenamed(from: source, to: destination) }
        sidebar.folderRenamed(from: source, to: destination)
        save()
    }
    func save() {
        guard !restoringSession else { return }
        updateControls()
        sidebar.select(directory: activePane?.directory)
        guard let root, let data = try? JSONEncoder().encode(root.snapshot()) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        if let index = sessions.firstIndex(where: { $0.id == currentSession }) { sessions[index].layout = root.snapshot() }
        persistSessions()
    }
    func updateControls() {
        updateWorkspaceTabs()

        viewModes.selectedSegment = FileViewMode.allCases.firstIndex(of: activePane?.settings.mode ?? .list) ?? 1
        let browsing = !(activePane?.terminalVisible ?? false)
        sortButton?.isEnabled = browsing; moreButton?.isEnabled = browsing
        shareButton?.isEnabled = browsing && !(activePane?.selectedURLs.isEmpty ?? true)
        let pinned = activePane.map { sidebar.isPinned($0.directory) } ?? false
        pinButton?.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 18, weight: .medium))
        pinButton?.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
        let label = pinned ? "Unpin Current Folder" : "Pin Current Folder to Sidebar"
        pinButton?.toolTip = label
        pinButton?.setAccessibilityLabel(label)
    }
    private func show(_ menu: NSMenu, from button: NSView) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 3), in: button)
    }
    private func persistSessions() {
        guard !sessions.isEmpty, let data = try? JSONEncoder().encode(WorkspaceArchive(selectedID: currentSession, workspaces: sessions)) else { return }
        UserDefaults.standard.set(data, forKey: sessionsKey)
    }
    private func updateWorkspaceTabs() {
        let signature = sessions.map { $0.id.uuidString + $0.name }.joined(separator: "|") + currentSession.uuidString
        guard signature != workspaceTabsSignature else { return }
        workspaceTabsSignature = signature
        workspaceTabs.arrangedSubviews.forEach { workspaceTabs.removeArrangedSubview($0); $0.removeFromSuperview() }
        var selectedButton: NSView?
        var tabsWidth: CGFloat = 0
        for (index, session) in sessions.enumerated() {
            let selected = session.id == currentSession
            let label = session.name.isEmpty ? "Workspace \(index + 1)" : session.name
            let button = WorkspaceTabButton(session.name, symbol: index < 50 ? "\(index + 1).circle" : "circle.grid.2x2", help: label) { [weak self] in
                self?.switchWorkspace(to: session.id)
            }
            button.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
            button.image = button.image?.withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
            button.cell?.lineBreakMode = .byTruncatingTail
            let width = button.intrinsicContentSize.width
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            tabsWidth += width + 24 + (index == 0 ? 0 : workspaceTabs.spacing)
            button.setButtonType(.pushOnPushOff)
            (button.cell as? NSButtonCell)?.highlightsBy = []
            (button.cell as? NSButtonCell)?.showsStateBy = []
            button.state = selected ? .on : .off
            button.contentTintColor = selected ? .controlAccentColor : .secondaryLabelColor
            button.setAccessibilityLabel("Workspace \(index + 1): \(label)" + (selected ? " (Current)" : ""))
            button.contextMenu = { [weak self] in
                let menu = NSMenu(); menu.autoenablesItems = false
                for (title, action) in [(session.name.isEmpty ? "Name Workspace…" : "Rename Workspace…", #selector(Workspace.renameWorkspaceTab(_:))), ("Close Workspace", #selector(Workspace.deleteWorkspaceTab(_:)))] {
                    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                    item.target = self; item.representedObject = session.id.uuidString
                    item.isEnabled = true
                    menu.addItem(item)
                }
                return menu
            }
            let close = ActionButton("", symbol: "xmark", help: "Close Workspace: " + label) { [weak self] in
                self?.deleteWorkspace(session.id)
            }
            close.compact = true
            close.image = close.image?.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
            close.widthAnchor.constraint(equalToConstant: 24).isActive = true
            let tab = NSStackView(views: [button, close]); tab.spacing = 0
            tab.widthAnchor.constraint(equalToConstant: width + 24).isActive = true
            workspaceTabs.addArrangedSubview(tab)
            if selected { selectedButton = tab }
        }
        workspaceTabs.frame = NSRect(x: 0, y: 0, width: max(32, tabsWidth), height: 34)
        workspaceTabsWidth?.constant = max(36, workspaceTabs.frame.width)
        workspaceTabs.layoutSubtreeIfNeeded()
        if let selectedButton { workspaceTabs.scrollToVisible(selectedButton.frame) }
    }
    @objc private func renameWorkspaceTab(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        renameWorkspace(id)
    }
    @objc private func deleteWorkspaceTab(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        deleteWorkspace(id)
    }
    private func switchWorkspace(to id: UUID) {
        guard id != currentSession else { workspaceTabsSignature = ""; updateWorkspaceTabs(); return }
        guard sessions.contains(where: { $0.id == id }) else { return }
        save()
        guard let target = sessions.first(where: { $0.id == id }) else { return }
        restoringSession = true
        liveWorkspaces[currentSession] = root
        currentSession = id; previousLayout = nil
        root.panes.forEach { $0.removeFromSuperview() }
        root = liveWorkspaces.removeValue(forKey: id) ?? restore(target.layout, depth: 0)
        rebuild(); activate(root.panes[0])
        restoringSession = false
        save()
    }
    private func askWorkspaceName(_ title: String, initial: String, completion: @escaping (String) -> Void) {
        guard let window = view.window else { return }
        let alert = NSAlert(); alert.messageText = title
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = initial; input.placeholderString = "Leave blank to show only the icon"; alert.accessoryView = input
        alert.beginSheetModal(for: window) { response in
            let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if response == .alertFirstButtonReturn { completion(name) }
        }
        alert.window.makeFirstResponder(input)
    }
    @objc private func newWorkspace() {
        save()
        let session = SavedWorkspace(id: UUID(), name: "", layout: root.snapshot())
        sessions.append(session)
        switchWorkspace(to: session.id)
    }
    private func renameWorkspace(_ id: UUID) {
        let existing = sessions.first { $0.id == id }?.name ?? ""
        askWorkspaceName(existing.isEmpty ? "Name Workspace" : "Rename Workspace", initial: existing) { [weak self] name in
            guard let self, let index = self.sessions.firstIndex(where: { $0.id == id }) else { return }
            self.sessions[index].name = name; self.save()
        }
    }
    private func deleteWorkspace(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }), let window = view.window, window.attachedSheet == nil else { return }
        let closing = currentSession == id ? root : liveWorkspaces[id]
        let terminalCount = closing?.panes.filter { $0.hasTerminal }.count ?? 0
        guard terminalCount > 0 else { finishClosingWorkspace(id); return }
        let name = sessions.first { $0.id == id }?.name ?? ""
        let alert = NSAlert()
        alert.messageText = name.isEmpty ? "Close this workspace?" : "Close workspace “\(name)”?"
        alert.informativeText = "This workspace has \(terminalCount) terminal session(s), including sessions running behind file views. Closing it will end these sessions and their running tasks. Your files will be kept."
        alert.addButton(withTitle: "End Terminals and Close"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.finishClosingWorkspace(id) }
        }
    }
    private func finishClosingWorkspace(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let closing = currentSession == id ? root : liveWorkspaces[id]
        closing?.panes.forEach { $0.stopTerminal() }
        if currentSession == id {
            if sessions.count == 1 {
                // Keep a usable window after closing the last workspace; do not clone its sessions.
                sessions.append(SavedWorkspace(id: UUID(), name: "", layout: SavedNode(path: FileManager.default.homeDirectoryForCurrentUser.path)))
            }
            let nextIndex = index + 1 < sessions.count ? index + 1 : index - 1
            switchWorkspace(to: sessions[nextIndex].id)
        }
        liveWorkspaces.removeValue(forKey: id)
        sessions.removeAll { $0.id == id }
        save()
    }
    @objc private func changeView(_ sender: NSSegmentedControl) {
        guard FileViewMode.allCases.indices.contains(sender.selectedSegment) else { return }
        activePane?.setViewMode(FileViewMode.allCases[sender.selectedSegment])
    }
    @objc func viewIcons() { activePane?.setViewMode(.icons) }
    @objc func viewList() { activePane?.setViewMode(.list) }
    @objc func viewColumns() { activePane?.setViewMode(.columns) }
    @objc func viewGallery() { activePane?.setViewMode(.gallery) }
    func layoutMenu() -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self
        for preset in LayoutPreset.allCases {
            let item = NSMenuItem(title: preset.title, action: #selector(choosePreset(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = preset.rawValue
            item.image = NSImage(systemSymbolName: preset.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let undo = NSMenuItem(title: "Restore Previous Layout", action: #selector(restorePreviousLayout), keyEquivalent: "")
        undo.target = self; undo.isEnabled = previousLayout != nil; menu.addItem(undo)
        return menu
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(restorePreviousLayout) }?.isEnabled = previousLayout != nil
    }
    @objc private func choosePreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = LayoutPreset(rawValue: raw) else { return }
        applyPreset(preset)
    }
    func applyPreset(_ preset: LayoutPreset) {
        guard let active = activePane else { return }
        previousLayout = root.snapshot()
        let available = [active] + root.panes.filter { $0 !== active }
        var index = 0
        func build(_ spec: LayoutSpec) -> LayoutNode {
            switch spec {
            case .pane:
                let pane: FilePane
                if available.indices.contains(index) { pane = available[index] }
                else { pane = makePane(active.directory); pane.restoreSettings(active.settings) }
                index += 1
                return LayoutNode(pane: pane)
            case let .split(vertical, fraction, a, b):
                let node = LayoutNode(build(a), build(b), vertical: vertical); node.fraction = fraction; return node
            }
        }
        let nextRoot = build(preset.spec)
        let removed = available.filter { pane in !nextRoot.panes.contains { $0 === pane } }
        guard confirmClosingTerminals(removed) else { return }
        removed.forEach { $0.stopTerminal() }
        available.forEach { $0.removeFromSuperview() }
        root = nextRoot; rebuild(); activate(active); save()
    }
    @objc func restorePreviousLayout() {
        guard let previousLayout, confirmClosingTerminals(root.panes) else { return }
        root.panes.forEach { $0.stopTerminal() }
        self.previousLayout = root.snapshot()
        root.panes.forEach { $0.removeFromSuperview() }
        root = restore(previousLayout, depth: 0); rebuild(); activate(root.panes[0]); save()
    }
    func confirmClosingTerminals(_ panes: [FilePane]) -> Bool {
        let count = panes.filter { $0.hasTerminal }.count
        guard count > 0 else { return true }
        let alert = NSAlert(); alert.messageText = "End \(count) terminal session(s)?"
        alert.informativeText = "Commands running in these sessions will also end. Return to the file view to keep a terminal session running."
        alert.addButton(withTitle: "End Sessions"); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    func confirmQuitTerminals() -> Bool {
        confirmClosingTerminals(root.panes + liveWorkspaces.values.flatMap { $0.panes })
    }
    func stopAllTerminals() {
        (root.panes + liveWorkspaces.values.flatMap { $0.panes }).forEach { $0.stopTerminal() }
    }
    @objc func splitDirectional(_ sender: NSMenuItem) {
        guard view.window?.attachedSheet == nil else { return }
        splitTowardKey(UInt16(sender.tag))
    }
    func splitTowardKey(_ key: UInt16) {
        guard let direction = PaneDirection.arrow(key) else { return }
        split(vertical: direction == .left || direction == .right, before: direction == .left || direction == .up)
    }
    @objc func splitRight() { split(vertical: true) }
    @objc func splitDown() { split(vertical: false) }
    @objc func closeActive() { closePane() }
    @objc func nextPane() { focusNext() }
    func pinFolders(_ urls: [URL]) { sidebar.pin(urls) }
    @objc func goToFolder() { activePane?.goToFolder() }
    @objc func goBack() { activePane?.back() }
    @objc func goForward() { activePane?.forward() }
    @objc func goUp() { activePane?.up() }
    @objc func refresh() { activePane?.reload() }
    @objc func toggleHidden() { activePane?.toggleHidden() }
    @objc func newFolder() { activePane?.newFolder() }
    @objc func renameFile() { activePane?.renameFile() }
    @objc func trashFiles() { activePane?.trashFiles() }
    @objc func preview() { activePane?.preview() }
}
