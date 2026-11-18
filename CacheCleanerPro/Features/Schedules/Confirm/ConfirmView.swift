import SwiftUI

struct ConfirmView: View {
    let ruleID: UUID
    let close: () -> Void

    @Environment(ScheduleStore.self) private var store

    private enum Phase {
        case loading
        case ready(CleanPreview)
        case nothing(String)
        case failed(String)
        case cleaning
        case done(RuleResult)
    }

    @State private var phase: Phase = .loading
    @State private var authMessage: String?

    private var rule: Rule? { store.rule(id: ruleID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let rule {
                header(rule)
                content(rule)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                if let authMessage {
                    Label(authMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                buttons(rule)
            } else {
                Text("This rule no longer exists.")
                HStack { Spacer(); Button("Close", action: close).keyboardShortcut(.defaultAction) }
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { await load() }
    }

    // MARK: Pieces

    private func header(_ rule: Rule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rule.symbol)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(.headline)
                Text(subtitle(rule)).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(_ rule: Rule) -> String {
        switch rule.kind {
        case .folder: "\(rule.folderURL.path.replacingOccurrences(of: FileCleaner.home.path, with: "~")) · \(Format.age(rule.olderThanDays))"
        case .trash: rule.olderThanDays > 0 ? "Items in the Trash for over \(rule.olderThanDays) days" : "Everything in the Trash"
        case .command: rule.preset.commandLine
        }
    }

    @ViewBuilder
    private func content(_ rule: Rule) -> some View {
        switch phase {
        case .loading:
            HStack { ProgressView().controlSize(.small); Text("Checking what can be cleaned…") }
        case .cleaning:
            HStack { ProgressView().controlSize(.small); Text("Cleaning…") }
        case .nothing(let message):
            Label(message, systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .ready(let preview):
            previewView(rule, preview)
        case .done(let result):
            VStack(alignment: .leading, spacing: 6) {
                Label(result.succeeded ? "Done" : "Finished with problems",
                      systemImage: result.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(result.succeeded ? .green : .orange)
                if result.bytesFreed > 0 { Text("Freed \(Format.bytes(result.bytesFreed)).") }
                Text(result.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func previewView(_ rule: Rule, _ preview: CleanPreview) -> some View {
        switch preview.content {
        case .items(let items):
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Format.items(items.count)) · \(Format.bytes(preview.totalSize))")
                    .font(.title3.weight(.semibold))
                VStack(spacing: 4) {
                    ForEach(items.prefix(6)) { item in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable().frame(width: 16, height: 16)
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Format.bytes(item.size)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                    }
                    if items.count > 6 {
                        Text("and \(items.count - 6) more")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                destinationNote(preview.permanent)
            }
        case .commandOutput(let output):
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview (\(rule.preset.previewCommandLine))").font(.callout).foregroundStyle(.secondary)
                ScrollView {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                Text(rule.preset.summary + " This can't be undone.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .trashUnreadable:
            VStack(alignment: .leading, spacing: 8) {
                Label("Cache Cleaner Pro can't read the Trash", systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.headline)
                Text(rule.olderThanDays > 0
                     ? "Without Full Disk Access it can't check how long items have been in the Trash. Cleaning now asks Finder to empty everything in the Trash, not just items older than \(rule.olderThanDays) days."
                     : "Cleaning asks Finder to empty everything in the Trash.")
                    .font(.callout)
                Button("Open Full Disk Access Settings…") { Permissions.openFullDiskAccessSettings() }
                    .buttonStyle(.link)
                destinationNote(true)
            }
        }
    }

    private func destinationNote(_ permanent: Bool) -> some View {
        Label(permanent ? "These items will be deleted for good. This can't be undone."
                        : "These items will be moved to the Trash.",
              systemImage: permanent ? "exclamationmark.octagon" : "trash")
            .font(.callout)
            .foregroundStyle(permanent ? .red : .secondary)
    }

    @ViewBuilder
    private func buttons(_ rule: Rule) -> some View {
        HStack {
            switch phase {
            case .done, .nothing, .failed:
                Spacer()
                Button("Close", action: close).keyboardShortcut(.defaultAction)
            default:
                Button("Skip This Time") {
                    store.skip(rule.id)
                    close()
                }
                .disabled(isBusy)
                Spacer()
                Button("Cancel", role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isBusy)
                Button {
                    Task { await clean(rule) }
                } label: {
                    if rule.requireAuth {
                        Label(Auth.cleanButtonTitle, systemImage: Auth.hasTouchID ? "touchid" : "lock")
                    } else {
                        Text("Clean")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canClean)
            }
        }
    }

    private var isBusy: Bool {
        switch phase {
        case .loading, .cleaning: true
        default: false
        }
    }

    private var canClean: Bool {
        if case .ready(let preview) = phase { return preview.hasWork }
        return false
    }

    // MARK: Actions

    private func load() async {
        guard let rule else { return }
        do {
            let preview = try await store.preview(rule)
            if preview.hasWork {
                phase = .ready(preview)
            } else {
                store.markDone(rule.id, message: "Nothing to clean.")
                phase = .nothing("Nothing to clean right now.")
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func clean(_ rule: Rule) async {
        guard case .ready(let preview) = phase else { return }
        authMessage = nil

        if rule.requireAuth {
            let reason: String = switch preview.content {
            case .items(let items): "clean \(Format.items(items.count)) for “\(rule.name)”"
            default: "run “\(rule.name)”"
            }
            switch await Auth.authenticate(reason: reason) {
            case .success: break
            case .cancelled: return
            case .failed(let message):
                authMessage = message
                return
            }
        }

        phase = .cleaning
        let result = await store.clean(rule, preview: preview)
        phase = .done(result)
    }
}
