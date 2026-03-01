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
        case .commandFailed(_, let output):
            return output
        case .parseFailed(let command):
            return "Failed to parse output from: brew \(command)"
        case .commandTimedOut(let command):
            return "Command timed out: brew \(command)"
        }
    }
}

@Observable
@MainActor
final class BrewService {
    @ObservationIgnored
    @AppStorage("brewPath") var customBrewPath = "/opt/homebrew/bin/brew"

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

    private var tapsLoaded = false
    @ObservationIgnored private var isBatchingUpdates = false
    @ObservationIgnored private var infoCache: [String: String] = [:]

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
        case .discover: searchResults
        case .maintenance: []
        }
    }

    // MARK: - Cache

    nonisolated private static let cacheDirectory: URL? = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("Brewy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    nonisolated private static let cacheURL: URL? = cacheDirectory?.appendingPathComponent("packageCache.json")

    private struct CachedData: Codable {
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
        }
    }

    private func saveToCache() {
        guard let cacheURL = Self.cacheURL else { return }
        let cached = CachedData(
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
        logger.info("Starting full refresh")
        let previousVersions = Dictionary(uniqueKeysWithValues: allInstalled.map { ($0.id, $0.version) })
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
        let outdatedByID = Dictionary(uniqueKeysWithValues: allOutdated.map { ($0.id, $0) })

        updateInstalledPackages(
            formulae: fetchedFormulae.map { Self.mergeOutdatedStatus($0, outdatedByID: outdatedByID) },
            casks: fetchedCasks.map { Self.mergeOutdatedStatus($0, outdatedByID: outdatedByID) },
            masApps: fetchedMasApps.map { Self.mergeOutdatedStatus($0, outdatedByID: outdatedByID) }
        )
        outdatedPackages = allOutdated
        lastUpdated = Date()

        let currentVersions = Dictionary(uniqueKeysWithValues: allInstalled.map { ($0.id, $0.version) })
        for id in infoCache.keys where currentVersions[id] != previousVersions[id] {
            infoCache.removeValue(forKey: id)
        }

        installedTaps = await fetchTaps()
        tapsLoaded = true

        let masCount = fetchedMasApps.count
        let outdatedCount = allOutdated.count
        logger.info("Refresh complete: \(fetchedFormulae.count) formulae, \(fetchedCasks.count) casks, \(masCount) mas, \(outdatedCount) outdated")
        saveToCache()
        Task { await checkTapHealth() }
    }

    func ensureTapsLoaded() async {
        guard !tapsLoaded else { return }
        tapsLoaded = true
        installedTaps = await fetchTaps()
        saveToCache()
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

    func install(package: BrewPackage) async {
        await performAction("install", package: package)
    }

    func uninstall(package: BrewPackage) async {
        await performAction("uninstall", package: package)
    }

    func upgrade(package: BrewPackage) async {
        await performAction("upgrade", package: package)
    }

    func upgradeAll() async {
        await performBrewAction(["upgrade"], refreshAfter: true)
    }

    func pin(package: BrewPackage) async {
        await performAction("pin", package: package)
    }

    func unpin(package: BrewPackage) async {
        await performAction("unpin", package: package)
    }

    func updateHomebrew() async {
        await performBrewAction(["update"], refreshAfter: true)
    }

    func cleanup() async {
        await performBrewAction(["cleanup", "--prune=all"])
    }

    func addTap(name: String) async {
        await performTapAction { await runTapCommand(["tap", name]) }
    }

    func removeTap(name: String) async {
        await performTapAction { await runTapCommand(["untap", name]) }
    }

    func migrateTap(from oldName: String, to newName: String) async {
        await performTapAction {
            logger.info("Migrating tap \(oldName) → \(newName)")
            guard await runTapCommand(["untap", oldName]) else { return false }
            tapHealthStatuses.removeValue(forKey: oldName)
            return await runTapCommand(["tap", newName])
        }
    }

    private func performTapAction(_ action: () async -> Bool) async {
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }
        _ = await action()
        tapsLoaded = false
        await ensureTapsLoaded()
        await refresh()
    }

    @discardableResult
    private func runTapCommand(_ arguments: [String]) async -> Bool {
        let result = await runBrewCommand(arguments)
        actionOutput += actionOutput.isEmpty ? result.output : "\n" + result.output
        if !result.success {
            lastError = .commandFailed(command: arguments.first ?? "", output: result.output)
        }
        return result.success
    }

    func upgradeSelected(packages: [BrewPackage]) async {
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let formulae = packages.filter { $0.source == .formula }.map(\.name)
        let casks = packages.filter { $0.source == .cask }.map(\.name)

        if !formulae.isEmpty {
            let result = await runBrewCommand(["upgrade"] + formulae)
            actionOutput += result.output
            if !result.success { lastError = .commandFailed(command: "upgrade", output: result.output) }
        }
        if !casks.isEmpty {
            let result = await runBrewCommand(["upgrade", "--cask"] + casks)
            actionOutput += result.output
            if !result.success { lastError = .commandFailed(command: "upgrade --cask", output: result.output) }
        }
        await refresh()
    }

    func doctor() async -> String {
        let result = await runBrewCommand(["doctor"])
        return result.output
    }

    func removeOrphans() async {
        await performBrewAction(["autoremove"], refreshAfter: true)
    }

    func cacheSize() async -> Int64 {
        let pathResult = await runBrewCommand(["--cache"])
        let cachePath = pathResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cachePath.isEmpty else { return 0 }

        let duResult = await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
            process.arguments = ["-sk", cachePath]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""
                if let sizeStr = output.split(separator: "\t").first,
                   let sizeKB = Int64(sizeStr) {
                    return sizeKB * 1024
                }
            } catch {
                logger.warning("Failed to calculate cache size: \(error.localizedDescription)")
            }
            return Int64(0)
        }.value
        return duResult
    }

    func purgeCache() async {
        await performBrewAction(["cleanup", "--prune=all", "-s"])
    }

    func config() async -> BrewConfig {
        let result = await runBrewCommand(["config"])
        return BrewConfig.parse(from: result.output)
    }

    func info(for package: BrewPackage) async -> String {
        guard !package.isMas else { return "" }
        if let cached = infoCache[package.id] { return cached }
        let command = package.isCask ? ["info", "--cask", package.name] : ["info", package.name]
        let result = await runBrewCommand(command)
        infoCache[package.id] = result.output
        return result.output
    }

    // MARK: - Private Helpers

    private func performBrewAction(_ arguments: [String], refreshAfter: Bool = false) async {
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(arguments)
        actionOutput = result.output
        if !result.success {
            lastError = .commandFailed(command: arguments.joined(separator: " "), output: result.output)
        }
        if refreshAfter {
            await refresh()
        }
    }

    private func performAction(_ action: String, package: BrewPackage) async {
        guard !package.isMas else {
            logger.warning("Cannot perform brew action \(action) on mas package \(package.name)")
            return
        }
        logger.info("Performing \(action) on \(package.name)")
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        var args = [action]
        if package.isCask { args.append("--cask") }
        args.append(package.name)

        let result = await runBrewCommand(args)
        actionOutput = result.output
        if !result.success {
            logger.warning("\(action) failed for \(package.name): \(result.output.prefix(200))")
            lastError = .commandFailed(command: action, output: result.output)
        }
        await refresh()
    }

    private func fetchInstalledFormulae() async -> [BrewPackage] {
        let result = await runBrewCommand(["info", "--installed", "--json=v2"])
        guard result.success, let data = result.output.data(using: .utf8) else {
            logger.warning("Failed to fetch installed formulae")
            return []
        }

        return await Task.detached(priority: .userInitiated) {
            do {
                let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
                return (response.formulae ?? []).map { $0.toPackage() }
            } catch {
                logger.error("Failed to parse formulae JSON: \(error.localizedDescription)")
                return []
            }
        }.value
    }

    private func fetchInstalledCasks() async -> [BrewPackage] {
        let result = await runBrewCommand(["info", "--installed", "--cask", "--json=v2"])
        guard result.success, let data = result.output.data(using: .utf8) else {
            logger.warning("Failed to fetch installed casks")
            return []
        }

        return await Task.detached(priority: .userInitiated) {
            do {
                let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
                return (response.casks ?? []).map { $0.toPackage() }
            } catch {
                logger.error("Failed to parse casks JSON: \(error.localizedDescription)")
                return []
            }
        }.value
    }

    private func fetchOutdatedPackages() async -> [BrewPackage] {
        let result = await runBrewCommand(["outdated", "--json=v2"])
        guard result.success, let data = result.output.data(using: .utf8) else {
            logger.warning("Failed to fetch outdated packages")
            return []
        }

        return await Task.detached(priority: .userInitiated) {
            do {
                let response = try JSONDecoder().decode(BrewOutdatedResponse.self, from: data)
                let formulae = (response.formulae ?? []).compactMap { $0.toPackage() }
                let casks = (response.casks ?? []).compactMap { $0.toPackage() }
                return formulae + casks
            } catch {
                logger.error("Failed to parse outdated JSON: \(error.localizedDescription)")
                return []
            }
        }.value
    }

    private func fetchTaps() async -> [BrewTap] {
        let result = await runBrewCommand(["tap-info", "--json=v1", "--installed"])
        guard result.success, let data = result.output.data(using: .utf8) else {
            logger.warning("Failed to fetch taps")
            return []
        }

        return await Task.detached(priority: .userInitiated) {
            do {
                let taps = try JSONDecoder().decode([TapJSON].self, from: data)
                return taps.map { $0.toTap() }
            } catch {
                logger.error("Failed to parse taps JSON: \(error.localizedDescription)")
                return []
            }
        }.value
    }

    private func performSearch(query: String) async -> [BrewPackage] {
        async let formulaeResult = runBrewCommand(["search", "--formula", query])
        async let casksResult = runBrewCommand(["search", "--cask", query])

        let formulaeOutput = await formulaeResult
        let casksOutput = await casksResult

        let knownNames = installedNames
        var packages: [BrewPackage] = []

        for output in [(formulaeOutput, PackageSource.formula), (casksOutput, PackageSource.cask)] {
            let (result, source) = output
            guard result.success else { continue }

            let prefix = source == .cask ? "cask" : "formula"
            for line in result.output.split(separator: "\n") {
                for token in line.split(whereSeparator: \.isWhitespace) where !token.hasPrefix("==>") {
                    let name = String(token)
                    packages.append(BrewPackage(
                        id: "\(prefix)-search-\(name)",
                        name: name,
                        version: "",
                        description: "",
                        homepage: "",
                        isInstalled: knownNames.contains(name),
                        isOutdated: false,
                        installedVersion: nil,
                        latestVersion: nil,
                        source: source,
                        pinned: false,
                        installedOnRequest: false,
                        dependencies: []
                    ))
                }
            }
        }

        return packages
    }

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

    private func runBrewCommand(_ arguments: [String]) async -> CommandResult {
        let brewPath = CommandRunner.resolvedBrewPath(preferred: customBrewPath)
        return await CommandRunner.run(arguments, brewPath: brewPath)
    }
}
