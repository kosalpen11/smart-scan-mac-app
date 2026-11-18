import SwiftUI

/// Trash panel in the main window: size, Open, and one-click Empty Trash.
struct TrashSection: View {
    @Environment(AppStore.self) private var store
    @State private var confirmEmptyTrash = false

    var body: some View {
        Section("Trash") {
            HStack(spacing: 12) {
                Image(systemName: store.trashItems.isEmpty ? "trash" : "trash.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                summary
                Spacer()
                if store.trashBusy { ProgressView().controlSize(.small) }
                Button("Open") { SystemLinks.openTrash() }
                Button("Empty Trash…") { confirmEmptyTrash = true }
                    .disabled(store.trashBusy || store.isTrashKnownEmpty)
            }
            if let message = store.trashMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .alert(store.emptyTrashQuestion, isPresented: $confirmEmptyTrash) {
            Button("Empty Trash", role: .destructive) { Task { await store.emptyTrash() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.emptyTrashWarning)
        }
    }

    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch store.trash {
            case .loading:
                Text("Checking the Trash…")
            case .listed(let items):
                Text(items.isEmpty ? "The Trash is empty" : Format.bytes(store.trashSize))
                    .font(.headline)
                if !items.isEmpty {
                    Text(Format.items(items.count)).foregroundStyle(.secondary)
                }
            case .unreadable:
                Text("Size unknown").font(.headline)
                Button("Grant Full Disk Access to see what's in the Trash…") {
                    SystemLinks.openFullDiskAccess()
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }
}
