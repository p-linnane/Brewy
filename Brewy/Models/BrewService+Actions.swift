import Foundation
import OSLog

private let logger = Logger(subsystem: "io.linnane.brewy", category: "BrewService+Actions")

extension BrewService {

    // MARK: - Package Actions

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

    func pin(package: BrewPackage) async { await performAction("pin", package: package) }
    func unpin(package: BrewPackage) async { await performAction("unpin", package: package) }
    func reinstall(package: BrewPackage) async { await performAction("reinstall", package: package) }
    func fetch(package: BrewPackage) async { await performAction("fetch", package: package) }
    func link(package: BrewPackage) async { await performAction("link", package: package) }
    func unlink(package: BrewPackage) async { await performAction("unlink", package: package) }

    func updateHomebrew() async {
        await performBrewAction(["update"], refreshAfter: true)
    }

    func cleanup() async {
        await performBrewAction(["cleanup", "--prune=all"])
    }

    // MARK: - Action Helpers

    func performBrewAction(_ arguments: [String], refreshAfter: Bool = false) async {
        guard !isPerformingAction else {
            logger.info("\(arguments.first ?? "action") skipped, action already in progress")
            return
        }
        isPerformingAction = true
        actionOutput = ""
        lastError = nil
        defer { isPerformingAction = false }

        let result = await runBrewCommand(arguments)
        actionOutput = result.output
        if !result.success {
            lastError = .commandFailed(command: arguments.joined(separator: " "), output: result.output)
        }
        recordAction(arguments: arguments, packageName: nil, packageSource: nil, success: result.success, output: result.output)
        if refreshAfter {
            await refresh()
        }
    }

    func performAction(_ action: String, package: BrewPackage) async {
        guard !package.isMas else {
            logger.warning("Cannot perform brew action \(action) on mas package \(package.name)")
            return
        }
        guard !isPerformingAction else {
            logger.info("\(action) on \(package.name) skipped, action already in progress")
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
        recordAction(
            arguments: args,
            packageName: package.name,
            packageSource: package.source,
            success: result.success,
            output: result.output
        )
        await refresh()
    }

    // MARK: - Maintenance

    func doctor() async -> String {
        let result = await runBrewCommand(["doctor"])
        recordAction(arguments: ["doctor"], packageName: nil, packageSource: nil, success: result.success, output: result.output)
        return result.output
    }

    func removeOrphans() async {
        await performBrewAction(["autoremove"], refreshAfter: true)
    }

    func cacheSize() async -> Int64 {
        let pathResult = await runBrewCommand(["--cache"])
        let cachePath = pathResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cachePath.isEmpty else { return 0 }

        let result = await commandRunner.runExecutable("/usr/bin/du", arguments: ["-sk", cachePath])
        guard result.success,
              let sizeStr = result.output.split(separator: "\t").first,
              let sizeKB = Int64(sizeStr) else {
            return 0
        }
        return sizeKB * 1_024
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
}
