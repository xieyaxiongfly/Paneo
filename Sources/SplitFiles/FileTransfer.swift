import AppKit

/// Runs one item at a time, asking before touching an existing destination.
final class FileTransfer {
    enum Choice { case replace, keepBoth, skip, cancel }
    private let sources: [URL]
    private let folder: URL
    private let window: NSWindow
    private let completion: ([String]) -> Void
    private var index = 0
    private var errors: [String] = []
    private var repeatedChoice: Choice?

    init(sources: [URL], folder: URL, window: NSWindow, duplicate: Bool, completion: @escaping ([String]) -> Void) {
        self.sources = sources; self.folder = folder; self.window = window; self.completion = completion
        if duplicate { repeatedChoice = .keepBoth }
    }

    func start() { next() }

    private func next() {
        guard index < sources.count else { completion(errors); return }
        let source = sources[index], destination = folder.appendingPathComponent(sources[index].lastPathComponent)
        FileOperations.queue.async {
            let exists = Self.exists(destination)
            DispatchQueue.main.async {
                if exists {
                    if let choice = self.repeatedChoice, choice != .replace || Self.canReplace(source, destination) {
                        self.perform(choice, source: source, destination: destination)
                    } else { self.ask(source: source, destination: destination) }
                } else { self.perform(nil, source: source, destination: destination) }
            }
        }
    }

    private func ask(source: URL, destination: URL) {
        let alert = NSAlert()
        alert.messageText = "An item named “\(source.lastPathComponent)” already exists."
        alert.informativeText = "Destination: \(folder.path)\nKeep Both gives the incoming item a unique name. Replace replaces the entire existing item, including its contents if it is a folder."
        let replaceAllowed = Self.canReplace(source, destination)
        if !replaceAllowed { alert.informativeText += "\nThis destination is the source itself or contains the source, so it cannot be replaced." }
        // Return should never silently authorize replacement.
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Replace").isEnabled = replaceAllowed
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = sources.count - index > 1
        alert.suppressionButton?.title = "Apply to All Conflicts"
        alert.beginSheetModal(for: window) { response in
            let choice: Choice
            switch response {
            case .alertFirstButtonReturn: choice = .keepBoth
            case .alertSecondButtonReturn: choice = .skip
            case .alertThirdButtonReturn: choice = .replace
            default: choice = .cancel
            }
            if alert.suppressionButton?.state == .on { self.repeatedChoice = choice }
            self.perform(choice, source: source, destination: destination)
        }
    }

    private func perform(_ choice: Choice?, source: URL, destination: URL) {
        if choice == .cancel { completion(errors); return }
        if choice == .skip { index += 1; next(); return }
        FileOperations.queue.async {
            do {
                try Self.copy(source, to: destination, choice: choice)
                DispatchQueue.main.async { self.index += 1; self.next() }
            } catch {
                // A destination may appear after the initial check. Ask rather than overwrite it.
                let collision = choice == nil && (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSFileWriteFileExistsError
                DispatchQueue.main.async {
                    if collision { self.ask(source: source, destination: destination) }
                    else {
                        self.errors.append("\(source.lastPathComponent): \(error.localizedDescription)")
                        self.index += 1; self.next()
                    }
                }
            }
        }
    }

    static func exists(_ url: URL) -> Bool {
        // Includes dangling symlinks, which fileExists(atPath:) follows and misses.
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    static func canReplace(_ source: URL, _ destination: URL) -> Bool {
        let src = source.resolvingSymlinksInPath().standardizedFileURL.path
        let dst = destination.resolvingSymlinksInPath().standardizedFileURL.path
        return src != dst && !src.hasPrefix(dst == "/" ? "/" : dst + "/")
    }

    static func copy(_ source: URL, to destination: URL, choice: Choice?) throws {
        let fm = FileManager.default
        if choice == .skip || choice == .cancel { return }
        if choice == .keepBoth {
            try fm.copyItem(at: source, to: FileOperations.copyDestination(for: destination, in: destination.deletingLastPathComponent()))
            return
        }
        guard choice == .replace else { try fm.copyItem(at: source, to: destination); return }
        guard canReplace(source, destination) else {
            throw NSError(domain: "Paneo.Transfer", code: 1, userInfo: [NSLocalizedDescriptionKey: "An item cannot replace itself or a folder containing it."])
        }
        // Finish copying before displacing the original. Keep a rollback copy until installation succeeds.
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".Paneo-transfer-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        let incoming = staging.appendingPathComponent("incoming"), backup = staging.appendingPathComponent("original")
        var retainBackup = false
        defer { if !retainBackup { try? fm.removeItem(at: staging) } }
        try fm.copyItem(at: source, to: incoming)
        let hadOriginal = exists(destination)
        if hadOriginal { try fm.moveItem(at: destination, to: backup) }
        do { try fm.moveItem(at: incoming, to: destination) }
        catch {
            if hadOriginal {
                do { try fm.moveItem(at: backup, to: destination) }
                catch {
                    retainBackup = true
                    throw NSError(domain: "Paneo.Transfer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Replacement failed. The original is preserved at \(backup.path). Restoration failed: \(error.localizedDescription)"])
                }
            }
            throw error
        }
        do { try fm.removeItem(at: staging) }
        catch {
            retainBackup = true
            throw NSError(domain: "Paneo.Transfer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Replacement succeeded, but its backup could not be removed: \(staging.path). \(error.localizedDescription)"])
        }
    }
}
