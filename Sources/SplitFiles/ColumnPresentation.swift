import AppKit

final class FileBrowser: NSBrowser {
    weak var pane: FilePane?
    override func mouseDown(with event: NSEvent) {
        pane?.activate()
        super.mouseDown(with: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        pane?.activate()
        var row = 0, column = 0
        if getRow(&row, column: &column, for: convert(event.locationInWindow, from: nil)) {
            if !(selectedRowIndexes(inColumn: column)?.contains(row) ?? false) { selectRow(row, inColumn: column) }
        } else { selectionIndexPaths = [] }
        pane?.presentationSelectionChanged()
        super.rightMouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if pane?.handleFileDeleteKey(event) == true { return }
        if pane?.handleVimKey(event) == true { return }
        switch event.keyCode { case 49: pane?.preview(); case 36: pane?.renameFile(); default: super.keyDown(with: event) }
    }
    @objc func copy(_ sender: Any?) { pane?.copyFiles() }
    @objc func paste(_ sender: Any?) { pane?.pasteFiles() }
}

private final class ColumnNode: NSObject {
    let entry: FileEntry
    var children: [ColumnNode]?
    var loading = false
    init(_ entry: FileEntry) { self.entry = entry; super.init() }
}

final class ColumnPresentation: NSView, NSBrowserDelegate {
    let browser = FileBrowser()
    weak var pane: FilePane? { didSet { browser.pane = pane } }
    private var root: ColumnNode?
    private var renamingURL: URL?
    private var generation = 0
    private var showsHiddenFiles = false
    private var settings = DisplaySettings()
    override init(frame: NSRect) {
        super.init(frame: frame)
        browser.delegate = self; browser.target = self; browser.action = #selector(selectionChanged); browser.doubleAction = #selector(openSelection)
        browser.isTitled = false; browser.hasHorizontalScroller = true
        browser.minColumnWidth = 180; browser.columnResizingType = .userColumnResizing; browser.maxVisibleColumns = 20
        browser.allowsMultipleSelection = true; browser.allowsEmptySelection = true
        browser.rowHeight = 30; browser.autohidesScroller = true
        browser.setAccessibilityLabel("File Columns")
        browser.setDraggingSourceOperationMask(.copy, forLocal: true); browser.setDraggingSourceOperationMask(.copy, forLocal: false)
        browser.registerForDraggedTypes([.fileURL])
        browser.translatesAutoresizingMaskIntoConstraints = false; addSubview(browser)
        NSLayoutConstraint.activate([browser.leadingAnchor.constraint(equalTo: leadingAnchor), browser.trailingAnchor.constraint(equalTo: trailingAnchor), browser.topAnchor.constraint(equalTo: topAnchor), browser.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    var selectedURLs: [URL] { browser.selectionIndexPaths.compactMap { (browser.item(at: $0) as? ColumnNode)?.entry.url } }
    var visibleItemCount: Int {
        if let selected = browser.selectionIndexPath.flatMap({ browser.item(at: $0) as? ColumnNode }), selected.entry.isFolder { return selected.children?.count ?? 0 }
        return (browser.parentForItems(inColumn: max(0, browser.selectedColumn)) as? ColumnNode)?.children?.count ?? root?.children?.count ?? 0
    }
    func display(_ entries: [FileEntry], directory: URL, hidden: Bool, settings: DisplaySettings, selection: Set<URL>) {
        generation += 1; self.showsHiddenFiles = hidden; self.settings = settings
        let root = ColumnNode(FileEntry(url: directory, isDirectory: true, isPackage: false, size: 0, modified: nil))
        root.children = entries.map(ColumnNode.init); self.root = root
        browser.loadColumnZero()
        let paths = entries.enumerated().compactMap { selection.contains($0.element.url) ? IndexPath(index: $0.offset) : nil }
        if !paths.isEmpty { browser.selectionIndexPaths = paths; synchronizeDirectoryFromSelection() }
    }
    func setRenamingURL(_ url: URL?) {
        let previous = renamingURL
        renamingURL = url
        let selection = browser.selectionIndexPaths
        for column in 0...max(0, browser.lastColumn) {
            guard let parent = browser.parentForItems(inColumn: column) as? ColumnNode,
                  (parent.children ?? []).contains(where: { $0.entry.url == previous || $0.entry.url == url }) else { continue }
            browser.reloadColumn(column)
        }
        browser.selectionIndexPaths = selection
    }

    func rootItem(for browser: NSBrowser) -> Any? { root }
    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? ColumnNode else { return 0 }
        if node.children == nil && !node.loading && node.entry.isFolder { load(node) }
        return node.children?.count ?? 0
    }
    private func load(_ node: ColumnNode) {
        node.loading = true
        let generation = self.generation, hidden = self.showsHiddenFiles, settings = self.settings
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try FileDisplay.sorted(FileEntry.readDirectory(node.entry.url, hidden: hidden), settings: settings) }
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                node.loading = false
                switch result {
                case .success(let entries): node.children = entries.map(ColumnNode.init)
                case .failure(let error): node.children = []; self.pane?.showError(error.localizedDescription)
                }
                for column in 0...max(0, self.browser.lastColumn) {
                    if self.browser.parentForItems(inColumn: column) as? ColumnNode === node { self.browser.reloadColumn(column) }
                }
                self.pane?.presentationSelectionChanged()
            }
        }
    }
    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any { (item as! ColumnNode).children![index] }
    func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool { (item as? ColumnNode).map { !$0.entry.isFolder } ?? false }
    func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? {
        guard let node = item as? ColumnNode else { return nil }
        return node.entry.url == renamingURL ? "" : node.entry.name
    }
    func browser(_ browser: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
        guard let node = browser.item(atRow: row, inColumn: column) as? ColumnNode, let cell = cell as? NSBrowserCell else { return }
        cell.image = NSWorkspace.shared.icon(forFile: node.entry.url.path); cell.image?.size = NSSize(width: 18, height: 18)
        cell.font = InterfaceStyle.body; cell.lineBreakMode = .byTruncatingMiddle
        cell.stringValue = node.entry.url == renamingURL ? "" : node.entry.name
    }
    @objc private func selectionChanged() {
        pane?.activate()
        synchronizeDirectoryFromSelection()
    }
    private func synchronizeDirectoryFromSelection() {
        let selected = browser.selectionIndexPaths.compactMap { browser.item(at: $0) as? ColumnNode }
        if selected.count == 1, let node = selected.first, node.entry.isFolder { pane?.columnDirectoryChanged(node.entry.url) }
        else if let parent = browser.parentForItems(inColumn: max(0, browser.selectedColumn)) as? ColumnNode { pane?.columnDirectoryChanged(parent.entry.url) }
        pane?.presentationSelectionChanged()
    }
    @objc private func openSelection() {
        pane?.openSelected()
    }
    func browser(_ browser: NSBrowser, writeRowsWith rowIndexes: IndexSet, inColumn column: Int, to pasteboard: NSPasteboard) -> Bool {
        let urls = rowIndexes.compactMap { (browser.item(atRow: $0, inColumn: column) as? ColumnNode)?.entry.url as NSURL? }
        pasteboard.clearContents(); return pasteboard.writeObjects(urls)
    }
    func browser(_ browser: NSBrowser, validateDrop info: NSDraggingInfo, proposedRow row: UnsafeMutablePointer<Int>, column: UnsafeMutablePointer<Int>, dropOperation: UnsafeMutablePointer<NSBrowser.DropOperation>) -> NSDragOperation {
        row.pointee = -1; dropOperation.pointee = .on
        return info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    func browser(_ browser: NSBrowser, acceptDrop info: NSDraggingInfo, atRow row: Int, column: Int, dropOperation: NSBrowser.DropOperation) -> Bool {
        guard let destination = browser.parentForItems(inColumn: column) as? ColumnNode else { return false }
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        pane?.activate(); pane?.copy(urls, into: destination.entry.url); return true
    }
}
