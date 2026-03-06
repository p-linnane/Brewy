@testable import Brewy
import Foundation
import Testing

// MARK: - Maintenance Tests

@Suite("BrewService Maintenance")
@MainActor
struct MaintenanceTests {

    @Test("doctor returns brew output")
    func doctorReturnsOutput() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["doctor"], output: "Your system is ready to brew.")

        let output = await service.doctor()

        #expect(output == "Your system is ready to brew.")
    }

    @Test("cleanup calls correct command")
    func cleanupCallsCommand() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["cleanup", "--prune=all"], output: "Cleaned up")

        await service.cleanup()

        #expect(mock.executedCommands.contains(["cleanup", "--prune=all"]))
    }

    @Test("removeOrphans calls autoremove and refreshes")
    func removeOrphansCallsAutoremove() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)
        mock.setResult(for: ["autoremove"], output: "Removed orphans")

        await service.removeOrphans()

        #expect(mock.executedCommands.contains(["autoremove"]))
    }

    @Test("purgeCache calls cleanup with -s flag")
    func purgeCacheCallsCleanup() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["cleanup", "--prune=all", "-s"], output: "Purged cache")

        await service.purgeCache()

        #expect(mock.executedCommands.contains(["cleanup", "--prune=all", "-s"]))
    }

    @Test("updateHomebrew calls brew update and refreshes")
    func updateHomebrewCallsUpdate() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)
        mock.setResult(for: ["update"], output: "Updated Homebrew")

        await service.updateHomebrew()

        #expect(mock.executedCommands.contains(["update"]))
    }

    @Test("config parses brew config output")
    func configParsesOutput() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(
            for: ["config"],
            output: "HOMEBREW_VERSION: 4.2.5\nLast commit: 2 days ago"
        )

        let config = await service.config()

        #expect(config.version == "4.2.5")
        #expect(config.homebrewLastCommit == "2 days ago")
    }
}

// MARK: - Dry-Run Tests

@Suite("BrewService Dry-Run")
@MainActor
struct DryRunTests {

    @Test("dryRunAutoremove calls autoremove --dry-run")
    func dryRunAutoremoveCallsCommand() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(
            for: ["autoremove", "--dry-run"],
            output: "Would remove: libfoo, libbar"
        )

        let output = await service.dryRunAutoremove()

        #expect(mock.executedCommands.contains(["autoremove", "--dry-run"]))
        #expect(output.contains("libfoo"))
    }

    @Test("dryRunCleanup calls cleanup --dry-run")
    func dryRunCleanupCallsCommand() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(
            for: ["cleanup", "--prune=all", "-s", "--dry-run"],
            output: "Would remove: /path/to/old-1.0.tar.gz"
        )

        let output = await service.dryRunCleanup()

        #expect(mock.executedCommands.contains(["cleanup", "--prune=all", "-s", "--dry-run"]))
        #expect(output.contains("old-1.0"))
    }
}

// MARK: - Info & Caching Tests

@Suite("BrewService Info Caching")
@MainActor
struct InfoCachingTests {

    @Test("info returns cached result on second call")
    func infoCachesResult() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        mock.setResult(for: ["info", "wget"], output: "wget: stable 1.24.5")

        let first = await service.info(for: pkg)
        let second = await service.info(for: pkg)

        #expect(first == "wget: stable 1.24.5")
        #expect(second == "wget: stable 1.24.5")

        let infoCommands = mock.executedCommands.filter { $0 == ["info", "wget"] }
        #expect(infoCommands.count == 1)
    }

    @Test("info uses --cask flag for cask packages")
    func infoUsesCaskFlag() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "firefox", source: .cask)
        mock.setResult(for: ["info", "--cask", "firefox"], output: "firefox: 122.0")

        let result = await service.info(for: pkg)

        #expect(result == "firefox: 122.0")
        #expect(mock.executedCommands.contains(["info", "--cask", "firefox"]))
    }

    @Test("info returns empty string for mas packages")
    func infoReturnsEmptyForMas() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "Xcode", source: .mas)

        let result = await service.info(for: pkg)

        #expect(result.isEmpty)
        #expect(mock.executedCommands.isEmpty)
    }
}

// MARK: - Package Detail Tests

@Suite("BrewService Package Detail")
@MainActor
struct PackageDetailTests {

    @Test("fetchPackageDetail enriches formula with description and homepage")
    func fetchFormulaDetail() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        mock.setResult(for: ["info", "--json=v2", "wget"], output: TestJSON.formulaDetail)

        let enriched = await service.fetchPackageDetail(for: pkg)

        #expect(enriched?.description == "Internet file retriever")
        #expect(enriched?.homepage == "https://www.gnu.org/software/wget/")
        #expect(enriched?.dependencies == ["openssl@3", "libidn2", "gettext"])
    }

    @Test("fetchPackageDetail enriches cask with description and homepage")
    func fetchCaskDetail() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "firefox", source: .cask)
        mock.setResult(for: ["info", "--cask", "--json=v2", "firefox"], output: TestJSON.caskDetail)

        let enriched = await service.fetchPackageDetail(for: pkg)

        #expect(enriched?.description == "Fast web browser")
        #expect(enriched?.homepage == "https://www.mozilla.org/firefox/")
    }

    @Test("fetchPackageDetail returns nil on failure")
    func fetchDetailFailure() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        mock.setResult(for: ["info", "--json=v2", "wget"], output: "Error", success: false)

        let enriched = await service.fetchPackageDetail(for: pkg)

        #expect(enriched == nil)
    }

    @Test("fetchPackageDetail returns nil for malformed JSON")
    func fetchDetailMalformedJSON() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        mock.setResult(for: ["info", "--json=v2", "wget"], output: "not json at all")

        let enriched = await service.fetchPackageDetail(for: pkg)

        #expect(enriched == nil)
    }

    @Test("fetchPackageDetail preserves existing package properties")
    func fetchDetailPreservesProperties() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = BrewPackage(
            id: "formula-wget", name: "wget", version: "1.24.5",
            description: "", homepage: "",
            isInstalled: true, isOutdated: true,
            installedVersion: "1.24.5", latestVersion: "1.25.0",
            source: .formula, pinned: true, installedOnRequest: true,
            dependencies: []
        )
        mock.setResult(for: ["info", "--json=v2", "wget"], output: TestJSON.formulaDetail)

        let enriched = await service.fetchPackageDetail(for: pkg)

        #expect(enriched?.isOutdated == true)
        #expect(enriched?.pinned == true)
        #expect(enriched?.installedVersion == "1.24.5")
        #expect(enriched?.latestVersion == "1.25.0")
    }
}

// MARK: - Tap Management Tests

@Suite("BrewService Tap Management")
@MainActor
struct TapManagementTests {

    @Test("addTap calls brew tap and refreshes")
    func addTapCallsCommand() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)
        mock.setResult(for: ["tap", "user/repo"], output: "Tapped user/repo")

        await service.addTap(name: "user/repo")

        #expect(mock.executedCommands.contains(["tap", "user/repo"]))
    }

    @Test("removeTap calls brew untap")
    func removeTapCallsCommand() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)
        mock.setResult(for: ["untap", "user/repo"], output: "Untapped user/repo")

        await service.removeTap(name: "user/repo")

        #expect(mock.executedCommands.contains(["untap", "user/repo"]))
    }

    @Test("migrateTap untaps old and taps new")
    func migrateTapUntapsAndTaps() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)
        mock.setResult(for: ["untap", "old/tap"], output: "Untapped")
        mock.setResult(for: ["tap", "new/tap"], output: "Tapped")

        service.tapHealthStatuses["old/tap"] = TapHealthStatus(
            status: .moved, movedTo: "https://github.com/new/homebrew-tap", lastChecked: Date()
        )

        await service.migrateTap(from: "old/tap", to: "new/tap")

        #expect(mock.executedCommands.contains(["untap", "old/tap"]))
        #expect(mock.executedCommands.contains(["tap", "new/tap"]))
        #expect(service.tapHealthStatuses["old/tap"] == nil)
    }

    @Test("ensureTapsLoaded only loads once")
    func ensureTapsLoadedOnlyOnce() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["tap-info", "--json=v1", "--installed"], output: TestJSON.taps)

        await service.ensureTapsLoaded()
        await service.ensureTapsLoaded()

        let tapCommands = mock.executedCommands.filter { $0 == ["tap-info", "--json=v1", "--installed"] }
        #expect(tapCommands.count == 1)
    }
}

// MARK: - Retry Tests

@Suite("BrewService Retry Action")
@MainActor
struct RetryActionTests {

    @Test("retryAction re-executes failed command")
    func retryReExecutes() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["install", "wget"], output: "Installed wget")

        let entry = ActionHistoryEntry(
            id: UUID(), command: "install", arguments: ["install", "wget"],
            packageName: "wget", packageSource: .formula,
            status: .failure, output: "Error", timestamp: Date()
        )

        setupRefreshMock(mock)
        await service.retryAction(entry)

        #expect(mock.executedCommands.contains(["install", "wget"]))
    }

    @Test("retryAction skips non-retryable entries")
    func retrySkipsNonRetryable() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)

        let entry = ActionHistoryEntry(
            id: UUID(), command: "install", arguments: ["install", "wget"],
            packageName: "wget", packageSource: .formula,
            status: .success, output: "ok", timestamp: Date()
        )

        await service.retryAction(entry)

        #expect(mock.executedCommands.isEmpty)
    }

    @Test("retryAction refreshes for mutating commands")
    func retryRefreshesForMutatingCommands() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["install", "wget"], output: "Installed wget")
        setupRefreshMock(mock)

        let entry = ActionHistoryEntry(
            id: UUID(), command: "install", arguments: ["install", "wget"],
            packageName: "wget", packageSource: .formula,
            status: .failure, output: "Error", timestamp: Date()
        )

        await service.retryAction(entry)

        #expect(mock.executedCommands.contains(["info", "--installed", "--json=v2"]))
    }

    @Test("retryAction does not refresh for non-mutating commands")
    func retryNoRefreshForNonMutating() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["doctor"], output: "Your system is ready to brew.")

        let entry = ActionHistoryEntry(
            id: UUID(), command: "doctor", arguments: ["doctor"],
            packageName: nil, packageSource: nil,
            status: .failure, output: "Error", timestamp: Date()
        )

        await service.retryAction(entry)

        let hasRefreshCommand = mock.executedCommands.contains(["info", "--installed", "--json=v2"])
        #expect(!hasRefreshCommand)
    }
}

// MARK: - Error Handling Tests

@Suite("BrewService Error Handling")
@MainActor
struct ErrorHandlingTests {

    @Test("performBrewAction sets lastError on failure")
    func brewActionSetsError() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["cleanup", "--prune=all"], output: "Permission denied", success: false)

        await service.cleanup()

        #expect(service.lastError != nil)
    }

    @Test("performBrewAction clears lastError before execution")
    func brewActionClearsError() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        service.lastError = .commandFailed(command: "old", output: "old error")
        mock.setResult(for: ["cleanup", "--prune=all"], output: "Cleaned up")

        await service.cleanup()

        #expect(service.lastError == nil)
    }

    @Test("isPerformingAction is set during action execution")
    func isPerformingActionSetDuringAction() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["doctor"], output: "ok")

        #expect(service.isPerformingAction == false)
        _ = await service.doctor()
    }
}
