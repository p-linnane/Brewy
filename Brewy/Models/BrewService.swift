import Foundation
import SwiftUI

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
    var errorMessage: String?
    var lastUpdated: Date?

    private var tapsLoaded = false

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
        case .taps: []
        case .maintenance: []
        }
    }

    // MARK: - Cache

    private nonisolated static let cacheDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Brewy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private nonisolated static let cacheURL = cacheDirectory.appendingPathComponent("packageCache.json")

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
        let hadCachedData = !installedFormulae.isEmpty || !installedCasks.isEmpty
        if !hadCachedData {
            isLoading = true
        }
        errorMessage = nil
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
        errorMessage = nil
        defer { isLoading = false }

        searchResults = await performSearch(query: query)
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
        errorMessage = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["upgrade"])
        actionOutput = result.output
        if !result.success {
            errorMessage = result.output
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
        errorMessage = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["update"])
        actionOutput = result.output
        if !result.success {
            errorMessage = result.output
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
        errorMessage = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["tap", name])
        actionOutput = result.output
        if !result.success {
            errorMessage = result.output
        }
        tapsLoaded = false
        await ensureTapsLoaded()
        await refresh()
    }

    func removeTap(name: String) async {
        isPerformingAction = true
        actionOutput = ""
        errorMessage = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["untap", name])
        actionOutput = result.output
        if !result.success {
            errorMessage = result.output
        }
        tapsLoaded = false
        await ensureTapsLoaded()
        await refresh()
    }

    func upgradeSelected(packages: [BrewPackage]) async {
        isPerformingAction = true
        actionOutput = ""
        errorMessage = nil
        defer { isPerformingAction = false }

        let formulae = packages.filter { !$0.isCask }.map(\.name)
        let casks = packages.filter(\.isCask).map(\.name)

        if !formulae.isEmpty {
            let result = await runBrewCommand(["upgrade"] + formulae)
            actionOutput += result.output
            if !result.success { errorMessage = result.output }
        }
        if !casks.isEmpty {
            let result = await runBrewCommand(["upgrade", "--cask"] + casks)
            actionOutput += result.output
            if !result.success { errorMessage = (errorMessage ?? "") + "\n" + result.output }
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
        errorMessage = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["autoremove"])
        actionOutput = result.output
        if !result.success {
            errorMessage = result.output
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
        errorMessage = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(["cleanup", "--prune=all", "-s"])
        actionOutput = result.output
        if !result.success {
            errorMessage = result.output
        }
    }

    func info(for package: BrewPackage) async -> String {
        let command = package.isCask ? ["info", "--cask", package.name] : ["info", package.name]
        let result = await runBrewCommand(command)
        return result.output
    }

    // MARK: - Private Helpers

    private func performAction(_ action: String, package: BrewPackage) async {
        isPerformingAction = true
        actionOutput = ""
        errorMessage = nil
        defer { isPerformingAction = false }

        var args = [action]
        if package.isCask { args.append("--cask") }
        args.append(package.name)

        let result = await runBrewCommand(args)
        actionOutput = result.output
        if !result.success {
            errorMessage = result.output
        }
        await refresh()
    }

    private func fetchInstalledFormulae() async -> [BrewPackage] {
        let result = await runBrewCommand(["info", "--installed", "--json=v2"])
        guard result.success, let data = result.output.data(using: .utf8) else { return [] }

        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let formulae = json?["formulae"] as? [[String: Any]] ?? []
                return formulae.compactMap { Self.parseFormula($0) }
            } catch {
                return []
            }
        }.value
    }

    private func fetchInstalledCasks() async -> [BrewPackage] {
        let result = await runBrewCommand(["info", "--installed", "--cask", "--json=v2"])
        guard result.success, let data = result.output.data(using: .utf8) else { return [] }

        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let casks = json?["casks"] as? [[String: Any]] ?? []
                return casks.compactMap { Self.parseCask($0) }
            } catch {
                return []
            }
        }.value
    }

    private func fetchOutdatedPackages() async -> [BrewPackage] {
        let result = await runBrewCommand(["outdated", "--json=v2"])
        guard result.success, let data = result.output.data(using: .utf8) else { return [] }

        return await Task.detached(priority: .userInitiated) {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let formulae = json?["formulae"] as? [[String: Any]] ?? []
                let casks = json?["casks"] as? [[String: Any]] ?? []

                let outdatedFormulae = formulae.compactMap { dict -> BrewPackage? in
                    guard let name = dict["name"] as? String,
                          let installedVersions = dict["installed_versions"] as? [String],
                          let currentVersion = dict["current_version"] as? String else { return nil }
                    return BrewPackage(
                        id: "formula-\(name)",
                        name: name,
                        version: installedVersions.first ?? "unknown",
                        description: "",
                        homepage: "",
                        isInstalled: true,
                        isOutdated: true,
                        installedVersion: installedVersions.first,
                        latestVersion: currentVersion,
                        isCask: false,
                        pinned: dict["pinned"] as? Bool ?? false,
                        installedOnRequest: true,
                        dependencies: []
                    )
                }

                let outdatedCasks = casks.compactMap { dict -> BrewPackage? in
                    guard let name = dict["name"] as? String,
                          let installedVersions = dict["installed_versions"] as? String,
                          let currentVersion = dict["current_version"] as? String else { return nil }
                    return BrewPackage(
                        id: "cask-\(name)",
                        name: name,
                        version: installedVersions,
                        description: "",
                        homepage: "",
                        isInstalled: true,
                        isOutdated: true,
                        installedVersion: installedVersions,
                        latestVersion: currentVersion,
                        isCask: true,
                        pinned: false,
                        installedOnRequest: true,
                        dependencies: []
                    )
                }

                return outdatedFormulae + outdatedCasks
            } catch {
                return []
            }
        }.value
    }

    private func fetchTaps() async -> [BrewTap] {
        let result = await runBrewCommand(["tap-info", "--json=v1", "--installed"])
        guard result.success, let data = result.output.data(using: .utf8) else { return [] }

        return await Task.detached(priority: .userInitiated) {
            do {
                let taps = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
                return taps.compactMap { dict -> BrewTap? in
                    guard let name = dict["name"] as? String else { return nil }
                    var remote = dict["remote"] as? String ?? ""
                    if remote.hasSuffix(".git") {
                        remote = String(remote.dropLast(4))
                    }
                    let official = dict["official"] as? Bool ?? false
                    let formulaNames = dict["formula_names"] as? [String] ?? []
                    let caskTokens = dict["cask_tokens"] as? [String] ?? []
                    return BrewTap(
                        name: name,
                        remote: remote,
                        isOfficial: official,
                        formulaNames: formulaNames,
                        caskTokens: caskTokens
                    )
                }
            } catch {
                return []
            }
        }.value
    }

    private func performSearch(query: String) async -> [BrewPackage] {
        let result = await runBrewCommand(["search", "--formulae", "--casks", query])
        guard result.success else { return [] }

        let lines = result.output.components(separatedBy: "\n").filter { !$0.isEmpty }
        let knownNames = installedNames
        var packages: [BrewPackage] = []
        packages.reserveCapacity(lines.count)
        var isCaskSection = false

        for line in lines {
            if line.hasPrefix("==> Formulae") { isCaskSection = false; continue }
            if line.hasPrefix("==> Casks") { isCaskSection = true; continue }
            if line.hasPrefix("==>") { continue }

            let name = line.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            packages.append(BrewPackage(
                id: "\(isCaskSection ? "cask" : "formula")-search-\(name)",
                name: name,
                version: "",
                description: "",
                homepage: "",
                isInstalled: knownNames.contains(name),
                isOutdated: false,
                installedVersion: nil,
                latestVersion: nil,
                isCask: isCaskSection,
                pinned: false,
                installedOnRequest: false,
                dependencies: []
            ))
        }

        return packages
    }

    private nonisolated static func parseFormula(_ dict: [String: Any]) -> BrewPackage? {
        guard let name = dict["name"] as? String else { return nil }
        let versions = dict["versions"] as? [String: Any]
        let stable = versions?["stable"] as? String ?? "unknown"
        let desc = dict["desc"] as? String ?? ""
        let homepage = dict["homepage"] as? String ?? ""
        let installed = dict["installed"] as? [[String: Any]]
        let installedVersion = installed?.first?["version"] as? String
        let pinned = dict["pinned"] as? Bool ?? false
        let installedOnRequest = installed?.first?["installed_on_request"] as? Bool ?? false
        let deps = dict["dependencies"] as? [String] ?? []

        return BrewPackage(
            id: "formula-\(name)",
            name: name,
            version: installedVersion ?? stable,
            description: desc,
            homepage: homepage,
            isInstalled: true,
            isOutdated: false,
            installedVersion: installedVersion,
            latestVersion: stable,
            isCask: false,
            pinned: pinned,
            installedOnRequest: installedOnRequest,
            dependencies: deps
        )
    }

    private nonisolated static func parseCask(_ dict: [String: Any]) -> BrewPackage? {
        guard let token = dict["token"] as? String else { return nil }
        let version = dict["version"] as? String ?? "unknown"
        let desc = dict["desc"] as? String ?? ""
        let homepage = dict["homepage"] as? String ?? ""

        return BrewPackage(
            id: "cask-\(token)",
            name: token,
            version: version,
            description: desc,
            homepage: homepage,
            isInstalled: true,
            isOutdated: false,
            installedVersion: version,
            latestVersion: nil,
            isCask: true,
            pinned: false,
            installedOnRequest: true,
            dependencies: []
        )
    }

    private nonisolated static func mergeOutdatedStatus(
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

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                process.waitUntilExit()

                let output = String(data: stdoutData, encoding: .utf8) ?? ""
                let errorOutput = String(data: stderrData, encoding: .utf8) ?? ""
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
