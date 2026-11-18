import SwiftUI

struct HistoryView: View {
    @Environment(CleanerStore.self) private var store
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.lifetimeFreed.formattedBytes)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("cleaned in total across \(store.history.count) sessions")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear History") { confirmClear = true }
                    .disabled(store.history.isEmpty)
            }
            .padding(24)

            Divider()

            if store.history.isEmpty {
                ContentUnavailableView(
                    "No cleanups yet",
                    systemImage: "clock",
                    description: Text("Each cleanup you run will be listed here.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(store.history) { record in
                    HStack(spacing: 12) {
                        HStack(spacing: -6) {
                            if record.categories.isEmpty {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Color.accentColor.gradient, in: Circle())
                            }
                            ForEach(record.categories.prefix(4), id: \.self) { category in
                                Image(systemName: category.symbol)
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(category.color.gradient, in: Circle())
                                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                            }
                        }
                        .frame(width: 80, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.date.formatted(date: .abbreviated, time: .shortened))
                            Text(record.ruleName ?? record.categories.map(\.title).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(record.bytes.formattedBytes)
                                .font(.headline)
                                .monospacedDigit()
                            Text("\(record.itemCount) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("History")
        .confirmationDialog("Clear cleanup history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { store.history.removeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes the list. No files are touched.")
        }
    }
}
