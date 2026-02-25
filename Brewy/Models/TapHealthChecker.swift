import Foundation
import OSLog

// MARK: - Logging

private let logger = Logger(subsystem: "io.linnane.brewy", category: "TapHealthChecker")

// MARK: - No-Redirect URL Session Delegate

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

// MARK: - Tap Health Checker

enum TapHealthChecker {

    private static let cacheDirectory: URL? = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("Brewy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let cacheURL: URL? = cacheDirectory?.appendingPathComponent("tapHealthCache.json")

    static func loadCache() -> [String: TapHealthStatus] {
        guard let cacheURL else { return [:] }
        do {
            let data = try Data(contentsOf: cacheURL)
            let statuses = try JSONDecoder().decode([String: TapHealthStatus].self, from: data)
            logger.info("Loaded tap health cache with \(statuses.count) entries")
            return statuses
        } catch {
            logger.debug("No tap health cache found: \(error.localizedDescription)")
            return [:]
        }
    }

    static func saveCache(_ statuses: [String: TapHealthStatus]) {
        guard let cacheURL else { return }
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(statuses)
                try data.write(to: cacheURL, options: .atomic)
                logger.debug("Tap health cache saved")
            } catch {
                logger.error("Failed to save tap health cache: \(error.localizedDescription)")
            }
        }
    }

    static func checkHealth(
        taps: [BrewTap],
        existing: [String: TapHealthStatus]
    ) async -> [String: TapHealthStatus] {
        var statuses = existing
        var updated = false

        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        for tap in taps {
            if let cached = statuses[tap.name], !cached.isStale {
                continue
            }
            guard let (owner, repo) = TapHealthStatus.parseGitHubRepo(from: tap.remote) else {
                continue
            }
            statuses[tap.name] = await fetchRepoHealth(owner: owner, repo: repo, session: session)
            updated = true
        }

        // Remove entries for taps no longer installed
        let tapNames = Set(taps.map(\.name))
        for key in statuses.keys where !tapNames.contains(key) {
            statuses.removeValue(forKey: key)
            updated = true
        }

        if updated { saveCache(statuses) }
        return statuses
    }

    // MARK: - GitHub API Models

    private struct GitHubRepo: Decodable {
        let archived: Bool?
        let htmlUrl: String?

        enum CodingKeys: String, CodingKey {
            case archived
            case htmlUrl = "html_url"
        }
    }

    // MARK: - Private Helpers

    private static func fetchRepoHealth(owner: String, repo: String, session: URLSession) async -> TapHealthStatus {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)"
        guard let url = URL(string: urlString) else {
            return TapHealthStatus(status: .unknown, movedTo: nil, lastChecked: Date())
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Brewy", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return TapHealthStatus(status: .unknown, movedTo: nil, lastChecked: Date())
            }
            return await mapResponse(statusCode: httpResponse.statusCode, data: data, response: httpResponse, owner: owner, repo: repo)
        } catch {
            logger.warning("Failed to check health for \(owner)/\(repo): \(error.localizedDescription)")
            return TapHealthStatus(status: .unknown, movedTo: nil, lastChecked: Date())
        }
    }

    private static func mapResponse(
        statusCode: Int,
        data: Data,
        response: HTTPURLResponse,
        owner: String,
        repo: String
    ) async -> TapHealthStatus {
        switch statusCode {
        case 200:
            return parseRepoResponse(data: data)
        case 301:
            let movedTo = await resolveRedirectLocation(data: data, response: response)
            return TapHealthStatus(status: .moved, movedTo: movedTo, lastChecked: Date())
        case 404:
            return TapHealthStatus(status: .notFound, movedTo: nil, lastChecked: Date())
        case 403:
            logger.warning("GitHub API rate limited for \(owner)/\(repo)")
            return TapHealthStatus(status: .unknown, movedTo: nil, lastChecked: Date())
        default:
            return TapHealthStatus(status: .unknown, movedTo: nil, lastChecked: Date())
        }
    }

    private static func parseRepoResponse(data: Data) -> TapHealthStatus {
        do {
            let repo = try JSONDecoder().decode(GitHubRepo.self, from: data)
            let status: TapHealthStatus.Status = (repo.archived == true) ? .archived : .healthy
            return TapHealthStatus(status: status, movedTo: nil, lastChecked: Date())
        } catch {
            return TapHealthStatus(status: .unknown, movedTo: nil, lastChecked: Date())
        }
    }

    private static func resolveRedirectLocation(data: Data, response: HTTPURLResponse) async -> String? {
        let apiUrl = parseRedirectApiUrl(data: data, response: response)

        // If redirect points to api.github.com, resolve the html_url
        if let apiUrl, apiUrl.host == "api.github.com" {
            if let htmlUrl = await fetchHtmlUrl(from: apiUrl) {
                return htmlUrl
            }
        }

        // Fall back to the raw redirect URL
        if let apiUrl {
            return apiUrl.absoluteString
        }
        return nil
    }

    private static func parseRedirectApiUrl(data: Data, response: HTTPURLResponse) -> URL? {
        if let location = response.value(forHTTPHeaderField: "Location"),
           let url = URL(string: location) {
            return url
        }
        struct GitHubRedirect: Decodable { let url: String? }
        if let urlString = try? JSONDecoder().decode(GitHubRedirect.self, from: data).url {
            return URL(string: urlString)
        }
        return nil
    }

    private static func fetchHtmlUrl(from apiUrl: URL) async -> String? {
        var request = URLRequest(url: apiUrl)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Brewy", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                logger.warning("Failed to resolve API URL \(apiUrl): unexpected status")
                return nil
            }
            let repo = try JSONDecoder().decode(GitHubRepo.self, from: data)
            return repo.htmlUrl
        } catch {
            logger.warning("Failed to resolve API URL \(apiUrl): \(error.localizedDescription)")
            return nil
        }
    }
}
