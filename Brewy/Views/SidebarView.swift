import SwiftUI

struct SidebarView: View {
    @Environment(BrewService.self) private var brewService
    @Binding var selectedCategory: SidebarCategory?

    var body: some View {
        List(selection: $selectedCategory) {
            Section("Library") {
                ForEach(SidebarCategory.allCases) { category in
                    SidebarRow(category: category, count: count(for: category))
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

    private func count(for category: SidebarCategory) -> Int? {
        switch category {
        case .taps: brewService.installedTaps.count
        case .maintenance: nil
        default: brewService.packages(for: category).count
        }
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let category: SidebarCategory
    let count: Int?

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

    private var iconColor: Color {
        switch category {
        case .installed: .blue
        case .formulae: .green
        case .casks: .purple
        case .outdated: .orange
        case .pinned: .red
        case .leaves: .mint
        case .taps: .teal
        case .maintenance: .indigo
        }
    }
}

// MARK: - Sidebar Footer

private struct SidebarFooter: View {
    @Environment(BrewService.self) private var brewService

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
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}
