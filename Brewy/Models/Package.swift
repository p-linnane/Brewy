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
