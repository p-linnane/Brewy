import SwiftUI

enum SearchScope: String, CaseIterable {
    case all = "All Packages"
    case installed = "Installed Only"
}

struct PackageListView: View {
    @Environment(BrewService.self)
    private var brewService
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
        let packages = displayedPackages
        return packageList(packages: packages)
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
                selectedPackage = nil
            }
            .overlay {
                if brewService.isLoading, packages.isEmpty {
                    ProgressView("Loading packages...")
                }
            }
            .navigationTitle(navigationTitle)
            .navigationSubtitle("\(packages.count) packages")
            .toolbar {
                PackageListToolbar(
                    isOutdated: isOutdatedCategory,
                    isSelecting: $isSelectingForUpgrade,
                    selectedForUpgrade: $selectedForUpgrade,
                    outdatedPackages: isOutdatedCategory ? packages : []
                )
            }
    }

    private func packageList(packages: [BrewPackage]) -> some View {
        List(selection: $selectedPackage) {
            if packages.isEmpty {
                emptyContent
            } else {
                ForEach(packages) { package in
                    HStack {
                        if isOutdatedCategory, isSelectingForUpgrade {
                            UpgradeSelectionToggle(
                                packageID: package.id,
                                selectedForUpgrade: $selectedForUpgrade
                            )
                        }
                        PackageRow(
                            package: package,
                            showInstalledBadge: isSearchingAll,
                            showUpgradeButton: isOutdatedCategory && !isSelectingForUpgrade,
                            onUpgrade: { pkg in await brewService.upgrade(package: pkg) }
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

    @ViewBuilder private var emptyContent: some View {
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
    @Environment(BrewService.self)
    private var brewService
    let isOutdated: Bool
    @Binding var isSelecting: Bool
    @Binding var selectedForUpgrade: Set<String>
    let outdatedPackages: [BrewPackage]

    var body: some ToolbarContent {
        if isOutdated {
            if isSelecting {
                ToolbarItem(placement: .primaryAction) {
                    Button("Upgrade (\(selectedForUpgrade.count))") {
                        let toUpgrade = outdatedPackages.filter { selectedForUpgrade.contains($0.id) }
                        Task {
                            await brewService.upgradeSelected(packages: toUpgrade)
                            selectedForUpgrade.removeAll()
                            isSelecting = false
                        }
                    }
                    .disabled(selectedForUpgrade.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        selectedForUpgrade.removeAll()
                        isSelecting = false
                    }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button("Upgrade All") {
                        Task { await brewService.upgradeAll() }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Select") {
                        isSelecting = true
                    }
                }
            }
        } else if !brewService.outdatedPackages.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button("Upgrade All") {
                    Task { await brewService.upgradeAll() }
                }
            }
        }
    }
}

// MARK: - Upgrade Selection Toggle

private struct UpgradeSelectionToggle: View {
    let packageID: String
    @Binding var selectedForUpgrade: Set<String>

    var body: some View {
        Toggle(isOn: Binding(
            get: { selectedForUpgrade.contains(packageID) },
            set: { isSelected in
                if isSelected {
                    selectedForUpgrade.insert(packageID)
                } else {
                    selectedForUpgrade.remove(packageID)
                }
            }
        )) { EmptyView() }
        .toggleStyle(.checkbox)
        .labelsHidden()
    }
}

// MARK: - Package Row

private struct PackageRow: View {
    let package: BrewPackage
    var showInstalledBadge = false
    var showUpgradeButton = false
    var onUpgrade: ((BrewPackage) async -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(.body)
                        .bold()
                    if showInstalledBadge, package.isInstalled {
                        InstalledBadge()
                    }
                    if package.isFormula {
                        FormulaBadge()
                    } else if package.isCask {
                        CaskBadge()
                    } else if package.isMas {
                        MasBadge()
                    }
                    if package.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Pinned")
                    }
                }
                if !package.description.isEmpty {
                    Text(package.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            versionLabel
            if showUpgradeButton, package.isOutdated {
                Button {
                    Task { await onUpgrade?(package) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Upgrade \(package.name)")
                .accessibilityLabel("Upgrade \(package.name)")
            }
        }
        .padding(.vertical, 4)
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
            .accessibilityLabel("Installed")
    }
}

private struct FormulaBadge: View {
    var body: some View {
        Text("formula")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.green)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.green.opacity(0.12), in: .capsule)
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

private struct MasBadge: View {
    var body: some View {
        Text("mas")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.pink)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.pink.opacity(0.12), in: .capsule)
    }
}
