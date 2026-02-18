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
                    TapRow(tap: tap)
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
                    if tap.isOfficial {
                        Text("official")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.teal.opacity(0.12), in: .capsule)
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

// MARK: - Add Tap Sheet

private struct AddTapSheet: View {
    @Environment(BrewService.self) private var brewService
    @Environment(\.dismiss) private var dismiss
    @State private var tapName = ""

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
            Text("Enter the tap name (e.g. homebrew/cask-fonts).")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("user/repo", text: $tapName)
                .textFieldStyle(.roundedBorder)
            if !tapName.isEmpty, !isValidTapName {
                Text("Tap name must be in user/repo format.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let name = tapName.trimmingCharacters(in: .whitespaces)
                    guard isValidTapName else { return }
                    Task {
                        await brewService.addTap(name: name)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidTapName)
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

    var body: some View {
        Form {
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
