import Foundation
import OSLog

private let logger = Logger(subsystem: "io.linnane.brewy", category: "BrewService+History")

// MARK: - Action History

extension BrewService {

    nonisolated static let historyURL: URL? = cacheDirectory?.appendingPathComponent("actionHistory.json")

    static let maxHistoryEntries = 100

    // MARK: - Load & Save

    func loadHistory() {
        guard let url = Self.historyURL else { return }
        do {
            let data = try Data(contentsOf: url)
            actionHistory = try JSONDecoder().decode([ActionHistoryEntry].self, from: data)
            logger.info("Loaded \(self.actionHistory.count) history entries")
        } catch {
            logger.warning("Failed to load history: \(error.localizedDescription)")
        }
    }

    private func saveHistory() {
        guard let url = Self.historyURL,
              ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil else { return }
        let history = actionHistory
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(history)
                try data.write(to: url, options: .atomic)
                logger.debug("History saved successfully")
            } catch {
                logger.error("Failed to save history: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Recording

    func recordAction(
        arguments: [String],
        packageName: String?,
        packageSource: PackageSource?,
        success: Bool,
        output: String
    ) {
        let entry = ActionHistoryEntry(
            id: UUID(),
            command: arguments.first ?? "",
            arguments: arguments,
            packageName: packageName,
            packageSource: packageSource,
            status: success ? .success : .failure,
            output: output,
            timestamp: Date()
        )
        actionHistory.insert(entry, at: 0)
        if actionHistory.count > Self.maxHistoryEntries {
            actionHistory = Array(actionHistory.prefix(Self.maxHistoryEntries))
        }
        saveHistory()
    }

    // MARK: - Retry

    func retryAction(_ entry: ActionHistoryEntry) async {
        guard entry.isRetryable else { return }
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(entry.arguments)
        actionOutput = result.output
        if !result.success {
            lastError = .commandFailed(command: entry.arguments.joined(separator: " "), output: result.output)
        }
        recordAction(
            arguments: entry.arguments,
            packageName: entry.packageName,
            packageSource: entry.packageSource,
            success: result.success,
            output: result.output
        )

        let mutatingCommands: Set<String> = [
            "install", "uninstall", "upgrade", "reinstall",
            "link", "unlink", "autoremove", "cleanup", "update",
            "tap", "untap"
        ]
        if let cmd = entry.arguments.first, mutatingCommands.contains(cmd) {
            await refresh()
        }
    }

    // MARK: - Clear

    func clearHistory() {
        actionHistory.removeAll()
        saveHistory()
    }

    // MARK: - Outdated Merge Helper

    nonisolated static func mergeOutdatedStatus(
        _ pkg: BrewPackage,
        outdatedByID: [String: BrewPackage]
    ) -> BrewPackage {
        guard let outdatedPkg = outdatedByID[pkg.id] else { return pkg }
        return BrewPackage(
            id: pkg.id, name: pkg.name, version: pkg.version,
            description: pkg.description, homepage: pkg.homepage,
            isInstalled: pkg.isInstalled, isOutdated: true,
            installedVersion: pkg.installedVersion,
            latestVersion: outdatedPkg.latestVersion,
            source: pkg.source, pinned: pkg.pinned,
            installedOnRequest: pkg.installedOnRequest,
            dependencies: pkg.dependencies
        )
    }
}
