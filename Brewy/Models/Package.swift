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

    static func == (lhs: BrewPackage, rhs: BrewPackage) -> Bool {
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

enum SidebarCategory: String, CaseIterable, Identifiable {
    case installed = "Installed"
    case formulae = "Formulae"
    case casks = "Casks"
    case outdated = "Outdated"
    case pinned = "Pinned"
    case taps = "Taps"
    case maintenance = "Maintenance"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .installed: "shippingbox.fill"
        case .formulae: "terminal.fill"
        case .casks: "macwindow"
        case .outdated: "arrow.triangle.2.circlepath"
        case .pinned: "pin.fill"
        case .taps: "spigot.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        }
    }
}

// MARK: - Brew Config

struct BrewConfig {
    let version: String?
    let homebrewLastCommit: String?
    let coreTapLastCommit: String?
    let coreCaskTapLastCommit: String?

    static func parse(from output: String) -> BrewConfig {
        var values: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        return BrewConfig(
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
        let installed_on_request: Bool?
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
            installedOnRequest: installed?.first?.installed_on_request ?? false,
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
        let v = version ?? "unknown"
        return BrewPackage(
            id: "cask-\(token)",
            name: token,
            version: v,
            description: desc ?? "",
            homepage: homepage ?? "",
            isInstalled: true,
            isOutdated: false,
            installedVersion: v,
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
    let installed_versions: [String]?
    let current_version: String?
    let pinned: Bool?

    func toPackage() -> BrewPackage? {
        guard let currentVersion = current_version else { return nil }
        return BrewPackage(
            id: "formula-\(name)",
            name: name,
            version: installed_versions?.first ?? "unknown",
            description: "",
            homepage: "",
            isInstalled: true,
            isOutdated: true,
            installedVersion: installed_versions?.first,
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
    let installed_versions: String?
    let current_version: String?

    func toPackage() -> BrewPackage? {
        guard let currentVersion = current_version,
              let installedVersions = installed_versions else { return nil }
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
    let formula_names: [String]?
    let cask_tokens: [String]?

    func toTap() -> BrewTap {
        var r = remote ?? ""
        if r.hasSuffix(".git") { r = String(r.dropLast(4)) }
        return BrewTap(
            name: name,
            remote: r,
            isOfficial: official ?? false,
            formulaNames: formula_names ?? [],
            caskTokens: cask_tokens ?? []
        )
    }
}
