import SwiftUI

struct RuleEditorItem: Identifiable {
    var rule: Rule
    var isNew: Bool
    var id: UUID { rule.id }
}

/// The rules list in the main window.
struct RulesSection: View {
    @Binding var editing: RuleEditorItem?
    @Environment(ScheduleStore.self) private var store
    @State private var deleting: Rule?

    var body: some View {
        Section {
            if store.rules.isEmpty {
                ContentUnavailableView {
                    Label("No rules yet", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Add a rule to clean a folder, empty the Trash, or run a tool cleanup on a schedule. You always review before anything is removed.")
                }
            } else {
                ForEach(store.rules) { rule in
                    RuleRow(rule: rule,
                            onEdit: { editing = RuleEditorItem(rule: rule, isNew: false) },
                            onDelete: { deleting = rule })
                }
            }
        } header: {
            HStack {
                Text("Rules")
                Spacer()
                AddRuleMenu { editing = RuleEditorItem(rule: $0, isNew: true) }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
        }
        .alert("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete Rule", role: .destructive) {
                if let deleting { store.delete(deleting) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The rule stops running. No files are touched.")
        }
    }
}

/// "Add Rule" menu: custom folder, Empty Trash, and each tool preset.
struct AddRuleMenu: View {
    let onAdd: (Rule) -> Void

    var body: some View {
        Menu {
            Button { onAdd(.newFolder()) } label: { Label("Custom Folder", systemImage: "folder") }
            Button { onAdd(.newTrash()) } label: { Label("Empty Trash", systemImage: "trash") }
            Divider()
            ForEach(CommandPreset.allCases) { preset in
                Button { onAdd(.newCommand(preset)) } label: { Label(preset.title, systemImage: preset.symbol) }
            }
        } label: {
            Label("Add Rule", systemImage: "plus")
        }
    }
}
