import Foundation
import OSLog

private let logger = Logger(subsystem: "io.linnane.brewy", category: "BrewService+Fetching")

extension BrewService {

    // MARK: - Fetch Installed Packages

    func fetchInstalledFormulae() async -> [BrewPackage] {
        let result = await runBrewCommand(["info", "--installed", "--json=v2"])
        guard result.success, let data = result.output.data(using: .utf8) else {
            if !result.success {
                lastError = .commandFailed(command: "info --installed", output: result.output)
            }
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

    func fetchInstalledCasks() async -> [BrewPackage] {
        let result = await runBrewCommand(["info", "--installed", "--cask", "--json=v2"])
        guard result.success, let data = result.output.data(using: .utf8) else {
            if !result.success {
                lastError = .commandFailed(command: "info --installed --cask", output: result.output)
            }
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

    func fetchOutdatedPackages() async -> [BrewPackage] {
        let result = await runBrewCommand(["outdated", "--json=v2"])
        guard result.success, let data = result.output.data(using: .utf8) else {
            if !result.success {
                lastError = .commandFailed(command: "outdated", output: result.output)
            }
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

    func fetchTaps() async -> [BrewTap] {
        let result = await runBrewCommand(["tap-info", "--json=v1", "--installed"])
        guard result.success, let data = result.output.data(using: .utf8) else {
            if !result.success {
                lastError = .commandFailed(command: "tap-info", output: result.output)
            }
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

    // MARK: - Search

    func performSearch(query: String) async -> [BrewPackage] {
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
}
