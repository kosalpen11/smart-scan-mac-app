import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(CleanerStore.self) private var store
    @Binding var route: Route?
    @State private var confirmClean = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !store.hasFullDiskAccess {
                    FullDiskAccessBanner()
                }

                HStack(alignment: .top, spacing: 20) {
                    ScanPanel(confirmClean: $confirmClean)
                    VStack(spacing: 20) {
                        DiskUsagePanel()
                        BreakdownPanel()
                    }
                }

                if let message = store.message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }

                Text("Categories")
                    .font(.title3.weight(.semibold))
                    .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    ForEach(CleanupCategory.allCases) { category in
                        Button {
                            route = .category(category)
                        } label: {
                            CategoryTile(category: category)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
        .confirmationDialog(
            "Clean \(store.selection.count) items (\(store.selectedSize.formattedBytes))?",
            isPresented: $confirmClean
        ) {
            Button(store.settings.deletePermanently ? "Delete Permanently" : "Move to Trash",
                   role: .destructive) {
                Task { await store.cleanSelection() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Quit other apps first so their caches aren't in use. Items from the Trash category are always deleted for good.")
        }
    }
}

// MARK: - Scan ring (the hero)

private struct ScanPanel: View {
    @Environment(CleanerStore.self) private var store
    @Binding var confirmClean: Bool

    private var ringValue: Double {
        switch store.phase {
        case .scanning: return store.progress
        case .cleaning: return 1
        case .idle: return store.hasScanned ? 1 : 0
        }
    }

    private var headline: String {
        switch store.phase {
        case .scanning: return "\(Int(store.progress * 100))%"
        case .cleaning: return "Cleaning"
        case .idle: return store.hasScanned ? store.selectedSize.formattedBytes : "Ready"
        }
    }

    private var caption: String {
        switch store.phase {
        case .scanning, .cleaning: return store.progressLabel
        case .idle: return store.hasScanned ? "selected to clean" : "Press Scan to start"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: ringValue)
                    .stroke(
                        AngularGradient(colors: [.cyan, .blue, .indigo, .cyan], center: .center),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: ringValue)
                VStack(spacing: 4) {
                    Text(headline)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(28)
            }
            .frame(width: 220, height: 220)

            VStack(spacing: 8) {
                Button {
                    Task { await store.openSmartClean() }
                } label: {
                    Label("Smart Clean…", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isBusy)
                .help("Pick junk by rules and preview it before cleaning")

                Button {
                    confirmClean = true
                } label: {
                    Label("Clean Selected", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(store.isBusy || store.selection.isEmpty)

                Button {
                    Task { await store.scan() }
                } label: {
                    Text(store.hasScanned ? "Scan Again" : "Scan")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(store.isBusy)

                if let last = store.lastScan {
                    Text("Last scan \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 220)
        }
        .padding(24)
        .panelStyle()
    }
}

// MARK: - Disk usage

private struct DiskUsagePanel: View {
    @Environment(CleanerStore.self) private var store

    var body: some View {
        let disk = store.disk
        let reclaimFraction = disk.total > 0
            ? min(Double(store.totalReclaimable) / Double(disk.total), disk.usedFraction)
            : 0

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Macintosh HD", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Text("\(disk.available.formattedBytes) free of \(disk.total.formattedBytes)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(Color.accentColor)
                        .frame(width: width * disk.usedFraction)
                    Capsule().fill(Color.orange)
                        .frame(width: width * reclaimFraction)
                        .offset(x: width * (disk.usedFraction - reclaimFraction))
                }
            }
            .frame(height: 12)

            HStack(spacing: 16) {
                LegendDot(color: .accentColor, text: "Used \(disk.used.formattedBytes)")
                LegendDot(color: .orange, text: "Can be cleaned \(store.totalReclaimable.formattedBytes)")
            }
            .font(.caption)
        }
        .padding(20)
        .panelStyle()
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

// MARK: - Breakdown chart

private struct Slice: Identifiable {
    let category: CleanupCategory
    let size: Int64
    var id: CleanupCategory { category }
}

private struct BreakdownPanel: View {
    @Environment(CleanerStore.self) private var store

    private var slices: [Slice] {
        CleanupCategory.allCases
            .compactMap { c in
                guard let size = store.result(for: c)?.totalSize, size > 0 else { return nil }
                return Slice(category: c, size: size)
            }
            .sorted { $0.size > $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where the space is")
                .font(.headline)

            if slices.isEmpty {
                Text(store.hasScanned ? "Nothing to clean." : "Scan to see a breakdown.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                HStack(spacing: 24) {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Size", Double(slice.size)),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .cornerRadius(3)
                        .foregroundStyle(slice.category.color)
                    }
                    .frame(width: 150, height: 150)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(slices.prefix(6)) { slice in
                            HStack {
                                Circle().fill(slice.category.color).frame(width: 8, height: 8)
                                Text(slice.category.title)
                                Spacer()
                                Text(slice.size.formattedBytes)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }
}

// MARK: - Category tile

private struct CategoryTile: View {
    @Environment(CleanerStore.self) private var store
    let category: CleanupCategory

    var body: some View {
        let result = store.result(for: category)

        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(category.color.gradient, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.headline)
                    .lineLimit(1)
                Group {
                    if let result {
                        if result.accessDenied {
                            Text("Needs Full Disk Access")
                        } else {
                            Text("\(result.totalSize.formattedBytes), \(result.items.count) items")
                        }
                    } else {
                        Text("Not scanned")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer(minLength: 0)
            Circle()
                .fill(category.safety.color)
                .frame(width: 7, height: 7)
                .help(category.safety.label)
        }
        .padding(12)
        .contentShape(Rectangle())
        .panelStyle(cornerRadius: 12)
    }
}

// MARK: - Full Disk Access banner

struct FullDiskAccessBanner: View {
    @Environment(CleanerStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Give Full Disk Access to clean everything")
                    .font(.headline)
                Text("Without it, macOS hides the Trash, Mail attachments and iPhone backups from this app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
            Button("Check Again") {
                store.refreshPermissions()
                Task { await store.scan() }
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Panel style

extension View {
    func panelStyle(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
    }
}
