import SwiftUI

struct RuleEditorView: View {
    @State var rule: Rule
    let isNew: Bool
    let onSave: (Rule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choosingFolder = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $rule.name)
                    Picker("Type", selection: $rule.kind) {
                        ForEach(RuleKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                switch rule.kind {
                case .folder: folderOptions
                case .command: toolOptions
                case .trash: trashOptions
                }

                scheduleSection

                Section {
                    Toggle("Require Touch ID or password to clean", isOn: $rule.requireAuth)
                } footer: {
                    Text("You always review what will be removed before anything is cleaned.")
                        .foregroundStyle(.secondary)
                }

                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Rule" : "Save") {
                    var saved = rule
                    saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if saved.kind == .trash { saved.deletePermanently = true }
                    // Don't immediately fire a rule whose schedule was just changed.
                    if !isNew { saved.lastNotified = nil }
                    onSave(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
            .padding(16)
        }
        .frame(width: 500, height: 600)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { rule.folderPath = url.path }
        }
    }

    // MARK: Type options

    private var folderOptions: some View {
        Section("Folder") {
            LabeledContent("Folder") {
                HStack {
                    Text(displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(rule.folderPath.isEmpty ? .secondary : .primary)
                    Button("Choose…") { choosingFolder = true }
                }
            }
            agePicker
            Picker("Remove items by", selection: $rule.deletePermanently) {
                Text("Moving them to the Trash").tag(false)
                Text("Deleting them permanently").tag(true)
            }
            Text("Only the folder's contents are removed, never the folder itself.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var toolOptions: some View {
        Section("Tool") {
            Picker("Cleanup", selection: $rule.preset) {
                ForEach(CommandPreset.allCases) { preset in
                    Label(preset.title, systemImage: preset.symbol).tag(preset)
                }
            }
            Text(rule.preset.summary).font(.callout).foregroundStyle(.secondary)
            LabeledContent("Runs") {
                Text(rule.preset.commandLine).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            }
            LabeledContent("Preview") {
                Text(rule.preset.previewCommandLine).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            }
        }
    }

    private var trashOptions: some View {
        Section("Trash") {
            agePicker
            Text("Age is how long an item has been in the Trash. Items in the Trash are always deleted for good.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var agePicker: some View {
        Picker("Items", selection: $rule.olderThanDays) {
            ForEach(Rule.ageOptions, id: \.self) { Text(Format.age($0)).tag($0) }
        }
    }

    // MARK: Schedule

    private var scheduleSection: some View {
        Section {
            Picker("Repeat", selection: $rule.schedule.frequency) {
                ForEach(ScheduleFrequency.allCases) { Text($0.title).tag($0) }
            }
            if rule.schedule.frequency == .weekly {
                Picker("On", selection: $rule.schedule.weekday) {
                    ForEach(1...7, id: \.self) { Text(Schedule.weekdayName($0)).tag($0) }
                }
            }
            if rule.schedule.frequency == .monthly {
                Picker("On day", selection: $rule.schedule.dayOfMonth) {
                    ForEach(1...28, id: \.self) { Text("\($0)").tag($0) }
                }
            }
            if rule.schedule.frequency != .manual {
                Picker("At", selection: $rule.schedule.hour) {
                    ForEach(0..<24, id: \.self) { Text(Schedule.hourText($0)).tag($0) }
                }
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text(scheduleFooter).foregroundStyle(.secondary)
        }
    }

    private var scheduleFooter: String {
        if rule.schedule.frequency == .manual { return "Runs only when you choose Run Now." }
        guard let next = rule.schedule.nextDate(after: max(Date(), rule.lastRun ?? rule.createdAt)) else { return "" }
        return "Next check \(Format.when(next)). You'll get a notification to review before anything is cleaned."
    }

    // MARK: Validation

    private var displayPath: String {
        guard !rule.folderPath.isEmpty else { return "No folder chosen" }
        return rule.folderPath.replacingOccurrences(of: FileCleaner.home.path, with: "~")
    }

    private var problem: String? {
        if rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give the rule a name."
        }
        switch rule.kind {
        case .folder:
            return FileCleaner.validateFolder(rule.folderPath)
        case .command:
            return CommandRunner.isInstalled(rule.preset.tool) ? nil : rule.preset.tool.missingMessage
        case .trash:
            return nil
        }
    }
}
