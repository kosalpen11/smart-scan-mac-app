import SwiftUI

struct RuleRow: View {
    let rule: Rule
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rule.symbol)
                .font(.title3)
                .foregroundStyle(rule.isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(rule.name).font(.headline)
                    if rule.requireAuth {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Touch ID or password required to clean")
                    }
                }
                Text(scheduleText).font(.callout).foregroundStyle(.secondary)
                if let result = rule.lastResult {
                    Label {
                        Text("\(Format.when(result.date).capitalizedFirst): \(result.message)").lineLimit(2)
                    } icon: {
                        Image(systemName: result.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(result.succeeded ? .green : .orange)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Run Now") { ConfirmWindowManager.shared.show(ruleID: rule.id) }

            Toggle("Enabled", isOn: Binding(
                get: { rule.isEnabled },
                set: { on in store.update(rule.id) { $0.isEnabled = on } }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)

            Menu {
                Button("Edit…", action: onEdit)
                Divider()
                Button("Delete…", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Run Now") { ConfirmWindowManager.shared.show(ruleID: rule.id) }
            Button("Edit…", action: onEdit)
            Button("Delete…", role: .destructive, action: onDelete)
        }
    }

    private var scheduleText: String {
        guard rule.isEnabled else { return "\(rule.schedule.description) · Off" }
        guard rule.schedule.frequency != .manual else { return "Runs only when you choose Run Now" }
        guard let next = rule.nextRun else { return rule.schedule.description }
        let nextText = next <= Date() ? "due now" : "next \(Format.when(next))"
        return "\(rule.schedule.description) · \(nextText)"
    }
}
