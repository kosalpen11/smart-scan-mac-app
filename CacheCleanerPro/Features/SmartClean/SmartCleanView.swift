import SwiftUI
import AppKit

/// Preview of what Smart Clean picked and why, before anything is removed.
struct SmartCleanView: View {
    @Environment(CleanerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var ticked: Set<URL> = []

    private var picks: [SmartPick] { store.smartPicks }

    private var tickedSize: Int64 {
        picks.filter { ticked.contains($0.id) }.reduce(0) { $0 + $1.item.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            ticked = Set(picks.filter(\.recommended).map(\.id))
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Junk Clean").font(.title2.bold())
                Text("Picked item by item, with the reason for each. Untick anything you want to keep.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(store.smartRecommendedSize.formattedBytes)
                .font(.system(.title, design: .rounded).bold())
                .monospacedDigit()
        }
        .padding(20)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if picks.isEmpty {
            ContentUnavailableView {
                Label("No junk found", systemImage: "checkmark.seal")
            } description: {
                Text("Nothing matched the Smart Clean rules. Browse the categories to clean by hand.")
            }
            .frame(maxHeight: .infinity)
        } else {
            Table(picks) {
                TableColumn("") { pick in
                    Toggle("", isOn: Binding(
                        get: { ticked.contains(pick.id) },
                        set: { isOn in
                            if isOn { ticked.insert(pick.id) } else { ticked.remove(pick.id) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }
                .width(24)

                TableColumn("Item") { pick in
                    HStack(spacing: 8) {
                        Image(systemName: pick.category.symbol)
                            .foregroundStyle(pick.category.color)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pick.item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(pick.category.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                TableColumn("Size") { pick in
                    Text(pick.item.size.formattedBytes)
                        .monospacedDigit()
                }
                .width(min: 80, ideal: 90)

                TableColumn("Why") { pick in
                    Text(pick.reason)
                        .foregroundStyle(pick.recommended ? .secondary : Color.orange)
                        .lineLimit(1)
                }
                .width(min: 160, ideal: 240)
            }
            .contextMenu(forSelectionType: URL.self) { urls in
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("\(ticked.count) of \(picks.count) ticked")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(store.settings.deletePermanently
                 ? "Items will be deleted for good."
                 : "Items go to the Trash, so you can put them back.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button {
                let urls = ticked
                dismiss()
                Task { await store.clean(urls) }
            } label: {
                Label(store.settings.deletePermanently
                      ? "Delete \(tickedSize.formattedBytes)"
                      : "Move \(tickedSize.formattedBytes) to Trash",
                      systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(store.isBusy || ticked.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
