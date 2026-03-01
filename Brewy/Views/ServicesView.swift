import SwiftUI

struct ServicesView: View {
    @Environment(BrewService.self) private var brewService
    @State private var services: [BrewServiceItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @Binding var selectedService: BrewServiceItem?
    var refreshTrigger: Bool

    var body: some View {
        List(selection: $selectedService) {
            ForEach(services) { service in
                ServiceRow(service: service)
                    .tag(service)
            }
        }
        .overlay {
            if isLoading && services.isEmpty {
                ProgressView("Loading services…")
            } else if !isLoading && services.isEmpty {
                ContentUnavailableView(
                    "No Services",
                    systemImage: "gearshape.2",
                    description: Text("No Homebrew services found. Install a formula that provides a service to get started.")
                )
            }
        }
        .task { await loadServices() }
        .refreshable { await loadServices() }
        .onChange(of: refreshTrigger) { Task { await loadServices() } }
        .navigationTitle("Services")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await cleanupServices() }
                } label: {
                    Label("Cleanup", systemImage: "trash")
                }
                .help("Remove stale service files")
                .disabled(isLoading)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    func loadServices() async {
        isLoading = true
        let fetched = await brewService.fetchServices()
        services = fetched
        // Update selected service with fresh data if it's still in the list
        if let selected = selectedService {
            selectedService = fetched.first { $0.id == selected.id }
        }
        isLoading = false
    }

    private func cleanupServices() async {
        let result = await brewService.cleanupServices()
        if !result.success {
            errorMessage = result.output.isEmpty ? "Cleanup failed" : result.output
            showError = true
        }
        await loadServices()
    }
}

// MARK: - Service Row

private struct ServiceRow: View {
    let service: BrewServiceItem

    var body: some View {
        HStack(spacing: 10) {
            statusIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(service.statusLabel)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    if let user = service.user {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(user)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let pid = service.pid {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("PID \(pid)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        if service.running || service.status == "started" { return .green }
        if service.status == "error" || (service.exitCode ?? 0) != 0 { return .red }
        if service.status == "scheduled" { return .blue }
        if service.loaded || service.status == "stopped" { return .yellow }
        return .secondary
    }
}

// MARK: - Service Detail View

struct ServiceDetailView: View {
    let service: BrewServiceItem
    let onRefresh: () async -> Void
    @Environment(BrewService.self) private var brewService
    @State private var isPerformingAction = false
    @State private var actionOutput: String?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var useSudo = false

    var body: some View {
        Form {
            serviceInfoSection
            actionsSection
            if let output = actionOutput, !output.isEmpty {
                outputSection(output)
            }
            pathsSection
        }
        .formStyle(.grouped)
        .navigationTitle(service.name)
        .alert("Error", isPresented: $showError) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Info Section

    private var serviceInfoSection: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(service.statusLabel)
                        .foregroundStyle(statusColor)
                }
            }

            if let serviceName = service.serviceName {
                LabeledContent("Service Name") {
                    Text(serviceName)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let pid = service.pid {
                LabeledContent("PID") {
                    Text("\(pid)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if let exitCode = service.exitCode, exitCode != 0 {
                LabeledContent("Exit Code") {
                    Text("\(exitCode)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }

            if let user = service.user {
                LabeledContent("User") {
                    Text(user)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Service Info", systemImage: "info.circle")
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section {
            Toggle("Run as root (sudo)", isOn: $useSudo)
                .font(.callout)

            HStack(spacing: 12) {
                if service.running || service.status == "started" {
                    Button {
                        Task { await performAction { await brewService.stopService(service.name, asSudo: useSudo) } }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .tint(.red)

                    Button {
                        Task { await performAction { await brewService.restartService(service.name, asSudo: useSudo) } }
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .tint(.orange)
                } else {
                    Button {
                        Task { await performAction { await brewService.startService(service.name, asSudo: useSudo) } }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .tint(.green)
                }

                if isPerformingAction {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isPerformingAction)
        } header: {
            Label("Actions", systemImage: "gearshape")
        }
    }

    // MARK: - Output Section

    private func outputSection(_ output: String) -> some View {
        Section {
            Text(output)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        } header: {
            Label("Output", systemImage: "terminal")
        }
    }

    // MARK: - Paths Section

    private var pathsSection: some View {
        Section {
            if let file = service.file {
                LabeledContent("Plist") {
                    Text(file)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
            if let logPath = service.logPath {
                LabeledContent("Log") {
                    Text(logPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
            if let errorLogPath = service.errorLogPath {
                LabeledContent("Error Log") {
                    Text(errorLogPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        } header: {
            Label("Paths", systemImage: "folder")
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if service.running || service.status == "started" { return .green }
        if service.status == "error" || (service.exitCode ?? 0) != 0 { return .red }
        if service.status == "scheduled" { return .blue }
        if service.loaded || service.status == "stopped" { return .yellow }
        return .secondary
    }

    private func performAction(_ action: () async -> CommandResult) async {
        isPerformingAction = true
        actionOutput = nil
        let result = await action()
        actionOutput = result.output
        if !result.success {
            errorMessage = result.output.isEmpty ? "Command failed" : result.output
            showError = true
        }
        isPerformingAction = false
        await onRefresh()
    }
}
