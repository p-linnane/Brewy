extension BrewService {
    // MARK: - Dry-Run Previews

    func dryRunAutoremove() async -> String {
        let result = await runBrewCommand(["autoremove", "--dry-run"])
        return result.output
    }

    func dryRunCleanup() async -> String {
        let result = await runBrewCommand(["cleanup", "--prune=all", "-s", "--dry-run"])
        return result.output
    }
}
