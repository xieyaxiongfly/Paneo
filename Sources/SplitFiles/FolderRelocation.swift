import Foundation

/// Relocate a folder and its descendants without matching similarly named siblings.
enum FolderRelocation {
    static func url(_ url: URL, from source: URL, to destination: URL) -> URL {
        let path = url.standardizedFileURL.path
        let old = source.standardizedFileURL.path
        if path == old { return destination.standardizedFileURL }
        guard path.hasPrefix(old + "/") else { return url }
        return destination.appendingPathComponent(String(path.dropFirst(old.count + 1)))
    }
}
