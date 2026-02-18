import SwiftUI

enum SearchScope: String, CaseIterable {
    case all = "All Packages"
    case installed = "Installed Only"
}

struct PackageListView: View {
    @Environment(BrewService.self) private var brewService
    let selectedCategory: SidebarCategory?
    @Binding var selectedPackage: BrewPackage?
    @Binding var searchText: String
    @State private var searchScope: SearchScope = .installed
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearchPresented = false
    @State private var selectedForUpgrade: Set<String> = []
    @State private var isSelectingForUpgrade = false

    private var isOutdatedCategory: Bool {
        selectedCategory == .outdated
    }

    private var isSearchingAll: Bool {
        isSearchPresented && searchScope == .all
    }

    private var displayedPackages: [BrewPackage] {
        if isSearchingAll {
            if !brewService.searchResults.isEmpty {
                return brewService.searchResults
            }
            return []
        }

        guard let category = selectedCategory else { return [] }
        let base = brewService.packages(for: category)

        if searchText.isEmpty {
            return base
        }

        return base.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        packageList
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: searchPrompt)
            .searchScopes($searchScope, activation: .onSearchPresentation) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .onChange(of: searchText) {
                guard isSearchingAll else { return }
                searchTask?.cancel()
                guard !searchText.isEmpty else { return }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await brewService.search(query: searchText)
                }
            }
            .onChange(of: searchScope) {
                if isSearchingAll, !searchText.isEmpty {
                    searchTask?.cancel()
                    searchTask = Task {
                        await brewService.search(query: searchText)
                    }
                }
            }
            .onChange(of: selectedCategory) {
                searchScope = .installed
                searchText = ""
                searchTask?.cancel()
            }
            .overlay {
                if brewService.isLoading, displayedPackages.isEmpty {
                    ProgressView("Loading packages...")
                }
            }
            .navigationTitle(navigationTitle)
            .navigationSubtitle("\(displayedPackages.count) packages")
            .toolbar {
                PackageListToolbar(
                    isOutdated: isOutdatedCategory,
                    isSelecting: $isSelectingForUpgrade,
                    selectedForUpgrade: $selectedForUpgrade,
                    outdatedPackages: isOutdatedCategory ? displayedPackages : []
                )
            }
    }

    private var packageList: some View {
        List(selection: $selectedPackage) {
            if displayedPackages.isEmpty {
                emptyContent
            } else {
                ForEach(displayedPackages) { package in
                    HStack {
                        if isOutdatedCategory, isSelectingForUpgrade {
                            Toggle(isOn: Binding(
                                get: { selectedForUpgrade.contains(package.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedForUpgrade.insert(package.id)
                                    } else {
                                        selectedForUpgrade.remove(package.id)
                                    }
                                }
                            )) {
                                EmptyView()
                            }
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        }
                        PackageRow(
                            package: package,
                            showInstalledBadge: isSearchingAll,
                            showUpgradeButton: isOutdatedCategory && !isSelectingForUpgrade
                        )
                    }
                    .tag(package)
                }
            }
        }
    }

    private var searchPrompt: String {
        "Search packages..."
    }

    private var navigationTitle: String {
        selectedCategory?.rawValue ?? "Packages"
    }

    @ViewBuilder
    private var emptyContent: some View {
        if brewService.isLoading {
            EmptyView()
        } else if isSearchingAll, searchText.isEmpty {
            ContentUnavailableView(
                "Search Homebrew",
                systemImage: "magnifyingglass",
                description: Text("Type a package name to search all of Homebrew.")
            )
        } else if isSearchingAll {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView(
                "No Packages",
                systemImage: "shippingbox",
                description: Text("No packages found in this category.")
            )
        }
    }
}

// MARK: - Toolbar

private struct PackageListToolbar: ToolbarContent {
    @Environment(BrewService.self) private var brewService
    let isOutdated: Bool
    @Binding var isSelecting: Bool
    @Binding var selectedForUpgrade: Set<String>
    let outdatedPackages: [BrewPackage]

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isOutdated {
                if isSelecting {
                    Button {
                        let toUpgrade = outdatedPackages.filter { selectedForUpgrade.contains($0.id) }
                        Task {
                            await brewService.upgradeSelected(packages: toUpgrade)
                            selectedForUpgrade.removeAll()
                            isSelecting = false
                        }
                    } label: {
                        Label("Upgrade Selected (\(selectedForUpgrade.count))", systemImage: "arrow.up.circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(selectedForUpgrade.isEmpty)

                    Button {
                        selectedForUpgrade.removeAll()
                        isSelecting = false
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                            .labelStyle(.titleAndIcon)
                    }
                } else {
                    Button {
                        isSelecting = true
                    } label: {
                        Label("Select Packages", systemImage: "checkmark.circle")
                            .labelStyle(.titleAndIcon)
                    }

                    Button {
                        Task { await brewService.upgradeAll() }
                    } label: {
                        Label("Upgrade All", systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.titleAndIcon)
                    }
                }
            } else if !brewService.outdatedPackages.isEmpty {
                Button {
                    Task { await brewService.upgradeAll() }
                } label: {
                    Label("Upgrade All", systemImage: "arrow.triangle.2.circlepath")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }
}

// MARK: - Package Row

private struct PackageRow: View {
    @Environment(BrewService.self) private var brewService
    let package: BrewPackage
    var showInstalledBadge = false
    var showUpgradeButton = false

    var body: some View {
        HStack(spacing: 10) {
            packageIcon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(.body)
                        .bold()
                    if showInstalledBadge, package.isInstalled {
                        InstalledBadge()
                    }
                    if package.isCask {
                        CaskBadge()
                    }
                    if package.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
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
            versionLabel
            if showUpgradeButton, package.isOutdated {
                Button {
                    Task { await brewService.upgrade(package: package) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Upgrade \(package.name)")
            }
        }
        .padding(.vertical, 2)
    }

    private var packageIcon: some View {
        Image(systemName: package.isCask ? "macwindow" : "terminal")
            .font(.title3)
            .foregroundStyle(package.isCask ? .purple : .green)
            .frame(width: 24)
    }

    private var versionLabel: some View {
        Group {
            if package.isOutdated {
                Label(package.displayVersion, systemImage: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if !package.version.isEmpty {
                Text(package.version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Badges

private struct InstalledBadge: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.caption2)
            .foregroundStyle(.green)
    }
}

private struct CaskBadge: View {
    var body: some View {
        Text("cask")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.purple)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.purple.opacity(0.12), in: .capsule)
    }
}
