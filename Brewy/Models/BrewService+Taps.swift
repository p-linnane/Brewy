import Foundation
import OSLog

private let logger = Logger(subsystem: "io.linnane.brewy", category: "BrewService+Taps")

extension BrewService {

    // MARK: - Ensure Taps Loaded

    func ensureTapsLoaded() async {
        guard !tapsLoaded else { return }
        tapsLoaded = true
        installedTaps = await fetchTaps()
        saveToCache()
    }

    // MARK: - Tap Management

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
            let tapped = await runTapCommand(["tap", newName])
            if !tapped {
                logger.warning("Rollback: re-adding \(oldName) after failure to add \(newName)")
                _ = await runTapCommand(["tap", oldName])
            }
            return tapped
        }
    }

    private func performTapAction(_ action: () async -> Bool) async {
        guard !isPerformingAction else {
            logger.info("Tap action skipped, action already in progress")
            return
        }
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
        recordAction(arguments: arguments, packageName: nil, packageSource: nil, success: result.success, output: result.output)
        return result.success
    }
}
