import Foundation

// MARK: - Package Detail Fetching

extension BrewService {

    func fetchPackageDetail(for package: BrewPackage) async -> BrewPackage? {
        let command = package.isCask
            ? ["info", "--cask", "--json=v2", package.name]
            : ["info", "--json=v2", package.name]
        let result = await runBrewCommand(command)
        guard result.success, let data = result.output.data(using: .utf8) else { return nil }

        return await Task.detached(priority: .userInitiated) {
            do {
                let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
                if package.isCask, let cask = response.casks?.first {
                    return BrewPackage(
                        id: package.id,
                        name: cask.token,
                        version: cask.version ?? package.version,
                        description: cask.desc ?? package.description,
                        homepage: cask.homepage ?? "",
                        isInstalled: package.isInstalled,
                        isOutdated: package.isOutdated,
                        installedVersion: package.installedVersion,
                        latestVersion: package.latestVersion,
                        source: package.source,
                        pinned: package.pinned,
                        installedOnRequest: package.installedOnRequest,
                        dependencies: package.dependencies
                    )
                }
                if let formula = response.formulae?.first {
                    return BrewPackage(
                        id: package.id,
                        name: formula.name,
                        version: formula.versions?.stable ?? package.version,
                        description: formula.desc ?? package.description,
                        homepage: formula.homepage ?? "",
                        isInstalled: package.isInstalled,
                        isOutdated: package.isOutdated,
                        installedVersion: package.installedVersion,
                        latestVersion: package.latestVersion,
                        source: package.source,
                        pinned: package.pinned,
                        installedOnRequest: package.installedOnRequest,
                        dependencies: formula.dependencies ?? package.dependencies
                    )
                }
                return nil
            } catch {
                return nil
            }
        }.value
    }
}
