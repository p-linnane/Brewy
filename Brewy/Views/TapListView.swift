import SwiftUI

struct TapListView: View {
    @Environment(BrewService.self) private var brewService
    @Binding var selectedTap: BrewTap?
    @State private var showAddSheet = false

    var body: some View {
        List(selection: $selectedTap) {
            if brewService.installedTaps.isEmpty {
                ContentUnavailableView(
                    "No Taps",
                    systemImage: "spigot.fill",
                    description: Text("No third-party taps are installed.")
                )
            } else {
                ForEach(brewService.installedTaps) { tap in
                    TapRow(tap: tap, healthStatus: brewService.tapHealthStatuses[tap.name])
                        .tag(tap)
                        .contextMenu {
                            Button("Remove Tap", role: .destructive) {
                                Task { await brewService.removeTap(name: tap.name) }
                            }
                        }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle("Taps")
        .navigationSubtitle("\(brewService.installedTaps.count) taps")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Tap", systemImage: "plus") {
                    showAddSheet = true
                }
                .help("Add a new tap")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTapSheet()
        }
        .overlay {
            if brewService.isLoading, brewService.installedTaps.isEmpty {
                ProgressView("Loading taps...")
            }
        }
    }
}

// MARK: - Tap Row

private struct TapRow: View {
    let tap: BrewTap
    var healthStatus: TapHealthStatus?

    private static let officialTaps: Set<String> = ["homebrew/core", "homebrew/cask"]

    private var isOfficialTap: Bool {
        Self.officialTaps.contains(tap.name)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "spigot.fill")
                .font(.title3)
                .foregroundStyle(.teal)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tap.name)
                        .font(.body)
                        .bold()
                    if let healthStatus, healthStatus.status != .healthy, healthStatus.status != .unknown {
                        TapHealthBadge(status: healthStatus.status)
                    } else if isOfficialTap, healthStatus?.status == .healthy {
                        TapBadge(text: "official", color: .teal)
                    }
                }
                if !tap.remote.isEmpty {
                    Text(tap.remote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(tap.formulaNames.count + tap.caskTokens.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tap Badges

private struct TapBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: .capsule)
    }
}

private struct TapHealthBadge: View {
    let status: TapHealthStatus.Status

    private var label: String {
        switch status {
        case .archived: "archived"
        case .moved: "moved"
        case .notFound: "not found"
        case .healthy, .unknown: ""
        }
    }

    private var color: Color {
        switch status {
        case .archived: .yellow
        case .moved: .orange
        case .notFound: .red
        case .healthy, .unknown: .secondary
        }
    }

    private var icon: String {
        switch status {
        case .archived: "archivebox.fill"
        case .moved: "arrow.right.arrow.left"
        case .notFound: "exclamationmark.triangle.fill"
        case .healthy, .unknown: "checkmark"
        }
    }

    var body: some View {
        Label(label, systemImage: icon)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: .capsule)
    }
}

// MARK: - Add Tap Sheet

private struct AddTapSheet: View {
    @Environment(BrewService.self) private var brewService
    @Environment(\.dismiss) private var dismiss
    @State private var tapName = ""
    @State private var isAdding = false

    private var isValidTapName: Bool {
        let trimmed = tapName.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "/")
        return parts.count == 2
            && parts.allSatisfy { !$0.isEmpty }
            && trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "/" || $0 == "-" || $0 == "_" || $0 == "." }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Tap")
                .font(.headline)
            Text("Enter the tap name (e.g. gromgit/fuse).")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("user/repo", text: $tapName)
                .textFieldStyle(.roundedBorder)
                .disabled(isAdding)
            if !tapName.isEmpty, !isValidTapName {
                Text("Tap name must be in user/repo format.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if isAdding {
                ProgressView("Adding \(tapName.trimmingCharacters(in: .whitespaces))…")
                    .font(.callout)
            }
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isAdding)
                Button("Add") {
                    let name = tapName.trimmingCharacters(in: .whitespaces)
                    guard isValidTapName else { return }
                    isAdding = true
                    Task {
                        await brewService.addTap(name: name)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidTapName || isAdding)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - Tap Detail

struct TapDetailView: View {
    @Environment(BrewService.self) private var brewService
    let tap: BrewTap

    private var installedFormulae: [BrewPackage] {
        let names = Set(tap.formulaNames)
        return brewService.installedFormulae.filter { names.contains($0.name) }
    }

    private var installedCasks: [BrewPackage] {
        let tokens = Set(tap.caskTokens)
        return brewService.installedCasks.filter { tokens.contains($0.name) }
    }

    private var healthStatus: TapHealthStatus? {
        brewService.tapHealthStatuses[tap.name]
    }

    var body: some View {
        Form {
            if let healthStatus, healthStatus.status != .healthy, healthStatus.status != .unknown {
                TapHealthWarningSection(tap: tap, healthStatus: healthStatus)
            }

            Section("Tap Info") {
                LabeledContent("Name", value: tap.name)
                if !tap.remote.isEmpty {
                    LabeledContent("Remote") {
                        Link(tap.remote, destination: URL(string: tap.remote) ?? URL(string: "https://github.com")!)
                            .foregroundStyle(.link)
                    }
                }
                LabeledContent("Official", value: tap.isOfficial ? "Yes" : "No")
                LabeledContent("Formulae", value: "\(tap.formulaNames.count)")
                LabeledContent("Casks", value: "\(tap.caskTokens.count)")
            }

            if !installedFormulae.isEmpty {
                Section("Installed Formulae") {
                    ForEach(installedFormulae) { package in
                        LabeledContent(package.name, value: package.version)
                    }
                }
            }

            if !installedCasks.isEmpty {
                Section("Installed Casks") {
                    ForEach(installedCasks) { package in
                        LabeledContent(package.name, value: package.version)
                    }
                }
            }

            Section {
                Button("Remove Tap", role: .destructive) {
                    Task { await brewService.removeTap(name: tap.name) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tap.name)
    }
}

// MARK: - Tap Health Warning

private struct TapHealthWarningSection: View {
    @Environment(BrewService.self) private var brewService
    let tap: BrewTap
    let healthStatus: TapHealthStatus
    @State private var showMigrateConfirmation = false

    private var movedToTapName: String? {
        guard let movedTo = healthStatus.movedTo else { return nil }
        return TapHealthStatus.tapName(from: movedTo)
    }

    private var warningMessage: String {
        switch healthStatus.status {
        case .archived:
            return "This tap's repository has been archived and will no longer receive updates. Consider removing it."
        case .moved:
            if let tapName = movedToTapName {
                return "This tap's repository has moved to \(tapName)."
            }
            if let movedTo = healthStatus.movedTo {
                return "This tap's repository has moved to \(movedTo)."
            }
            return "This tap's repository has moved."
        case .notFound:
            return "This tap's repository could not be found on GitHub. It may have been deleted."
        case .healthy, .unknown:
            return ""
        }
    }

    private var warningColor: Color {
        switch healthStatus.status {
        case .archived: .yellow
        case .moved: .orange
        case .notFound: .red
        case .healthy, .unknown: .secondary
        }
    }

    private var warningIcon: String {
        switch healthStatus.status {
        case .archived: "archivebox.fill"
        case .moved: "arrow.right.arrow.left"
        case .notFound: "exclamationmark.triangle.fill"
        case .healthy, .unknown: "checkmark"
        }
    }

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 6) {
                    Text(warningMessage)
                        .font(.callout)
                    if let movedTo = healthStatus.movedTo,
                       let url = URL(string: movedTo) {
                        Link("View new repository", destination: url)
                            .font(.callout)
                    }
                }
            } icon: {
                Image(systemName: warningIcon)
                    .foregroundStyle(warningColor)
            }

            if healthStatus.status == .moved, let newTapName = movedToTapName {
                Button {
                    showMigrateConfirmation = true
                } label: {
                    Label("Migrate to \(newTapName)", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .alert("Migrate Tap", isPresented: $showMigrateConfirmation) {
                    Button("Migrate", role: .destructive) {
                        Task { await brewService.migrateTap(from: tap.name, to: newTapName) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove \(tap.name) and re-add it as \(newTapName). Any local changes to this tap will be lost.")
                }
            }

            Button("Remove Tap", role: .destructive) {
                Task { await brewService.removeTap(name: tap.name) }
            }
        }
    }
}
