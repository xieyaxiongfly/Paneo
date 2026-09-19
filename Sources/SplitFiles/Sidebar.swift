import AppKit

private final class SidebarItem {
    let title: String
    let symbol: String
    let url: URL?
    let children: [SidebarItem]
    init(_ title: String, symbol: String = "folder", url: URL? = nil, children: [SidebarItem] = []) {
        self.title = title; self.symbol = symbol; self.url = url; self.children = children
    }
}

/// A native source list provides Finder-style groups, vibrancy and selection.
final class Sidebar: NSVisualEffectView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    var onNavigate: ((URL) -> Void)?
    var onPinsChanged: (() -> Void)?
    private let outline = NSOutlineView()
    private var groups: [SidebarItem] = []
    private var synchronizing = false
    private var selectedDirectory: URL?
    private var pinnedPaths = UserDefaults.standard.stringArray(forKey: "pinnedFolders") ?? []
    private var pinnedGroup: SidebarItem?

    init() {
        super.init(frame: .zero)
        material = .sidebar
        blendingMode = .behindWindow
        state = .followsWindowActiveState
        let home = FileManager.default.homeDirectoryForCurrentUser
        groups = [SidebarItem("Favorites", children: [
            SidebarItem(home.lastPathComponent, symbol: "house", url: home),
            SidebarItem("Applications", symbol: "square.grid.2x2", url: URL(fileURLWithPath: "/Applications")),
            SidebarItem("Desktop", symbol: "menubar.dock.rectangle", url: home.appendingPathComponent("Desktop")),
            SidebarItem("Documents", symbol: "doc", url: home.appendingPathComponent("Documents")),
            SidebarItem("Downloads", symbol: "arrow.down.circle", url: home.appendingPathComponent("Downloads")),
            SidebarItem("Pictures", symbol: "photo", url: home.appendingPathComponent("Pictures")),
            SidebarItem("Music", symbol: "music.note", url: home.appendingPathComponent("Music"))
        ])]
        let root = URL(fileURLWithPath: "/")
        var locations = [SidebarItem(FileManager.default.displayName(atPath: "/"), symbol: "internaldrive", url: root)]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey], options: .skipHiddenVolumes) ?? []
        for volume in volumes where volume.path != "/" && volume.path.hasPrefix("/Volumes/") {
            locations.append(SidebarItem(FileManager.default.displayName(atPath: volume.path), symbol: "externaldrive", url: volume))
        }
        groups.append(SidebarItem("Locations", children: locations))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("location"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column); outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.backgroundColor = .clear
        outline.rowHeight = 32
        outline.intercellSpacing = NSSize(width: 0, height: 2)
        outline.indentationPerLevel = 12
        outline.floatsGroupRows = false
        outline.focusRingType = .none
        outline.allowsEmptySelection = true
        outline.allowsMultipleSelection = false
        outline.delegate = self; outline.dataSource = self
        outline.target = self; outline.action = #selector(clickedLocation)
        let menu = NSMenu(); menu.delegate = self; outline.menu = menu
        outline.setAccessibilityLabel("Sidebar")
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = outline
        scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
        outline.reloadData()
        groups.forEach { outline.expandItem($0) }
        reloadPins()
        loadCloudFolders(home: home)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func folderRenamed(from source: URL, to destination: URL) {
        pinnedPaths = pinnedPaths.map { FolderRelocation.url(URL(fileURLWithPath: $0), from: source, to: destination).path }
        UserDefaults.standard.set(pinnedPaths, forKey: "pinnedFolders")
        reloadPins()
    }
    func isPinned(_ url: URL) -> Bool { pinnedPaths.contains(url.standardizedFileURL.path) }
    func togglePin(_ url: URL) {
        if isPinned(url) {
            pinnedPaths.removeAll { $0 == url.standardizedFileURL.path }
            UserDefaults.standard.set(pinnedPaths, forKey: "pinnedFolders")
            reloadPins()
        } else { pin([url]) }
    }
    func pin(_ urls: [URL]) {
        for url in urls {
            let path = url.standardizedFileURL.path
            if !pinnedPaths.contains(path) { pinnedPaths.append(path) }
        }
        UserDefaults.standard.set(pinnedPaths, forKey: "pinnedFolders")
        reloadPins()
    }
    private func reloadPins() {
        if let pinnedGroup { groups.removeAll { $0 === pinnedGroup } }
        let group = SidebarItem("Pinned", children: pinnedPaths.map {
            let url = URL(fileURLWithPath: $0)
            return SidebarItem(url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent, symbol: "pin", url: url)
        })
        pinnedGroup = group
        if !pinnedPaths.isEmpty { groups.insert(group, at: 0) }
        outline.reloadData(); outline.expandItem(group)
        select(directory: selectedDirectory)
        onPinsChanged?()
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let item = outline.item(atRow: outline.clickedRow) as? SidebarItem,
              let group = pinnedGroup, group.children.contains(where: { $0 === item }), let url = item.url else { return }
        let remove = NSMenuItem(title: "Unpin", action: #selector(unpin(_:)), keyEquivalent: "")
        remove.target = self; remove.representedObject = url.path; menu.addItem(remove)
    }
    @objc private func unpin(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        pinnedPaths.removeAll { $0 == path }
        UserDefaults.standard.set(pinnedPaths, forKey: "pinnedFolders")
        reloadPins()
    }

    func select(directory: URL?) {
        selectedDirectory = directory
        synchronizing = true
        defer { synchronizing = false }
        guard let directory else { outline.deselectAll(nil); return }
        let path = directory.standardizedFileURL.path
        let items = groups.flatMap(\.children)
        let selected = items.filter { item in
            guard let candidate = item.url?.standardizedFileURL.path else { return false }
            return path == candidate || (candidate != "/" && path.hasPrefix(candidate + "/"))
        }.max { ($0.url?.path.count ?? 0) < ($1.url?.path.count ?? 0) }
        if let selected, outline.row(forItem: selected) >= 0 {
            outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: selected)), byExtendingSelection: false)
        } else { outline.deselectAll(nil) }
    }
    private func loadCloudFolders(home: URL) {
        // File providers may take time to respond; discovery must not block the window.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let manager = FileManager.default
            let cloudRoot = home.appendingPathComponent("Library/CloudStorage")
            var candidates = (try? manager.contentsOfDirectory(at: cloudRoot, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
            candidates += [home.appendingPathComponent("Dropbox"), home.appendingPathComponent("Google Drive"), home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")]
            var seen = Set<String>()
            var folders: [(String, URL)] = []
            for candidate in candidates {
                var directory: ObjCBool = false
                guard manager.fileExists(atPath: candidate.path, isDirectory: &directory), directory.boolValue else { continue }
                let url = candidate.resolvingSymlinksInPath().standardizedFileURL
                guard seen.insert(url.path).inserted else { continue }
                let name = url.lastPathComponent
                let title: String
                if name.hasPrefix("GoogleDrive-") { title = "Google Drive" }
                else if name == "Box-Box" { title = "Box" }
                else if name == "com~apple~CloudDocs" { title = "iCloud Drive" }
                else { title = name }
                folders.append((title, url))
            }
            let counts = Dictionary(grouping: folders, by: { $0.0 }).mapValues(\.count)
            let items = folders.map { title, url in
                SidebarItem(counts[title, default: 0] > 1 ? "\(title) · \(url.lastPathComponent)" : title, symbol: title == "iCloud Drive" ? "icloud" : "externaldrive.badge.icloud", url: url)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            DispatchQueue.main.async { [weak self] in
                guard let self, !items.isEmpty else { return }
                let group = SidebarItem("Cloud Storage", children: items)
                self.groups.insert(group, at: self.groups.count - 1)
                self.outline.reloadData()
                self.outline.expandItem(group)
                self.select(directory: self.selectedDirectory)
            }
        }
    }
    @objc private func clickedLocation() {
        guard !synchronizing, let item = outline.item(atRow: outline.clickedRow) as? SidebarItem, let url = item.url else { return }
        onNavigate?(url)
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SidebarItem)?.children.count ?? groups.count
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SidebarItem)?.children[index] ?? groups[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !(item as! SidebarItem).children.isEmpty }
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { (item as! SidebarItem).url == nil }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { (item as! SidebarItem).url != nil }
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { (item as! SidebarItem).url == nil ? 34 : 32 }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let item = item as! SidebarItem
        if item.url == nil {
            let label = NSTextField(labelWithString: item.title)
            label.font = InterfaceStyle.section; label.textColor = .secondaryLabelColor
            return label
        }
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: item.title)
        label.font = InterfaceStyle.body; label.lineBreakMode = .byTruncatingTail
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        icon.contentTintColor = item.symbol.contains("drive") ? .secondaryLabelColor : .controlAccentColor
        if let url = item.url, let cloud = FolderIcons.cloudImage(for: url) {
            icon.image = cloud; icon.contentTintColor = nil
        } else if item.symbol == "pin", let url = item.url {
            icon.image = FolderIcons.image(for: url); icon.contentTintColor = nil
        }
        for child in [icon, label] { child.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(child) }
        cell.textField = label; cell.imageView = icon; cell.toolTip = item.url?.path
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 19), icon.heightAnchor.constraint(equalToConstant: 19),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5)
        ])
        return cell
    }
}
