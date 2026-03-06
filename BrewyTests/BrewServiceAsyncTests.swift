@testable import Brewy
import Foundation
import Testing

// MARK: - Refresh Tests

@Suite("BrewService.refresh()")
@MainActor
struct RefreshTests {

    @Test("refresh fetches formulae, casks, outdated, and taps")
    func refreshFetchesAllData() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)

        await service.refresh()

        #expect(service.installedFormulae.count == 1)
        #expect(service.installedFormulae[0].name == "wget")
        #expect(service.installedCasks.count == 1)
        #expect(service.installedCasks[0].name == "firefox")
        #expect(service.outdatedPackages.count == 1)
        #expect(service.installedTaps.count == 1)
        #expect(service.installedTaps[0].name == "homebrew/core")
    }

    @Test("refresh merges outdated status into installed packages")
    func refreshMergesOutdatedStatus() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)

        await service.refresh()

        let wget = service.installedFormulae.first { $0.name == "wget" }
        #expect(wget?.isOutdated == true)
        #expect(wget?.latestVersion == "1.25.0")
    }

    @Test("refresh sets lastUpdated")
    func refreshSetsLastUpdated() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)

        #expect(service.lastUpdated == nil)
        await service.refresh()
        #expect(service.lastUpdated != nil)
    }

    @Test("refresh handles empty results gracefully")
    func refreshHandlesEmptyResults() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["info", "--installed", "--json=v2"], output: TestJSON.emptyFormulae)
        mock.setResult(for: ["info", "--installed", "--cask", "--json=v2"], output: TestJSON.emptyFormulae)
        mock.setResult(for: ["outdated", "--json=v2"], output: TestJSON.emptyOutdated)
        mock.setResult(for: ["tap-info", "--json=v1", "--installed"], output: TestJSON.emptyTaps)

        await service.refresh()

        #expect(service.installedFormulae.isEmpty)
        #expect(service.installedCasks.isEmpty)
        #expect(service.outdatedPackages.isEmpty)
        #expect(service.allInstalled.isEmpty)
    }

    @Test("refresh handles fetch failures gracefully")
    func refreshHandlesFailures() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["info", "--installed", "--json=v2"], output: "Error", success: false)
        mock.setResult(for: ["info", "--installed", "--cask", "--json=v2"], output: TestJSON.casks)
        mock.setResult(for: ["outdated", "--json=v2"], output: TestJSON.emptyOutdated)
        mock.setResult(for: ["tap-info", "--json=v1", "--installed"], output: TestJSON.emptyTaps)

        await service.refresh()

        #expect(service.installedFormulae.isEmpty)
        #expect(service.installedCasks.count == 1)
    }

    @Test("refresh invalidates info cache when versions change")
    func refreshInvalidatesInfoCache() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)

        await service.refresh()

        mock.setResult(for: ["info", "wget"], output: "wget: stable 1.24.5")
        let info = await service.info(for: service.installedFormulae[0])
        #expect(!info.isEmpty)

        let updatedFormulae = """
        {"formulae":[{"name":"wget","desc":"Internet file retriever",\
        "homepage":"https://www.gnu.org/software/wget/",\
        "versions":{"stable":"1.25.0"},"pinned":false,\
        "installed":[{"version":"1.25.0","installed_on_request":true}],\
        "dependencies":["openssl@3"]}],"casks":[]}
        """
        mock.setResult(for: ["info", "--installed", "--json=v2"], output: updatedFormulae)
        mock.setResult(for: ["outdated", "--json=v2"], output: TestJSON.emptyOutdated)

        await service.refresh()

        mock.setResult(for: ["info", "wget"], output: "wget: stable 1.25.0")
        let newInfo = await service.info(for: service.installedFormulae[0])
        #expect(newInfo == "wget: stable 1.25.0")
    }

    @Test("refresh updates derived state")
    func refreshUpdatesDerivedState() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)

        await service.refresh()

        #expect(service.allInstalled.count == 2)
        #expect(service.installedNames == Set(["wget", "firefox"]))
        #expect(!service.leavesPackages.isEmpty)
    }

    @Test("refresh clears isLoading when done")
    func refreshClearsLoadingState() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)

        await service.refresh()

        #expect(service.isLoading == false)
    }

    @Test("refresh skips tap health check when all statuses are fresh")
    func refreshSkipsTapHealthWhenFresh() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)

        service.tapHealthStatuses["homebrew/core"] = TapHealthStatus(
            status: .healthy, movedTo: nil, lastChecked: Date()
        )

        await service.refresh()

        #expect(service.tapHealthStatuses["homebrew/core"]?.status == .healthy)
    }
}

// MARK: - Search Tests

@Suite("BrewService.search()")
@MainActor
struct SearchTests {

    @Test("search returns formula and cask results")
    func searchReturnsBoth() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["search", "--formula", "fire"], output: "firewalld\nfirejail")
        mock.setResult(for: ["search", "--cask", "fire"], output: "firefox\nfirealpaca")

        await service.search(query: "fire")

        #expect(service.searchResults.count == 4)
        let names = Set(service.searchResults.map(\.name))
        #expect(names.contains("firefox"))
        #expect(names.contains("firewalld"))
    }

    @Test("search marks installed packages")
    func searchMarksInstalled() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        service.installedFormulae = [makePackage(name: "wget")]

        mock.setResult(for: ["search", "--formula", "wget"], output: "wget\nwget2")
        mock.setResult(for: ["search", "--cask", "wget"], output: "")

        await service.search(query: "wget")

        let wgetResult = service.searchResults.first { $0.name == "wget" }
        let wget2Result = service.searchResults.first { $0.name == "wget2" }
        #expect(wgetResult?.isInstalled == true)
        #expect(wget2Result?.isInstalled == false)
    }

    @Test("search with empty query clears results")
    func searchEmptyQueryClears() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        service.searchResults = [makePackage(name: "old-result")]

        await service.search(query: "")

        #expect(service.searchResults.isEmpty)
    }

    @Test("search handles failure gracefully")
    func searchHandlesFailure() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["search", "--formula", "test"], output: "Error", success: false)
        mock.setResult(for: ["search", "--cask", "test"], output: "test-app")

        await service.search(query: "test")

        #expect(service.searchResults.count == 1)
        #expect(service.searchResults[0].name == "test-app")
    }

    @Test("search filters out ==> header lines")
    func searchFiltersHeaders() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["search", "--formula", "test"], output: "==> Formulae\ntest-formula")
        mock.setResult(for: ["search", "--cask", "test"], output: "==> Casks\ntest-cask")

        await service.search(query: "test")

        let names = service.searchResults.map(\.name)
        #expect(!names.contains("==>"))
        #expect(names.contains("test-formula"))
        #expect(names.contains("test-cask"))
    }

    @Test("search results have correct source types")
    func searchResultSourceTypes() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        mock.setResult(for: ["search", "--formula", "test"], output: "test-formula")
        mock.setResult(for: ["search", "--cask", "test"], output: "test-cask")

        await service.search(query: "test")

        let formula = service.searchResults.first { $0.name == "test-formula" }
        let cask = service.searchResults.first { $0.name == "test-cask" }
        #expect(formula?.source == .formula)
        #expect(cask?.source == .cask)
    }
}

// MARK: - Package Action Tests

@Suite("BrewService Package Actions")
@MainActor
struct PackageActionTests {

    @Test("install calls brew install with package name")
    func installCallsCorrectCommand() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        setupRefreshMock(mock)
        mock.setResult(for: ["install", "wget"], output: "Installed wget")

        await service.install(package: pkg)

        #expect(mock.executedCommands.contains(["install", "wget"]))
        #expect(service.actionOutput == "Installed wget")
    }

    @Test("install adds --cask flag for cask packages")
    func installAddsCaskFlag() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "firefox", source: .cask)
        setupRefreshMock(mock)
        mock.setResult(for: ["install", "--cask", "firefox"], output: "Installed firefox")

        await service.install(package: pkg)

        #expect(mock.executedCommands.contains(["install", "--cask", "firefox"]))
    }

    @Test("install skips mas packages")
    func installSkipsMas() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "Xcode", source: .mas)

        await service.install(package: pkg)

        #expect(mock.executedCommands.isEmpty)
    }

    @Test("uninstall calls brew uninstall")
    func uninstallCallsCorrectCommand() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        setupRefreshMock(mock)
        mock.setResult(for: ["uninstall", "wget"], output: "Uninstalled wget")

        await service.uninstall(package: pkg)

        #expect(mock.executedCommands.contains(["uninstall", "wget"]))
    }

    @Test("upgrade calls brew upgrade")
    func upgradeCallsCorrectCommand() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        setupRefreshMock(mock)
        mock.setResult(for: ["upgrade", "wget"], output: "Upgraded wget")

        await service.upgrade(package: pkg)

        #expect(mock.executedCommands.contains(["upgrade", "wget"]))
    }

    @Test("pin calls brew pin")
    func pinCallsCorrectCommand() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        setupRefreshMock(mock)
        mock.setResult(for: ["pin", "wget"], output: "Pinned wget")

        await service.pin(package: pkg)

        #expect(mock.executedCommands.contains(["pin", "wget"]))
    }

    @Test("unpin calls brew unpin")
    func unpinCallsCorrectCommand() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        setupRefreshMock(mock)
        mock.setResult(for: ["unpin", "wget"], output: "Unpinned wget")

        await service.unpin(package: pkg)

        #expect(mock.executedCommands.contains(["unpin", "wget"]))
    }

    @Test("reinstall calls brew reinstall")
    func reinstallCallsCorrectCommand() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        setupRefreshMock(mock)
        mock.setResult(for: ["reinstall", "wget"], output: "Reinstalled wget")

        await service.reinstall(package: pkg)

        #expect(mock.executedCommands.contains(["reinstall", "wget"]))
    }

    @Test("failed action records failure in history")
    func failedActionRecordsFailure() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        setupRefreshMock(mock)
        mock.setResult(for: ["install", "wget"], output: "Error: something failed", success: false)

        await service.install(package: pkg)

        let entry = service.actionHistory.first { $0.packageName == "wget" }
        #expect(entry?.status == .failure)
        #expect(entry?.output.contains("Error: something failed") == true)
    }

    @Test("action records history entry")
    func actionRecordsHistory() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        setupRefreshMock(mock)
        mock.setResult(for: ["install", "wget"], output: "Installed wget")

        await service.install(package: pkg)

        #expect(service.actionHistory.count >= 1)
        let entry = service.actionHistory.first { $0.packageName == "wget" }
        #expect(entry?.command == "install")
        #expect(entry?.status == .success)
    }

    @Test("action triggers refresh after completion")
    func actionTriggersRefresh() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        let pkg = makePackage(name: "wget")
        setupRefreshMock(mock)
        mock.setResult(for: ["install", "wget"], output: "Installed wget")

        await service.install(package: pkg)

        #expect(!service.installedFormulae.isEmpty || !service.installedCasks.isEmpty || service.lastUpdated != nil)
    }
}

// MARK: - Bulk Upgrade Tests

@Suite("BrewService Bulk Upgrade")
@MainActor
struct BulkUpgradeTests {

    @Test("upgradeAll calls brew upgrade")
    func upgradeAllCallsCommand() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)
        mock.setResult(for: ["upgrade"], output: "All upgraded")

        await service.upgradeAll()

        #expect(mock.executedCommands.contains(["upgrade"]))
    }

    @Test("upgradeSelected separates formulae and casks")
    func upgradeSelectedSeparates() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)

        let formula = makePackage(name: "wget", source: .formula)
        let cask = makePackage(name: "firefox", source: .cask)
        mock.setResult(for: ["upgrade", "wget"], output: "Upgraded wget")
        mock.setResult(for: ["upgrade", "--cask", "firefox"], output: "Upgraded firefox")

        await service.upgradeSelected(packages: [formula, cask])

        #expect(mock.executedCommands.contains(["upgrade", "wget"]))
        #expect(mock.executedCommands.contains(["upgrade", "--cask", "firefox"]))
    }

    @Test("upgradeSelected with only formulae skips cask upgrade")
    func upgradeSelectedFormulaOnly() async {
        let mock = MockCommandRunner()
        let (service, _) = makeService(mock: mock)
        setupRefreshMock(mock)

        let formula = makePackage(name: "wget", source: .formula)
        mock.setResult(for: ["upgrade", "wget"], output: "Upgraded wget")

        await service.upgradeSelected(packages: [formula])

        #expect(mock.executedCommands.contains(["upgrade", "wget"]))
        let hasCaskUpgrade = mock.executedCommands.contains { $0.first == "upgrade" && $0.contains("--cask") }
        #expect(!hasCaskUpgrade)
    }
}
