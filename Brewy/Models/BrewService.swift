import Foundation
import SwiftUI

// MARK: - Error Types

enum BrewError: LocalizedError {
    case brewNotFound(path: String)
    case commandFailed(command: String, output: String)
    case parseFailed(command: String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound(let path):
            return "Homebrew not found at \(path)"
        case .commandFailed(_, let output):
            return output
        case .parseFailed(let command):
            return "Failed to parse output from: brew \(command)"
        }
    }
}

@Observable
@MainActor
final class BrewService {
    @ObservationIgnored
    @AppStorage("brewPath") var customBrewPath = "/opt/homebrew/bin/brew"

    var installedFormulae: [BrewPackage] = [] {
        didSet { invalidateDerivedState() }
    }
    var installedCasks: [BrewPackage] = [] {
        didSet { invalidateDerivedState() }
    }
    var outdatedPackages: [BrewPackage] = []
    var installedTaps: [BrewTap] = []
    var searchResults: [BrewPackage] = []
    var isLoading = false
    var isPerformingAction = false
    var actionOutput: String = ""
    var lastError: BrewError?
    var lastUpdated: Date?

    private var tapsLoaded = false
    private var infoCache: [String: String] = [:]

    // MARK: - Cached Derived State

    private(set) var allInstalled: [BrewPackage] = []
    private(set) var installedNames: Set<String> = []
    private(set) var reverseDependencies: [String: [BrewPackage]] = [:]

    private func invalidateDerivedState() {
        let all = installedFormulae + installedCasks
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
    }

    var pinnedPackages: [BrewPackage] {
        allInstalled.filter(\.pinned)
    }

    var leavesPackages: [BrewPackage] {
        installedFormulae.filter { pkg in
            (reverseDependencies[pkg.name] ?? []).isEmpty
        }
    }

    func dependents(of name: String) -> [BrewPackage] {
        reverseDependencies[name] ?? []
    }

    func packages(for category: SidebarCategory) -> [BrewPackage] {
        switch category {
        case .installed: allInstalled
        case .formulae: installedFormulae
        case .casks: installedCasks
        case .outdated: outdatedPackages
        case .pinned: pinnedPackages
        case .leaves: leavesPackages
        case .taps: []
        case .discover: searchResults
        case .maintenance: []
        }
    }

    // MARK: - Cache

    nonisolated private static let cacheDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Brewy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    nonisolated private static let cacheURL = cacheDirectory.appendingPathComponent("packageCache.json")

    private struct CachedData: Codable {
        let formulae: [BrewPackage]
        let casks: [BrewPackage]
        let outdated: [BrewPackage]
        let taps: [BrewTap]
        let lastUpdated: Date
    }

    func loadFromCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data) else { return }
        installedFormulae = cached.formulae
        installedCasks = cached.casks
        outdatedPackages = cached.outdated
        installedTaps = cached.taps
        tapsLoaded = !cached.taps.isEmpty
        lastUpdated = cached.lastUpdated
    }

    private func saveToCache() {
        let cached = CachedData(
            formulae: installedFormulae,
            casks: installedCasks,
            outdated: outdatedPackages,
            taps: installedTaps,
            lastUpdated: lastUpdated ?? Date()
        )
        Task.detached(priority: .utility) {
            try? JSONEncoder().encode(cached).write(to: Self.cacheURL, options: .atomic)
        }
    }

    // MARK: - Homebrew CLI Interactions

    func refresh() async {
        infoCache.removeAll()
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

        let fetchedFormulae = await formulae
        let fetchedCasks = await casks
        let fetchedOutdated = await outdated
        let outdatedByID = Dictionary(uniqueKeysWithValues: fetchedOutdated.map { ($0.id, $0) })

        installedFormulae = fetchedFormulae.map { Self.mergeOutdatedStatus($0, outdatedByID: outdatedByID) }
        installedCasks = fetchedCasks.map { Self.mergeOutdatedStatus($0, outdatedByID: outdatedByID) }
        outdatedPackages = fetchedOutdated
        lastUpdated = Date()

        installedTaps = await fetchTaps()
        tapsLoaded = true

        saveToCache()
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
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["upgrade"])
        actionOutput = result.output
        if !result.success {
            lastError = .commandFailed(command: "upgrade", output: result.output)
        }
        await refresh()
    }

    func pin(package: BrewPackage) async {
        await performAction("pin", package: package)
    }

    func unpin(package: BrewPackage) async {
        await performAction("unpin", package: package)
    }

    func updateHomebrew() async {
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["update"])
        actionOutput = result.output
        if !result.success {
            lastError = .commandFailed(command: "update", output: result.output)
        }
        await refresh()
    }

    func cleanup() async {
        isPerformingAction = true
        actionOutput = ""
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["cleanup", "--prune=all"])
        actionOutput = result.output
    }

    func addTap(name: String) async {
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["tap", name])
        actionOutput = result.output
        if !result.success {
            lastError = .commandFailed(command: "tap", output: result.output)
        }
        tapsLoaded = false
        await ensureTapsLoaded()
        await refresh()
    }

    func removeTap(name: String) async {
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["untap", name])
        actionOutput = result.output
        if !result.success {
            lastError = .commandFailed(command: "untap", output: result.output)
        }
        tapsLoaded = false
        await ensureTapsLoaded()
        await refresh()
    }

    func upgradeSelected(packages: [BrewPackage]) async {
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let formulae = packages.filter { !$0.isCask }.map(\.name)
        let casks = packages.filter(\.isCask).map(\.name)

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
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["autoremove"])
        actionOutput = result.output
        if !result.success {
            lastError = .commandFailed(command: "autoremove", output: result.output)
        }
        await refresh()
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
            } catch {}
            return Int64(0)
        }.value
        return duResult
    }

    func purgeCache() async {
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["cleanup", "--prune=all", "-s"])
        actionOutput = result.output
        if !result.success {
            lastError = .commandFailed(command: "cleanup", output: result.output)
        }
    }

    func config() async -> BrewConfig {
        let result = await runBrewCommand(["config"])
        return BrewConfig.parse(from: result.output)
    }

    func info(for package: BrewPackage) async -> String {
        if let cached = infoCache[package.id] { return cached }
        let command = package.isCask ? ["info", "--cask", package.name] : ["info", package.name]
        let result = await runBrewCommand(command)
        infoCache[package.id] = result.output
        return result.output
    }

    // MARK: - Private Helpers

    private func performAction(_ action: String, package: BrewPackage) async {
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
            lastError = .commandFailed(command: action, output: result.output)
        }
        await refresh()
    }

    private func fetchInstalledFormulae() async -> [BrewPackage] {
        let result = await runBrewCommand(["info", "--installed", "--json=v2"])
        guard result.success, let data = result.output.data(using: .utf8) else { return [] }

        return await Task.detached(priority: .userInitiated) {
            guard let response = try? JSONDecoder().decode(BrewInfoResponse.self, from: data) else { return [] }
            return (response.formulae ?? []).map { $0.toPackage() }
        }.value
    }

    private func fetchInstalledCasks() async -> [BrewPackage] {
        let result = await runBrewCommand(["info", "--installed", "--cask", "--json=v2"])
        guard result.success, let data = result.output.data(using: .utf8) else { return [] }

        return await Task.detached(priority: .userInitiated) {
            guard let response = try? JSONDecoder().decode(BrewInfoResponse.self, from: data) else { return [] }
            return (response.casks ?? []).map { $0.toPackage() }
        }.value
    }

    private func fetchOutdatedPackages() async -> [BrewPackage] {
        let result = await runBrewCommand(["outdated", "--json=v2"])
        guard result.success, let data = result.output.data(using: .utf8) else { return [] }

        return await Task.detached(priority: .userInitiated) {
            guard let response = try? JSONDecoder().decode(BrewOutdatedResponse.self, from: data) else { return [] }
            let formulae = (response.formulae ?? []).compactMap { $0.toPackage() }
            let casks = (response.casks ?? []).compactMap { $0.toPackage() }
            return formulae + casks
        }.value
    }

    private func fetchTaps() async -> [BrewTap] {
        let result = await runBrewCommand(["tap-info", "--json=v1", "--installed"])
        guard result.success, let data = result.output.data(using: .utf8) else { return [] }

        return await Task.detached(priority: .userInitiated) {
            guard let taps = try? JSONDecoder().decode([TapJSON].self, from: data) else { return [] }
            return taps.map { $0.toTap() }
        }.value
    }

    private func performSearch(query: String) async -> [BrewPackage] {
        async let formulaeResult = runBrewCommand(["search", "--formula", query])
        async let casksResult = runBrewCommand(["search", "--cask", query])

        let formulaeOutput = await formulaeResult
        let casksOutput = await casksResult

        let knownNames = installedNames
        var packages: [BrewPackage] = []

        for output in [(formulaeOutput, false), (casksOutput, true)] {
            let (result, isCask) = output
            guard result.success else { continue }

            let names = result.output
                .components(separatedBy: "\n")
                .flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
                .filter { !$0.isEmpty && !$0.hasPrefix("==>") }

            for name in names {
                packages.append(BrewPackage(
                    id: "\(isCask ? "cask" : "formula")-search-\(name)",
                    name: name,
                    version: "",
                    description: "",
                    homepage: "",
                    isInstalled: knownNames.contains(name),
                    isOutdated: false,
                    installedVersion: nil,
                    latestVersion: nil,
                    isCask: isCask,
                    pinned: false,
                    installedOnRequest: false,
                    dependencies: []
                ))
            }
        }

        return packages
    }

    nonisolated private static func mergeOutdatedStatus(
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
            isCask: pkg.isCask, pinned: pkg.pinned,
            installedOnRequest: pkg.installedOnRequest,
            dependencies: pkg.dependencies
        )
    }

    private func resolvedBrewPath() -> String {
        let primary = customBrewPath
        let fallback = "/usr/local/bin/brew"
        if FileManager.default.isExecutableFile(atPath: primary) { return primary }
        if FileManager.default.isExecutableFile(atPath: fallback) { return fallback }
        return primary
    }

    private func runBrewCommand(_ arguments: [String]) async -> CommandResult {
        let brewPath = resolvedBrewPath()
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()

                async let stderrData = withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        continuation.resume(returning: data)
                    }
                }

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let resolvedStderr = await stderrData

                process.waitUntilExit()

                let output = String(data: stdoutData, encoding: .utf8) ?? ""
                let errorOutput = String(data: resolvedStderr, encoding: .utf8) ?? ""
                let combinedOutput = output.isEmpty ? errorOutput : output

                return CommandResult(output: combinedOutput, success: process.terminationStatus == 0)
            } catch {
                return CommandResult(
                    output: "Failed to run brew: \(error.localizedDescription)",
                    success: false
                )
            }
        }.value
    }
}

private struct CommandResult: Sendable {
    let output: String
    let success: Bool
}
