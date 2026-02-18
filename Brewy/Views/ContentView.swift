import SwiftUI

// MARK: - Package Navigation Environment

private struct SelectPackageActionKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (String) -> Void = { _ in }
}

extension EnvironmentValues {
    var selectPackage: @MainActor @Sendable (String) -> Void {
        get { self[SelectPackageActionKey.self] }
        set { self[SelectPackageActionKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(BrewService.self) private var brewService
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval = 0
    @AppStorage("showCasksByDefault") private var showCasksByDefault = false
    @State private var selectedCategory: SidebarCategory? = .installed
    @State private var selectedPackage: BrewPackage?
    @State private var selectedTap: BrewTap?
    @State private var searchText = ""
    @State private var showError = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedCategory: $selectedCategory
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } content: {
            if selectedCategory == .taps {
                TapListView(selectedTap: $selectedTap)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 500)
            } else if selectedCategory == .maintenance {
                MaintenanceView()
                    .navigationSplitViewColumnWidth(min: 400, ideal: 600, max: .infinity)
            } else {
                PackageListView(
                    selectedCategory: selectedCategory,
                    selectedPackage: $selectedPackage,
                    searchText: $searchText
                )
            }
        } detail: {
            if selectedCategory == .maintenance {
                Color.clear
                    .navigationSplitViewColumnWidth(0)
            } else if selectedCategory == .taps, let tap = selectedTap {
                TapDetailView(tap: tap)
            } else if selectedCategory == .taps {
                EmptyStateView(
                    icon: "spigot",
                    title: "Select a Tap",
                    subtitle: "Choose a tap from the list to view its details."
                )
            } else if let selectedPackage {
                let package = brewService.allInstalled.first(where: { $0.id == selectedPackage.id }) ?? selectedPackage
                let isOutdated = brewService.outdatedPackages.contains { $0.id == selectedPackage.id }
                PackageDetailView(package: package)
                    .id(isOutdated)
            } else {
                EmptyStateView()
            }
        }
        .environment(\.selectPackage) { [self] name in navigateToPackage(name) }
        .task {
            if showCasksByDefault {
                selectedCategory = .casks
            }
            brewService.loadFromCache()
            await brewService.refresh()
        }
        .task(id: autoRefreshInterval) {
            guard autoRefreshInterval > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(autoRefreshInterval))
                guard !Task.isCancelled else { break }
                await brewService.refresh()
            }
        }
        .onChange(of: brewService.errorMessage) {
            showError = brewService.errorMessage != nil
        }
        .alert(
            "Error",
            isPresented: $showError,
            presenting: brewService.errorMessage
        ) { _ in
            Button("OK") { brewService.errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private func navigateToPackage(_ name: String) {
        if let match = brewService.allInstalled.first(where: { $0.name == name }) {
            selectedCategory = match.isCask ? .casks : .formulae
            selectedPackage = match
        }
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    var icon: String = "shippingbox"
    var title: String = "Select a Package"
    var subtitle: String = "Choose a package from the list to view its details."

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
