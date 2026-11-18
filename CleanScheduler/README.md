# Clean Scheduler

macOS 14+ menu bar app for scheduled cleanups (folders, Docker/Homebrew/simulator presets, the Trash) and one-click Empty Trash. Nothing is ever removed without a review window and, by default, Touch ID or the account password.

```sh
# from this folder
xcodebuild -project CleanScheduler.xcodeproj -scheme CleanScheduler -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/Clean Scheduler.app"
```

App Sandbox is off. Without Full Disk Access the Trash can't be listed, so Empty Trash falls back to asking Finder to empty everything (Apple Events entitlement + `NSAppleEventsUsageDescription`).

## Layout

The `CleanScheduler/` source folder is a file-system-synchronized group: new files are compiled automatically.

```
App/                 entry point (Window + MenuBarExtra), AppDelegate (scheduler start, notification actions)
Core/Models/         Rule, Schedule, CommandPreset, CleanPreview, RuleResult, CleanError
Core/Store/          AppStore (@MainActor @Observable): rules, history, Trash state, persistence
Core/Format.swift    byte/date/count formatting
Services/            nonisolated file + process work: FileCleaner, CommandRunner, Auth, FinderTrash, LoginItem, SystemLinks
Features/Main/       main window composition
Features/Trash/      Trash panel
Features/Rules/      rule list, row, editor sheet, RuleEngine (preview + perform)
Features/Scheduler/  15-min/wake/launch checks, notifications
Features/Confirm/    standalone review window (NSWindow + NSHostingController)
Features/History/    history list
Features/Settings/   Open at login
Features/MenuBar/    menu bar window
```

## Safety rules

- Folder rules: the folder must be inside home and not a protected folder (home itself, Library, Documents, Desktop, Pictures, Music, Movies, Applications, Application Support, Containers, `.ssh`, `.gnupg`, Keychains, Docker data, Trash).
- `FileCleaner.remove` deletes only the items from the preview, only directly inside the rule's folder, only inside home, and never a top-level home folder. Symlinks are removed, never followed.
- Trash items are always deleted for good; folder items go to the Trash unless the rule says otherwise.
