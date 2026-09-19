import AppKit

enum PaneDirection {
    case left, down, up, right

    static func from(_ key: String) -> PaneDirection? {
        switch key { case "h": return .left; case "j": return .down; case "k": return .up; case "l": return .right; default: return nil }
    }

    static func arrow(_ keyCode: UInt16) -> PaneDirection? {
        switch keyCode { case 123: return .left; case 124: return .right; case 125: return .down; case 126: return .up; default: return nil }
    }

    // Coordinates are in the workspace canvas (positive y points upward).
    func neighbor(from origin: NSRect, among frames: [NSRect]) -> Int? {
        let horizontal = self == .left || self == .right
        let sign: CGFloat = self == .left || self == .down ? -1 : 1
        return frames.indices.compactMap { index -> (Int, CGFloat)? in
            let frame = frames[index]
            let primary = horizontal ? frame.midX - origin.midX : frame.midY - origin.midY
            guard primary * sign > 1 else { return nil }
            let overlap = horizontal
                ? min(origin.maxY, frame.maxY) - max(origin.minY, frame.minY)
                : min(origin.maxX, frame.maxX) - max(origin.minX, frame.minX)
            let offset = horizontal ? abs(frame.midY - origin.midY) : abs(frame.midX - origin.midX)
            return (index, (overlap > 0 ? 0 : 1_000_000) + abs(primary) + offset)
        }.min { $0.1 < $1.1 }?.0
    }
}

extension FilePane {
    func handleVimKey(_ event: NSEvent) -> Bool {
        guard window?.attachedSheet == nil, let key = event.charactersIgnoringModifiers?.lowercased(),
              let direction = PaneDirection.from(key) else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command {
            activate(); workspace?.focusPane(direction); return true
        }
        guard modifiers.isEmpty else { return false }
        if settings.mode != .columns {
            if direction == .left { up(); return true }
            if direction == .right { enterSelectedFolder(); return true }
        }
        let code: UInt16
        let character: Int
        switch direction {
        case .left: code = 123; character = NSLeftArrowFunctionKey
        case .right: code = 124; character = NSRightArrowFunctionKey
        case .down: code = 125; character = NSDownArrowFunctionKey
        case .up: code = 126; character = NSUpArrowFunctionKey
        }
        guard let scalar = UnicodeScalar(character), let arrow = NSEvent.keyEvent(with: .keyDown,
            location: event.locationInWindow, modifierFlags: [.function, .numericPad], timestamp: event.timestamp,
            windowNumber: event.windowNumber, context: nil, characters: String(scalar),
            charactersIgnoringModifiers: String(scalar), isARepeat: event.isARepeat, keyCode: code) else { return false }
        focusView.keyDown(with: arrow)
        return true
    }

    private func enterSelectedFolder() {
        guard let url = selectedURLs.first else { return }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if values?.isDirectory == true && values?.isPackage != true { navigate(to: url) }
    }
}

extension Workspace {
    @objc func focusDirectionalPane(_ sender: NSMenuItem) {
        guard view.window?.attachedSheet == nil,
              !(view.window?.firstResponder is NSTextView),
              let direction = PaneDirection.from(sender.keyEquivalent) else { return }
        focusPane(direction)
    }
}
