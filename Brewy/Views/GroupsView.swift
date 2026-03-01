import SwiftUI

struct GroupsView: View {
    @Environment(BrewService.self) private var brewService
    @Binding var selectedGroup: PackageGroup?
    @State private var showCreateSheet = false

    var body: some View {
        List(selection: $selectedGroup) {
            if brewService.packageGroups.isEmpty {
                ContentUnavailableView(
                    "No Groups",
                    systemImage: "folder.fill",
                    description: Text("Create groups to organize your packages into custom collections.")
                )
            } else {
                ForEach(brewService.packageGroups) { group in
                    GroupRow(group: group)
                        .tag(group)
                        .contextMenu {
                            Button("Delete Group", systemImage: "trash", role: .destructive) {
                                if selectedGroup?.id == group.id {
                                    selectedGroup = nil
                                }
                                brewService.deleteGroup(group)
                            }
                        }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle("Groups")
        .navigationSubtitle("\(brewService.packageGroups.count) groups")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Group", systemImage: "plus") {
                    showCreateSheet = true
                }
                .help("Create a new group")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateGroupSheet()
        }
    }
}

// MARK: - Group Row

private struct GroupRow: View {
    @Environment(BrewService.self) private var brewService
    let group: PackageGroup

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: group.systemImage)
                .font(.title3)
                .foregroundStyle(.brown)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.body)
                    .bold()
            }
            Spacer()
            Text("\(brewService.packages(in: group).count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Create Group Sheet

private struct CreateGroupSheet: View {
    @Environment(BrewService.self) private var brewService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedIcon = "folder.fill"

    private static let availableIcons = [
        "folder.fill", "star.fill", "heart.fill", "bookmark.fill",
        "flag.fill", "tag.fill", "bolt.fill", "flame.fill",
        "wrench.fill", "hammer.fill", "paintbrush.fill", "globe",
        "desktopcomputer", "server.rack", "network", "lock.fill"
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("New Group")
                .font(.headline)
            Text("Create a group to organize your packages.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Group name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 8), spacing: 8) {
                    ForEach(Self.availableIcons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.body)
                                .frame(width: 32, height: 32)
                                .background(
                                    selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear,
                                    in: .rect(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    brewService.createGroup(name: trimmed, systemImage: selectedIcon)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - Group Detail View

struct GroupDetailView: View {
    @Environment(BrewService.self) private var brewService
    @Environment(\.selectPackage) private var selectPackage
    let group: PackageGroup
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false

    private var groupPackages: [BrewPackage] {
        brewService.packages(in: group)
    }

    var body: some View {
        Form {
            headerSection
            packagesSection
            Section {
                Button("Delete Group", systemImage: "trash", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(group.name)
        .sheet(isPresented: $showEditSheet) {
            EditGroupSheet(group: group)
        }
        .confirmationDialog("Delete \(group.name)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                brewService.deleteGroup(group)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the group. Your packages will not be affected.")
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.brown.opacity(0.1))
                        .frame(width: 56, height: 56)
                    Image(systemName: group.systemImage)
                        .font(.title)
                        .foregroundStyle(.brown)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.title2)
                        .bold()
                    Text("\(groupPackages.count) packages")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit", systemImage: "pencil") {
                    showEditSheet = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var packagesSection: some View {
        if groupPackages.isEmpty {
            Section {
                ContentUnavailableView(
                    "No Packages",
                    systemImage: "shippingbox",
                    description: Text("Add packages to this group from the package detail view.")
                )
            }
        } else {
            Section("Packages") {
                ForEach(groupPackages) { package in
                    GroupPackageRow(package: package) {
                        selectPackage(package.name)
                    } onRemove: {
                        brewService.removeFromGroup(group, packageID: package.id)
                    }
                }
            }

            if groupPackages.contains(where: \.isOutdated) {
                Section {
                    Button("Upgrade Outdated in Group", systemImage: "arrow.up.circle") {
                        let outdated = groupPackages.filter(\.isOutdated)
                        Task { await brewService.upgradeSelected(packages: outdated) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        }
    }
}

// MARK: - Group Package Row

private struct GroupPackageRow: View {
    let package: BrewPackage
    let onNavigate: () -> Void
    let onRemove: () -> Void

    private var iconName: String {
        switch package.source {
        case .formula: "terminal"
        case .cask: "macwindow"
        case .mas: "app.badge.fill"
        }
    }

    private var iconColor: Color {
        switch package.source {
        case .formula: .green
        case .cask: .purple
        case .mas: .pink
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(.body)
                        .fontWeight(.medium)
                    if package.isOutdated {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                if !package.version.isEmpty {
                    Text(package.displayVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                onNavigate()
            } label: {
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Go to \(package.name)")
        }
        .contextMenu {
            Button("Go to Package", systemImage: "arrow.right.circle") {
                onNavigate()
            }
            Divider()
            Button("Remove from Group", systemImage: "minus.circle", role: .destructive) {
                onRemove()
            }
        }
    }
}

// MARK: - Edit Group Sheet

private struct EditGroupSheet: View {
    @Environment(BrewService.self) private var brewService
    @Environment(\.dismiss) private var dismiss
    let group: PackageGroup
    @State private var name: String
    @State private var selectedIcon: String

    private static let availableIcons = [
        "folder.fill", "star.fill", "heart.fill", "bookmark.fill",
        "flag.fill", "tag.fill", "bolt.fill", "flame.fill",
        "wrench.fill", "hammer.fill", "paintbrush.fill", "globe",
        "desktopcomputer", "server.rack", "network", "lock.fill"
    ]

    init(group: PackageGroup) {
        self.group = group
        _name = State(initialValue: group.name)
        _selectedIcon = State(initialValue: group.systemImage)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Group")
                .font(.headline)

            TextField("Group name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 8), spacing: 8) {
                    ForEach(Self.availableIcons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.body)
                                .frame(width: 32, height: 32)
                                .background(
                                    selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear,
                                    in: .rect(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    brewService.updateGroup(group, name: trimmed, systemImage: selectedIcon)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
