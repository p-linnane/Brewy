import Foundation
import OSLog

private let logger = Logger(subsystem: "io.linnane.brewy", category: "ServicesService")

// MARK: - Services Parser

enum ServicesParser {

    static func parseJSON(_ output: String) -> [BrewServiceItem] {
        guard let data = output.data(using: .utf8) else { return [] }
        do {
            return try JSONDecoder().decode([BrewServiceItem].self, from: data)
        } catch {
            logger.error("Failed to parse services JSON: \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - BrewService Services Integration

extension BrewService {

    func fetchServices() async -> [BrewServiceItem] {
        let brewPath = CommandRunner.resolvedBrewPath(preferred: customBrewPath)

        let infoResult = await CommandRunner.run(["services", "info", "--all", "--json"], brewPath: brewPath)
        if infoResult.success {
            let services = ServicesParser.parseJSON(infoResult.output)
            if !services.isEmpty { return services }
        }

        let listResult = await CommandRunner.run(["services", "list", "--json"], brewPath: brewPath)
        guard listResult.success else {
            logger.warning("Failed to fetch services: \(listResult.output.prefix(200))")
            return []
        }
        return ServicesParser.parseJSON(listResult.output)
    }

    func startService(_ name: String, asSudo: Bool = false) async -> CommandResult {
        await runServiceCommand(["services", "start", name], asSudo: asSudo)
    }

    func stopService(_ name: String, asSudo: Bool = false) async -> CommandResult {
        await runServiceCommand(["services", "stop", name], asSudo: asSudo)
    }

    func restartService(_ name: String, asSudo: Bool = false) async -> CommandResult {
        await runServiceCommand(["services", "restart", name], asSudo: asSudo)
    }

    func cleanupServices() async -> CommandResult {
        let brewPath = CommandRunner.resolvedBrewPath(preferred: customBrewPath)
        let result = await CommandRunner.run(["services", "cleanup"], brewPath: brewPath)
        if !result.success {
            logger.warning("Services cleanup failed: \(result.output.prefix(200))")
        }
        return result
    }

    private func runServiceCommand(_ arguments: [String], asSudo: Bool) async -> CommandResult {
        let brewPath = CommandRunner.resolvedBrewPath(preferred: customBrewPath)
        if asSudo {
            return await CommandRunner.runExecutable(
                "/usr/bin/sudo",
                arguments: [brewPath] + arguments
            )
        }
        return await CommandRunner.run(arguments, brewPath: brewPath)
    }
}
