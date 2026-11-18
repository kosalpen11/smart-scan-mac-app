# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Cache Cleaner Pro: a macOS (14+) SwiftUI app that scans the user's home folder for caches, logs, developer junk, backups and large files, then moves the chosen items to the Trash or deletes them. It also runs scheduled cleanup rules (folders, Docker/Homebrew/simulator tools, the Trash) and has a one-click Empty Trash. It has a main window, a Settings window and a `MenuBarExtra`.

## Commands

```sh
# Build (Debug)
xcodebuild -project CacheCleanerPro.xcodeproj -scheme CacheCleanerPro -configuration Debug -derivedDataPath build build

# Run the built app
open "build/Build/Products/Debug/Cache Cleaner Pro.app"
```

If the built app is killed at launch (exit 137, `ASP: Security policy would not allow process` in the log), the files carry a `com.apple.quarantine` flag from how the repo was received, and the old `build/` folder passes it to the product. Build with a fresh `-derivedDataPath` instead.

There is no test target and no linter. To check scan/clean logic without the UI, compile `Core/Models/Models.swift` + `Core/Services/ScanEngine.swift` (plus `Features/Schedules/Models/*.swift` and `Features/Schedules/Services/{FileCleaner,CommandRunner,RuleEngine}.swift` for schedules) with a throwaway `main.swift` via `xcrun swiftc -swift-version 6`. Point it at temp folders **inside the home folder**, because `Cleaner.run` refuses any path outside it.

## Project setup constraints

- The project uses a file-system-synchronized group: any file placed in `CacheCleanerPro/` is compiled automatically, so there is no need to edit `project.pbxproj` when adding files.
- Folders: `App/` (entry point, `AppDelegate`, `RootView` sidebar), `Core/{Models,Store,Services}` (shared models, `CleanerStore`, `ScanEngine` + `Cleaner`), `Features/<Feature>/` for each screen (Dashboard, Categories, SmartClean, History, Settings, MenuBar, Schedules). `Assets.xcassets` holds the app icon.
- Schedules need the Apple Events entitlement (`CacheCleanerPro.entitlements`) and `NSAppleEventsUsageDescription` (set as an `INFOPLIST_KEY_` build setting) for the Finder Empty Trash fallback.
- **App Sandbox must stay off.** The app reads `~/Library`, `~/.Trash` etc. via `homeDirectoryForCurrentUser`, which under the sandbox resolves to the app's container.
- Swift 6 language mode **without** default MainActor isolation. Turning on Xcode 26's "Default Actor Isolation = MainActor" breaks the build (model types and `ScanEngine` become main-actor-isolated). Scan/clean functions are marked `nonisolated static` so they run off the main actor.
- Some protected folders (Trash, Mail downloads, iOS backups) need Full Disk Access; without it a category reports `accessDenied` rather than failing.

## Architecture

Data flows one way: `CleanupCategory` (definition) → `ScanEngine` (finds items) → `CleanerStore` (state + selection) → views → `Cleaner` (removal).

- **`CleanupCategory` (Models.swift) is the single source of truth for a category.** Its title, colour, group, `safety`, home-relative `roots`, `scanMode` (`.children` = one row per child, `.wholeRoot` = the folder is one row, `.largeFiles` = recursive size search) and `allowedExtensions` all live on the enum. To add a category, add a case and fill in every switch; the sidebar, dashboard and scan pick it up through `allCases`.
- **Safety level drives defaults.** `.safe` categories are ticked after a scan; `.review` categories are never auto-ticked. `.trash` is `alwaysPermanent`.
- **Smart Clean is rule-based, separate from category ticks.** After each scan, `SmartRules.evaluate` (run off the main actor) turns scan results into `SmartPick`s, each with a reason and a `recommended` flag. Examples: DerivedData whose `info.plist` `WorkspacePath` is gone or `LastAccessedDate` is 30+ days old; all but the newest Device Support version; caches of running apps shown unticked. Folder ages use the newest file inside (`latestModification`), because a folder's own date doesn't reflect nested changes. `SmartCleanView` is a sheet on the main window with its own tick state; the Dashboard and the menu bar open it via `store.openSmartClean()`. It removes items through the same `store.clean(_:)` path. To add a rule, add a `case` in `evaluate`.
- **`CleanerStore`** (`@MainActor @Observable`, injected via `.environment`) holds results, the selection (`Set<URL>`, keyed by item URL across all categories), settings and history. Settings and history are persisted to `UserDefaults` as JSON in their `didSet`. Scans run one task per category in a `TaskGroup`; cleaning runs `Cleaner.run` in a detached task.
- **Schedules (`Features/Schedules/`)** is a separate flow with its own `ScheduleStore` (`@MainActor @Observable`, `.shared`, also injected via `.environment`). A `Rule` (folder | command | trash, saved under `ScheduleRules.v1`) has a `Schedule`; it is due when `schedule.nextDate(after: lastRun ?? createdAt) <= now`. `Scheduler` checks at launch, every 15 minutes and on wake; for a due rule it runs a read-only preview (`RuleEngine.preview`), marks it done if there's nothing to clean, otherwise posts one notification per due date (`lastNotified`) or, if notifications aren't allowed, opens the review window. `ConfirmWindowManager` shows `ConfirmView` in a standalone `NSWindow` (works with only the menu bar open); it asks for Touch ID/password via `Auth` and removes **only the previewed items**. Command presets run with `Process` (no shell) from fixed paths. `AppDelegate` starts the scheduler and handles the notification actions. Scheduled cleanups are written to `CleanerStore.history` with `ruleName` set and no categories. `CleanerStore.shared` exists so the scheduler and review window can reach it.
- **Exclusions ("Never Clean") are enforced in three places, and they must stay consistent:**
  1. `ScanEngine.cleanableItems` skips excluded items. If an item *contains* an excluded path, it lists the item's children instead, recursively.
  2. `Cleaner.run` refuses any job whose path equals, is inside, or contains an excluded path. This guards against stale scan results.
  3. `CleanerStore.exclude` removes overlapping rows from the current results and selection.

  Schedules also hide excluded items from their previews (`RuleEngine.preview`), and remove files through `FileCleaner.remove`, which adds its own checks (item must sit directly in the rule's folder) and then calls `Cleaner.run`.
- **`Cleaner.run` safety net:** it only touches paths inside the home folder and never a protected top-level folder (`~/Documents`, `~/Library`, …). Keep these checks when changing removal code.
