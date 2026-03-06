@testable import Brewy
import Foundation
import Testing

// MARK: - PackageGroup Model Tests

@Suite("PackageGroup Model")
struct PackageGroupTests {

    @Test("PackageGroup initializes with defaults")
    func defaultInitialization() {
        let group = PackageGroup(name: "My Group")
        #expect(group.name == "My Group")
        #expect(group.systemImage == "folder.fill")
        #expect(group.packageIDs.isEmpty)
    }

    @Test("PackageGroup initializes with custom values")
    func customInitialization() {
        let group = PackageGroup(
            name: "Dev Tools",
            systemImage: "wrench.fill",
            packageIDs: ["formula-git", "formula-curl"]
        )
        #expect(group.name == "Dev Tools")
        #expect(group.systemImage == "wrench.fill")
        #expect(group.packageIDs.count == 2)
    }

    @Test("PackageGroup equality is based on ID")
    func equalityById() {
        let id = UUID()
        let group1 = PackageGroup(id: id, name: "Group A")
        let group2 = PackageGroup(id: id, name: "Group B", systemImage: "star.fill")
        #expect(group1 == group2)
        #expect(group1.hashValue == group2.hashValue)
    }

    @Test("PackageGroups with different IDs are not equal")
    func inequalityByDifferentId() {
        let group1 = PackageGroup(name: "Group A")
        let group2 = PackageGroup(name: "Group A")
        #expect(group1 != group2)
    }

    @Test("PackageGroup encodes and decodes correctly")
    func encodeDecode() throws {
        let group = PackageGroup(
            name: "Server Tools",
            systemImage: "server.rack",
            packageIDs: ["formula-nginx", "formula-redis"]
        )
        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(PackageGroup.self, from: data)
        #expect(decoded.id == group.id)
        #expect(decoded.name == "Server Tools")
        #expect(decoded.systemImage == "server.rack")
        #expect(decoded.packageIDs == ["formula-nginx", "formula-redis"])
    }
}

// MARK: - BrewService Package Group Tests

@Suite("BrewService Package Groups")
@MainActor
struct BrewServicePackageGroupTests {

    @Test("createGroup adds a group")
    func createGroupAddsGroup() {
        let service = BrewService()
        service.createGroup(name: "Dev Tools", systemImage: "wrench.fill")

        #expect(service.packageGroups.count == 1)
        #expect(service.packageGroups[0].name == "Dev Tools")
        #expect(service.packageGroups[0].systemImage == "wrench.fill")
    }

    @Test("deleteGroup removes the group")
    func deleteGroupRemovesGroup() {
        let service = BrewService()
        service.createGroup(name: "Group A")
        service.createGroup(name: "Group B")
        let groupA = service.packageGroups[0]

        service.deleteGroup(groupA)

        #expect(service.packageGroups.count == 1)
        #expect(service.packageGroups[0].name == "Group B")
    }

    @Test("updateGroup modifies name and icon")
    func updateGroupModifies() {
        let service = BrewService()
        service.createGroup(name: "Old Name")
        let group = service.packageGroups[0]

        service.updateGroup(group, name: "New Name", systemImage: "star.fill")

        #expect(service.packageGroups[0].name == "New Name")
        #expect(service.packageGroups[0].systemImage == "star.fill")
    }

    @Test("addToGroup adds package ID")
    func addToGroupAddsPackageID() {
        let service = BrewService()
        service.createGroup(name: "Test")
        let group = service.packageGroups[0]

        service.addToGroup(group, packageID: "formula-wget")

        #expect(service.packageGroups[0].packageIDs == ["formula-wget"])
    }

    @Test("addToGroup prevents duplicates")
    func addToGroupPreventsDuplicates() {
        let service = BrewService()
        service.createGroup(name: "Test")
        let group = service.packageGroups[0]

        service.addToGroup(group, packageID: "formula-wget")
        service.addToGroup(group, packageID: "formula-wget")

        #expect(service.packageGroups[0].packageIDs.count == 1)
    }

    @Test("removeFromGroup removes package ID")
    func removeFromGroupRemovesPackageID() {
        let service = BrewService()
        service.createGroup(name: "Test")
        let group = service.packageGroups[0]
        service.addToGroup(group, packageID: "formula-wget")
        service.addToGroup(group, packageID: "formula-curl")

        service.removeFromGroup(service.packageGroups[0], packageID: "formula-wget")

        #expect(service.packageGroups[0].packageIDs == ["formula-curl"])
    }

    @Test("packages(in:) resolves package IDs to installed packages")
    func packagesInGroupResolvesIDs() {
        let service = BrewService()
        service.installedFormulae = [
            makePackage(name: "wget"),
            makePackage(name: "curl"),
            makePackage(name: "git")
        ]
        service.createGroup(name: "Test")
        let group = service.packageGroups[0]
        service.addToGroup(group, packageID: "formula-wget")
        service.addToGroup(group, packageID: "formula-git")

        let packages = service.packages(in: service.packageGroups[0])
        #expect(packages.count == 2)
        #expect(Set(packages.map(\.name)) == Set(["wget", "git"]))
    }

    @Test("packages(in:) ignores uninstalled package IDs")
    func packagesInGroupIgnoresUninstalled() {
        let service = BrewService()
        service.installedFormulae = [makePackage(name: "wget")]
        service.createGroup(name: "Test")
        let group = service.packageGroups[0]
        service.addToGroup(group, packageID: "formula-wget")
        service.addToGroup(group, packageID: "formula-removed")

        let packages = service.packages(in: service.packageGroups[0])
        #expect(packages.count == 1)
        #expect(packages[0].name == "wget")
    }

    @Test("packages(for: .groups) returns empty")
    func packagesForGroupsCategoryReturnsEmpty() {
        let service = BrewService()
        service.createGroup(name: "Test")
        #expect(service.packages(for: .groups).isEmpty)
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
