import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var workspace: Workspace!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: iconURL) { NSApp.applicationIconImage = icon }
        workspace = Workspace()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Paneo"
        window.minSize = NSSize(width: 820, height: 480)
        window.contentViewController = workspace
        window.setContentSize(NSSize(width: 1240, height: 780))
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SplitFiles.mainWindow")
        if !window.setFrameUsingName("SplitFiles.mainWindow") || window.frame.height < 480 {
            window.setContentSize(NSSize(width: 1240, height: 780)); window.center()
        }
        setupMenus()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(workspace.activePane?.focusView)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func setupMenus() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); item.title = title
            let submenu = NSMenu(title: title); item.submenu = submenu; main.addItem(item); return submenu
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.keyEquivalentModifierMask = modifiers; item.target = target; menu.addItem(item)
        }
        let app = menu("Paneo")
        item(app, "About Paneo", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        app.addItem(.separator())
        item(app, "Hide Paneo", #selector(NSApplication.hide(_:)), target: NSApp)
        item(app, "Quit Paneo", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = menu("File")
        item(file, "New Folder…", #selector(Workspace.newFolder), "n", [.command, .shift], target: workspace)
        item(file, "Rename…", #selector(Workspace.renameFile), target: workspace)
        item(file, "Quick Look", #selector(Workspace.preview), "y", target: workspace)
        item(file, "Move to Trash…", #selector(Workspace.trashFiles), String(UnicodeScalar(NSDeleteCharacter)!), target: workspace)
        file.addItem(.separator())
        item(file, "Close Window", #selector(NSWindow.performClose(_:)), "w")
        let edit = menu("Edit")
        item(edit, "Undo", Selector(("undo:")), "z")
        item(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        item(edit, "Cut Text", #selector(NSText.cut(_:)), "x")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        let display = menu("View")
        item(display, "Icons", #selector(Workspace.viewIcons), "1", target: workspace)
        item(display, "List", #selector(Workspace.viewList), "2", target: workspace)
        item(display, "Columns", #selector(Workspace.viewColumns), "3", target: workspace)
        item(display, "Gallery", #selector(Workspace.viewGallery), "4", target: workspace)
        let layout = menu("Pane")
        item(layout, "Split Right", #selector(Workspace.splitRight), "d", target: workspace)
        item(layout, "Split Down", #selector(Workspace.splitDown), "d", [.command, .shift], target: workspace)
        item(layout, "Close Current Pane", #selector(Workspace.closeActive), "w", [.command, .shift], target: workspace)
        item(layout, "Next Pane", #selector(Workspace.nextPane), "\t", .control, target: workspace)
        for (title, key) in [("Focus Left Pane", "h"), ("Focus Pane Below", "j"), ("Focus Pane Above", "k"), ("Focus Right Pane", "l")] {
            item(layout, title, #selector(Workspace.focusDirectionalPane(_:)), key, target: workspace)
        }
        for (title, key, code) in [("Split Left", NSLeftArrowFunctionKey, 123), ("Split Right", NSRightArrowFunctionKey, 124), ("Split Down", NSDownArrowFunctionKey, 125), ("Split Up", NSUpArrowFunctionKey, 126)] {
            let split = NSMenuItem(title: title, action: #selector(Workspace.splitDirectional(_:)), keyEquivalent: String(UnicodeScalar(key)!))
            split.keyEquivalentModifierMask = .control; split.tag = code; split.target = workspace; layout.addItem(split)
        }
        layout.addItem(.separator())
        let presets = NSMenuItem(title: "Layout Presets", action: nil, keyEquivalent: "")
        presets.submenu = workspace.layoutMenu(); layout.addItem(presets)
        item(layout, "Restore Previous Layout", #selector(Workspace.restorePreviousLayout), target: workspace)
        let go = menu("Go")
        item(go, "Go to Folder…", #selector(Workspace.goToFolder), "g", [.command, .shift], target: workspace)
        item(go, "Back", #selector(Workspace.goBack), "[", target: workspace)
        item(go, "Forward", #selector(Workspace.goForward), "]", target: workspace)
        item(go, "Enclosing Folder", #selector(Workspace.goUp), String(UnicodeScalar(NSUpArrowFunctionKey)!), target: workspace)
        item(go, "Open Selected Items", #selector(FilePane.openSelected), String(UnicodeScalar(NSDownArrowFunctionKey)!))
        item(go, "Refresh", #selector(Workspace.refresh), "r", target: workspace)
        item(go, "Toggle Hidden Files", #selector(Workspace.toggleHidden), ".", [.command, .shift], target: workspace)
        NSApp.mainMenu = main
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { canClose() }
    private func canClose() -> Bool {
        if FileOperations.activeCount > 0 {
            let alert = NSAlert(); alert.messageText = "File Operation in Progress"; alert.informativeText = "Please wait for file operations to finish before quitting."; alert.runModal(); return false
        }
        guard workspace.confirmQuitTerminals() else { return false }
        workspace.save(); workspace.stopAllTerminals(); return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { canClose() ? .terminateNow : .terminateCancel }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

if CommandLine.arguments.contains("--self-test") {
    do { try runSelfTests(); exit(0) }
    catch { fputs("Self-test failed: \(error)\n", stderr); exit(1) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
