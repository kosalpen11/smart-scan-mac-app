import SwiftUI

struct GeneralSection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Section("General") {
            Toggle("Open at login", isOn: Binding(
                get: { store.openAtLogin },
                set: { store.setOpenAtLogin($0) }))
            if let message = store.loginItemMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
