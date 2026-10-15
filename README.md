# Space Manager for macOS

A native SwiftUI app that shows what is using your disk and helps you reclaim space.

## Features

- **Square pie chart overview.** A 10×10 grid where each square is 1% of the disk, colored by category
  (Applications, Documents, Photos & Media, Developer, Caches & Logs, Mail & Messages, Trash, Other,
  System and Free). Hover a square to highlight its category; click one to list the biggest space
  consumers in it.
- **Explorer.** A squarified treemap of the scanned folder. Tiles are sized by disk usage and labeled with
  name and size in a high-contrast color. Click a folder tile to open it, click a file to inspect it, and
  use the breadcrumb bar to go back up. A "Largest here" list sits next to the map.
- **Largest Files.** A filterable table of the 500 biggest files and apps, with multi-select delete.
- **Cleanup.** Finds space that can be reclaimed and shows how much each category would save:
  - *Safe to delete:* app caches, logs & crash reports, Trash, Xcode DerivedData, device support files,
    simulator caches, package manager caches (npm, Gradle, Cargo, pip…), Mail attachment copies.
  - *Review first:* installers (`.dmg`, `.pkg`, …) in Downloads, Xcode archives, iPhone/iPad backups and
    leftovers of apps that are no longer installed.
- **Delete with leftovers.** Deleting an app also finds what it left in `~/Library` (Application Support,
  Caches, Preferences, Containers, Group Containers, Saved Application State, Logs, cookies, WebKit data,
  LaunchAgents). Choose which leftovers to remove and whether to move everything to the Trash or delete it
  right away.
- **Safety.** System folders and top-level user folders (`/System`, `~/Library`, `~/Documents`, …) are
  never deleted, and nothing is removed without confirmation.

## Design

The UI follows the current macOS design language: Liquid Glass surfaces on macOS 26 and later (with a
translucent material fallback on macOS 14–15), SF Symbols, a sidebar split view, and a bright palette.
Every chart color has its label color (black or white) chosen by WCAG contrast so text on tiles stays
readable in light and dark mode.

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later (Xcode 26 enables Liquid Glass)

## Build & run

```bash
# Run directly
swift run MacSpaceManager

# Or build a double-clickable app bundle in ./build
./scripts/build-app.sh
open "build/Space Manager.app"

# Tests for the scanning, layout, cleanup and deletion logic
swift test
```

You can also open `Package.swift` in Xcode and run the `MacSpaceManager` scheme.

### Full Disk Access

macOS protects folders such as Mail, Safari and app containers. To measure them, add the app (or Terminal,
when using `swift run`) in **System Settings › Privacy & Security › Full Disk Access**. The app shows a
banner with a shortcut when access is missing.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/SpaceCore` | UI-independent logic: parallel disk scanner, squarified treemap and square-pie layout, usage categories, cleanup rules, leftover finder, safe file remover |
| `Sources/MacSpaceManager` | SwiftUI app: model, theme, Overview, Explorer, Largest Files, Cleanup and delete sheet |
| `Tests/SpaceCoreTests` | Unit tests for `SpaceCore` |
| `scripts/build-app.sh` | Packages the executable into `Space Manager.app` |
