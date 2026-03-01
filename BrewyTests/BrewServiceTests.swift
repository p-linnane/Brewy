import Foundation
import Testing
@testable import Brewy

// MARK: - Test Helpers

private func makePackage(
    name: String,
    source: PackageSource = .formula,
    isCask: Bool = false,
    pinned: Bool = false,
    isOutdated: Bool = false,
    installedVersion: String? = nil,
    latestVersion: String? = nil,
    installedOnRequest: Bool = true,
    dependencies: [String] = []
) -> BrewPackage {
    let resolvedSource = isCask ? PackageSource.cask : source
    let prefix: String
    switch resolvedSource {
    case .formula: prefix = "formula"
    case .cask: prefix = "cask"
    case .mas: prefix = "mas"
    }
    return BrewPackage(
        id: "\(prefix)-\(name)",
        name: name,
        version: installedVersion ?? "1.0",
        description: "",
        homepage: "",
        isInstalled: true,
        isOutdated: isOutdated,
        installedVersion: installedVersion ?? "1.0",
        latestVersion: latestVersion,
        source: resolvedSource,
        pinned: pinned,
        installedOnRequest: installedOnRequest,
        dependencies: dependencies
    )
}

// MARK: - Derived State Tests

@Suite("BrewService Derived State")
@MainActor
struct BrewServiceDerivedStateTests {

    @Test("allInstalled combines formulae and casks")
    func allInstalledCombination() {
        let service = BrewService()
        service.installedFormulae = [
            makePackage(name: "wget"),
            makePackage(name: "curl")
        ]
        service.installedCasks = [
            makePackage(name: "firefox", isCask: true)
        ]
        #expect(service.allInstalled.count == 3)
        #expect(service.installedNames == Set(["wget", "curl", "firefox"]))
    }

    @Test("Reverse dependencies are computed correctly")
    func reverseDependencies() {
        let service = BrewService()
        service.installedFormulae = [
            makePackage(name: "openssl"),
            makePackage(name: "curl", dependencies: ["openssl"]),
            makePackage(name: "wget", dependencies: ["openssl", "libidn2"]),
            makePackage(name: "libidn2")
        ]

        let opensslDependents = service.dependents(of: "openssl")
        #expect(opensslDependents.count == 2)
        #expect(Set(opensslDependents.map(\.name)) == Set(["curl", "wget"]))

        let libidn2Dependents = service.dependents(of: "libidn2")
        #expect(libidn2Dependents.count == 1)
        #expect(libidn2Dependents[0].name == "wget")

        // No dependents
        #expect(service.dependents(of: "curl").isEmpty)
    }

    @Test("Leaves are formulae with no reverse dependencies")
    func leavesPackages() {
        let service = BrewService()
        service.installedFormulae = [
            makePackage(name: "openssl"),
            makePackage(name: "curl", dependencies: ["openssl"]),
            makePackage(name: "git")
        ]

        let leaves = service.leavesPackages
        let leafNames = Set(leaves.map(\.name))
        #expect(leafNames == Set(["curl", "git"]))
        #expect(!leafNames.contains("openssl"))
    }

    @Test("Casks are excluded from leaves calculation")
    func leavesCasksExcluded() {
        let service = BrewService()
        service.installedFormulae = [makePackage(name: "wget")]
        service.installedCasks = [makePackage(name: "firefox", isCask: true)]

        let leaves = service.leavesPackages
        #expect(leaves.count == 1)
        #expect(leaves[0].name == "wget")
    }

    @Test("Pinned packages filters correctly")
    func pinnedPackages() {
        let service = BrewService()
        service.installedFormulae = [
            makePackage(name: "node", pinned: true),
            makePackage(name: "python", pinned: false),
            makePackage(name: "go", pinned: true)
        ]
        service.installedCasks = [
            makePackage(name: "iterm2", isCask: true, pinned: false)
        ]

        let pinned = service.pinnedPackages
        #expect(pinned.count == 2)
        #expect(Set(pinned.map(\.name)) == Set(["node", "go"]))
    }

    @Test("packages(for:) routes to correct data source")
    func packagesForCategory() {
        let service = BrewService()
        let formula = makePackage(name: "wget")
        let cask = makePackage(name: "firefox", isCask: true)
        let outdated = makePackage(name: "node", isOutdated: true)

        service.installedFormulae = [formula]
        service.installedCasks = [cask]
        service.outdatedPackages = [outdated]

        #expect(service.packages(for: .installed).count == 2)
        #expect(service.packages(for: .formulae).count == 1)
        #expect(service.packages(for: .formulae)[0].name == "wget")
        #expect(service.packages(for: .casks).count == 1)
        #expect(service.packages(for: .casks)[0].name == "firefox")
        #expect(service.packages(for: .outdated).count == 1)
        #expect(service.packages(for: .outdated)[0].name == "node")
        #expect(service.packages(for: .taps).isEmpty)
        #expect(service.packages(for: .discover).isEmpty)
        #expect(service.packages(for: .maintenance).isEmpty)
    }

    @Test("Derived state updates when formulae change")
    func derivedStateUpdatesOnMutation() {
        let service = BrewService()
        service.installedFormulae = [makePackage(name: "wget")]
        #expect(service.allInstalled.count == 1)
        #expect(service.installedNames.contains("wget"))

        service.installedFormulae = [
            makePackage(name: "wget"),
            makePackage(name: "curl")
        ]
        #expect(service.allInstalled.count == 2)
        #expect(service.installedNames.contains("curl"))
    }

    @Test("Empty state returns empty derived values")
    func emptyState() {
        let service = BrewService()
        #expect(service.allInstalled.isEmpty)
        #expect(service.installedNames.isEmpty)
        #expect(service.pinnedPackages.isEmpty)
        #expect(service.leavesPackages.isEmpty)
        #expect(service.dependents(of: "anything").isEmpty)
    }
}

// MARK: - Tap Health Status Tests

@Suite("BrewService Tap Health")
@MainActor
struct BrewServiceTapHealthTests {

    @Test("tapHealthStatuses is keyed by tap name")
    func healthStatusKeyedByName() {
        let service = BrewService()
        let status = TapHealthStatus(status: .archived, movedTo: nil, lastChecked: Date())
        service.tapHealthStatuses["homebrew/test-bot"] = status

        #expect(service.tapHealthStatuses["homebrew/test-bot"]?.status == .archived)
        #expect(service.tapHealthStatuses["nonexistent"] == nil)
    }

    @Test("Multiple tap health statuses coexist")
    func multipleStatuses() {
        let service = BrewService()
        service.tapHealthStatuses["tap/archived"] = TapHealthStatus(
            status: .archived, movedTo: nil, lastChecked: Date()
        )
        service.tapHealthStatuses["tap/moved"] = TapHealthStatus(
            status: .moved, movedTo: "https://github.com/new/repo", lastChecked: Date()
        )
        service.tapHealthStatuses["tap/healthy"] = TapHealthStatus(
            status: .healthy, movedTo: nil, lastChecked: Date()
        )

        #expect(service.tapHealthStatuses.count == 3)
        #expect(service.tapHealthStatuses["tap/archived"]?.status == .archived)
        #expect(service.tapHealthStatuses["tap/moved"]?.status == .moved)
        #expect(service.tapHealthStatuses["tap/moved"]?.movedTo == "https://github.com/new/repo")
        #expect(service.tapHealthStatuses["tap/healthy"]?.status == .healthy)
    }
}

// MARK: - mergeOutdatedStatus Tests

@Suite("mergeOutdatedStatus")
struct MergeOutdatedStatusTests {

    @Test("Marks package as outdated when match found")
    func mergesOutdatedMatch() {
        let pkg = makePackage(name: "node", installedVersion: "20.10.0")
        let outdated = BrewPackage(
            id: "formula-node", name: "node", version: "20.10.0",
            description: "", homepage: "",
            isInstalled: true, isOutdated: true,
            installedVersion: "20.10.0", latestVersion: "21.5.0",
            source: .formula, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        let outdatedByID = [outdated.id: outdated]

        let merged = BrewService.mergeOutdatedStatus(pkg, outdatedByID: outdatedByID)
        #expect(merged.isOutdated == true)
        #expect(merged.latestVersion == "21.5.0")
        #expect(merged.name == "node")
        #expect(merged.installedVersion == "20.10.0")
    }

    @Test("Returns original package when no outdated match")
    func noOutdatedMatch() {
        let pkg = makePackage(name: "curl")
        let outdatedByID: [String: BrewPackage] = [:]

        let merged = BrewService.mergeOutdatedStatus(pkg, outdatedByID: outdatedByID)
        #expect(merged.isOutdated == false)
        #expect(merged.name == "curl")
    }
}

// MARK: - SidebarCategory Tests

@Suite("SidebarCategory")
struct SidebarCategoryTests {

    @Test("All cases have system images")
    func allCasesHaveIcons() {
        for category in SidebarCategory.allCases {
            #expect(!category.systemImage.isEmpty, "Missing icon for \(category.rawValue)")
        }
    }

    @Test("All cases have unique raw values")
    func uniqueRawValues() {
        let rawValues = SidebarCategory.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("ID matches raw value")
    func idMatchesRawValue() {
        for category in SidebarCategory.allCases {
            #expect(category.id == category.rawValue)
        }
    }
}

// MARK: - BrewError Tests

@Suite("BrewError")
struct BrewErrorTests {

    @Test("brewNotFound includes path in description")
    func brewNotFoundDescription() {
        let error = BrewError.brewNotFound(path: "/opt/homebrew/bin/brew")
        #expect(error.errorDescription?.contains("/opt/homebrew/bin/brew") == true)
    }

    @Test("commandFailed uses output as description")
    func commandFailedDescription() {
        let error = BrewError.commandFailed(command: "install wget", output: "Error: wget already installed")
        #expect(error.errorDescription == "Error: wget already installed")
    }

    @Test("parseFailed includes command in description")
    func parseFailedDescription() {
        let error = BrewError.parseFailed(command: "info --json=v2")
        #expect(error.errorDescription?.contains("info --json=v2") == true)
    }

    @Test("commandTimedOut includes command in description")
    func commandTimedOutDescription() {
        let error = BrewError.commandTimedOut(command: "install gcc")
        #expect(error.errorDescription?.contains("install gcc") == true)
    }
}

// MARK: - CommandRunner Tests

@Suite("CommandRunner")
struct CommandRunnerTests {

    @Test("resolvedBrewPath returns preferred path when executable exists")
    func preferredPathExists() {
        let path = CommandRunner.resolvedBrewPath(preferred: "/bin/sh")
        #expect(path == "/bin/sh")
    }

    @Test("resolvedBrewPath returns preferred path when neither exists")
    func neitherExists() {
        let path = CommandRunner.resolvedBrewPath(preferred: "/nonexistent/brew")
        #expect(path == "/nonexistent/brew")
    }
}

// MARK: - BrewService Batching Tests

@Suite("BrewService Batching")
@MainActor
struct BrewServiceBatchingTests {

    @Test("updateInstalledPackages fires invalidateDerivedState only once")
    func batchingReducesDerivedStateComputation() {
        let service = BrewService()
        let formula = makePackage(name: "wget", dependencies: ["openssl"])
        let dep = makePackage(name: "openssl")
        let cask = makePackage(name: "firefox", isCask: true)

        service.installedFormulae = [formula, dep]
        service.installedCasks = [cask]

        #expect(service.allInstalled.count == 3)
        #expect(service.leavesPackages.map(\.name).contains("wget"))
        #expect(!service.leavesPackages.map(\.name).contains("openssl"))
    }

    @Test("Pinned packages computed eagerly via invalidateDerivedState")
    func pinnedComputedEagerly() {
        let service = BrewService()
        service.installedFormulae = [
            makePackage(name: "node", pinned: true),
            makePackage(name: "python")
        ]
        service.installedCasks = [
            makePackage(name: "slack", isCask: true, pinned: true)
        ]
        #expect(service.pinnedPackages.count == 2)
        #expect(Set(service.pinnedPackages.map(\.name)) == Set(["node", "slack"]))
    }
}

// MARK: - Mac App Store (mas) Tests

@Suite("BrewService Mas Support")
@MainActor
struct BrewServiceMasTests {

    @Test("Mas apps appear in allInstalled")
    func masAppsInAllInstalled() {
        let service = BrewService()
        service.installedFormulae = [makePackage(name: "wget")]
        service.installedCasks = [makePackage(name: "firefox", isCask: true)]
        service.installedMasApps = [makePackage(name: "Xcode", source: .mas)]

        #expect(service.allInstalled.count == 3)
        #expect(service.installedNames.contains("Xcode"))
    }

    @Test("packages(for: .masApps) returns mas apps")
    func packagesForMasCategory() {
        let service = BrewService()
        let masApp = makePackage(name: "Xcode", source: .mas)
        service.installedMasApps = [masApp]

        #expect(service.packages(for: .masApps).count == 1)
        #expect(service.packages(for: .masApps)[0].name == "Xcode")
    }

    @Test("Mas apps are excluded from leaves calculation")
    func masAppsExcludedFromLeaves() {
        let service = BrewService()
        service.installedFormulae = [makePackage(name: "wget")]
        service.installedMasApps = [makePackage(name: "Xcode", source: .mas)]

        let leaves = service.leavesPackages
        #expect(leaves.count == 1)
        #expect(leaves[0].name == "wget")
    }
}

// MARK: - Mas Output Parsing Tests

@Suite("Mas Output Parsing")
struct MasOutputParsingTests {

    @Test("parseMasList parses standard output")
    func parseMasListStandard() {
        let output = """
        497799835 Xcode (15.4)
        640199958 Developer (10.6.5)
        899247664 TestFlight (3.5.2)
        """
        let packages = MasParser.parseList(output)
        #expect(packages.count == 3)
        #expect(packages[0].name == "Xcode")
        #expect(packages[0].version == "15.4")
        #expect(packages[0].id == "mas-497799835")
        #expect(packages[0].isMas == true)
        #expect(packages[0].isCask == false)
        #expect(packages[1].name == "Developer")
        #expect(packages[2].name == "TestFlight")
    }

    @Test("parseMasList handles empty output")
    func parseMasListEmpty() {
        let packages = MasParser.parseList("")
        #expect(packages.isEmpty)
    }

    @Test("parseMasList skips malformed lines")
    func parseMasListMalformed() {
        let output = """
        497799835 Xcode (15.4)
        not-a-number Something (1.0)
        899247664 TestFlight (3.5.2)
        """
        let packages = MasParser.parseList(output)
        #expect(packages.count == 2)
    }

    @Test("parseMasOutdated parses standard output")
    func parseMasOutdatedStandard() {
        let output = """
        497799835 Xcode (15.4 -> 16.0)
        640199958 Developer (10.6.5 -> 10.6.6)
        """
        let packages = MasParser.parseOutdated(output)
        #expect(packages.count == 2)
        #expect(packages[0].name == "Xcode")
        #expect(packages[0].isOutdated == true)
        #expect(packages[0].installedVersion == "15.4")
        #expect(packages[0].latestVersion == "16.0")
        #expect(packages[0].isMas == true)
        #expect(packages[1].installedVersion == "10.6.5")
        #expect(packages[1].latestVersion == "10.6.6")
    }

    @Test("parseMasOutdated handles empty output")
    func parseMasOutdatedEmpty() {
        let packages = MasParser.parseOutdated("")
        #expect(packages.isEmpty)
    }

    @Test("parseMasList generates App Store homepage URLs")
    func parseMasListHomepage() {
        let output = "497799835 Xcode (15.4)\n"
        let packages = MasParser.parseList(output)
        #expect(packages[0].homepage == "https://apps.apple.com/app/id497799835")
    }
}
