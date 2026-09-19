import AppKit
import QuickLookUI
import QuickLookThumbnailing

final class FileCollection: NSCollectionView {
    weak var pane: FilePane?
    override func mouseDown(with event: NSEvent) {
        pane?.activate(); super.mouseDown(with: event)
        if event.clickCount == 2 { pane?.openSelected() }
    }
    override func rightMouseDown(with event: NSEvent) {
        pane?.activate()
        if let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)), !selectionIndexPaths.contains(path) { selectionIndexPaths = [path] }
        pane?.presentationSelectionChanged()
        super.rightMouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if pane?.handleVimKey(event) == true { return }
        switch event.keyCode { case 49: pane?.preview(); case 36: pane?.renameFile(); default: super.keyDown(with: event) }
    }
    @objc func copy(_ sender: Any?) { pane?.copyFiles() }
    @objc func paste(_ sender: Any?) { pane?.pasteFiles() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        pane?.activate(); pane?.copy(urls); return true
    }
}

final class FileIconItem: NSCollectionViewItem {
    private static let thumbnails = NSCache<NSURL, NSImage>()
    private var fileURL: URL?
    private var request: QLThumbnailGenerator.Request?
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 108, height: 108)); view.wantsLayer = true; view.layer?.cornerRadius = 7
        let icon = NSImageView(); icon.imageScaling = .scaleProportionallyUpOrDown
        let label = NSTextField(wrappingLabelWithString: ""); label.font = InterfaceStyle.label; label.alignment = .center
        label.maximumNumberOfLines = 2; label.lineBreakMode = .byTruncatingMiddle
        for child in [icon, label] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        imageView = icon; textField = label
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: view.topAnchor, constant: 5), icon.centerXAnchor.constraint(equalTo: view.centerXAnchor), icon.widthAnchor.constraint(equalToConstant: 60), icon.heightAnchor.constraint(equalToConstant: 60),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 5), label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4), label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4)
        ])
    }
    override var isSelected: Bool { didSet { updateSelection() } }
    private func updateSelection() {
        view.layer?.backgroundColor = (isSelected ? NSColor.selectedContentBackgroundColor : .clear).cgColor
        textField?.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
    }
    func configure(_ entry: FileEntry) {
        _ = view
        if let request { QLThumbnailGenerator.shared.cancel(request) }
        fileURL = entry.url; textField?.stringValue = entry.name; view.toolTip = entry.url.path
        view.setAccessibilityLabel(entry.name)
        imageView?.image = Self.thumbnails.object(forKey: entry.url as NSURL) ?? NSWorkspace.shared.icon(forFile: entry.url.path)
        updateSelection()
        guard !entry.isDirectory, Self.thumbnails.object(forKey: entry.url as NSURL) == nil else { return }
        let request = QLThumbnailGenerator.Request(fileAt: entry.url, size: NSSize(width: 72, height: 72), scale: 2, representationTypes: .thumbnail)
        self.request = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            guard let thumbnail else { return }
            DispatchQueue.main.async {
                Self.thumbnails.countLimit = 300
                Self.thumbnails.setObject(thumbnail.nsImage, forKey: entry.url as NSURL)
                guard self?.fileURL == entry.url else { return }
                self?.imageView?.image = thumbnail.nsImage
            }
        }
    }
    override func prepareForReuse() {
        super.prepareForReuse(); fileURL = nil
        if let request { QLThumbnailGenerator.shared.cancel(request) }; request = nil
    }
}

final class FileGroupHeader: NSView {
    let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame); label.font = .systemFont(ofSize: 12, weight: .semibold); label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false; addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), label.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class IconPresentation: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let collection = FileCollection()
    private let flow = NSCollectionViewFlowLayout()
    private let scroll = NSScrollView()
    private var previewView: QLPreviewView?
    private var groups: [FileGroup] = []
    private var stripHeight: NSLayoutConstraint?
    private var contentConstraints: [NSLayoutConstraint] = []
    private var gallery = false
    weak var pane: FilePane? { didSet { collection.pane = pane } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        flow.itemSize = NSSize(width: 108, height: 108)
        flow.minimumInteritemSpacing = 8; flow.minimumLineSpacing = 14
        flow.sectionInset = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        collection.collectionViewLayout = flow
        collection.isSelectable = true; collection.allowsMultipleSelection = true
        collection.backgroundColors = [.controlBackgroundColor]
        collection.register(FileIconItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("file"))
        collection.register(FileGroupHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: NSUserInterfaceItemIdentifier("group"))
        collection.dataSource = self; collection.delegate = self
        collection.setDraggingSourceOperationMask(.copy, forLocal: true); collection.setDraggingSourceOperationMask(.copy, forLocal: false)
        collection.registerForDraggedTypes([.fileURL])
        collection.setAccessibilityLabel("File Icons")
        scroll.documentView = collection; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
        setGallery(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { previewView?.close() }
    var selectedURLs: [URL] {
        collection.selectionIndexPaths.sorted().compactMap { path in
            guard groups.indices.contains(path.section), groups[path.section].entries.indices.contains(path.item) else { return nil }
            return groups[path.section].entries[path.item].url
        }
    }
    func setGallery(_ gallery: Bool) {
        self.gallery = gallery
        NSLayoutConstraint.deactivate(contentConstraints)
        previewView?.close(); previewView?.removeFromSuperview(); previewView = nil
        contentConstraints = [scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor)]
        if gallery, let preview = QLPreviewView(frame: .zero, style: .normal) {
            preview.shouldCloseWithWindow = false; preview.autostarts = false
            preview.translatesAutoresizingMaskIntoConstraints = false; addSubview(preview); previewView = preview
            contentConstraints += [preview.leadingAnchor.constraint(equalTo: leadingAnchor), preview.trailingAnchor.constraint(equalTo: trailingAnchor), preview.topAnchor.constraint(equalTo: topAnchor), preview.bottomAnchor.constraint(equalTo: scroll.topAnchor), scroll.heightAnchor.constraint(equalToConstant: 132)]
        } else { contentConstraints.append(scroll.topAnchor.constraint(equalTo: topAnchor)) }
        flow.scrollDirection = gallery ? .horizontal : .vertical
        flow.headerReferenceSize = gallery ? .zero : (groups.first?.title.isEmpty == false ? NSSize(width: 100, height: 28) : .zero)
        NSLayoutConstraint.activate(contentConstraints)
        collection.setAccessibilityLabel(gallery ? "Gallery Thumbnails" : "File Icons")
        updatePreview()
    }
    func display(_ groups: [FileGroup], selection: Set<URL>, gallery: Bool) {
        self.groups = groups
        if self.gallery != gallery { setGallery(gallery) }
        flow.headerReferenceSize = !gallery && groups.first?.title.isEmpty == false ? NSSize(width: 100, height: 28) : .zero
        collection.reloadData()
        var paths: Set<IndexPath> = []
        for (section, group) in groups.enumerated() {
            for (item, entry) in group.entries.enumerated() where selection.contains(entry.url) { paths.insert(IndexPath(item: item, section: section)) }
        }
        if gallery && paths.isEmpty, let section = groups.firstIndex(where: { !$0.entries.isEmpty }) { paths = [IndexPath(item: 0, section: section)] }
        collection.selectionIndexPaths = paths
        updatePreview()
    }
    func clearPreview() { previewView?.previewItem = nil }
    private func updatePreview() { previewView?.previewItem = selectedURLs.first.map { $0 as NSURL } }
    func numberOfSections(in collectionView: NSCollectionView) -> Int { groups.count }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { groups[section].entries.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("file"), for: indexPath) as! FileIconItem
        item.configure(groups[indexPath.section].entries[indexPath.item]); return item
    }
    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: NSUserInterfaceItemIdentifier("group"), for: indexPath) as! FileGroupHeader
        header.label.stringValue = groups[indexPath.section].title; return header
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { updatePreview(); pane?.presentationSelectionChanged() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { updatePreview(); pane?.presentationSelectionChanged() }
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? { groups[indexPath.section].entries[indexPath.item].url as NSURL }
}
