import Foundation

private struct TestFailure: Error { let message: String }
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(message: message) }
}

func runSelfTests() throws {
    let fm = FileManager.default
    let temporary = fm.temporaryDirectory.appendingPathComponent("SplitFilesTests-" + UUID().uuidString)
    try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: temporary) }

    let source = temporary.appendingPathComponent("notes.txt")
    try Data("original".utf8).write(to: source)
    let first = FileOperations.copyDestination(for: source, in: temporary)
    try expect(first.lastPathComponent == "notes copy.txt", "First collision suffix")
    try fm.copyItem(at: source, to: first)
    let second = FileOperations.copyDestination(for: source, in: temporary)
    try expect(second.lastPathComponent == "notes copy 2.txt", "Repeated collision suffix")
    try fm.copyItem(at: source, to: second)
    for url in [source, first, second] {
        let content = try String(contentsOf: url)
        try expect(content == "original", "Copy preserves original content")
    }
    print("PASS: conflicting copies preserve originals and create unique destinations")

    let folder = temporary.appendingPathComponent("source")
    let child = folder.appendingPathComponent("child")
    try fm.createDirectory(at: child, withIntermediateDirectories: true)
    let alias = temporary.appendingPathComponent("alias")
    try fm.createSymbolicLink(at: alias, withDestinationURL: child)
    try expect(!FileOperations.canCopy(folder, into: folder), "Reject self copy")
    try expect(!FileOperations.canCopy(folder, into: child), "Reject recursive copy")
    try expect(!FileOperations.canCopy(folder, into: alias), "Reject symlink recursive copy")
    try expect(FileOperations.canCopy(folder, into: temporary), "Allow parent destination")
    try expect(FileOperations.canCopy(folder, into: temporary.appendingPathComponent("source-other")), "Allow similarly named sibling")
    print("PASS: recursive copies rejected, including symlink destinations")

    let layout = SavedNode(vertical: true, fraction: 0.4, children: [SavedNode(path: "/tmp/文件"), SavedNode(vertical: false, fraction: 0.6, children: [SavedNode(path: "/Applications"), SavedNode(path: "/")])])
    let restored = try JSONDecoder().decode(SavedNode.self, from: JSONEncoder().encode(layout))
    try expect(restored.fraction == 0.4, "Restore ratio")
    try expect(restored.children?[0].path == "/tmp/文件", "Restore Unicode path")
    try expect(restored.children?[1].vertical == false, "Restore nested split direction")
    try expect(restored.children?[1].children?.count == 2, "Restore nested panes")
    print("PASS: nested layout, proportions and Unicode paths round-trip")
    let expectedCounts = [1, 2, 2, 4, 6, 6, 3, 3, 3, 3, 3]
    func areas(_ spec: LayoutSpec, area: Double = 1) -> [Double] {
        switch spec {
        case .pane: return [area]
        case let .split(_, fraction, a, b): return areas(a, area: area * fraction) + areas(b, area: area * (1 - fraction))
        }
    }
    for (preset, count) in zip(LayoutPreset.allCases, expectedCounts) {
        try expect(preset.spec.paneCount == count, "Preset pane count: " + preset.title)
        let sizes = areas(preset.spec)
        try expect(abs(sizes.reduce(0, +) - 1) < 0.000001, "Preset fills the window")
        try expect(sizes.allSatisfy { $0 > 0 }, "No collapsed preset pane")
        if [.four, .sixWide, .sixTall].contains(preset) {
            try expect(sizes.allSatisfy { abs($0 - 1 / Double(count)) < 0.000001 }, "Grid panes have equal area")
        }
    }
    print("PASS: all 11 presets have correct pane counts, coverage and grid proportions")

    let files = [
        FileEntry(url: temporary.appendingPathComponent("file10.txt"), isDirectory: false, isPackage: false, size: 10, modified: nil),
        FileEntry(url: temporary.appendingPathComponent("file2.txt"), isDirectory: false, isPackage: false, size: 20, modified: nil),
        FileEntry(url: temporary.appendingPathComponent("folder"), isDirectory: true, isPackage: false, size: 0, modified: nil)
    ]
    let ordered = FileDisplay.sorted(files, settings: DisplaySettings())
    try expect(ordered.map(\.name) == ["folder", "file2.txt", "file10.txt"], "Natural name sort and folders first")
    let sizeSettings = DisplaySettings(mode: .icons, sortKey: "size", ascending: false, groupByKind: true, foldersFirst: false)
    try expect(FileDisplay.sorted(files, settings: sizeSettings).map(\.size) == [20, 10, 0], "Descending size sort")
    var recentSettings = DisplaySettings(mode: .gallery, groupByKind: true)
    recentSettings.sortByRecent()
    let datedFiles = [
        FileEntry(url: temporary.appendingPathComponent("older-folder"), isDirectory: true, isPackage: false, size: 0, modified: Date(timeIntervalSince1970: 100)),
        FileEntry(url: temporary.appendingPathComponent("newest.txt"), isDirectory: false, isPackage: false, size: 10, modified: Date(timeIntervalSince1970: 300)),
        FileEntry(url: temporary.appendingPathComponent("recent-folder"), isDirectory: true, isPackage: false, size: 0, modified: Date(timeIntervalSince1970: 200)),
        FileEntry(url: temporary.appendingPathComponent("unknown.txt"), isDirectory: false, isPackage: false, size: 0, modified: nil)
    ]
    let recentFiles = FileDisplay.sorted(datedFiles, settings: recentSettings)
    try expect(recentFiles.map(\.name) == ["newest.txt", "recent-folder", "older-folder", "unknown.txt"], "Recent sort mixes files and folders by date, with unknown dates last")
    try expect(recentSettings.mode == .gallery && FileDisplay.groups(recentFiles, enabled: recentSettings.groupByKind).count == 1, "Recent sort preserves view mode and removes grouping")
    let restoredRecent = try JSONDecoder().decode(DisplaySettings.self, from: JSONEncoder().encode(recentSettings))
    try expect(restoredRecent.isRecentFirst, "Recent sort persists across launches")
    let groups = FileDisplay.groups(ordered, enabled: true)
    try expect(groups.map(\.title) == ["Folders", "Text & Code"], "Grouping labels")
    try expect(groups.flatMap(\.entries).count == files.count, "Grouping preserves all files")
    let savedDisplay = SavedNode(path: temporary.path, display: sizeSettings)
    let decodedDisplay = try JSONDecoder().decode(SavedNode.self, from: JSONEncoder().encode(savedDisplay))
    try expect(decodedDisplay.display?.mode == .icons && decodedDisplay.display?.groupByKind == true && decodedDisplay.display?.ascending == false, "Display options persist")
    let legacy = try JSONDecoder().decode(SavedNode.self, from: Data("{\"path\":\"/tmp\"}".utf8))
    try expect(legacy.display == nil, "Old saved layouts still load")
    print("PASS: natural sorting, descending sorting, grouping and backwards-compatible display settings")
    let originalFolder = temporary.appendingPathComponent("slides")
    let renamedFolder = temporary.appendingPathComponent("lecture-slides")
    try expect(FolderRelocation.url(originalFolder, from: originalFolder, to: renamedFolder) == renamedFolder, "Renamed folder path follows new name")
    try expect(FolderRelocation.url(originalFolder.appendingPathComponent("week1/notes.pdf"), from: originalFolder, to: renamedFolder) == renamedFolder.appendingPathComponent("week1/notes.pdf"), "Descendant paths follow folder rename")
    let sibling = temporary.appendingPathComponent("slides-backup")
    try expect(FolderRelocation.url(sibling, from: originalFolder, to: renamedFolder) == sibling, "Similarly named siblings remain unchanged")
    print("PASS: renamed folder paths, descendants and sibling boundaries")
    let origin = NSRect(x: 0, y: 100, width: 100, height: 100)
    let neighbors = [NSRect(x: 105, y: 100, width: 100, height: 100), NSRect(x: 0, y: -5, width: 100, height: 100), NSRect(x: 105, y: -5, width: 100, height: 100)]
    try expect(PaneDirection.right.neighbor(from: origin, among: neighbors) == 0, "Right prefers aligned pane over diagonal")
    try expect(PaneDirection.down.neighbor(from: origin, among: neighbors) == 1, "Down respects canvas coordinates")
    try expect(PaneDirection.left.neighbor(from: origin, among: neighbors) == nil, "Outer edge keeps focus")
    try expect(PaneDirection.up.neighbor(from: neighbors[1], among: [origin]) == 0, "Up returns to original pane")
    let tall = NSRect(x: 0, y: 0, width: 100, height: 200)
    try expect(PaneDirection.left.neighbor(from: neighbors[0], among: [tall]) == 0, "Asymmetric split reaches tall adjacent pane")
    print("PASS: directional pane navigation handles grids, edges and asymmetric layouts")
    let contextFolder = temporary.appendingPathComponent("context-actions")
    try fm.createDirectory(at: contextFolder, withIntermediateDirectories: true)
    let document = contextFolder.appendingPathComponent("notes with spaces.txt")
    try Data("context test".utf8).write(to: document)
    try ContextFileOperations.makeAlias(for: document)
    let finderAlias = contextFolder.appendingPathComponent("notes with spaces.txt alias")
    let resolvedAlias = try URL(resolvingAliasFileAt: finderAlias, options: [.withoutUI, .withoutMounting])
    try expect(resolvedAlias.resolvingSymlinksInPath() == document.resolvingSymlinksInPath(), "Finder alias resolves to original")
    try ContextFileOperations.makeAlias(for: document)
    try expect(fm.fileExists(atPath: contextFolder.appendingPathComponent("notes with spaces.txt alias copy").path), "Alias name conflicts preserve existing alias")
    try ContextFileOperations.compress([document], in: contextFolder)
    try ContextFileOperations.compress([document], in: contextFolder)
    try expect(fm.fileExists(atPath: contextFolder.appendingPathComponent("notes with spaces.txt copy.zip").path), "Archive name conflicts preserve existing archive")
    let subfolder = contextFolder.appendingPathComponent("nested")
    try fm.createDirectory(at: subfolder, withIntermediateDirectories: true)
    try Data("nested test".utf8).write(to: subfolder.appendingPathComponent("child.txt"))
    try ContextFileOperations.compress([document, subfolder], in: contextFolder)
    let extracted = contextFolder.appendingPathComponent("extracted")
    let unzip = Process(); unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    unzip.arguments = ["-x", "-k", contextFolder.appendingPathComponent("Archive.zip").path, extracted.path]
    try unzip.run(); unzip.waitUntilExit()
    try expect(unzip.terminationStatus == 0, "Archive extracts successfully")
    let contents = try String(contentsOf: extracted.appendingPathComponent("notes with spaces.txt"))
    let nestedContents = try String(contentsOf: extracted.appendingPathComponent("nested/child.txt"))
    try expect(contents == "context test" && nestedContents == "nested test", "Multiple-item archive preserves names, folders and content")
    try (document as NSURL).setResourceValue(["Paneo Test"], forKey: .tagNamesKey)
    let tags = try document.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
    try expect(tags.contains("Paneo Test"), "Finder tags persist on disk")
    let renamedDocument = contextFolder.appendingPathComponent("renamed.txt")
    try ContextFileOperations.moveWithoutReplacing([(document, renamedDocument)])
    try expect(fm.fileExists(atPath: renamedDocument.path) && !fm.fileExists(atPath: document.path), "Batch move reaches destination")
    do {
        try ContextFileOperations.moveWithoutReplacing([(renamedDocument, document), (contextFolder.appendingPathComponent("missing.txt"), contextFolder.appendingPathComponent("missing-renamed.txt"))])
        throw TestFailure(message: "Missing source should reject batch move")
    } catch is TestFailure { throw TestFailure(message: "Missing source should reject batch move") }
    catch { }
    try expect(fm.fileExists(atPath: renamedDocument.path) && !fm.fileExists(atPath: document.path), "Failed batch rolls back completed moves")
    do {
        try ContextFileOperations.moveWithoutReplacing([(renamedDocument, subfolder)])
        throw TestFailure(message: "Existing destination should reject batch move")
    } catch is TestFailure { throw TestFailure(message: "Existing destination should reject batch move") }
    catch { }
    let renamedContents = try String(contentsOf: renamedDocument)
    try expect(renamedContents == "context test" && fm.fileExists(atPath: subfolder.appendingPathComponent("child.txt").path), "Rejected collision preserves both source and destination")
    print("PASS: Finder aliases, archives, tags and batch-move rollback")
    let transferRoot = temporary.appendingPathComponent("transfer")
    let incomingFolder = transferRoot.appendingPathComponent("incoming")
    let destinationFolder = transferRoot.appendingPathComponent("destination")
    try fm.createDirectory(at: incomingFolder, withIntermediateDirectories: true)
    try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
    let incomingFile = incomingFolder.appendingPathComponent("same.txt")
    let existingFile = destinationFolder.appendingPathComponent("same.txt")
    try Data("new".utf8).write(to: incomingFile)
    try Data("old".utf8).write(to: existingFile)
    do {
        try FileTransfer.copy(incomingFile, to: existingFile, choice: nil)
        throw TestFailure(message: "Unresolved collision must fail")
    } catch is TestFailure { throw TestFailure(message: "Unresolved collision must fail") }
    catch { }
    try FileTransfer.copy(incomingFile, to: existingFile, choice: .skip)
    try FileTransfer.copy(incomingFile, to: existingFile, choice: .cancel)
    var transferContents = try String(contentsOf: existingFile)
    try expect(transferContents == "old", "Skip, cancel and unresolved collisions preserve destination")
    try FileTransfer.copy(incomingFile, to: existingFile, choice: .keepBoth)
    transferContents = try String(contentsOf: destinationFolder.appendingPathComponent("same copy.txt"))
    try expect(transferContents == "new", "Keep Both retains incoming data under a unique name")
    try FileTransfer.copy(incomingFile, to: existingFile, choice: .replace)
    transferContents = try String(contentsOf: existingFile)
    try expect(transferContents == "new" && fm.fileExists(atPath: incomingFile.path), "Replace installs incoming data without deleting the copied source")
    do {
        try FileTransfer.copy(incomingFolder.appendingPathComponent("missing"), to: existingFile, choice: .replace)
        throw TestFailure(message: "Missing source must fail")
    } catch is TestFailure { throw TestFailure(message: "Missing source must fail") }
    catch { }
    transferContents = try String(contentsOf: existingFile)
    try expect(transferContents == "new", "Failed replacement leaves original destination intact")
    try expect(!FileTransfer.canReplace(incomingFile, incomingFile), "Reject self replacement")
    try expect(!FileTransfer.canReplace(incomingFile, incomingFolder), "Reject replacing source ancestor")
    let newDirectory = incomingFolder.appendingPathComponent("Folder")
    let oldDirectory = destinationFolder.appendingPathComponent("Folder")
    try fm.createDirectory(at: newDirectory, withIntermediateDirectories: true)
    try fm.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
    try Data("new child".utf8).write(to: newDirectory.appendingPathComponent("new.txt"))
    try Data("old child".utf8).write(to: oldDirectory.appendingPathComponent("old.txt"))
    try FileTransfer.copy(newDirectory, to: oldDirectory, choice: .replace)
    try expect(fm.fileExists(atPath: oldDirectory.appendingPathComponent("new.txt").path) && !fm.fileExists(atPath: oldDirectory.appendingPathComponent("old.txt").path), "Folder replacement replaces rather than silently merging")
    let dangling = destinationFolder.appendingPathComponent("dangling")
    try fm.createSymbolicLink(atPath: dangling.path, withDestinationPath: "/nonexistent-Paneo-test-target")
    try expect(FileTransfer.exists(dangling), "Detect dangling symlink conflict")
    let remaining = try fm.contentsOfDirectory(atPath: destinationFolder.path)
    try expect(!remaining.contains { $0.hasPrefix(".Paneo-transfer-") }, "No staging leftovers after success or failed source copy")
    print("PASS: transfer conflict choices, folder replacement, failed-copy preservation and self-replacement protection")
    print("All 9 self-test groups passed.")
}
