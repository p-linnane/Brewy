import SwiftUI

struct MaintenanceView: View {
    @Environment(BrewService.self) private var brewService
    @State private var doctorOutput: String?
    @State private var isRunningDoctor = false
    @State private var isCalculatingCache = false
    @State private var cacheSizeBytes: Int64?

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
            await loadCacheSize()
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
                Label("Orphaned Packages", systemImage: "shippingbox.and.arrow.clockwise")
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
                    Task { await brewService.updateHomebrew() }
                }
                .disabled(brewService.isPerformingAction)
            }

            if let lastUpdated = brewService.lastUpdated {
                LabeledContent("Last refreshed") {
                    Text(lastUpdated.formatted(.relative(presentation: .named)))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
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

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private func formattedSize(_ bytes: Int64) -> String {
        Self.sizeFormatter.string(fromByteCount: bytes)
    }
}
