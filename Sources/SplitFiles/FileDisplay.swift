import AppKit
import UniformTypeIdentifiers

enum FileViewMode: String, CaseIterable, Codable {
    case icons, list, columns, gallery
    var title: String {
        switch self { case .icons: return "Icons"; case .list: return "List"; case .columns: return "Columns"; case .gallery: return "Gallery" }
    }
    var symbol: String {
        switch self { case .icons: return "square.grid.2x2"; case .list: return "list.bullet"; case .columns: return "rectangle.split.3x1"; case .gallery: return "rectangle.bottomthird.inset.filled" }
    }
}

struct DisplaySettings: Codable {
    var mode: FileViewMode = .list
    var sortKey = "name"
    var ascending = true
    var groupByKind = false
    var foldersFirst = true
}

struct FileGroup {
    let title: String
    let entries: [FileEntry]
}

extension FileEntry {
    var isFolder: Bool { isDirectory && !isPackage }
    var kind: String {
        if isFolder { return "Folders" }
        if isPackage { return "Apps & Packages" }
        // Common text formats remain classifiable even without a LaunchServices
        // registration (for example, during command-line self-tests).
        if ["txt", "text", "md", "markdown", "swift", "py", "js", "ts", "jsx", "tsx", "json", "yaml", "yml", "csv", "log", "sh", "html", "css", "xml"].contains(url.pathExtension.lowercased()) { return "Text & Code" }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return "Other Files" }
        if type.conforms(to: .image) { return "Images" }
        if type.conforms(to: .movie) { return "Videos" }
        if type.conforms(to: .audio) { return "Audio" }
        if type.conforms(to: .pdf) { return "PDF Documents" }
        if type.conforms(to: .text) { return "Text & Code" }
        if type.conforms(to: .archive) { return "Archives" }
        return "Other Documents"
    }
    static func readDirectory(_ directory: URL, hidden: Bool) throws -> [FileEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: hidden ? [] : [.skipsHiddenFiles])
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: keys)
            return FileEntry(url: url, isDirectory: values?.isDirectory ?? false, isPackage: values?.isPackage ?? false, size: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate)
        }
    }
}

enum FileDisplay {
    static func sorted(_ entries: [FileEntry], settings: DisplaySettings) -> [FileEntry] {
        entries.sorted { a, b in
            if settings.foldersFirst && a.isFolder != b.isFolder { return a.isFolder }
            let ascending = settings.ascending
            if settings.sortKey == "size" && a.size != b.size { return ascending ? a.size < b.size : a.size > b.size }
            if settings.sortKey == "date" && a.modified != b.modified { return ascending ? (a.modified ?? .distantPast) < (b.modified ?? .distantPast) : (a.modified ?? .distantPast) > (b.modified ?? .distantPast) }
            if settings.sortKey == "kind" && a.kind != b.kind { return ascending ? a.kind < b.kind : a.kind > b.kind }
            let comparison = a.name.localizedStandardCompare(b.name)
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
    static func groups(_ entries: [FileEntry], enabled: Bool) -> [FileGroup] {
        guard enabled else { return [FileGroup(title: "", entries: entries)] }
        let kinds = ["Folders", "Apps & Packages", "Images", "Videos", "Audio", "PDF Documents", "Text & Code", "Archives", "Other Documents", "Other Files"]
        let grouped = Dictionary(grouping: entries, by: \.kind)
        return kinds.compactMap { kind in grouped[kind].map { FileGroup(title: kind, entries: $0) } }
    }
}
