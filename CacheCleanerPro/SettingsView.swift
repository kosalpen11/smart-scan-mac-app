import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ExclusionSettings()
                .tabItem { Label("Never Clean", systemImage: "hand.raised") }
            PermissionSettings()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 380)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(CleanerStore.self) private var store

    var body: some View {
        @Bindable var store = store

        Form {
            Section("Cleaning") {
                Toggle("Delete permanently instead of moving to Trash",
                       isOn: $store.settings.deletePermanently)
                Toggle("Include Apple system caches (com.apple.*)",
                       isOn: $store.settings.includeAppleCaches)
                Picker("Large file size", selection: $store.settings.largeFileThresholdMB) {
                    Text("100 MB").tag(100)
                    Text("250 MB").tag(250)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1000)
                    Text("2 GB").tag(2000)
                }
            }

            Section("Startup") {
                Toggle("Scan when the app opens", isOn: $store.settings.scanOnLaunch)
                Toggle("Open at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
            }

            Section {
                Text("Settings take effect on the next scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Exclusions

private struct ExclusionSettings: View {
    @Environment(CleanerStore.self) private var store
    @State private var highlighted: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cache Cleaner Pro skips these files and folders when scanning.")
                .foregroundStyle(.secondary)

            List(selection: $highlighted) {
                ForEach(store.settings.excludedPaths, id: \.self) { path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .tag(path)
                }
            }
            .listStyle(.bordered)
            .overlay {
                if store.settings.excludedPaths.isEmpty {
                    Text("Nothing excluded. Right-click an item in any list and choose Never Clean.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }

            HStack {
                Button("Add…", action: addPaths)
                Button("Remove") {
                    if let highlighted { store.removeExclusion(highlighted) }
                    highlighted = nil
                }
                .disabled(highlighted == nil)
            }
        }
        .padding(20)
    }

    private func addPaths() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Never Clean"
        if panel.runModal() == .OK {
            panel.urls.forEach { store.exclude($0) }
        }
    }
}

// MARK: - Permissions

private struct PermissionSettings: View {
    @Environment(CleanerStore.self) private var store

    var body: some View {
        Form {
            Section("Full Disk Access") {
                HStack {
                    Image(systemName: store.hasFullDiskAccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(store.hasFullDiskAccess ? .green : .orange)
                    Text(store.hasFullDiskAccess ? "Turned on" : "Turned off")
                    Spacer()
                    Button("Check Again") { store.refreshPermissions() }
                }
                Text("Needed to see the Trash, Mail attachments and iPhone backups. Open System Settings, then Privacy & Security, then Full Disk Access, and turn on Cache Cleaner Pro.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open Full Disk Access Settings") {
                    Permissions.openFullDiskAccessSettings()
                }
            }
        }
        .formStyle(.grouped)
    }
}
