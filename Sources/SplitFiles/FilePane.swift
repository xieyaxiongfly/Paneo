import AppKit
import QuickLookUI
import Darwin

struct FileEntry {
    let url: URL
    let isDirectory: Bool
    let isPackage: Bool
    let size: Int64
    let modified: Date?
    var name: String { url.lastPathComponent }
}

final class FileTable: NSTableView {
    weak var pane: FilePane?
    override func mouseDown(with event: NSEvent) { pane?.activate(); super.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) {
        pane?.activate()
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        if row < 0 { deselectAll(nil) }
        super.rightMouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if pane?.handleVimKey(event) == true { return }
        switch event.keyCode {
        case 49: pane?.preview()
        case 36: pane?.renameFile()
        default: super.keyDown(with: event)
        }
    }
    @objc func copy(_ sender: Any?) { pane?.copyFiles() }
    @objc func paste(_ sender: Any?) { pane?.pasteFiles() }
    override func selectAll(_ sender: Any?) { selectAllRows() }
    private func selectAllRows() { selectRowIndexes(IndexSet(integersIn: 0..<numberOfRows), byExtendingSelection: false) }
}

enum FileOperations {
    static let queue = DispatchQueue(label: "local.splitfiles.file-operations", qos: .userInitiated)
    static var activeCount = 0 // Main-thread only; prevents quitting during a copy.
    static func canCopy(_ source: URL, into destination: URL) -> Bool {
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
        let destinationPath = destination.resolvingSymlinksInPath().standardizedFileURL.path
        return destinationPath != sourcePath && !destinationPath.hasPrefix(sourcePath == "/" ? "/" : sourcePath + "/")
    }
    static func copyDestination(for source: URL, in folder: URL) -> URL {
        var candidate = folder.appendingPathComponent(source.lastPathComponent)
        let ext = source.pathExtension
        let base = ext.isEmpty ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = index == 1 ? " copy" : " copy \(index)"
            candidate = folder.appendingPathComponent(base + suffix + (ext.isEmpty ? "" : "." + ext))
            index += 1
        }
        return candidate
    }
}

private enum FileListRow {
    case group(String)
    case file(FileEntry)
    var entry: FileEntry? { if case .file(let entry) = self { return entry }; return nil }
}

final class FilePane: NSView, NSTableViewDataSource, NSTableViewDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate, NSMenuDelegate {
    weak var workspace: Workspace?
    private(set) var directory: URL
    let table = FileTable()
    private var entries: [FileEntry] = []
    private var rows: [FileListRow] = []
    private(set) var settings = DisplaySettings()
    private let content = NSView()
    private var embeddedTerminal: EmbeddedTerminal?
    var hasTerminal: Bool { embeddedTerminal != nil }
    var terminalVisible: Bool { embeddedTerminal.map { !$0.isHidden } ?? false }
    private let listScroll = NSScrollView()
    private let icons = IconPresentation(frame: .zero)
    private let columns = ColumnPresentation(frame: .zero)
    private var sharingPicker: NSSharingServicePicker?
    var focusView: NSView {
        if let terminal = embeddedTerminal, !terminal.isHidden { return terminal.terminal }
        switch settings.mode { case .list: return table; case .columns: return columns.browser; case .icons, .gallery: return icons.collection }
    }
    private var history: [URL] = []
    private var historyIndex = -1
    private var generation = 0
    private var showHidden = false
    private var watcherGeneration = 0
    private var watcher: DispatchSourceFileSystemObject?
    private var reloadWork: DispatchWorkItem?
    private let pathControl = FolderBreadcrumb(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let activeLine = NSView()
    private var backButton: ActionButton!
    private var forwardButton: ActionButton!
    private var hiddenButton: ActionButton!
    private var previewURLs: [URL] = []
    private var operationMessage: String?
    private var loadError: String?
    private var loadingSince: Date?
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .short; return formatter
    }()

    init(directory: URL, workspace: Workspace) {
        self.directory = directory; self.workspace = workspace
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 700))
        autoresizingMask = [.width, .height]
        wantsLayer = true; layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 10; layer?.masksToBounds = true
        buildUI()
        navigate(to: directory)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { watcher?.cancel(); reloadWork?.cancel() }

    private func buildUI() {
        activeLine.wantsLayer = true
        let header = ChromeStack(); header.spacing = 2; header.distribution = .fill
        header.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        backButton = ActionButton("", symbol: "chevron.left", help: "Back · ⌘[") { [weak self] in self?.activate(); self?.back() }
        forwardButton = ActionButton("", symbol: "chevron.right", help: "Forward · ⌘]") { [weak self] in self?.activate(); self?.forward() }
        let up = ActionButton("", symbol: "arrow.up", help: "Enclosing Folder · ⌘↑") { [weak self] in self?.activate(); self?.up() }
        for button in [backButton!, forwardButton!, up] { header.addArrangedSubview(button) }
        pathControl.onNavigate = { [weak self] url in self?.activate(); self?.navigate(to: url) }
        pathControl.setAccessibilityLabel("Folder Path")
        pathControl.setAccessibilityHelp("Click any folder in the path to open it")
        pathControl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(pathControl)
        hiddenButton = ActionButton("", symbol: "eye.slash", help: "Toggle Hidden Files · ⇧⌘.") { [weak self] in self?.activate(); self?.toggleHidden() }
        header.addArrangedSubview(ActionButton("", symbol: "terminal", help: "Open Terminal in Current Folder") { [weak self] in
            self?.activate(); self?.openTerminal()
        })
        header.addArrangedSubview(hiddenButton)
        header.addArrangedSubview(ActionButton("", symbol: "arrow.clockwise", help: "Refresh · ⌘R") { [weak self] in self?.activate(); self?.reload() })
        for case let button as ActionButton in header.arrangedSubviews {
            button.compact = true
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.image = button.image?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            button.isBordered = false
        }
        let scroll = listScroll; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        table.pane = self; table.delegate = self; table.dataSource = self
        table.rowHeight = 26; table.intercellSpacing = NSSize(width: 8, height: 1)
        table.style = .inset; table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true; table.allowsColumnReordering = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.target = self; table.doubleAction = #selector(openSelected)
        for (id, title, width) in [("name", "Name", 260.0), ("date", "Date Modified", 160.0), ("size", "Size", 88.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width
            column.headerCell.font = .systemFont(ofSize: 13, weight: .semibold)
            column.minWidth = id == "name" ? 140 : 60
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            table.addTableColumn(column)
        }
        table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        table.registerForDraggedTypes([.fileURL]); table.setDraggingSourceOperationMask(.copy, forLocal: false); table.setDraggingSourceOperationMask(.copy, forLocal: true)
        let menu = NSMenu(); menu.delegate = self
        for (title, action) in [("Open", #selector(openSelected)), ("Quick Look", #selector(preview)), ("Show in Finder", #selector(reveal)), ("Rename…", #selector(renameFile)), ("Copy", #selector(copyFiles)), ("Paste Items", #selector(pasteFiles)), ("New Folder…", #selector(newFolder)), ("Move to Trash…", #selector(trashFiles))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        table.menu = menu; scroll.documentView = table
        for (title, action) in [("Pin Current Folder to Sidebar", #selector(pinCurrentFolder)), ("Pin Selected Folders to Sidebar", #selector(pinSelectedFolders))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        icons.pane = self; columns.pane = self
        icons.collection.menu = menu; columns.browser.menu = menu
        for child in [scroll, icons, columns] {
            child.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(child)
            NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: content.leadingAnchor), child.trailingAnchor.constraint(equalTo: content.trailingAnchor), child.topAnchor.constraint(equalTo: content.topAnchor), child.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        }
        icons.isHidden = true; columns.isHidden = true
        statusLabel.font = InterfaceStyle.caption; statusLabel.textColor = .secondaryLabelColor; statusLabel.lineBreakMode = .byTruncatingMiddle
        emptyLabel.font = .systemFont(ofSize: 13); emptyLabel.textColor = .secondaryLabelColor; emptyLabel.alignment = .center; emptyLabel.isHidden = true
        for item in [activeLine, header, content, statusLabel, emptyLabel] { item.translatesAutoresizingMaskIntoConstraints = false; addSubview(item) }
        NSLayoutConstraint.activate([
            activeLine.topAnchor.constraint(equalTo: topAnchor), activeLine.leadingAnchor.constraint(equalTo: leadingAnchor), activeLine.trailingAnchor.constraint(equalTo: trailingAnchor), activeLine.heightAnchor.constraint(equalToConstant: 2),
            header.topAnchor.constraint(equalTo: activeLine.bottomAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor), header.trailingAnchor.constraint(equalTo: trailingAnchor), header.heightAnchor.constraint(equalToConstant: InterfaceStyle.paneHeaderHeight),
            content.topAnchor.constraint(equalTo: header.bottomAnchor), content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor), content.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -7),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13), statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10), statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9), statusLabel.heightAnchor.constraint(equalToConstant: 15),
            emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor), emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor), emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -40)
        ])
    }
    override func mouseDown(with event: NSEvent) { activate(); super.mouseDown(with: event) }
    func activate() { workspace?.activate(self) }
    func setActive(_ active: Bool) {
        activeLine.layer?.backgroundColor = (active ? NSColor.controlAccentColor.withAlphaComponent(0.75) : NSColor.separatorColor.withAlphaComponent(0.2)).cgColor
    }
    var selectedURLs: [URL] {
        switch settings.mode {
        case .list: return table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].entry?.url : nil }
        case .columns: return columns.selectedURLs
        case .icons, .gallery: return icons.selectedURLs
        }
    }
    func restoreSettings(_ settings: DisplaySettings) {
        self.settings = settings
        table.sortDescriptors = [NSSortDescriptor(key: settings.sortKey, ascending: settings.ascending)]
        render(selection: [])
    }
    func setViewMode(_ mode: FileViewMode) {
        if terminalVisible { hideTerminal() }
        guard mode != settings.mode else { return }
        let selected = Set(selectedURLs), wasColumns = settings.mode == .columns
        settings.mode = mode
        if mode != .gallery { icons.clearPreview() }
        render(selection: selected)
        if wasColumns { reload(preservingSelection: selected) }
        activate(); workspace?.save()
    }
    private func render(selection: Set<URL>) {
        let groups = FileDisplay.groups(entries, enabled: settings.groupByKind)
        rows = groups.flatMap { group in
            (group.title.isEmpty ? [] : [FileListRow.group(group.title)]) + group.entries.map(FileListRow.file)
        }
        table.reloadData()
        table.selectRowIndexes(IndexSet(rows.indices.filter { rows[$0].entry.map { selection.contains($0.url) } ?? false }), byExtendingSelection: false)
        listScroll.isHidden = settings.mode != .list
        icons.isHidden = settings.mode != .icons && settings.mode != .gallery
        columns.isHidden = settings.mode != .columns
        if !icons.isHidden { icons.display(groups, selection: selection, gallery: settings.mode == .gallery) }
        if !columns.isHidden { columns.display(entries, directory: directory, hidden: showHidden, settings: settings, selection: selection) }
        emptyLabel.isHidden = loadingSince != nil || !entries.isEmpty
        updateStatus()
    }
    func presentationSelectionChanged() { updateStatus(); workspace?.updateControls() }
    func columnDirectoryChanged(_ url: URL) {
        guard url != directory else { return }
        history = Array(history.prefix(historyIndex + 1)); history.append(url); historyIndex = history.count - 1
        directory = url
        pathControl.url = url; pathControl.toolTip = url.path
        backButton.isEnabled = historyIndex > 0; forwardButton.isEnabled = false
        watchDirectory(); workspace?.save()
    }

    func navigate(to url: URL, recordHistory: Bool = true) {
        if terminalVisible { hideTerminal() }
        let url = url.standardizedFileURL
        if recordHistory {
            if historyIndex >= 0 && history[historyIndex] == url { reload(); return }
            history = Array(history.prefix(historyIndex + 1)); history.append(url); historyIndex = history.count - 1
        }
        directory = url; entries = []; rows = []; table.reloadData()
        pathControl.url = url; pathControl.toolTip = url.path
        backButton.isEnabled = historyIndex > 0; forwardButton.isEnabled = historyIndex < history.count - 1
        watchDirectory(); reload(); workspace?.save()
    }
    func back() { guard historyIndex > 0 else { return }; historyIndex -= 1; navigate(to: history[historyIndex], recordHistory: false) }
    func forward() { guard historyIndex + 1 < history.count else { return }; historyIndex += 1; navigate(to: history[historyIndex], recordHistory: false) }
    func up() { navigate(to: directory.deletingLastPathComponent()) }
    func toggleHidden() { showHidden.toggle(); hiddenButton.image = NSImage(systemSymbolName: showHidden ? "eye" : "eye.slash", accessibilityDescription: "Hidden Files"); reload() }

    func reload(preservingSelection: Set<URL>? = nil) {
        generation += 1
        let token = generation, url = directory, hidden = showHidden
        let selected = preservingSelection ?? Set(selectedURLs)
        loadingSince = Date()
        statusLabel.stringValue = operationMessage ?? "Loading…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.generation == token, self.loadingSince != nil else { return }
            self.updateStatus()
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<[FileEntry], Error> = Result {
                try FileEntry.readDirectory(url, hidden: hidden)
            }
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.loadingSince = nil
                switch result {
                case .success(let entries): self.entries = entries; self.loadError = nil
                case .failure(let error): self.entries = []; self.loadError = error.localizedDescription
                }
                self.sortEntries(); self.render(selection: selected)
                self.emptyLabel.stringValue = self.loadError.map { "Unable to read this folder.\n\n\($0)\n\nUse the path bar to open another folder." } ?? "This folder is empty"
                self.emptyLabel.isHidden = !self.entries.isEmpty
                self.updateStatus()
            }
        }
    }
    private func watchDirectory() {
        watcher?.cancel(); watcher = nil
        watcherGeneration += 1
        let token = watcherGeneration, path = directory.path
        // Opening a cloud-backed or permission-protected directory can block.
        // Never let that keep the application's window from appearing.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { return }
            DispatchQueue.main.async {
                guard let self, self.watcherGeneration == token else { close(descriptor); return }
                let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .attrib], queue: .main)
                source.setEventHandler { [weak self] in
                    guard let self else { return }
                    self.reloadWork?.cancel()
                    let work = DispatchWorkItem { [weak self] in self?.reload() }; self.reloadWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
                }
                source.setCancelHandler { close(descriptor) }; source.resume(); self.watcher = source
            }
        }
    }
    private func sortEntries() { entries = FileDisplay.sorted(entries, settings: settings) }
    private func updateStatus() {
        if let loadingSince {
            statusLabel.stringValue = operationMessage ?? (Date().timeIntervalSince(loadingSince) > 5 ? "Waiting for the file system or access permission…" : "Loading…")
            return
        }
        let itemCount = settings.mode == .columns ? columns.visibleItemCount : entries.count
        statusLabel.stringValue = operationMessage ?? (loadError == nil ? "\(itemCount) " + (itemCount == 1 ? "item" : "items") + (!selectedURLs.isEmpty ? " · \(selectedURLs.count) selected" : "") : "Unable to Load")
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { rows[row].entry == nil }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row].entry != nil }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let key = tableColumn?.identifier.rawValue ?? "name"
        guard let entry = rows[row].entry else {
            if case .group(let title) = rows[row], key == "name" {
                let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 12, weight: .semibold); label.textColor = .secondaryLabelColor; return label
            }
            return nil
        }
        let id = NSUserInterfaceItemIdentifier(key)
        if key == "name" {
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView { cell = reused }
            else {
                cell = NSTableCellView(); cell.identifier = id
                let icon = NSImageView(); let label = NSTextField(labelWithString: "")
                icon.translatesAutoresizingMaskIntoConstraints = false; label.translatesAutoresizingMaskIntoConstraints = false
                label.font = InterfaceStyle.body; label.lineBreakMode = .byTruncatingMiddle
                cell.addSubview(icon); cell.addSubview(label); cell.imageView = icon; cell.textField = label
                NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18), label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            }
            cell.textField?.stringValue = entry.name; cell.imageView?.image = NSWorkspace.shared.icon(forFile: entry.url.path); cell.toolTip = entry.url.path
            return cell
        }
        let label = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? NSTextField(labelWithString: "")
        label.identifier = id; label.font = InterfaceStyle.body; label.textColor = .secondaryLabelColor; label.lineBreakMode = .byTruncatingTail
        label.stringValue = key == "size" ? (entry.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)) : entry.modified.map { dateFormatter.string(from: $0) } ?? "—"
        return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) { presentationSelectionChanged() }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        let selected = Set(selectedURLs)
        settings.sortKey = table.sortDescriptors.first?.key ?? "name"
        settings.ascending = table.sortDescriptors.first?.ascending ?? true
        if settings.mode == .columns { reload(preservingSelection: selected) }
        else { sortEntries(); render(selection: selected) }
        workspace?.save()
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? { rows[row].entry.map { $0.url as NSURL } }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        tableView.setDropRow(-1, dropOperation: .above)
        return info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }; activate(); copy(urls); return true
    }
    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            if item.action == #selector(renameFile) { item.isEnabled = selectedURLs.count == 1 }
            else if item.action == #selector(newFolder) || item.action == #selector(pasteFiles) || item.action == #selector(pinCurrentFolder) { item.isEnabled = true }
            else { item.isEnabled = !selectedURLs.isEmpty }
        }
        menu.autoenablesItems = false
    }
    @objc func openSelected() {
        guard !terminalVisible else { return }
        let selected = selectedURLs
        guard !selected.isEmpty else { return }
        if selected.count == 1, let values = try? selected[0].resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]), values.isDirectory == true && values.isPackage != true { navigate(to: selected[0]) }
        else { selected.forEach { if !NSWorkspace.shared.open($0) { showError("Unable to open \($0.lastPathComponent)") } } }
    }
    @objc func reveal() { NSWorkspace.shared.activateFileViewerSelecting(selectedURLs.isEmpty ? [directory] : selectedURLs) }
    func goToFolder() {
        prompt(title: "Go to Folder", initial: directory.path, button: "Go") { [weak self] path in
            let expanded = (path as NSString).expandingTildeInPath
            let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : self?.directory.appendingPathComponent(expanded)
            if let url { self?.navigate(to: url) }
        }
    }
    @objc func newFolder() {
        guard !terminalVisible else { return }
        let target = directory
        prompt(title: "New Folder", initial: "Untitled Folder", button: "Create") { [weak self] name in
            guard let self, self.validName(name) else { return }
            do { try FileManager.default.createDirectory(at: target.appendingPathComponent(name), withIntermediateDirectories: false); self.reload() }
            catch { self.showError(error.localizedDescription) }
        }
    }
    @objc func renameFile() {
        guard !terminalVisible else { return }
        guard selectedURLs.count == 1, let source = selectedURLs.first else { return }
        prompt(title: "Rename", initial: source.lastPathComponent, button: "Rename") { [weak self] name in
            guard let self, self.validName(name), name != source.lastPathComponent else { return }
            do { try FileManager.default.moveItem(at: source, to: source.deletingLastPathComponent().appendingPathComponent(name)); self.reload() }
            catch { self.showError(error.localizedDescription) }
        }
    }
    @objc func copyFiles() {
        guard !terminalVisible else { return }
        guard !selectedURLs.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(selectedURLs.map { $0 as NSURL })
    }
    @objc func pasteFiles() {
        guard !terminalVisible else { return }
        let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty { copy(urls) } else { NSSound.beep() }
    }
    func copy(_ urls: [URL], into target: URL? = nil) {
        let destination = (target ?? directory).resolvingSymlinksInPath().standardizedFileURL
        for url in urls {
            if !FileOperations.canCopy(url, into: destination) {
                showError("A folder cannot be copied into itself or one of its subfolders."); return
            }
        }
        FileOperations.activeCount += 1
        operationMessage = "Copying \(urls.count) items to \(destination.lastPathComponent)…"; updateStatus()
        FileOperations.queue.async {
            var errors: [String] = []
            for url in urls {
                do { try FileManager.default.copyItem(at: url, to: FileOperations.copyDestination(for: url, in: destination)) }
                catch { errors.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            }
            DispatchQueue.main.async { [self] in
                FileOperations.activeCount -= 1; operationMessage = nil; reload()
                if !errors.isEmpty { showError("Some items could not be copied:\n" + errors.joined(separator: "\n")) }
            }
        }
    }
    @objc func trashFiles() {
        guard !terminalVisible else { return }
        let urls = selectedURLs; guard !urls.isEmpty, let window else { return }
        let alert = NSAlert(); alert.messageText = "Move \(urls.count) items to the Trash?"; alert.informativeText = "You can restore them from the Trash in Finder."; alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            for url in urls {
                do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
                catch { self.showError(error.localizedDescription); break }
            }
            self.reload()
        }
    }
    private func validName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0") else { showError("Enter a valid filename without / or :."); return false }; return true
    }
    private func prompt(title: String, initial: String, button: String, completion: @escaping (String) -> Void) {
        guard let window else { return }; activate()
        let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle: button); alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24)); input.stringValue = initial; alert.accessoryView = input
        alert.window.initialFirstResponder = input
        alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { completion(input.stringValue) } }
    }
    func openTerminal() {
        if embeddedTerminal == nil {
            let terminal = EmbeddedTerminal(pane: self, directory: directory)
            embeddedTerminal = terminal
            terminal.translatesAutoresizingMaskIntoConstraints = false; addSubview(terminal)
            NSLayoutConstraint.activate([
                terminal.topAnchor.constraint(equalTo: topAnchor, constant: 2), terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
                terminal.trailingAnchor.constraint(equalTo: trailingAnchor), terminal.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        embeddedTerminal?.isHidden = false
        embeddedTerminal?.terminal.setSurfaceVisible(true)
        activate()
    }
    func hideTerminal() {
        embeddedTerminal?.isHidden = true
        embeddedTerminal?.terminal.setSurfaceVisible(false)
        activate()
    }
    func closeTerminal() {
        guard workspace?.confirmClosingTerminals([self]) == true else { return }
        stopTerminal()
    }
    func stopTerminal() {
        guard let terminal = embeddedTerminal else { return }
        embeddedTerminal = nil; terminal.stop()
        if workspace?.activePane === self { activate() }
    }

    func showError(_ message: String) {
        guard let window else { return }; let alert = NSAlert(); alert.messageText = "Operation Could Not Be Completed"; alert.informativeText = message; alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
    }
    @objc func preview() {
        guard !terminalVisible else { return }
        guard !selectedURLs.isEmpty else { return }; activate(); window?.makeFirstResponder(focusView)
        previewURLs = selectedURLs
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.makeKeyAndOrderFront(nil); panel.reloadData() }
    }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { workspace?.activePane === self }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self; panel.delegate = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURLs[index] as NSURL }

    func sortMenu() -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        let recent = NSMenuItem(title: "Recently Modified", action: #selector(sortByRecent), keyEquivalent: "")
        recent.target = self; recent.state = settings.isRecentFirst ? .on : .off
        recent.toolTip = "Newest first, with files and folders together and no grouping"
        menu.addItem(recent); menu.addItem(.separator())
        let heading = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: ""); heading.isEnabled = false; menu.addItem(heading)
        for (key, title) in [("name", "Name"), ("kind", "Kind"), ("date", "Date Modified"), ("size", "Size")] {
            let item = NSMenuItem(title: title, action: #selector(changeSort(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = key; item.state = settings.sortKey == key ? .on : .off; menu.addItem(item)
        }
        menu.addItem(.separator())
        let reverse = NSMenuItem(title: "Descending", action: #selector(reverseSort), keyEquivalent: ""); reverse.target = self; reverse.state = settings.ascending ? .off : .on; menu.addItem(reverse)
        let folders = NSMenuItem(title: "Folders First", action: #selector(toggleFoldersFirst), keyEquivalent: ""); folders.target = self; folders.state = settings.foldersFirst ? .on : .off; menu.addItem(folders)
        menu.addItem(.separator())
        let grouping = NSMenuItem(title: "Group by Kind", action: #selector(toggleGrouping), keyEquivalent: ""); grouping.target = self; grouping.state = settings.groupByKind ? .on : .off
        grouping.isEnabled = settings.mode != .columns; grouping.toolTip = "Column view follows the folder hierarchy and does not group by kind"; menu.addItem(grouping)
        return menu
    }
    @objc private func sortByRecent() {
        let selected = Set(selectedURLs)
        settings.sortByRecent()
        // Apply once even if the table already has the same date sort descriptor.
        table.delegate = nil
        table.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        table.delegate = self
        if settings.mode == .columns { reload(preservingSelection: selected) }
        else { sortEntries(); render(selection: selected) }
        workspace?.save()
    }
    @objc private func changeSort(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        table.sortDescriptors = [NSSortDescriptor(key: key, ascending: settings.ascending)]
    }
    @objc private func reverseSort() { table.sortDescriptors = [NSSortDescriptor(key: settings.sortKey, ascending: !settings.ascending)] }
    @objc private func toggleFoldersFirst() {
        let selected = Set(selectedURLs); settings.foldersFirst.toggle()
        if settings.mode == .columns { reload(preservingSelection: selected) }
        else { sortEntries(); render(selection: selected) }
        workspace?.save()
    }
    @objc private func toggleGrouping() { let selected = Set(selectedURLs); settings.groupByKind.toggle(); render(selection: selected); workspace?.save() }

    func actionsMenu() -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        for (title, action, enabled) in [
            ("Open", #selector(openSelected), !selectedURLs.isEmpty),
            ("Quick Look", #selector(preview), !selectedURLs.isEmpty),
            ("Get Info…", #selector(fileInfo), !selectedURLs.isEmpty),
            ("Show in Finder", #selector(reveal), true),
            ("Pin Current Folder to Sidebar", #selector(pinCurrentFolder), true),
            ("Pin Selected Folders to Sidebar", #selector(pinSelectedFolders), !selectedURLs.isEmpty),
            ("New Folder…", #selector(newFolder), true),
            ("Rename…", #selector(renameFile), selectedURLs.count == 1),
            ("Duplicate", #selector(duplicateFiles), !selectedURLs.isEmpty),
            ("Copy", #selector(copyFiles), !selectedURLs.isEmpty),
            ("Paste Items", #selector(pasteFiles), NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])),
            ("Copy Path", #selector(copyPaths), true),
            ("Move to Trash…", #selector(trashFiles), !selectedURLs.isEmpty),
            (showHidden ? "Hide Hidden Files" : "Show Hidden Files", #selector(toggleHiddenFromMenu), true)
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; item.isEnabled = enabled; menu.addItem(item)
        }
        return menu
    }
    @objc private func pinCurrentFolder() { workspace?.pinFolders([directory]) }
    @objc private func pinSelectedFolders() {
        let urls = selectedURLs
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let folders = urls.filter {
                let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                return values?.isDirectory == true && values?.isPackage != true
            }
            DispatchQueue.main.async { [weak self] in
                if folders.isEmpty { NSSound.beep() }
                else { self?.workspace?.pinFolders(folders) }
            }
        }
    }
    @objc private func toggleHiddenFromMenu() { toggleHidden() }
    @objc private func duplicateFiles() {
        guard let first = selectedURLs.first else { return }
        copy(selectedURLs, into: first.deletingLastPathComponent())
    }
    @objc private func copyPaths() {
        let urls = selectedURLs.isEmpty ? [directory] : selectedURLs
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }
    @objc private func fileInfo() {
        guard let window, !selectedURLs.isEmpty else { return }
        let urls = selectedURLs
        let details = urls.prefix(12).map { url -> String in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            let size = values?.isDirectory == true ? "Folder" : ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
            let date = values?.contentModificationDate.map { dateFormatter.string(from: $0) } ?? "—"
            return "\(url.lastPathComponent)\n\(url.path)\n\(size) · Modified \(date)"
        }.joined(separator: "\n\n")
        let alert = NSAlert(); alert.messageText = "Info for \(urls.count) Items"; alert.informativeText = details + (urls.count > 12 ? "\n\nShowing only the first 12 items" : "")
        alert.beginSheetModal(for: window)
    }
    func share(from view: NSView) {
        guard !selectedURLs.isEmpty else { NSSound.beep(); return }
        sharingPicker = NSSharingServicePicker(items: selectedURLs)
        sharingPicker?.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}
