import SwiftUI

/// Menu bar part of Schedules: Trash size with an in-place Empty Trash, and the next scheduled rule.
struct ScheduleMenuSection: View {
    @Environment(ScheduleStore.self) private var schedules
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            trashRow

            if confirming {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(schedules.emptyTrashQuestion) \(schedules.emptyTrashWarning)")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Cancel") { confirming = false }
                        Button("Empty Trash", role: .destructive) {
                            confirming = false
                            Task { await schedules.emptyTrash() }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            if let message = schedules.trashMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            nextRuleRow
        }
        .task { await schedules.refreshTrash() }
    }

    private var trashRow: some View {
        HStack {
            Image(systemName: schedules.trashItems.isEmpty ? "trash" : "trash.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("Trash")
                Text(schedules.trashSummary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if schedules.trashBusy {
                ProgressView().controlSize(.small)
            } else if !confirming {
                Button("Empty Trash") { confirming = true }
                    .disabled(schedules.isTrashKnownEmpty)
            }
        }
    }

    @ViewBuilder
    private var nextRuleRow: some View {
        HStack {
            if let next = schedules.nextScheduled {
                Image(systemName: next.rule.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next: \(next.rule.name)").lineLimit(1)
                    Text(next.date <= Date() ? "Due now" : Format.when(next.date).capitalizedFirst)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("No scheduled cleanups").foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
