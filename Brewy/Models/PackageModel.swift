import Foundation

// MARK: - Package Source

enum PackageSource: String, Codable {
    case formula
    case cask
    case mas
}

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
    let source: PackageSource
    let pinned: Bool
    let installedOnRequest: Bool
    let dependencies: [String]

    var isCask: Bool { source == .cask }
    var isMas: Bool { source == .mas }

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

    static func tapName(from githubUrl: String) -> String? {
        guard let (owner, repo) = parseGitHubRepo(from: githubUrl) else { return nil }
        let tapRepo = repo.hasPrefix("homebrew-") ? String(repo.dropFirst("homebrew-".count)) : repo
        guard !tapRepo.isEmpty else { return nil }
        return "\(owner)/\(tapRepo)"
    }
}

enum SidebarCategory: String, CaseIterable, Identifiable {
    case installed = "Installed"
    case formulae = "Formulae"
    case casks = "Casks"
    case masApps = "Mac App Store"
    case outdated = "Outdated"
    case pinned = "Pinned"
    case leaves = "Leaves"
    case taps = "Taps"
    case services = "Services"
    case discover = "Discover"
    case maintenance = "Maintenance"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .installed: "shippingbox.fill"
        case .formulae: "terminal.fill"
        case .casks: "macwindow"
        case .masApps: "app.badge.fill"
        case .outdated: "arrow.triangle.2.circlepath"
        case .pinned: "pin.fill"
        case .leaves: "leaf.fill"
        case .taps: "spigot.fill"
        case .services: "gearshape.2"
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

    private static let pubDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    var publishedDate: Date? {
        guard let pubDate else { return nil }
        return Self.pubDateFormatter.date(from: pubDate)
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

// MARK: - Brew Service Item

struct BrewServiceItem: Identifiable, Hashable, Codable {
    let name: String
    let serviceName: String?
    let running: Bool
    let loaded: Bool
    let pid: Int?
    let exitCode: Int?
    let user: String?
    let status: String?
    let file: String?
    let logPath: String?
    let errorLogPath: String?

    var id: String { name }

    var statusLabel: String {
        if running || status == "started" { return "Running" }
        if status == "scheduled" { return "Scheduled" }
        if status == "error" { return "Error" }
        if status == "stopped" || status == "none" { return "Stopped" }
        if let status, !status.isEmpty { return status.capitalized }
        if loaded { return "Loaded" }
        return "Stopped"
    }

    var isHealthy: Bool {
        running || status == "started" || (!loaded && status != "error")
    }

    enum CodingKeys: String, CodingKey {
        case name
        case serviceName = "service_name"
        case running, loaded, pid
        case exitCode = "exit_code"
        case user, status, file
        case logPath = "log_path"
        case errorLogPath = "error_log_path"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        serviceName = try container.decodeIfPresent(String.self, forKey: .serviceName)
        running = try container.decodeIfPresent(Bool.self, forKey: .running) ?? false
        loaded = try container.decodeIfPresent(Bool.self, forKey: .loaded) ?? false
        pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        exitCode = try container.decodeIfPresent(Int.self, forKey: .exitCode)
        user = try container.decodeIfPresent(String.self, forKey: .user)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        file = try container.decodeIfPresent(String.self, forKey: .file)
        logPath = try container.decodeIfPresent(String.self, forKey: .logPath)
        errorLogPath = try container.decodeIfPresent(String.self, forKey: .errorLogPath)
    }

    init(
        name: String, serviceName: String?, running: Bool, loaded: Bool,
        pid: Int?, exitCode: Int?, user: String?, status: String?,
        file: String?, logPath: String?, errorLogPath: String?
    ) {
        self.name = name
        self.serviceName = serviceName
        self.running = running
        self.loaded = loaded
        self.pid = pid
        self.exitCode = exitCode
        self.user = user
        self.status = status
        self.file = file
        self.logPath = logPath
        self.errorLogPath = errorLogPath
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
            source: .formula,
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
            source: .cask,
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
            source: .formula,
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
            source: .cask,
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
