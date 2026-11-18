import SwiftUI

enum Route: Hashable {
    case dashboard
    case history
    case schedules
    case category(CleanupCategory)
}

struct RootView: View {
    @Environment(CleanerStore.self) private var store
    @State private var route: Route? = .dashboard

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            List(selection: $route) {
                Section("Overview") {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                        .tag(Route.dashboard)
                    Label("History", systemImage: "clock.arrow.circlepath")
                        .tag(Route.history)
                    Label("Schedules", systemImage: "calendar.badge.clock")
                        .tag(Route.schedules)
                }
                ForEach(CategoryGroup.allCases) { group in
                    Section(group.rawValue) {
                        ForEach(CleanupCategory.allCases.filter { $0.group == group }) { category in
                            SidebarRow(category: category)
                                .tag(Route.category(category))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            switch route ?? .dashboard {
            case .dashboard:
                DashboardView(route: $route)
            case .history:
                HistoryView()
            case .schedules:
                SchedulesView()
            case .category(let category):
                CategoryView(category: category)
                    .id(category)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.scan() }
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .help("Scan again (⌘R)")
                .disabled(store.isBusy)
            }
        }
        .sheet(isPresented: $store.showSmartClean) {
            SmartCleanView()
                .environment(store)
        }
    }
}

struct SidebarRow: View {
    @Environment(CleanerStore.self) private var store
    let category: CleanupCategory

    var body: some View {
        Label {
            HStack {
                Text(category.title)
                Spacer()
                if let size = store.result(for: category)?.totalSize, size > 0 {
                    Text(size.formattedBytes)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: category.symbol)
                .foregroundStyle(category.color)
        }
    }
}
