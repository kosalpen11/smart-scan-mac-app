import SwiftUI

/// The main window: Trash panel, rules, history and general settings.
struct MainView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: RuleEditorItem?

    var body: some View {
        Form {
            TrashSection()
            RulesSection(editing: $editing)
            HistorySection()
            GeneralSection()
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AddRuleMenu { editing = RuleEditorItem(rule: $0, isNew: true) }
            }
        }
        .sheet(item: $editing) { item in
            RuleEditorView(rule: item.rule, isNew: item.isNew) { store.save($0) }
        }
        .task { await store.refreshTrash() }
    }
}
