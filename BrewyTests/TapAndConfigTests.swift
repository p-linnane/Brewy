import Foundation
import Testing
@testable import Brewy

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
            movedTo: "https://github.com/new-owner/homebrew-new-repo",
            lastChecked: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TapHealthStatus.self, from: data)
        #expect(decoded.status == .moved)
        #expect(decoded.movedTo == "https://github.com/new-owner/homebrew-new-repo")
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

// MARK: - tapName Tests

@Suite("tapName")
struct TapNameTests {

    @Test("Derives tap name from standard homebrew- prefixed URL")
    func standardHomebrewPrefix() {
        let result = TapHealthStatus.tapName(from: "https://github.com/DomT4/homebrew-autoupdate")
        #expect(result == "DomT4/autoupdate")
    }

    @Test("Derives tap name from URL without homebrew- prefix")
    func noHomebrewPrefix() {
        let result = TapHealthStatus.tapName(from: "https://github.com/user/my-tap")
        #expect(result == "user/my-tap")
    }

    @Test("Returns nil for non-GitHub URL")
    func nonGitHub() {
        let result = TapHealthStatus.tapName(from: "https://gitlab.com/user/homebrew-tap")
        #expect(result == nil)
    }

    @Test("Returns nil for empty string")
    func emptyString() {
        let result = TapHealthStatus.tapName(from: "")
        #expect(result == nil)
    }

    @Test("Handles www.github.com")
    func wwwGitHub() {
        let result = TapHealthStatus.tapName(from: "https://www.github.com/owner/homebrew-fonts")
        #expect(result == "owner/fonts")
    }

    @Test("Strips .git suffix before deriving tap name")
    func gitSuffix() {
        let result = TapHealthStatus.tapName(from: "https://github.com/user/homebrew-tools.git")
        #expect(result == "user/tools")
    }

    @Test("Returns nil when repo is exactly 'homebrew-' with nothing after")
    func emptyAfterPrefix() {
        let result = TapHealthStatus.tapName(from: "https://github.com/user/homebrew-")
        #expect(result == nil)
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

    @Test("Parses empty output")
    func parseEmptyConfig() {
        let config = BrewConfig.parse(from: "")
        #expect(config.version == nil)
        #expect(config.homebrewLastCommit == nil)
    }

    @Test("Handles lines without colons")
    func parseMalformedConfig() {
        let output = "Some garbage line\nHOMEBREW_VERSION: 4.2.5\nAnother garbage"
        let config = BrewConfig.parse(from: output)
        #expect(config.version == "4.2.5")
    }

    @Test("Handles values containing colons")
    func parseValueWithColon() {
        let output = "Last commit: 2 days ago at 14:30:00"
        let config = BrewConfig.parse(from: output)
        #expect(config.homebrewLastCommit == "2 days ago at 14:30:00")
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

    @Test("Parses item without CDATA description")
    func parseNonCDATADescription() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.net/xml-namespaces/sparkle">
            <channel>
                <item>
                    <title>Version 0.1.0</title>
                    <description>Plain text release notes</description>
                    <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
                </item>
            </channel>
        </rss>
        """
        let data = try #require(xml.data(using: .utf8))
        let parser = AppcastParser()
        let release = try #require(parser.parse(data: data))
        #expect(release.descriptionHTML == "Plain text release notes")
        #expect(release.pubDate?.isEmpty != false)
    }

    @Test("Parses only the first item when multiple exist")
    func parseMultipleItems() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.net/xml-namespaces/sparkle">
            <channel>
                <item>
                    <title>Version 0.2.0</title>
                    <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
                </item>
                <item>
                    <title>Version 0.1.0</title>
                    <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
                </item>
            </channel>
        </rss>
        """
        let data = try #require(xml.data(using: .utf8))
        let parser = AppcastParser()
        let release = try #require(parser.parse(data: data))
        #expect(release.version == "0.1.0")
    }
}

// MARK: - AppcastRelease Tests

@Suite("AppcastRelease")
struct AppcastReleaseTests {

    @Test("publishedDate parses valid RFC 2822 date")
    func validPubDate() {
        let release = AppcastRelease(
            title: "v1.0",
            pubDate: "Mon, 17 Feb 2026 12:00:00 +0000",
            version: "1.0",
            descriptionHTML: nil
        )
        #expect(release.publishedDate != nil)
    }

    @Test("publishedDate returns nil for invalid date string")
    func invalidPubDate() {
        let release = AppcastRelease(
            title: "v1.0",
            pubDate: "not-a-date",
            version: "1.0",
            descriptionHTML: nil
        )
        #expect(release.publishedDate == nil)
    }

    @Test("publishedDate returns nil when pubDate is nil")
    func nilPubDate() {
        let release = AppcastRelease(
            title: "v1.0",
            pubDate: nil,
            version: "1.0",
            descriptionHTML: nil
        )
        #expect(release.publishedDate == nil)
    }

    @Test("ID uses version when available")
    func idFromVersion() {
        let release = AppcastRelease(title: "Release", pubDate: nil, version: "2.0", descriptionHTML: nil)
        #expect(release.id == "2.0")
    }

    @Test("ID falls back to title when version is nil")
    func idFromTitle() {
        let release = AppcastRelease(title: "Release", pubDate: nil, version: nil, descriptionHTML: nil)
        #expect(release.id == "Release")
    }
}

// MARK: - BrewTap Tests

@Suite("BrewTap")
struct BrewTapTests {

    @Test("ID is derived from name")
    func tapId() {
        let tap = BrewTap(name: "homebrew/core", remote: "", isOfficial: true, formulaNames: [], caskTokens: [])
        #expect(tap.id == "homebrew/core")
    }
}
