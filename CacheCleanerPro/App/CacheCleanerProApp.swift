import SwiftUI

@main
struct CacheCleanerProApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = CleanerStore.shared
    @State private var schedules = ScheduleStore.shared

    var body: some Scene {
        WindowGroup("Cache Cleaner Pro", id: "main") {
            RootView()
                .environment(store)
                .environment(schedules)
                .frame(minWidth: 920, minHeight: 620)
                .task {
                    if store.settings.scanOnLaunch && !store.hasScanned {
                        await store.scan()
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan") { Task { await store.scan() } }
                    .keyboardShortcut("r")
                    .disabled(store.isBusy)
            }
        }

        Settings {
            SettingsView()
                .environment(store)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(store)
                .environment(schedules)
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)
    }
}
