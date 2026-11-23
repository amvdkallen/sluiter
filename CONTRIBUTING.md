# Contributing to Sluiter

Thanks for helping out! Issues and pull requests are welcome, in English or Dutch.
*Bijdragen mag in het Nederlands of Engels.*

## Build it
Requirements: macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`). No Xcode project, no dependencies.

```bash
./build.sh            # builds Sluiter.app in this folder
./build.sh --install  # also copies it to /Applications and starts it
```

Every new build has a new ad-hoc signature, so macOS forgets the Accessibility permission. Remove Sluiter from *System Settings → Privacy & Security → Accessibility* with **−** and add it again.

## Where things live
| File | What it does |
|---|---|
| `main.swift`, `AppDelegate.swift` | app start, window, menus, keyboard handling |
| `Model.swift` | list state, loading apps/windows/processes, closing |
| `Views.swift` | SwiftUI list, rows, system bar |
| `System.swift` | memory/CPU per process (libproc), hang detection, system stats |
| `BrowserTabs.swift` | browser tabs via AppleScript (Chrome family + Safari) |
| `Settings.swift`, `SettingsView.swift` | preferences window (⌘,) |
| `HotKey.swift` | global shortcut (Carbon) |
| `AlertMonitor.swift` | background notifications |
| `UsageTracker.swift` | "last used" per app |
| `Workspaces.swift` | saved sets of apps |
| `makeicon.swift` | draws the app icon at build time |

## Ground rules
- **Never show or close macOS system processes.** Safety first: the Processes tab filters them out on purpose.
- **Stay local.** No network calls, analytics or accounts.
- **Keyboard first.** Typing filters the list, so new actions go on ⌘-shortcuts, buttons or the context menu.
- Keep it dependency-free and buildable with `swiftc` alone.
- One feature or fix per pull request, and say how you tested it.

## Good places to start
- English translation of the interface (it is Dutch only right now)
- Support for more browsers (Arc, Firefox, Opera)
- A signed and notarized download, so people don't have to build it themselves
