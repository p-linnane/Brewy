import Foundation
import OSLog

private let logger = Logger(subsystem: "io.linnane.brewy", category: "BrewService+Groups")

// MARK: - Package Groups

extension BrewService {

    nonisolated static let groupsURL: URL? = cacheDirectory?.appendingPathComponent("packageGroups.json")

    func loadGroups() {
        guard let url = Self.groupsURL else { return }
        do {
            let data = try Data(contentsOf: url)
            packageGroups = try JSONDecoder().decode([PackageGroup].self, from: data)
            logger.info("Loaded \(self.packageGroups.count) package groups")
        } catch {
            logger.warning("Failed to load groups: \(error.localizedDescription)")
        }
    }

    private func saveGroups() {
        guard let url = Self.groupsURL else { return }
        let groups = packageGroups
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(groups)
                try data.write(to: url, options: .atomic)
                logger.debug("Groups saved successfully")
            } catch {
                logger.error("Failed to save groups: \(error.localizedDescription)")
            }
        }
    }

    func createGroup(name: String, systemImage: String = "folder.fill") {
        let group = PackageGroup(name: name, systemImage: systemImage)
        packageGroups.append(group)
        saveGroups()
    }

    func deleteGroup(_ group: PackageGroup) {
        packageGroups.removeAll { $0.id == group.id }
        saveGroups()
    }

    func updateGroup(_ group: PackageGroup, name: String, systemImage: String) {
        guard let index = packageGroups.firstIndex(where: { $0.id == group.id }) else { return }
        packageGroups[index].name = name
        packageGroups[index].systemImage = systemImage
        saveGroups()
    }

    func addToGroup(_ group: PackageGroup, packageID: String) {
        guard let index = packageGroups.firstIndex(where: { $0.id == group.id }) else { return }
        guard !packageGroups[index].packageIDs.contains(packageID) else { return }
        packageGroups[index].packageIDs.append(packageID)
        saveGroups()
    }

    func removeFromGroup(_ group: PackageGroup, packageID: String) {
        guard let index = packageGroups.firstIndex(where: { $0.id == group.id }) else { return }
        packageGroups[index].packageIDs.removeAll { $0 == packageID }
        saveGroups()
    }

    func packages(in group: PackageGroup) -> [BrewPackage] {
        let idSet = Set(group.packageIDs)
        return allInstalled.filter { idSet.contains($0.id) }
    }
}
