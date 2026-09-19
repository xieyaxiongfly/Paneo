import AppKit
import UniformTypeIdentifiers

/// Reuse the installed providers' own artwork instead of approximating logos.
enum FolderIcons {
    private static var cache: [String: NSImage] = [:]
    static func cloudImage(for url: URL) -> NSImage? {
        let name = url.lastPathComponent.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let providerRoot = url.deletingLastPathComponent().standardizedFileURL == home.appendingPathComponent("Library/CloudStorage").standardizedFileURL
        let legacyRoot = url.deletingLastPathComponent().standardizedFileURL == home.standardizedFileURL
        if url.standardizedFileURL == home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs").standardizedFileURL {
            return cached("icloud") {
                let symbol = NSImage(systemSymbolName: "icloud.fill", accessibilityDescription: "iCloud Drive")?.withSymbolConfiguration(.init(paletteColors: [.systemBlue])) ?? NSImage()
                return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in symbol.draw(in: rect.insetBy(dx: 0, dy: 2)); return true }
            }
        }
        guard providerRoot || legacyRoot else { return nil }
        let bundle: String
        if name == "google drive" || (providerRoot && name.hasPrefix("googledrive-")) { bundle = "com.google.drivefs" }
        else if name == "dropbox" || (providerRoot && name.hasPrefix("dropbox")) { bundle = "com.getdropbox.dropbox" }
        else if providerRoot && name.hasPrefix("box-") { bundle = "com.box.desktop" }
        else { return nil }
        return cached(bundle) {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return NSWorkspace.shared.icon(for: .folder) }
            return NSWorkspace.shared.icon(forFile: app.path)
        }
    }
    static func image(for url: URL) -> NSImage {
        if let cloud = cloudImage(for: url) { return cloud }
        return cached(url.path == "/" ? "disk" : "folder") {
            url.path == "/" ? NSWorkspace.shared.icon(forFile: "/") : roundedFolder()
        }
    }
    private static func roundedFolder() -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSColor(calibratedRed: 0.23, green: 0.65, blue: 0.92, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 8, width: 7.5, height: 6), xRadius: 2.2, yRadius: 2.2).fill()
            let body = NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: 14, height: 10.5), xRadius: 3, yRadius: 3)
            NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.65, blue: 0.94, alpha: 1), ending: NSColor(calibratedRed: 0.50, green: 0.85, blue: 1, alpha: 1))?.draw(in: body, angle: 90)
            NSColor.white.withAlphaComponent(0.24).setStroke(); body.lineWidth = 0.5; body.stroke()
            return true
        }
    }
    private static func cached(_ key: String, create: () -> NSImage) -> NSImage {
        if let image = cache[key] { return image }
        let image = create().copy() as! NSImage
        image.size = NSSize(width: 16, height: 16); image.isTemplate = false
        cache[key] = image
        return image
    }
}
