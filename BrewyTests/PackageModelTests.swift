import Foundation
import Testing
@testable import Brewy

// MARK: - BrewPackage Tests

@Suite("BrewPackage Model")
struct BrewPackageTests {

    @Test("Display version shows upgrade arrow when outdated")
    func displayVersionOutdated() {
        let pkg = BrewPackage(
            id: "formula-wget", name: "wget", version: "1.21",
            description: "Internet file retriever", homepage: "https://www.gnu.org/software/wget/",
            isInstalled: true, isOutdated: true,
            installedVersion: "1.21", latestVersion: "1.24",
            source: .formula, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        #expect(pkg.displayVersion == "1.21 → 1.24")
    }

    @Test("Display version shows plain version when up to date")
    func displayVersionCurrent() {
        let pkg = BrewPackage(
            id: "formula-curl", name: "curl", version: "8.5.0",
            description: "Command line tool for transferring data",
            homepage: "https://curl.se",
            isInstalled: true, isOutdated: false,
            installedVersion: "8.5.0", latestVersion: nil,
            source: .formula, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        #expect(pkg.displayVersion == "8.5.0")
    }

    @Test("Display version shows plain version when outdated but latestVersion is nil")
    func displayVersionOutdatedNoLatest() {
        let pkg = BrewPackage(
            id: "formula-wget", name: "wget", version: "1.21",
            description: "", homepage: "",
            isInstalled: true, isOutdated: true,
            installedVersion: "1.21", latestVersion: nil,
            source: .formula, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        #expect(pkg.displayVersion == "1.21")
    }

    @Test("Different IDs are not equal even with same name")
    func inequalityByDifferentId() {
        let formula = BrewPackage(
            id: "formula-git", name: "git", version: "2.43",
            description: "", homepage: "",
            isInstalled: true, isOutdated: false,
            installedVersion: "2.43", latestVersion: nil,
            source: .formula, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        let cask = BrewPackage(
            id: "cask-git", name: "git", version: "2.43",
            description: "", homepage: "",
            isInstalled: true, isOutdated: false,
            installedVersion: "2.43", latestVersion: nil,
            source: .cask, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        #expect(formula != cask)
    }

    @Test("Equality is based on ID only")
    func equalityById() {
        let first = BrewPackage(
            id: "formula-git", name: "git", version: "2.43",
            description: "VCS", homepage: "",
            isInstalled: true, isOutdated: false,
            installedVersion: "2.43", latestVersion: nil,
            source: .formula, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        let second = BrewPackage(
            id: "formula-git", name: "git", version: "2.44",
            description: "Different desc", homepage: "https://git-scm.com",
            isInstalled: true, isOutdated: true,
            installedVersion: "2.43", latestVersion: "2.44",
            source: .formula, pinned: true, installedOnRequest: false,
            dependencies: ["curl"]
        )
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }
}

// MARK: - FormulaJSON Parsing Tests

@Suite("Brew JSON v2 Parsing")
struct BrewJSONParsingTests {

    @Test("FormulaJSON parses and converts to BrewPackage")
    func formulaJSONConversion() throws {
        let json = """
        {
            "formulae": [
                {
                    "name": "wget",
                    "desc": "Internet file retriever",
                    "homepage": "https://www.gnu.org/software/wget/",
                    "versions": { "stable": "1.24.5" },
                    "pinned": false,
                    "installed": [
                        { "version": "1.24.5", "installed_on_request": true }
                    ],
                    "dependencies": ["gettext", "libidn2", "openssl@3"]
                }
            ],
            "casks": []
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
        let formulae = try #require(response.formulae)
        #expect(formulae.count == 1)

        let pkg = formulae[0].toPackage()
        #expect(pkg.name == "wget")
        #expect(pkg.version == "1.24.5")
        #expect(pkg.description == "Internet file retriever")
        #expect(pkg.isCask == false)
        #expect(pkg.isInstalled == true)
        #expect(pkg.pinned == false)
        #expect(pkg.installedOnRequest == true)
        #expect(pkg.dependencies == ["gettext", "libidn2", "openssl@3"])
        #expect(pkg.id == "formula-wget")
    }

    @Test("CaskJSON parses and converts to BrewPackage")
    func caskJSONConversion() throws {
        let json = """
        {
            "formulae": [],
            "casks": [
                {
                    "token": "firefox",
                    "version": "122.0",
                    "desc": "Web browser",
                    "homepage": "https://www.mozilla.org/firefox/"
                }
            ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
        let casks = try #require(response.casks)
        #expect(casks.count == 1)

        let pkg = casks[0].toPackage()
        #expect(pkg.name == "firefox")
        #expect(pkg.version == "122.0")
        #expect(pkg.isCask == true)
        #expect(pkg.isInstalled == true)
        #expect(pkg.id == "cask-firefox")
    }

    @Test("OutdatedFormulaJSON parses correctly")
    func outdatedFormulaJSON() throws {
        let json = """
        {
            "formulae": [
                {
                    "name": "node",
                    "installed_versions": ["20.10.0"],
                    "current_version": "21.5.0",
                    "pinned": false
                }
            ],
            "casks": []
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(BrewOutdatedResponse.self, from: data)
        let formulae = try #require(response.formulae)
        #expect(formulae.count == 1)

        let pkg = try #require(formulae[0].toPackage())
        #expect(pkg.name == "node")
        #expect(pkg.isOutdated == true)
        #expect(pkg.installedVersion == "20.10.0")
        #expect(pkg.latestVersion == "21.5.0")
    }

    @Test("OutdatedCaskJSON parses correctly")
    func outdatedCaskJSON() throws {
        let json = """
        {
            "formulae": [],
            "casks": [
                {
                    "name": "discord",
                    "installed_versions": "0.0.290",
                    "current_version": "0.0.295"
                }
            ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(BrewOutdatedResponse.self, from: data)
        let casks = try #require(response.casks)
        #expect(casks.count == 1)

        let pkg = try #require(casks[0].toPackage())
        #expect(pkg.name == "discord")
        #expect(pkg.isCask == true)
        #expect(pkg.isOutdated == true)
        #expect(pkg.installedVersion == "0.0.290")
        #expect(pkg.latestVersion == "0.0.295")
    }

    @Test("TapJSON parses and strips .git suffix")
    func tapJSONConversion() throws {
        let json = """
        [
            {
                "name": "homebrew/core",
                "remote": "https://github.com/Homebrew/homebrew-core.git",
                "official": true,
                "formula_names": ["wget", "curl"],
                "cask_tokens": []
            }
        ]
        """
        let data = try #require(json.data(using: .utf8))
        let taps = try JSONDecoder().decode([TapJSON].self, from: data)
        #expect(taps.count == 1)

        let tap = taps[0].toTap()
        #expect(tap.name == "homebrew/core")
        #expect(tap.remote == "https://github.com/Homebrew/homebrew-core")
        #expect(tap.isOfficial == true)
        #expect(tap.formulaNames == ["wget", "curl"])
    }

    @Test("OutdatedFormulaJSON returns nil when currentVersion is missing")
    func outdatedFormulaMissingCurrentVersion() throws {
        let json = """
        {
            "formulae": [
                {
                    "name": "node",
                    "installed_versions": ["20.10.0"],
                    "pinned": false
                }
            ],
            "casks": []
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(BrewOutdatedResponse.self, from: data)
        let formulae = try #require(response.formulae)
        #expect(formulae[0].toPackage() == nil)
    }

    @Test("OutdatedCaskJSON returns nil when fields are missing")
    func outdatedCaskMissingFields() throws {
        let json = """
        {
            "formulae": [],
            "casks": [
                {
                    "name": "slack"
                }
            ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(BrewOutdatedResponse.self, from: data)
        let casks = try #require(response.casks)
        #expect(casks[0].toPackage() == nil)
    }

    @Test("CaskJSON with nil version uses 'unknown'")
    func caskNilVersion() throws {
        let json = """
        {
            "formulae": [],
            "casks": [
                {
                    "token": "sketch",
                    "desc": "Design tool"
                }
            ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
        let casks = try #require(response.casks)
        let pkg = casks[0].toPackage()
        #expect(pkg.version == "unknown")
        #expect(pkg.installedVersion == "unknown")
    }

    @Test("TapJSON without remote uses empty string")
    func tapNoRemote() throws {
        let json = """
        [{ "name": "local/tap" }]
        """
        let data = try #require(json.data(using: .utf8))
        let taps = try JSONDecoder().decode([TapJSON].self, from: data)
        let tap = taps[0].toTap()
        #expect(tap.remote.isEmpty)
        #expect(tap.isOfficial == false)
        #expect(tap.formulaNames.isEmpty)
        #expect(tap.caskTokens.isEmpty)
    }

    @Test("TapJSON remote without .git suffix is preserved")
    func tapRemoteNoGitSuffix() throws {
        let json = """
        [{
            "name": "user/tap",
            "remote": "https://github.com/user/homebrew-tap",
            "official": false,
            "formula_names": [],
            "cask_tokens": ["app"]
        }]
        """
        let data = try #require(json.data(using: .utf8))
        let taps = try JSONDecoder().decode([TapJSON].self, from: data)
        let tap = taps[0].toTap()
        #expect(tap.remote == "https://github.com/user/homebrew-tap")
        #expect(tap.caskTokens == ["app"])
    }

    @Test("Handles missing optional fields gracefully")
    func missingOptionalFields() throws {
        let json = """
        {
            "formulae": [
                {
                    "name": "minimal",
                    "installed": []
                }
            ],
            "casks": []
        }
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
        let formulae = try #require(response.formulae)

        let pkg = formulae[0].toPackage()
        #expect(pkg.name == "minimal")
        #expect(pkg.description.isEmpty)
        #expect(pkg.homepage.isEmpty)
        #expect(pkg.version == "unknown")
        #expect(pkg.dependencies.isEmpty)
        #expect(pkg.pinned == false)
    }
}

// MARK: - PackageSource Tests

@Suite("PackageSource")
struct PackageSourceTests {

    @Test("isCask computed property works correctly")
    func isCaskComputed() {
        let formula = BrewPackage(
            id: "formula-test", name: "test", version: "1.0",
            description: "", homepage: "",
            isInstalled: true, isOutdated: false,
            installedVersion: "1.0", latestVersion: nil,
            source: .formula, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        let cask = BrewPackage(
            id: "cask-test", name: "test", version: "1.0",
            description: "", homepage: "",
            isInstalled: true, isOutdated: false,
            installedVersion: "1.0", latestVersion: nil,
            source: .cask, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        let mas = BrewPackage(
            id: "mas-test", name: "test", version: "1.0",
            description: "", homepage: "",
            isInstalled: true, isOutdated: false,
            installedVersion: "1.0", latestVersion: nil,
            source: .mas, pinned: false, installedOnRequest: true,
            dependencies: []
        )

        #expect(formula.isCask == false)
        #expect(formula.isMas == false)
        #expect(cask.isCask == true)
        #expect(cask.isMas == false)
        #expect(mas.isCask == false)
        #expect(mas.isMas == true)
    }

    @Test("PackageSource encodes and decodes correctly")
    func sourceEncodeDecode() throws {
        let pkg = BrewPackage(
            id: "mas-123", name: "TestApp", version: "1.0",
            description: "", homepage: "",
            isInstalled: true, isOutdated: false,
            installedVersion: "1.0", latestVersion: nil,
            source: .mas, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        let data = try JSONEncoder().encode(pkg)
        let decoded = try JSONDecoder().decode(BrewPackage.self, from: data)
        #expect(decoded.source == .mas)
        #expect(decoded.isMas == true)
        #expect(decoded.isCask == false)
    }

    @Test("SidebarCategory.masApps has correct properties")
    func masAppsCategoryProperties() {
        let category = SidebarCategory.masApps
        #expect(category.rawValue == "Mac App Store")
        #expect(!category.systemImage.isEmpty)
        #expect(category.id == "Mac App Store")
    }

    @Test("SidebarCategory.groups has correct properties")
    func groupsCategoryProperties() {
        let category = SidebarCategory.groups
        #expect(category.rawValue == "Groups")
        #expect(category.systemImage == "folder.fill")
        #expect(category.id == "Groups")
    }
}

// MARK: - PackageGroup Tests

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
