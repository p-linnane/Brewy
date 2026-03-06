@testable import Brewy
import Foundation
import Testing

// MARK: - Mock Command Runner

final class MockCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _results: [[String]: CommandResult] = [:]
    private var _executedCommands: [[String]] = []

    var executedCommands: [[String]] {
        lock.withLock { _executedCommands }
    }

    func setResult(for arguments: [String], output: String, success: Bool = true) {
        lock.withLock {
            _results[arguments] = CommandResult(output: output, success: success)
        }
    }

    func run(_ arguments: [String], brewPath: String, timeout: Duration) async -> CommandResult {
        lock.withLock {
            _executedCommands.append(arguments)
            return _results[arguments] ?? CommandResult(output: "", success: false)
        }
    }

    func runExecutable(_ executablePath: String, arguments: [String], timeout: Duration) async -> CommandResult {
        lock.withLock {
            _executedCommands.append(arguments)
            return _results[arguments] ?? CommandResult(output: "", success: false)
        }
    }
}

// MARK: - Test Data

enum TestJSON {
    static let formulae = """
    {"formulae":[{"name":"wget","desc":"Internet file retriever",\
    "homepage":"https://www.gnu.org/software/wget/",\
    "versions":{"stable":"1.24.5"},"pinned":false,\
    "installed":[{"version":"1.24.5","installed_on_request":true}],\
    "dependencies":["openssl@3","libidn2"]}],"casks":[]}
    """

    static let casks = """
    {"formulae":[],"casks":[{"token":"firefox","version":"122.0",\
    "desc":"Web browser","homepage":"https://www.mozilla.org/firefox/"}]}
    """

    static let outdated = """
    {"formulae":[{"name":"wget","installed_versions":["1.24.5"],\
    "current_version":"1.25.0","pinned":false}],"casks":[]}
    """

    static let taps = """
    [{"name":"homebrew/core","remote":"https://github.com/Homebrew/homebrew-core.git",\
    "official":true,"formula_names":["wget"],"cask_tokens":[]}]
    """

    static let emptyFormulae = """
    {"formulae":[],"casks":[]}
    """

    static let emptyOutdated = """
    {"formulae":[],"casks":[]}
    """

    static let emptyTaps = "[]"

    static let formulaDetail = """
    {"formulae":[{"name":"wget","desc":"Internet file retriever",\
    "homepage":"https://www.gnu.org/software/wget/",\
    "versions":{"stable":"1.25.0"},"pinned":false,\
    "installed":[{"version":"1.24.5","installed_on_request":true}],\
    "dependencies":["openssl@3","libidn2","gettext"]}],"casks":[]}
    """

    static let caskDetail = """
    {"formulae":[],"casks":[{"token":"firefox","version":"123.0",\
    "desc":"Fast web browser","homepage":"https://www.mozilla.org/firefox/"}]}
    """
}

// MARK: - Test Helpers

@MainActor
func makeService(mock: MockCommandRunner) -> (BrewService, MockCommandRunner) {
    let service = BrewService(commandRunner: mock)
    return (service, mock)
}

func setupRefreshMock(_ mock: MockCommandRunner) {
    mock.setResult(for: ["info", "--installed", "--json=v2"], output: TestJSON.formulae)
    mock.setResult(for: ["info", "--installed", "--cask", "--json=v2"], output: TestJSON.casks)
    mock.setResult(for: ["outdated", "--json=v2"], output: TestJSON.outdated)
    mock.setResult(for: ["tap-info", "--json=v1", "--installed"], output: TestJSON.taps)
}

func makePackage(
    name: String,
    source: PackageSource = .formula,
    pinned: Bool = false,
    isOutdated: Bool = false,
    installedVersion: String? = nil,
    latestVersion: String? = nil,
    dependencies: [String] = []
) -> BrewPackage {
    let prefix: String
    switch source {
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
        source: source,
        pinned: pinned,
        installedOnRequest: true,
        dependencies: dependencies
    )
}
