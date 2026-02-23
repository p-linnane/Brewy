import SwiftUI

struct MaintenanceView: View {
    @Environment(BrewService.self) private var brewService
    @State private var doctorOutput: String?
    @State private var isRunningDoctor = false
    @State private var isCalculatingCache = false
    @State private var cacheSizeBytes: Int64?
    @State private var brewConfig: BrewConfig?
    @State private var isLoadingConfig = true

    var body: some View {
        Form {
            healthCheckSection
            orphansSection
            cacheSection
            homebrewUpdateSection
        }
        .formStyle(.grouped)
        .navigationTitle("Maintenance")
        .task {
            async let cacheTask: () = loadCacheSize()
            async let configTask: () = loadConfig()
            _ = await (cacheTask, configTask)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                brewConfig = await brewService.config()
            }
        }
    }

    // MARK: - Health Check

    private var healthCheckSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Health Check", systemImage: "stethoscope")
                        .font(.headline)
                    Spacer()
                    if isRunningDoctor {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Run brew doctor") {
                        isRunningDoctor = true
                        Task {
                            doctorOutput = await brewService.doctor()
                            isRunningDoctor = false
                        }
                    }
                    .disabled(isRunningDoctor)
                }

                if let output = doctorOutput {
                    Text(output.isEmpty ? "Your system is ready to brew." : output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(output.isEmpty ? .green : .secondary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                }
            }
        } footer: {
            Text("Checks your system for potential problems with Homebrew.")
        }
    }

    // MARK: - Orphans

    private var orphansSection: some View {
        Section {
            HStack {
                Label("Orphaned Packages", systemImage: "shippingbox.and.arrow.backward")
                    .font(.headline)
                Spacer()
                if brewService.isPerformingAction {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Remove Orphans") {
                    Task { await brewService.removeOrphans() }
                }
                .disabled(brewService.isPerformingAction)
            }
        } footer: {
            Text("Removes packages that were installed as dependencies but are no longer needed.")
        }
    }

    // MARK: - Cache

    private var cacheSection: some View {
        Section {
            HStack {
                Label("Download Cache", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()

                if isCalculatingCache {
                    ProgressView()
                        .controlSize(.small)
                } else if let size = cacheSizeBytes {
                    Text(formattedSize(size))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button("Clear Cache") {
                    Task {
                        await brewService.purgeCache()
                        await loadCacheSize()
                    }
                }
                .disabled(brewService.isPerformingAction)
            }
        } footer: {
            Text("Removes cached package downloads and old versions.")
        }
    }

    // MARK: - Update

    private var homebrewUpdateSection: some View {
        Section {
            HStack {
                Label("Update Homebrew", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                Spacer()
                if brewService.isPerformingAction {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Update") {
                    Task {
                        await brewService.updateHomebrew()
                        await loadConfig()
                    }
                }
                .disabled(brewService.isPerformingAction)
            }

            configRow("Homebrew version", value: brewConfig?.version)
            configRow("Homebrew/brew last updated", value: brewConfig?.homebrewLastCommit)
            configRow("Homebrew/core last updated", value: brewConfig?.coreTapLastCommit)
            configRow("Homebrew/cask last updated", value: brewConfig?.coreCaskTapLastCommit)
        } footer: {
            Text("Fetches the newest version of Homebrew and all formulae from GitHub.")
        }
    }

    // MARK: - Helpers

    private func loadCacheSize() async {
        isCalculatingCache = true
        cacheSizeBytes = await brewService.cacheSize()
        isCalculatingCache = false
    }

    private func loadConfig() async {
        isLoadingConfig = true
        brewConfig = await brewService.config()
        isLoadingConfig = false
    }

    private func configRow(_ label: String, value: String?) -> some View {
        LabeledContent(label) {
            if isLoadingConfig {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(value ?? "—")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private func formattedSize(_ bytes: Int64) -> String {
        Self.sizeFormatter.string(fromByteCount: bytes)
    }
}
