import SwiftUI

struct PackageDetailView: View {
    @Environment(BrewService.self) private var brewService
    let package: BrewPackage
    @State private var detailedInfo: String = ""
    @State private var isLoadingInfo = false
    @State private var showUninstallConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PackageHeader(package: package)
                Divider()
                    .padding(.horizontal)
                ActionBar(
                    package: package,
                    showUninstallConfirm: $showUninstallConfirm
                )
                Divider()
                    .padding(.horizontal)
                PackageInfoSection(package: package)
                if !package.isMas {
                    Divider()
                        .padding(.horizontal)
                    BrewInfoSection(info: detailedInfo, isLoading: isLoadingInfo)
                }
            }
            .padding(.vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .task(id: package.id) {
            guard !package.isMas else { return }
            detailedInfo = ""
            isLoadingInfo = true
            detailedInfo = await brewService.info(for: package)
            isLoadingInfo = false
        }
        .confirmationDialog(
            "Uninstall \(package.name)?",
            isPresented: $showUninstallConfirm
        ) {
            Button("Uninstall", role: .destructive) {
                Task { await brewService.uninstall(package: package) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove \(package.name) from your system. This action cannot be undone.")
        }
        .overlay {
            if brewService.isPerformingAction {
                ActionOverlay(output: brewService.actionOutput)
            }
        }
    }
}

// MARK: - Package Header

private struct PackageHeader: View {
    let package: BrewPackage

    private var headerIcon: String {
        switch package.source {
        case .formula: "terminal.fill"
        case .cask: "macwindow"
        case .mas: "app.badge.fill"
        }
    }

    private var headerColor: Color {
        switch package.source {
        case .formula: .green
        case .cask: .purple
        case .mas: .pink
        }
    }

    private var sourceBadgeText: String {
        switch package.source {
        case .formula: "Formula"
        case .cask: "Cask"
        case .mas: "Mac App Store"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(headerColor.opacity(0.1))
                    .frame(width: 56, height: 56)
                Image(systemName: headerIcon)
                    .font(.title)
                    .foregroundStyle(headerColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(package.name)
                        .font(.title2)
                        .bold()
                    Text(sourceBadgeText)
                        .font(.caption)
                        .foregroundStyle(headerColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(headerColor.opacity(0.12), in: .capsule)
                    if package.pinned {
                        Label("Pinned", systemImage: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if package.isOutdated {
                        Label("Update Available", systemImage: "arrow.up.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if !package.description.isEmpty {
                    Text(package.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Text("Version \(package.version)")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Action Bar

private struct ActionBar: View {
    @Environment(BrewService.self) private var brewService
    let package: BrewPackage
    @Binding var showUninstallConfirm: Bool

    var body: some View {
        HStack(spacing: 12) {
            if package.isMas {
                Text("Managed via Mac App Store")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if package.isInstalled {
                if package.isOutdated {
                    Button("Upgrade", systemImage: "arrow.up.circle") {
                        Task { await brewService.upgrade(package: package) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                if !package.isCask {
                    if package.pinned {
                        Button("Unpin", systemImage: "pin.slash") {
                            Task { await brewService.unpin(package: package) }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Pin", systemImage: "pin") {
                            Task { await brewService.pin(package: package) }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Button("Uninstall", systemImage: "trash") {
                    showUninstallConfirm = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button("Install", systemImage: "arrow.down.circle") {
                    Task { await brewService.install(package: package) }
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()

            if !package.homepage.isEmpty, let url = URL(string: package.homepage) {
                Link(destination: url) {
                    Label(package.isMas ? "App Store" : "Homepage", systemImage: package.isMas ? "app.badge.fill" : "globe")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .disabled(brewService.isPerformingAction)
    }
}

// MARK: - Package Info

private struct PackageInfoSection: View {
    @Environment(BrewService.self) private var brewService
    let package: BrewPackage

    private var packageTypeName: String {
        switch package.source {
        case .formula: "Formula"
        case .cask: "Cask"
        case .mas: "Mac App Store"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .topLeading),
                GridItem(.flexible(), alignment: .topLeading)
            ], spacing: 10) {
                InfoField(label: "Type", value: packageTypeName)
                InfoField(label: "Installed Version", value: package.installedVersion ?? "—")

                if let latest = package.latestVersion {
                    InfoField(label: "Latest Version", value: latest)
                }

                InfoField(label: "Installed on Request", value: package.installedOnRequest ? "Yes" : "No")
            }

            if !package.dependencies.isEmpty {
                DependencyTags(label: "Dependencies", packages: package.dependencies)
            }

            if !package.installedOnRequest {
                let dependents = brewService.dependents(of: package.name)
                if !dependents.isEmpty {
                    DependencyTags(label: "Required by", packages: dependents.map(\.name))
                }
            }
        }
        .padding()
    }
}

private struct InfoField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Dependency Tags

private struct DependencyTags: View {
    @Environment(\.selectPackage) private var selectPackage
    @Environment(BrewService.self) private var brewService
    let label: String
    let packages: [String]

    var body: some View {
        let knownNames = brewService.installedNames
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(packages, id: \.self) { name in
                    let isInstalled = knownNames.contains(name)
                    Button {
                        selectPackage(name)
                    } label: {
                        Text(name)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.1), in: .capsule)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isInstalled)
                    .opacity(isInstalled ? 1 : 0.5)
                    .help(isInstalled ? "Go to \(name)" : "\(name) (not installed)")
                }
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    struct CacheData {
        var sizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> CacheData {
        CacheData(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout CacheData, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
        let rows = computeRows(proposal: proposal, sizes: cache.sizes)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map(\.height).max() ?? 0
            height += rowHeight
            if index < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        let rows = computeRows(proposal: proposal, sizes: cache.sizes)
        var y = bounds.minY
        var subviewIndex = 0
        for row in rows {
            let rowHeight = row.map(\.height).max() ?? 0
            var x = bounds.minX
            for size in row {
                subviews[subviewIndex].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
                subviewIndex += 1
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, sizes: [CGSize]) -> [[CGSize]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var currentWidth: CGFloat = 0
        for size in sizes {
            if currentWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(size)
            currentWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Brew Info Output

private struct BrewInfoSection: View {
    let info: String
    let isLoading: Bool
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Brew Info")
                        .font(.headline)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                } else if !info.isEmpty {
                    Text(info)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                }
            }
        }
        .padding()
    }
}

// MARK: - Action Overlay

private struct ActionOverlay: View {
    let output: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Running...")
                .font(.headline)
            if !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 200)
                .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 8))
            }
        }
        .padding(24)
        .frame(maxWidth: 400)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .shadow(radius: 20, y: 10)
    }
}
