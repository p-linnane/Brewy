import Foundation

struct BrewPackage: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let version: String
    let description: String
    let homepage: String
    let isInstalled: Bool
    let isOutdated: Bool
    let installedVersion: String?
    let latestVersion: String?
    let isCask: Bool
    let pinned: Bool
    let installedOnRequest: Bool
    let dependencies: [String]

    var displayVersion: String {
        if isOutdated, let latest = latestVersion {
            return "\(version) → \(latest)"
        }
        return version
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct BrewTap: Identifiable, Hashable, Codable {
    let name: String
    let remote: String
    let isOfficial: Bool
    let formulaNames: [String]
    let caskTokens: [String]

    var id: String { name }
}

// MARK: - Tap Health Status

struct TapHealthStatus: Codable, Equatable {
    enum Status: String, Codable {
        case healthy
        case archived
        case moved
        case notFound
        case unknown
    }

    let status: Status
    let movedTo: String?
    let lastChecked: Date

    static let cacheTTL: TimeInterval = 24 * 60 * 60 // 1 day

    var isStale: Bool {
        Date().timeIntervalSince(lastChecked) > Self.cacheTTL
    }

    static func parseGitHubRepo(from remote: String) -> (owner: String, repo: String)? {
        guard let url = URL(string: remote),
              url.host == "github.com" || url.host == "www.github.com" else {
            return nil
        }
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { return nil }
        let repo = pathComponents[1].hasSuffix(".git")
            ? String(pathComponents[1].dropLast(4))
            : pathComponents[1]
        return (owner: pathComponents[0], repo: repo)
    }
}

enum SidebarCategory: String, CaseIterable, Identifiable {
    case installed = "Installed"
    case formulae = "Formulae"
    case casks = "Casks"
    case outdated = "Outdated"
    case pinned = "Pinned"
    case leaves = "Leaves"
    case taps = "Taps"
    case discover = "Discover"
    case maintenance = "Maintenance"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .installed: "shippingbox.fill"
        case .formulae: "terminal.fill"
        case .casks: "macwindow"
        case .outdated: "arrow.triangle.2.circlepath"
        case .pinned: "pin.fill"
        case .leaves: "leaf.fill"
        case .taps: "spigot.fill"
        case .discover: "magnifyingglass"
        case .maintenance: "wrench.and.screwdriver.fill"
        }
    }
}

// MARK: - Appcast Release

struct AppcastRelease: Identifiable {
    let title: String
    let pubDate: String?
    let version: String?
    let descriptionHTML: String?

    var id: String { version ?? title }

    var publishedDate: Date? {
        guard let pubDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: pubDate)
    }
}

// MARK: - Appcast Parser

final class AppcastParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentTitle = ""
    private var currentPubDate = ""
    private var currentVersion = ""
    private var currentDescription = ""
    private var release: AppcastRelease?
    private var insideItem = false

    func parse(data: Data) -> AppcastRelease? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return release
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentPubDate = ""
            currentVersion = ""
            currentDescription = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "pubDate": currentPubDate += string
        case "sparkle:shortVersionString": currentVersion += string
        case "description": currentDescription += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard insideItem, currentElement == "description" else { return }
        if let text = String(data: CDATABlock, encoding: .utf8) {
            currentDescription += text
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "item" {
            release = AppcastRelease(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines),
                version: currentVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                descriptionHTML: currentDescription.isEmpty ? nil : currentDescription
            )
            insideItem = false
        }
        currentElement = ""
    }
}

// MARK: - Brew Config

struct BrewConfig {
    let version: String?
    let homebrewLastCommit: String?
    let coreTapLastCommit: String?
    let coreCaskTapLastCommit: String?

    static func parse(from output: String) -> Self {
        var values: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        return Self(
            version: values["HOMEBREW_VERSION"],
            homebrewLastCommit: values["Last commit"],
            coreTapLastCommit: values["Core tap last commit"],
            coreCaskTapLastCommit: values["Core cask tap last commit"]
        )
    }
}

// MARK: - Brew JSON v2 Response Types

struct BrewInfoResponse: Decodable {
    let formulae: [FormulaJSON]?
    let casks: [CaskJSON]?
}

struct FormulaJSON: Decodable {
    let name: String
    let desc: String?
    let homepage: String?
    let versions: FormulaVersions?
    let pinned: Bool?
    let installed: [FormulaInstalled]?
    let dependencies: [String]?

    struct FormulaVersions: Decodable {
        let stable: String?
    }

    struct FormulaInstalled: Decodable {
        let version: String?
        let installedOnRequest: Bool?

        enum CodingKeys: String, CodingKey {
            case version
            case installedOnRequest = "installed_on_request"
        }
    }

    func toPackage() -> BrewPackage {
        let installedVersion = installed?.first?.version
        let stable = versions?.stable ?? "unknown"
        return BrewPackage(
            id: "formula-\(name)",
            name: name,
            version: installedVersion ?? stable,
            description: desc ?? "",
            homepage: homepage ?? "",
            isInstalled: true,
            isOutdated: false,
            installedVersion: installedVersion,
            latestVersion: stable,
            isCask: false,
            pinned: pinned ?? false,
            installedOnRequest: installed?.first?.installedOnRequest ?? false,
            dependencies: dependencies ?? []
        )
    }
}

struct CaskJSON: Decodable {
    let token: String
    let version: String?
    let desc: String?
    let homepage: String?

    func toPackage() -> BrewPackage {
        let resolvedVersion = version ?? "unknown"
        return BrewPackage(
            id: "cask-\(token)",
            name: token,
            version: resolvedVersion,
            description: desc ?? "",
            homepage: homepage ?? "",
            isInstalled: true,
            isOutdated: false,
            installedVersion: resolvedVersion,
            latestVersion: nil,
            isCask: true,
            pinned: false,
            installedOnRequest: true,
            dependencies: []
        )
    }
}

struct BrewOutdatedResponse: Decodable {
    let formulae: [OutdatedFormulaJSON]?
    let casks: [OutdatedCaskJSON]?
}

struct OutdatedFormulaJSON: Decodable {
    let name: String
    let installedVersions: [String]?
    let currentVersion: String?
    let pinned: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
        case pinned
    }

    func toPackage() -> BrewPackage? {
        guard let currentVersion else { return nil }
        return BrewPackage(
            id: "formula-\(name)",
            name: name,
            version: installedVersions?.first ?? "unknown",
            description: "",
            homepage: "",
            isInstalled: true,
            isOutdated: true,
            installedVersion: installedVersions?.first,
            latestVersion: currentVersion,
            isCask: false,
            pinned: pinned ?? false,
            installedOnRequest: true,
            dependencies: []
        )
    }
}

struct OutdatedCaskJSON: Decodable {
    let name: String
    let installedVersions: String?
    let currentVersion: String?

    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
    }

    func toPackage() -> BrewPackage? {
        guard let currentVersion,
              let installedVersions else { return nil }
        return BrewPackage(
            id: "cask-\(name)",
            name: name,
            version: installedVersions,
            description: "",
            homepage: "",
            isInstalled: true,
            isOutdated: true,
            installedVersion: installedVersions,
            latestVersion: currentVersion,
            isCask: true,
            pinned: false,
            installedOnRequest: true,
            dependencies: []
        )
    }
}

struct TapJSON: Decodable {
    let name: String
    let remote: String?
    let official: Bool?
    let formulaNames: [String]?
    let caskTokens: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case remote
        case official
        case formulaNames = "formula_names"
        case caskTokens = "cask_tokens"
    }

    func toTap() -> BrewTap {
        var resolvedRemote = remote ?? ""
        if resolvedRemote.hasSuffix(".git") { resolvedRemote = String(resolvedRemote.dropLast(4)) }
        return BrewTap(
            name: name,
            remote: resolvedRemote,
            isOfficial: official ?? false,
            formulaNames: formulaNames ?? [],
            caskTokens: caskTokens ?? []
        )
    }
}
