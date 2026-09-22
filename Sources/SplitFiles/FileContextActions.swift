import AppKit
import Darwin
import UniformTypeIdentifiers

extension FilePane {
    func openWithMenu(_ urls: [URL]) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        if let first = urls.first {
            let candidates = NSWorkspace.shared.urlsForApplications(toOpen: first)
            let otherSets = urls.dropFirst().map { Set(NSWorkspace.shared.urlsForApplications(toOpen: $0)) }
            let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: first)
            for app in candidates.filter({ app in otherSets.allSatisfy { $0.contains(app) } }).sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                let name = app.deletingPathExtension().lastPathComponent + (app == defaultApp ? " (Default)" : "")
                let item = NSMenuItem(title: name, action: #selector(openWithApplication(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = (app, urls)
                item.image = NSWorkspace.shared.icon(forFile: app.path); item.image?.size = NSSize(width: 16, height: 16)
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let other = NSMenuItem(title: "Other…", action: #selector(chooseApplication), keyEquivalent: "")
        other.target = self; menu.addItem(other)
        return menu
    }
    @objc func openWithApplication(_ sender: NSMenuItem) {
        guard let (app, urls) = sender.representedObject as? (URL, [URL]) else { return }
        open(urls, with: app)
    }
    private func open(_ urls: [URL], with app: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.showError(error.localizedDescription) } }
        }
    }
    @objc func chooseApplication() {
        guard let window else { return }
        let urls = selectedURLs, panel = NSOpenPanel()
        panel.title = "Choose an Application"; panel.prompt = "Open"
        panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let app = panel.url { self?.open(urls, with: app) }
        }
    }
    @objc func showPackageContents() { if let url = selectedURLs.first { navigate(to: url) } }
    @objc func openSelectedTerminal() {
        if let url = selectedURLs.first { navigate(to: url) }
        openTerminal()
    }
    @objc func renameItems() {
        let urls = selectedURLs
        guard urls.count > 1, let window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = "Rename \(urls.count) Items"
        alert.informativeText = "Replace text in each name. Leave Find empty to add a prefix. Existing files will not be replaced."
        let find = NSTextField(frame: NSRect(x: 0, y: 34, width: 380, height: 24)); find.placeholderString = "Find"
        let replacement = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24)); replacement.placeholderString = "Replace with / Prefix"
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 58)); fields.addSubview(find); fields.addSubview(replacement)
        alert.accessoryView = fields; alert.window.initialFirstResponder = find
        alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let changes = urls.map { source in
                let name = find.stringValue.isEmpty ? replacement.stringValue + source.lastPathComponent : source.lastPathComponent.replacingOccurrences(of: find.stringValue, with: replacement.stringValue)
                return (source, source.deletingLastPathComponent().appendingPathComponent(name), name)
            }
            guard changes.allSatisfy({ !$0.2.isEmpty && $0.2 != "." && $0.2 != ".." && !$0.2.contains("/") && !$0.2.contains(":") && !$0.2.contains("\0") }) else {
                self.showError("Enter valid names without / or :."); return
            }
            self.moveContextItems(changes.map { ($0.0, $0.1) })
        }
    }
    @objc func newFolderWithSelection() {
        let urls = selectedURLs
        guard let parent = urls.first?.deletingLastPathComponent(), urls.allSatisfy({ $0.deletingLastPathComponent() == parent }) else { return }
        prompt(title: "New Folder with Selection", initial: "New Folder", button: "Create") { [weak self] name in
            guard let self else { return }
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0") else { self.showError("Enter a valid folder name."); return }
            let folder = parent.appendingPathComponent(name)
            self.moveContextItems(urls.map { ($0, folder.appendingPathComponent($0.lastPathComponent)) }, creating: folder)
        }
    }
    private func moveContextItems(_ changes: [(URL, URL)], creating folder: URL? = nil) {
        FileOperations.activeCount += 1
        FileOperations.queue.async { [weak self] in
            var failure: Error?
            var createdFolder = false
            do {
                if let folder {
                    guard !FileManager.default.fileExists(atPath: folder.path) else { throw CocoaError(.fileWriteFileExists) }
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                    createdFolder = true
                }
                try ContextFileOperations.moveWithoutReplacing(changes)
            } catch {
                failure = error
                // Only remove our new directory if rollback left it empty.
                if createdFolder, let folder { _ = folder.path.withCString { rmdir($0) } }
            }
            DispatchQueue.main.async {
                FileOperations.activeCount -= 1
                // Follow successful moves even if a later move or rollback failed.
                for (source, destination) in changes where source != destination && !FileManager.default.fileExists(atPath: source.path) && FileManager.default.fileExists(atPath: destination.path) {
                    self?.workspace?.folderRenamed(from: source, to: destination)
                }
                self?.reload()
                if let failure { self?.showError(failure.localizedDescription) }
            }
        }
    }
    @objc func makeAliases() {
        let urls = selectedURLs
        runContextOperation {
            for url in urls { try ContextFileOperations.makeAlias(for: url) }
        }
    }
    @objc func compressSelected() {
        let urls = selectedURLs, folder = directory
        guard !urls.isEmpty else { return }
        runContextOperation { try ContextFileOperations.compress(urls, in: folder) }
    }
    private func runContextOperation(_ action: @escaping () throws -> Void) {
        FileOperations.activeCount += 1
        FileOperations.queue.async { [weak self] in
            var failure: Error?
            do { try action() } catch { failure = error }
            DispatchQueue.main.async {
                FileOperations.activeCount -= 1
                self?.reload()
                if let failure { self?.showError(failure.localizedDescription) }
            }
        }
    }
    @objc func editTags() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        let existing: [Set<String>]
        do { existing = try urls.map { Set(try $0.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []) } }
        catch { showError(error.localizedDescription); return }
        let common = existing.dropFirst().reduce(existing[0]) { $0.intersection($1) }
        prompt(title: urls.count == 1 ? "Tags (comma-separated)" : "Shared Tags (comma-separated)", initial: common.sorted().joined(separator: ", "), button: "Save") { [weak self] text in
            let desired = Set(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            self?.runContextOperation {
                for url in urls {
                    let current = Set(try url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? [])
                    let tags = Array(current.subtracting(common.subtracting(desired)).union(desired)).sorted()
                    try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
                }
            }
        }
    }
}

enum ContextFileOperations {
    static func moveWithoutReplacing(_ changes: [(URL, URL)]) throws {
        let changes = changes.filter { $0.0 != $0.1 }
        let destinations = changes.map { $0.1.standardizedFileURL.path }
        guard Set(destinations).count == destinations.count else { throw CocoaError(.fileWriteFileExists) }
        for (_, destination) in changes {
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        }
        var completed: [(URL, URL)] = []
        do {
            for (source, destination) in changes {
                try FileManager.default.moveItem(at: source, to: destination)
                completed.append((source, destination))
            }
        } catch {
            var failures: [String] = []
            for (source, destination) in completed.reversed() {
                do { try FileManager.default.moveItem(at: destination, to: source) }
                catch { failures.append(destination.path + ": " + error.localizedDescription) }
            }
            if !failures.isEmpty { throw NSError(domain: "Paneo.Move", code: 1, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription + "\nSome items could not be restored:\n" + failures.joined(separator: "\n")]) }
            throw error
        }
    }

    static func makeAlias(for source: URL) throws {
        let candidate = source.deletingLastPathComponent().appendingPathComponent(source.lastPathComponent + " alias")
        let destination = FileOperations.copyDestination(for: candidate, in: candidate.deletingLastPathComponent())
        let data = try source.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("PaneoAlias-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let alias = work.appendingPathComponent("alias")
        try URL.writeBookmarkData(data, to: alias)
        try FileManager.default.moveItem(at: alias, to: destination)
    }
    static func compress(_ urls: [URL], in folder: URL) throws {
        guard !urls.isEmpty else { return }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("PaneoArchive-" + UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let archive = work.appendingPathComponent("result.zip")
        var source = urls[0]
        if urls.count > 1 {
            source = work.appendingPathComponent("items")
            try fm.createDirectory(at: source, withIntermediateDirectories: true)
            for url in urls { try fm.copyItem(at: url, to: FileOperations.copyDestination(for: url, in: source)) }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc"] + (urls.count == 1 ? ["--keepParent"] : []) + [source.path, archive.path]
        let errors = Pipe(); process.standardError = errors
        try process.run()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Paneo.Archive", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(data: errorData, encoding: .utf8) ?? "Unable to create archive."])
        }
        let name = urls.count == 1 ? urls[0].lastPathComponent + ".zip" : "Archive.zip"
        let destination = FileOperations.copyDestination(for: folder.appendingPathComponent(name), in: folder)
        try fm.moveItem(at: archive, to: destination)
    }
}
