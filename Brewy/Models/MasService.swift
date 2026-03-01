import Foundation
import OSLog

private let logger = Logger(subsystem: "io.linnane.brewy", category: "MasService")

// MARK: - Mas Output Parser

enum MasParser {

    /// Parses `mas list` output: `497799835 Xcode (15.4)`
    static func parseList(_ output: String) -> [BrewPackage] {
        var packages: [BrewPackage] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Format: <id> <name> (<version>)
            guard let firstSpace = trimmed.firstIndex(of: " ") else { continue }
            let appId = String(trimmed[trimmed.startIndex..<firstSpace])
            guard Int(appId) != nil else { continue }

            let rest = trimmed[trimmed.index(after: firstSpace)...].trimmingCharacters(in: .whitespaces)

            var name = rest
            var version = "unknown"
            if let parenOpen = rest.lastIndex(of: "("),
               let parenClose = rest.lastIndex(of: ")"),
               parenClose > parenOpen {
                name = rest[rest.startIndex..<parenOpen].trimmingCharacters(in: .whitespaces)
                version = String(rest[rest.index(after: parenOpen)..<parenClose])
            }

            packages.append(BrewPackage(
                id: "mas-\(appId)",
                name: name,
                version: version,
                description: "",
                homepage: "https://apps.apple.com/app/id\(appId)",
                isInstalled: true,
                isOutdated: false,
                installedVersion: version,
                latestVersion: nil,
                source: .mas,
                pinned: false,
                installedOnRequest: true,
                dependencies: []
            ))
        }
        return packages
    }

    /// Parses `mas outdated` output: `497799835 Xcode (15.4 -> 16.0)`
    static func parseOutdated(_ output: String) -> [BrewPackage] {
        var packages: [BrewPackage] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let firstSpace = trimmed.firstIndex(of: " ") else { continue }
            let appId = String(trimmed[trimmed.startIndex..<firstSpace])
            guard Int(appId) != nil else { continue }

            let rest = trimmed[trimmed.index(after: firstSpace)...].trimmingCharacters(in: .whitespaces)

            var name = rest
            var installedVersion = "unknown"
            var latestVersion = "unknown"
            if let parenOpen = rest.lastIndex(of: "("),
               let parenClose = rest.lastIndex(of: ")"),
               parenClose > parenOpen {
                name = rest[rest.startIndex..<parenOpen].trimmingCharacters(in: .whitespaces)
                let versionStr = String(rest[rest.index(after: parenOpen)..<parenClose])
                let parts = versionStr.components(separatedBy: "->").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if parts.count == 2 {
                    installedVersion = parts[0]
                    latestVersion = parts[1]
                } else {
                    installedVersion = versionStr
                    latestVersion = versionStr
                }
            }

            packages.append(BrewPackage(
                id: "mas-\(appId)",
                name: name,
                version: installedVersion,
                description: "",
                homepage: "https://apps.apple.com/app/id\(appId)",
                isInstalled: true,
                isOutdated: true,
                installedVersion: installedVersion,
                latestVersion: latestVersion,
                source: .mas,
                pinned: false,
                installedOnRequest: true,
                dependencies: []
            ))
        }
        return packages
    }
}

// MARK: - BrewService Mas Integration

extension BrewService {

    func fetchInstalledMasApps() async -> [BrewPackage] {
        let masPath = CommandRunner.resolvedMasPath()
        guard FileManager.default.isExecutableFile(atPath: masPath) else {
            isMasAvailable = false
            return []
        }
        isMasAvailable = true

        let result = await CommandRunner.runExecutable(masPath, arguments: ["list"])
        guard result.success else {
            logger.warning("Failed to fetch installed mas apps")
            return []
        }
        return MasParser.parseList(result.output)
    }

    func fetchOutdatedMasApps() async -> [BrewPackage] {
        let masPath = CommandRunner.resolvedMasPath()
        guard FileManager.default.isExecutableFile(atPath: masPath) else { return [] }

        let result = await CommandRunner.runExecutable(masPath, arguments: ["outdated"])
        guard result.success else {
            logger.warning("Failed to fetch outdated mas apps")
            return []
        }
        return MasParser.parseOutdated(result.output)
    }

    func installMas() async {
        logger.info("Installing mas via Homebrew")
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let brewPath = CommandRunner.resolvedBrewPath(preferred: customBrewPath)
        let result = await CommandRunner.run(["install", "mas"], brewPath: brewPath)
        actionOutput = result.output
        if result.success {
            isMasAvailable = true
            await refresh()
        } else {
            lastError = .commandFailed(command: "install mas", output: result.output)
        }
    }
}
