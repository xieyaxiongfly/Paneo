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
    let groups = FileDisplay.groups(ordered, enabled: true)
    try expect(groups.map(\.title) == ["Folders", "Text & Code"], "Grouping labels")
    try expect(groups.flatMap(\.entries).count == files.count, "Grouping preserves all files")
    let savedDisplay = SavedNode(path: temporary.path, display: sizeSettings)
    let decodedDisplay = try JSONDecoder().decode(SavedNode.self, from: JSONEncoder().encode(savedDisplay))
    try expect(decodedDisplay.display?.mode == .icons && decodedDisplay.display?.groupByKind == true && decodedDisplay.display?.ascending == false, "Display options persist")
    let legacy = try JSONDecoder().decode(SavedNode.self, from: Data("{\"path\":\"/tmp\"}".utf8))
    try expect(legacy.display == nil, "Old saved layouts still load")
    print("PASS: natural sorting, descending sorting, grouping and backwards-compatible display settings")
    let origin = NSRect(x: 0, y: 100, width: 100, height: 100)
    let neighbors = [NSRect(x: 105, y: 100, width: 100, height: 100), NSRect(x: 0, y: -5, width: 100, height: 100), NSRect(x: 105, y: -5, width: 100, height: 100)]
    try expect(PaneDirection.right.neighbor(from: origin, among: neighbors) == 0, "Right prefers aligned pane over diagonal")
    try expect(PaneDirection.down.neighbor(from: origin, among: neighbors) == 1, "Down respects canvas coordinates")
    try expect(PaneDirection.left.neighbor(from: origin, among: neighbors) == nil, "Outer edge keeps focus")
    try expect(PaneDirection.up.neighbor(from: neighbors[1], among: [origin]) == 0, "Up returns to original pane")
    let tall = NSRect(x: 0, y: 0, width: 100, height: 200)
    try expect(PaneDirection.left.neighbor(from: neighbors[0], among: [tall]) == 0, "Asymmetric split reaches tall adjacent pane")
    print("PASS: directional pane navigation handles grids, edges and asymmetric layouts")
    print("All 6 self-test groups passed.")
}
