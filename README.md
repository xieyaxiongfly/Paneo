<p align="center">
  <img src="Assets/Paneo-logo.png" width="144" alt="Paneo logo">
</p>

<h1 align="center">Paneo</h1>
<p align="center">A native macOS file manager with split panes, workspaces, and embedded terminals.</p>

Paneo brings terminal-style split layouts to file browsing. Open multiple folders in one window, work independently in each pane, and switch a pane into a terminal without losing your place.

Built with Swift and AppKit. Paneo implements its own file browser and uses macOS APIs for file icons, Quick Look, sharing, and the Trash. Its embedded terminal uses the Ghostty engine through GhosttyTerminal.

## Features

- **Flexible split panes:** nested horizontal and vertical splits, draggable dividers, and up to eight panes per workspace.
- **Layout presets:** eleven layouts, including two columns, two rows, four- and six-pane grids, and asymmetric layouts.
- **Workspaces:** one-click switching, optional names, close buttons, and automatic restoration of folders, layouts, and view settings.
- **Four file views:** icons, list, columns, and gallery, with sorting and grouping controls.
- **Clickable paths:** rounded folder breadcrumbs, cloud-provider icons, and an overflow menu for narrow panes.
- **Sidebar shortcuts:** favorites, pinned folders, and locally synced Google Drive, Dropbox, Box, and iCloud Drive folders when available.
- **Embedded terminals:** open a terminal in a pane's current folder; return to files while keeping the session running.
- **Keyboard navigation:** Vim-style file selection, directional pane switching, and directional splitting.
- **File operations:** create folders, rename, copy, duplicate, paste, drag-and-drop copying, share, preview, and move to Trash.

## Requirements

- macOS 13 or later to run.
- A **Swift 6.0 or newer** toolchain to build, required by the pinned terminal dependency. Recent Apple Command Line Tools or Xcode can provide it.
- Internet access for the first build to fetch Swift package dependencies and their artifacts.

Check your toolchain with `swift --version`. Builds target the current machine's architecture; the locally tested package is Apple Silicon (`arm64`). Intel builds have not been verified.

## Build and install

```sh
git clone git@github.com:xieyaxiongfly/Paneo.git
cd Paneo
bash scripts/build.sh
open dist/Paneo.app
```

To install, quit Paneo and drag `dist/Paneo.app` into **Applications**, then launch that copy. Existing preferences are preserved.

The build script bundles terminal resources and license notices, then applies an ad-hoc signature. These are local development builds, not Developer ID-signed or Apple-notarized releases. Packaging as a DMG does not change that signing status.

### Create a DMG

```sh
bash scripts/build-dmg.sh
```

The output is `dist/Paneo-<version>-<architecture>.dmg`, containing Paneo.app and an Applications shortcut. Open the image, drag Paneo into Applications, and eject the image before launching the installed app.

To package an existing build:

```sh
bash scripts/build-dmg.sh --skip-build
```

Generated apps and disk images are excluded from Git. A release binary can be distributed separately through GitHub Releases.

## Using workspaces and terminals

Click **+** to create an unnamed workspace from the current folder layout. Unnamed workspaces display only their numbered icon. Right-click a workspace to name or rename it. A fresh installation starts with **Default**.

Each pane has its own directory, navigation history, selection, and view settings. Layouts and folders persist across launches. Pinned sidebar folders are shared across workspaces.

Click a pane's terminal icon to replace its file view with a terminal in the current directory. The folder button returns to files and keeps the terminal running. The terminal's **×** ends its session. Switching workspaces preserves running sessions; restarting Paneo does not restore processes.

A workspace's **×** closes it immediately when it has no terminals. If it contains terminal sessions, including hidden sessions, Paneo asks before ending them and their running tasks. Closing the last workspace leaves a new empty workspace.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Split right / down | `⌘D` / `⇧⌘D` |
| Split left / right / up / down | `⌃←` / `⌃→` / `⌃↑` / `⌃↓` |
| Focus left / below / above / right | `⌘H` / `⌘J` / `⌘K` / `⌘L` |
| Next pane | `⌃Tab` |
| Close current pane | `⇧⌘W` |
| Select previous / next item | `k` / `j` |
| Parent folder / enter selected folder | `h` / `l` |
| Icons / list / columns / gallery | `⌘1` / `⌘2` / `⌘3` / `⌘4` |
| Go to folder | `⇧⌘G` |
| Back / forward | `⌘[` / `⌘]` |
| Enclosing folder | `⌘↑` |
| Open selected item | `⌘↓` or double-click |
| Quick Look | `Space` / `⌘Y` |
| Rename | `Return` |
| New folder | `⇧⌘N` |
| Copy / paste copies | `⌘C` / `⌘V` |
| Move to Trash | `⌘Delete` |
| Refresh | `⌘R` |
| Toggle hidden files | `⇧⌘.` |

Vim keys apply to file views, not text fields. In column view, `h` and `l` navigate between columns. `⌘H` focuses the left pane; Hide Paneo remains available in the application menu. macOS Mission Control shortcuts may take precedence over Control-arrow splits; adjust those assignments in System Settings if needed.

## Development

```sh
# Build the app and run the existing self-checks.
bash scripts/build.sh
dist/Paneo.app/Contents/MacOS/SplitFiles --self-test

# Verify the packaged signature.
codesign --verify --deep --strict dist/Paneo.app

# Regenerate the macOS icon from the source artwork.
bash scripts/build-icon.sh
```

The six self-test groups cover copy conflicts, recursive-copy protection, saved-layout round trips, all eleven layout presets, sorting/grouping settings, and directional pane navigation. UI changes also need manual verification in the app.

### Repository layout

```text
Assets/                 App artwork and third-party license notices
Sources/SplitFiles/     Swift/AppKit application and self-checks
scripts/                App, icon, and DMG build scripts
Package.swift           Swift package definition
Package.resolved        Pinned dependency versions
```

The internal package/executable name remains `SplitFiles`, and the application identifier remains `local.splitfiles.app`, to retain compatibility with existing settings. The product name is **Paneo**. Preferences are stored locally using UserDefaults; they are not part of this repository.

The build script adjusts SwiftPM's generated resource accessor so GhosttyTerminal resources resolve inside the signed macOS application bundle. Use the script when creating an app bundle.

## Current limitations

Paneo is an early prototype. It does not currently support file moves/cut, file-operation undo, search, file tags, copy cancellation, or byte-level copy progress. Undo/Redo menu items apply to text editing only.

Copying and dropping files creates copies, leaves originals in place, and adds a ` copy` suffix on name conflicts. Interrupted copies can leave incomplete destinations. Cloud placeholder files, network volumes, and very large directories have not been comprehensively tested. Cloud entries use locally synced folders, not cloud-service APIs.

Paneo does not embed Finder or inherit all Finder extensions. macOS may request permission to access protected folders such as Desktop and Documents.

## Acknowledgments

The embedded terminal is provided by [libghostty-spm](https://github.com/Lakr233/libghostty-spm), using [Ghostty](https://github.com/ghostty-org/ghostty), with [MSDisplayLink](https://github.com/Lakr233/MSDisplayLink). Third-party license notices are retained in [Assets/Licenses](Assets/Licenses) and included in app bundles.

Logo source and design provenance are documented in [Assets/brand.md](Assets/brand.md).
