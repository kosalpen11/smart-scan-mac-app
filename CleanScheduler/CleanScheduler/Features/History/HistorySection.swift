import SwiftUI

/// Recent cleanups: date, bytes freed, rule name.
struct HistorySection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Section {
            if store.history.isEmpty {
                Text("Nothing cleaned yet.").foregroundStyle(.secondary)
            } else {
                ForEach(store.history.prefix(10)) { entry in
                    HStack {
                        Text(entry.ruleName)
                        Spacer()
                        Text(entry.bytesFreed > 0 ? Format.bytes(entry.bytesFreed) : "—")
                            .monospacedDigit()
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .trailing)
                    }
                }
            }
        } header: {
            HStack {
                Text("History")
                Spacer()
                if !store.history.isEmpty {
                    Button("Clear") { store.clearHistory() }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
        }
    }
}
