import SwiftUI

/// The "Schedules" page in the sidebar: Trash panel and scheduled cleanup rules.
struct SchedulesView: View {
    @Environment(ScheduleStore.self) private var schedules
    @State private var editing: RuleEditorItem?

    var body: some View {
        Form {
            TrashSection()
            RulesSection(editing: $editing)
            Section {
                Text("Cleanups you run here are listed in History.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Schedules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AddRuleMenu { editing = RuleEditorItem(rule: $0, isNew: true) }
            }
        }
        .sheet(item: $editing) { item in
            RuleEditorView(rule: item.rule, isNew: item.isNew) { schedules.save($0) }
        }
        .task { await schedules.refreshTrash() }
    }
}
