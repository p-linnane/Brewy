import SwiftUI

struct DiscoverView: View {
    @Environment(BrewService.self) private var brewService
    @Binding var selectedPackage: BrewPackage?
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List(selection: $selectedPackage) {
            if brewService.searchResults.isEmpty {
                emptyContent
            } else {
                ForEach(brewService.searchResults) { package in
                    DiscoverRow(package: package)
                        .tag(package)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .searchable(text: $searchText, prompt: "Search all of Homebrew...")
        .onChange(of: searchText) {
            searchTask?.cancel()
            guard !searchText.isEmpty else {
                brewService.searchResults = []
                return
            }
            brewService.isLoading = true
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await brewService.search(query: searchText)
            }
        }
        .overlay {
            if brewService.isLoading, !searchText.isEmpty, brewService.searchResults.isEmpty {
                ProgressView("Searching...")
            }
        }
        .navigationTitle("Discover")
        .navigationSubtitle(
            searchText.isEmpty
                ? "Search to find new packages"
                : "\(brewService.searchResults.count) results"
        )
    }

    @ViewBuilder
    private var emptyContent: some View {
        if searchText.isEmpty {
            ContentUnavailableView(
                "Find New Packages",
                systemImage: "magnifyingglass",
                description: Text("Search all of Homebrew to discover and install formulae and casks.")
            )
        } else if !brewService.isLoading {
            ContentUnavailableView.search(text: searchText)
        }
    }
}

// MARK: - Discover Row

private struct DiscoverRow: View {
    @Environment(BrewService.self) private var brewService
    let package: BrewPackage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: package.isCask ? "macwindow" : "terminal")
                .font(.title3)
                .foregroundStyle(package.isCask ? .purple : .green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(.body)
                        .bold()
                    if package.isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    if package.isCask {
                        Text("cask")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.purple.opacity(0.12), in: .capsule)
                    }
                }
                if !package.description.isEmpty {
                    Text(package.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if package.isInstalled {
                Text("Installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await brewService.install(package: package) }
                } label: {
                    Label("Install", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
