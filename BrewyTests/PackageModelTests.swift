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
            isCask: false, pinned: false, installedOnRequest: true,
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
            isCask: false, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        #expect(pkg.displayVersion == "8.5.0")
    }

    @Test("Equality is based on ID only")
    func equalityById() {
        let first = BrewPackage(
            id: "formula-git", name: "git", version: "2.43",
            description: "VCS", homepage: "",
            isInstalled: true, isOutdated: false,
            installedVersion: "2.43", latestVersion: nil,
            isCask: false, pinned: false, installedOnRequest: true,
            dependencies: []
        )
        let second = BrewPackage(
            id: "formula-git", name: "git", version: "2.44",
            description: "Different desc", homepage: "https://git-scm.com",
            isInstalled: true, isOutdated: true,
            installedVersion: "2.43", latestVersion: "2.44",
            isCask: false, pinned: true, installedOnRequest: false,
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

// MARK: - TapHealthStatus Tests

@Suite("TapHealthStatus")
struct TapHealthStatusTests {

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = TapHealthStatus(status: .archived, movedTo: nil, lastChecked: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapHealthStatus.self, from: data)
        #expect(decoded.status == .archived)
        #expect(decoded.movedTo == nil)
        #expect(decoded.lastChecked == original.lastChecked)
    }

    @Test("Codable round-trip with movedTo URL")
    func codableRoundTripWithMovedTo() throws {
        let original = TapHealthStatus(
            status: .moved,
            movedTo: "https://api.github.com/repos/new-owner/new-repo",
            lastChecked: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapHealthStatus.self, from: data)
        #expect(decoded.status == .moved)
        #expect(decoded.movedTo == "https://api.github.com/repos/new-owner/new-repo")
    }

    @Test("isStale returns false for recent entries")
    func freshEntryNotStale() {
        let status = TapHealthStatus(status: .healthy, movedTo: nil, lastChecked: Date())
        #expect(!status.isStale)
    }

    @Test("isStale returns true for old entries")
    func oldEntryIsStale() {
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        let status = TapHealthStatus(status: .healthy, movedTo: nil, lastChecked: twoDaysAgo)
        #expect(status.isStale)
    }

    @Test("All status cases encode to expected raw values")
    func statusRawValues() {
        #expect(TapHealthStatus.Status.healthy.rawValue == "healthy")
        #expect(TapHealthStatus.Status.archived.rawValue == "archived")
        #expect(TapHealthStatus.Status.moved.rawValue == "moved")
        #expect(TapHealthStatus.Status.notFound.rawValue == "notFound")
        #expect(TapHealthStatus.Status.unknown.rawValue == "unknown")
    }
}

// MARK: - parseGitHubRepo Tests

@Suite("parseGitHubRepo")
struct ParseGitHubRepoTests {

    @Test("Parses standard GitHub HTTPS URL")
    func standardGitHubURL() {
        let result = TapHealthStatus.parseGitHubRepo(from: "https://github.com/Homebrew/homebrew-core")
        #expect(result?.owner == "Homebrew")
        #expect(result?.repo == "homebrew-core")
    }

    @Test("Strips .git suffix from URL")
    func gitSuffixStripped() {
        let result = TapHealthStatus.parseGitHubRepo(from: "https://github.com/Homebrew/homebrew-core.git")
        #expect(result?.owner == "Homebrew")
        #expect(result?.repo == "homebrew-core")
    }

    @Test("Returns nil for non-GitHub URLs")
    func nonGitHubURL() {
        let result = TapHealthStatus.parseGitHubRepo(from: "https://gitlab.com/user/repo")
        #expect(result == nil)
    }

    @Test("Returns nil for empty string")
    func emptyString() {
        let result = TapHealthStatus.parseGitHubRepo(from: "")
        #expect(result == nil)
    }

    @Test("Returns nil for GitHub URL with insufficient path components")
    func insufficientPath() {
        let result = TapHealthStatus.parseGitHubRepo(from: "https://github.com/Homebrew")
        #expect(result == nil)
    }

    @Test("Handles www.github.com")
    func wwwGitHubURL() {
        let result = TapHealthStatus.parseGitHubRepo(from: "https://www.github.com/user/repo")
        #expect(result?.owner == "user")
        #expect(result?.repo == "repo")
    }
}

// MARK: - BrewConfig Tests

@Suite("BrewConfig Parsing")
struct BrewConfigTests {

    @Test("Parses brew config output correctly")
    func parseConfig() {
        let output = """
        HOMEBREW_VERSION: 4.2.5
        ORIGIN: https://github.com/Homebrew/brew
        HEAD: abc123
        Last commit: 2 days ago
        Core tap HEAD: def456
        Core tap last commit: 3 days ago
        Core cask tap HEAD: ghi789
        Core cask tap last commit: 1 day ago
        """
        let config = BrewConfig.parse(from: output)
        #expect(config.version == "4.2.5")
        #expect(config.homebrewLastCommit == "2 days ago")
        #expect(config.coreTapLastCommit == "3 days ago")
        #expect(config.coreCaskTapLastCommit == "1 day ago")
    }

    @Test("Returns nil for missing config values")
    func parseMissingConfig() {
        let output = "HOMEBREW_VERSION: 4.2.5\n"
        let config = BrewConfig.parse(from: output)
        #expect(config.version == "4.2.5")
        #expect(config.homebrewLastCommit == nil)
        #expect(config.coreTapLastCommit == nil)
    }
}

// MARK: - AppcastParser Tests

@Suite("Appcast XML Parsing")
struct AppcastParserTests {

    @Test("Parses Sparkle appcast item")
    func parseAppcastItem() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.net/xml-namespaces/sparkle">
            <channel>
                <item>
                    <title>Version 0.3.0</title>
                    <pubDate>Mon, 17 Feb 2026 12:00:00 +0000</pubDate>
                    <sparkle:shortVersionString>0.3.0</sparkle:shortVersionString>
                    <description><![CDATA[<h2>New Features</h2><ul><li>Added tap management</li></ul>]]></description>
                    <enclosure url="https://example.com/Brewy-0.3.0.tar.xz"
                        sparkle:version="42"
                        sparkle:shortVersionString="0.3.0"
                        type="application/octet-stream" />
                </item>
            </channel>
        </rss>
        """
        let data = try #require(xml.data(using: .utf8))
        let parser = AppcastParser()
        let release = try #require(parser.parse(data: data))

        #expect(release.title == "Version 0.3.0")
        #expect(release.version == "0.3.0")
        #expect(release.descriptionHTML?.contains("tap management") == true)
        #expect(release.pubDate == "Mon, 17 Feb 2026 12:00:00 +0000")
        #expect(release.publishedDate != nil)
    }

    @Test("Returns nil for empty feed")
    func parseEmptyFeed() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0"><channel></channel></rss>
        """
        let data = try #require(xml.data(using: .utf8))
        let parser = AppcastParser()
        let release = parser.parse(data: data)
        #expect(release == nil)
    }
}
