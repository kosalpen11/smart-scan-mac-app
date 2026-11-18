import SwiftUI
import AppKit

struct CategoryView: View {
    @Environment(CleanerStore.self) private var store
    let category: CleanupCategory

    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\CleanupItem.size, order: .reverse)]
    @State private var highlighted: Set<URL> = []
    @State private var confirmClean = false

    private var result: CategoryResult? { store.result(for: category) }

    private var items: [CleanupItem] {
        let base = result?.items ?? []
        let filtered = search.isEmpty ? base : base.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.url.path.localizedCaseInsensitiveContains(search)
        }
        return filtered.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .navigationTitle(category.title)
        .searchable(text: $search, placement: .toolbar, prompt: "Filter \(category.title)")
        .confirmationDialog(
            "Clean \(store.selectedItems(in: category).count) items (\(store.selectedSize(in: category).formattedBytes))?",
            isPresented: $confirmClean
        ) {
            Button(deletesPermanently ? "Delete Permanently" : "Move to Trash", role: .destructive) {
                let urls = Set(store.selectedItems(in: category).map(\.url))
                Task { await store.clean(urls) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletesPermanently
                 ? "These items will be deleted for good. This can't be undone."
                 : "You can put items back from the Trash until you empty it.")
        }
    }

    private var deletesPermanently: Bool {
        category.alwaysPermanent || store.settings.deletePermanently
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: category.symbol)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(category.color.gradient, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title).font(.title2.bold())
                Text(category.subtitle).foregroundStyle(.secondary)
                Label(category.safety.label, systemImage: category.safety == .safe
                      ? "checkmark.shield" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(category.safety.color)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text((result?.totalSize ?? 0).formattedBytes)
                    .font(.system(.title, design: .rounded).bold())
                    .monospacedDigit()
                HStack {
                    Button("Select All") { store.selectAll(in: category, true) }
                    Button("Select None") { store.selectAll(in: category, false) }
                }
                .controlSize(.small)
                .disabled(items.isEmpty || store.isBusy)
            }
        }
        .padding(20)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if result == nil {
            ContentUnavailableView {
                Label("Not scanned yet", systemImage: "magnifyingglass")
            } description: {
                Text("Scan your Mac to see what's here.")
            } actions: {
                Button("Scan") { Task { await store.scan() } }
                    .disabled(store.isBusy)
            }
            .frame(maxHeight: .infinity)
        } else if result?.accessDenied == true {
            ContentUnavailableView {
                Label("macOS is blocking this folder", systemImage: "lock.shield")
            } description: {
                Text("Turn on Full Disk Access for Cache Cleaner Pro, then scan again.")
            } actions: {
                Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
            }
            .frame(maxHeight: .infinity)
        } else if items.isEmpty {
            ContentUnavailableView {
                Label(search.isEmpty ? "All clean" : "No matches",
                      systemImage: search.isEmpty ? "checkmark.seal" : "magnifyingglass")
            } description: {
                Text(search.isEmpty ? "Nothing to remove here." : "Try a different filter.")
            }
            .frame(maxHeight: .infinity)
        } else {
            table
        }
    }

    private var table: some View {
        Table(items, selection: $highlighted, sortOrder: $sortOrder) {
            TableColumn("") { item in
                Toggle("", isOn: store.binding(for: item.url))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .width(24)

            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if category == .largeFiles || category.roots.count > 1 || !isDirectlyInRoot(item) {
                            Text(item.url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
                }
            }

            TableColumn("Size", value: \.size) { item in
                Text(item.size.formattedBytes)
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 90)

            TableColumn("Modified", value: \.modifiedSortKey) { item in
                Text(item.modified?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
        }
        .disabled(store.isBusy)
        .contextMenu(forSelectionType: URL.self) { urls in
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
            }
            Divider()
            Button("Tick for Cleaning") { store.setSelected(urls, true) }
            Button("Untick") { store.setSelected(urls, false) }
            Divider()
            Button("Never Clean \(urls.count == 1 ? "This" : "These")") {
                urls.forEach { store.exclude($0) }
            }
        } primaryAction: { urls in
            NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
        }
    }

    /// False for rows a scan split out of a folder that holds an excluded path.
    private func isDirectlyInRoot(_ item: CleanupItem) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let parent = item.url.deletingLastPathComponent().path
        return category.roots.contains { home.appendingPathComponent($0).path == parent }
            || category.roots.contains { home.appendingPathComponent($0).path == item.url.path }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            let selected = store.selectedItems(in: category)
            Text("\(selected.count) of \(result?.items.count ?? 0) ticked, \(store.selectedSize(in: category).formattedBytes)")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if let message = store.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if store.isBusy {
                ProgressView().controlSize(.small)
            }

            Button {
                confirmClean = true
            } label: {
                Label("Clean \(category.title)", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isBusy || selected.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
