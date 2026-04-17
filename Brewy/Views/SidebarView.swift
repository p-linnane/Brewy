import SwiftUI

struct SidebarView: View {
    @Binding var selectedCategory: SidebarCategory?

    var body: some View {
        List(selection: $selectedCategory) {
            Section("Packages") {
                ForEach(SidebarCategory.packageCategories) { category in
                    SidebarRow(category: category)
                        .tag(category)
                }
            }
            Section("Management") {
                ForEach(SidebarCategory.managementCategories) { category in
                    SidebarRow(category: category)
                        .tag(category)
                }
            }
            Section("Tools") {
                ForEach(SidebarCategory.toolCategories) { category in
                    SidebarRow(category: category)
                        .tag(category)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
        .navigationTitle("Brewy")
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    @Environment(BrewService.self)
    private var brewService
    let category: SidebarCategory

    var body: some View {
        Label {
            HStack {
                Text(category.rawValue)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: category.systemImage)
                .foregroundStyle(iconColor)
        }
    }

    private var count: Int? {
        switch category {
        case .masApps: brewService.isMasAvailable ? brewService.packages(for: category).count : nil
        case .taps: brewService.installedTaps.count
        case .services: nil
        case .groups: brewService.packageGroups.isEmpty ? nil : brewService.packageGroups.count
        case .history: brewService.actionHistory.isEmpty ? nil : brewService.actionHistory.count
        case .discover: nil
        case .maintenance: nil
        default: brewService.packages(for: category).count
        }
    }

    private var iconColor: Color {
        switch category {
        case .installed: .blue
        case .formulae: .green
        case .casks: .purple
        case .masApps: .pink
        case .outdated: .orange
        case .pinned: .red
        case .leaves: .mint
        case .taps: .teal
        case .services: .gray
        case .groups: .brown
        case .history: .secondary
        case .discover: .cyan
        case .maintenance: .indigo
        }
    }
}

// MARK: - Sidebar Footer

private struct SidebarFooter: View {
    @Environment(BrewService.self)
    private var brewService

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Button {
                    Task { await brewService.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(brewService.isLoading)

                Spacer()

                if brewService.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if let lastUpdated = brewService.lastUpdated {
                    Text(Self.relativeTime(since: lastUpdated))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private static func relativeTime(since date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "Just now" }
        if minutes == 1 { return "1 min ago" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours == 1 { return "1 hour ago" }
        return "\(hours) hours ago"
    }
}
