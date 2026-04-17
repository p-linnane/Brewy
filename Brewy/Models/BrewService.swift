import Foundation
import OSLog
import SwiftUI

// MARK: - Logging

private let logger = Logger(subsystem: "io.linnane.brewy", category: "BrewService")

// MARK: - Error Types

enum BrewError: LocalizedError {
    case brewNotFound(path: String)
    case commandFailed(command: String, output: String)
    case parseFailed(command: String)
    case commandTimedOut(command: String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound(let path):
            return "Homebrew not found at \(path)"
        case .commandFailed(let command, let output):
            return Self.summarize(command: command, output: output)
        case .parseFailed(let command):
            return "Failed to parse output from: brew \(command)"
        case .commandTimedOut(let command):
            return "Command timed out: brew \(command)"
        }
    }

    private static let maxOutputChars = 800

    private static func summarize(command: String, output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "brew \(command) failed." }

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        if let errorLine = lines.first(where: { $0.lowercased().hasPrefix("error:") }) {
            return String(errorLine)
        }
        let tail = lines.suffix(6).joined(separator: "\n")
        if tail.count <= maxOutputChars { return tail }
        return "…" + String(tail.suffix(maxOutputChars))
    }
}

@Observable
@MainActor
final class BrewService {
    @ObservationIgnored let commandRunner: CommandRunning

    @AppStorage("brewPath")
    @ObservationIgnored var customBrewPath = "/opt/homebrew/bin/brew"

    init(commandRunner: CommandRunning = DefaultCommandRunner()) {
        self.commandRunner = commandRunner
    }

    var installedFormulae: [BrewPackage] = [] {
        didSet {
            guard !isBatchingUpdates else { return }
            invalidateDerivedState()
        }
    }
    var installedCasks: [BrewPackage] = [] {
        didSet {
            guard !isBatchingUpdates else { return }
            invalidateDerivedState()
        }
    }
    var installedMasApps: [BrewPackage] = [] {
        didSet {
            guard !isBatchingUpdates else { return }
            invalidateDerivedState()
        }
    }
    var isMasAvailable = false
    var outdatedPackages: [BrewPackage] = []
    var installedTaps: [BrewTap] = []
    var searchResults: [BrewPackage] = []
    var isLoading = false
    var isPerformingAction = false
    var actionOutput: String = ""
    var lastError: BrewError?
    var lastUpdated: Date?
    var tapHealthStatuses: [String: TapHealthStatus] = [:]
    var packageGroups: [PackageGroup] = []
    var actionHistory: [ActionHistoryEntry] = []

    var tapsLoaded = false
    private var isRefreshing = false
    @ObservationIgnored private var isBatchingUpdates = false
    @ObservationIgnored var infoCache: [String: String] = [:]
    @ObservationIgnored private var tapHealthTask: Task<Void, Never>?

    // MARK: - Cached Derived State

    private(set) var allInstalled: [BrewPackage] = []
    private(set) var installedNames: Set<String> = []
    private(set) var reverseDependencies: [String: [BrewPackage]] = [:]
    private(set) var leavesPackages: [BrewPackage] = []
    private(set) var pinnedPackages: [BrewPackage] = []

    private func updateInstalledPackages(formulae: [BrewPackage], casks: [BrewPackage], masApps: [BrewPackage] = []) {
        isBatchingUpdates = true
        installedFormulae = formulae
        installedCasks = casks
        installedMasApps = masApps
        isBatchingUpdates = false
        invalidateDerivedState()
    }

    private func applyRefreshResults(
        formulae: [BrewPackage],
        casks: [BrewPackage],
        masApps: [BrewPackage],
        outdated: [BrewPackage]
    ) {
        isBatchingUpdates = true
        installedFormulae = formulae
        installedCasks = casks
        installedMasApps = masApps
        outdatedPackages = outdated
        isBatchingUpdates = false
        invalidateDerivedState()
    }

    private func invalidateDerivedState() {
        let all = installedFormulae + installedCasks + installedMasApps
        allInstalled = all
        installedNames = Set(all.map(\.name))

        var reverse: [String: [BrewPackage]] = [:]
        reverse.reserveCapacity(all.count)
        for pkg in all {
            for dep in pkg.dependencies {
                reverse[dep, default: []].append(pkg)
            }
        }
        reverseDependencies = reverse
        leavesPackages = installedFormulae.filter { reverse[$0.name] == nil || reverse[$0.name]!.isEmpty }
        pinnedPackages = all.filter(\.pinned)
    }

    func dependents(of name: String) -> [BrewPackage] {
        reverseDependencies[name] ?? []
    }

    func packages(for category: SidebarCategory) -> [BrewPackage] {
        switch category {
        case .installed: allInstalled
        case .formulae: installedFormulae
        case .casks: installedCasks
        case .masApps: installedMasApps
        case .outdated: outdatedPackages
        case .pinned: pinnedPackages
        case .leaves: leavesPackages
        case .taps: []
        case .services: []
        case .groups: []
        case .history: []
        case .discover: searchResults
        case .maintenance: []
        }
    }

    // MARK: - Cache

    nonisolated static let cacheDirectory: URL? = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("Brewy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    nonisolated private static let cacheURL: URL? = cacheDirectory?.appendingPathComponent("packageCache.json")

    /// Current schema version for the package cache. Bump when `CachedData` gains a non-optional
    /// field or changes semantics so old caches are deleted rather than silently discarded each launch.
    static let cacheSchemaVersion = 1

    private struct CachedData: Codable {
        let schemaVersion: Int
        let formulae: [BrewPackage]
        let casks: [BrewPackage]
        let masApps: [BrewPackage]?
        let outdated: [BrewPackage]
        let taps: [BrewTap]
        let lastUpdated: Date
    }

    func loadFromCache() {
        guard let cacheURL = Self.cacheURL else { return }
        do {
            let data = try Data(contentsOf: cacheURL)
            let cached = try JSONDecoder().decode(CachedData.self, from: data)
            guard cached.schemaVersion == Self.cacheSchemaVersion else {
                logger.warning("Cache schema version \(cached.schemaVersion) != \(Self.cacheSchemaVersion), discarding")
                try? FileManager.default.removeItem(at: cacheURL)
                return
            }
            let masApps = cached.masApps ?? []
            updateInstalledPackages(formulae: cached.formulae, casks: cached.casks, masApps: masApps)
            outdatedPackages = cached.outdated
            installedTaps = cached.taps
            tapsLoaded = !cached.taps.isEmpty
            isMasAvailable = !masApps.isEmpty || FileManager.default.isExecutableFile(atPath: CommandRunner.resolvedMasPath())
            lastUpdated = cached.lastUpdated
            logger.info("Loaded \(cached.formulae.count) formulae and \(cached.casks.count) casks from cache")
        } catch {
            logger.warning("Failed to load cache: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: cacheURL)
        }
    }

    func saveToCache() {
        guard let cacheURL = Self.cacheURL,
              ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil else { return }
        let cached = CachedData(
            schemaVersion: Self.cacheSchemaVersion,
            formulae: installedFormulae,
            casks: installedCasks,
            masApps: installedMasApps,
            outdated: outdatedPackages,
            taps: installedTaps,
            lastUpdated: lastUpdated ?? Date()
        )
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(cached)
                try data.write(to: cacheURL, options: .atomic)
                logger.debug("Cache saved successfully")
            } catch {
                logger.error("Failed to save cache: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Tap Health

    func loadTapHealthCache() {
        tapHealthStatuses = TapHealthChecker.loadCache()
    }

    func checkTapHealth() async {
        tapHealthStatuses = await TapHealthChecker.checkHealth(
            taps: installedTaps,
            existing: tapHealthStatuses
        )
    }

    // MARK: - Homebrew CLI Interactions

    func refresh() async {
        guard !isRefreshing else {
            logger.info("Refresh already in progress, skipping")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        logger.info("Starting full refresh")
        let previousVersions = Dictionary(allInstalled.map { ($0.id, $0.version) }, uniquingKeysWith: { _, last in last })
        let hadCachedData = !installedFormulae.isEmpty || !installedCasks.isEmpty
        if !hadCachedData {
            isLoading = true
        }
        lastError = nil
        defer {
            isLoading = false
        }

        async let formulae = fetchInstalledFormulae()
        async let casks = fetchInstalledCasks()
        async let outdated = fetchOutdatedPackages()
        async let masApps = fetchInstalledMasApps()
        async let masOutdated = fetchOutdatedMasApps()

        let fetchedFormulae = await formulae
        let fetchedCasks = await casks
        let fetchedOutdated = await outdated
        let fetchedMasApps = await masApps
        let fetchedMasOutdated = await masOutdated
        let allOutdated = fetchedOutdated + fetchedMasOutdated
        let outdatedByID = Dictionary(allOutdated.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        applyRefreshResults(
            formulae: fetchedFormulae.map { Self.mergeOutdatedStatus($0, outdatedByID: outdatedByID) },
            casks: fetchedCasks.map { Self.mergeOutdatedStatus($0, outdatedByID: outdatedByID) },
            masApps: fetchedMasApps.map { Self.mergeOutdatedStatus($0, outdatedByID: outdatedByID) },
            outdated: allOutdated
        )
        lastUpdated = Date()

        let currentVersions = Dictionary(allInstalled.map { ($0.id, $0.version) }, uniquingKeysWith: { _, last in last })
        for id in infoCache.keys where currentVersions[id] != previousVersions[id] {
            infoCache.removeValue(forKey: id)
        }

        installedTaps = await fetchTaps()
        tapsLoaded = true

        let masCount = fetchedMasApps.count
        let outdatedCount = allOutdated.count
        logger.info("Refresh complete: \(fetchedFormulae.count) formulae, \(fetchedCasks.count) casks, \(masCount) mas, \(outdatedCount) outdated")
        saveToCache()
        if installedTaps.contains(where: { tapHealthStatuses[$0.name]?.isStale ?? true }) {
            tapHealthTask?.cancel()
            tapHealthTask = Task { [weak self] in
                await self?.checkTapHealth()
            }
        }
    }

    func search(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isLoading = true
        lastError = nil

        let results = await performSearch(query: query)
        guard !Task.isCancelled else { return }
        searchResults = results
        isLoading = false
    }

    func upgradeSelected(packages: [BrewPackage]) async {
        guard !isPerformingAction else {
            logger.info("upgradeSelected skipped, action already in progress")
            return
        }
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let formulae = packages.filter { $0.source == .formula }.map(\.name)
        let casks = packages.filter { $0.source == .cask }.map(\.name)

        if !formulae.isEmpty {
            let args = ["upgrade"] + formulae
            let result = await runBrewCommand(args)
            actionOutput += result.output
            if !result.success { lastError = .commandFailed(command: "upgrade", output: result.output) }
            recordAction(arguments: args, packageName: nil, packageSource: .formula, success: result.success, output: result.output)
        }
        if !casks.isEmpty {
            let args = ["upgrade", "--cask"] + casks
            let result = await runBrewCommand(args)
            actionOutput += result.output
            if !result.success { lastError = .commandFailed(command: "upgrade --cask", output: result.output) }
            recordAction(arguments: args, packageName: nil, packageSource: .cask, success: result.success, output: result.output)
        }
        await refresh()
    }

    func runBrewCommand(_ arguments: [String]) async -> CommandResult {
        let brewPath = CommandRunner.resolvedBrewPath(preferred: customBrewPath)
        return await commandRunner.run(arguments, brewPath: brewPath)
    }
}
