import SwiftUI

struct MenuBarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clean Scheduler").font(.headline)

            trashPanel

            Divider()

            if let next = store.nextScheduled {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next: \(next.rule.name)")
                        Text(next.date <= Date() ? "Due now" : Format.when(next.date).capitalizedFirst)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: next.rule.symbol)
                }
            } else {
                Label("No scheduled rules", systemImage: "calendar")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Open Clean Scheduler") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
        .task { await store.refreshTrash() }
    }

    @ViewBuilder
    private var trashPanel: some View {
        HStack {
            Image(systemName: store.trashItems.isEmpty ? "trash" : "trash.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Trash")
                Text(store.trashSummary).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if store.trashBusy {
                ProgressView().controlSize(.small)
            } else if !confirming {
                Button("Empty Trash") { confirming = true }
                    .disabled(store.isTrashKnownEmpty)
            }
        }

        if confirming {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(store.emptyTrashQuestion) \(store.emptyTrashWarning)").font(.callout)
                HStack {
                    Spacer()
                    Button("Cancel") { confirming = false }
                    Button("Empty Trash", role: .destructive) {
                        confirming = false
                        Task { await store.emptyTrash() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }

        if let message = store.trashMessage {
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }
}
