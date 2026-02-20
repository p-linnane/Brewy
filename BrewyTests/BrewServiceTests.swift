import Foundation
import Testing
@testable import Brewy

// MARK: - Test Helpers

/// Creates a minimal BrewPackage for testing. Only specify the fields you care about.
private func makePackage(
    name: String,
    isCask: Bool = false,
    pinned: Bool = false,
    isOutdated: Bool = false,
    installedVersion: String? = nil,
    latestVersion: String? = nil,
    installedOnRequest: Bool = true,
    dependencies: [String] = []
) -> BrewPackage {
    BrewPackage(
        id: "\(isCask ? "cask" : "formula")-\(name)",
        name: name,
        version: installedVersion ?? "1.0",
        description: "",
        homepage: "",
        isInstalled: true,
        isOutdated: isOutdated,
        installedVersion: installedVersion ?? "1.0",
        latestVersion: latestVersion,
        isCask: isCask,
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
        // curl and git have no dependents, so they're leaves
        // openssl is depended on by curl, so it's not a leaf
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
        // firefox is a cask and should not appear in leaves
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

        // Simulate a refresh that adds a package
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
            isCask: false, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        let outdatedByID = [outdated.id: outdated]

        let merged = BrewService.mergeOutdatedStatus(pkg, outdatedByID: outdatedByID)
        #expect(merged.isOutdated == true)
        #expect(merged.latestVersion == "21.5.0")
        // Original fields preserved
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
