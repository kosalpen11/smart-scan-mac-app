import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(CleanerStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Macintosh HD", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Text("\(store.disk.available.formattedBytes) free")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: store.disk.usedFraction)
                .tint(store.disk.usedFraction > 0.9 ? .red : .accentColor)

            Divider()

            if store.isBusy {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: store.phase == .scanning ? store.progress : nil)
                    Text(store.progressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if store.hasScanned {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.smartRecommendedSize.formattedBytes)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("of junk Smart Clean found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Scan to see how much space you can get back.")
                    .foregroundStyle(.secondary)
            }

            if let message = store.message, !store.isBusy {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Scan") { Task { await store.scan() } }
                    .disabled(store.isBusy)
                Spacer()
                // The preview sheet lives on the main window.
                Button("Smart Clean…") {
                    openWindow(id: "main")
                    NSApp.activate()
                    Task { await store.openSmartClean() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isBusy)
            }

            Divider()

            ScheduleMenuSection()

            Divider()

            HStack {
                Button("Open Cache Cleaner Pro") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .buttonStyle(.link)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.link)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
