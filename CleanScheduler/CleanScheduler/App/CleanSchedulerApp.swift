import SwiftUI

@preconcurrency import UserNotifications

@main
struct CleanSchedulerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore.shared

    var body: some Scene {
        Window("Clean Scheduler", id: "main") {
            MainView()
                .environment(store)
                .frame(minWidth: 560, minHeight: 520)
        }
        .defaultSize(width: 640, height: 680)

        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            Image(systemName: "calendar.badge.clock")
        }
        .menuBarExtraStyle(.window)
    }
}
