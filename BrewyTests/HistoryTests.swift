import Foundation
import Testing
@testable import Brewy

// MARK: - ActionHistoryEntry Model Tests

@Suite("ActionHistoryEntry Model")
struct ActionHistoryEntryTests {

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let entry = ActionHistoryEntry(
            id: UUID(),
            command: "install",
            arguments: ["install", "--cask", "firefox"],
            packageName: "firefox",
            packageSource: .cask,
            status: .success,
            output: "==> Downloading firefox\n==> Installing Cask firefox",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ActionHistoryEntry.self, from: data)
        #expect(decoded.id == entry.id)
        #expect(decoded.command == "install")
        #expect(decoded.arguments == ["install", "--cask", "firefox"])
        #expect(decoded.packageName == "firefox")
        #expect(decoded.packageSource == .cask)
        #expect(decoded.status == .success)
        #expect(decoded.output.contains("firefox"))
        #expect(decoded.timestamp == entry.timestamp)
    }

    @Test("Codable round-trip with nil package fields")
    func codableRoundTripNilPackage() throws {
        let entry = ActionHistoryEntry(
            id: UUID(),
            command: "cleanup",
            arguments: ["cleanup", "--prune=all"],
            packageName: nil,
            packageSource: nil,
            status: .success,
            output: "",
            timestamp: Date()
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ActionHistoryEntry.self, from: data)
        #expect(decoded.packageName == nil)
        #expect(decoded.packageSource == nil)
    }

    @Test("Equality is based on ID only")
    func equalityById() {
        let id = UUID()
        let first = ActionHistoryEntry(
            id: id, command: "install", arguments: ["install", "wget"],
            packageName: "wget", packageSource: .formula,
            status: .success, output: "ok", timestamp: Date()
        )
        let second = ActionHistoryEntry(
            id: id, command: "uninstall", arguments: ["uninstall", "curl"],
            packageName: "curl", packageSource: .formula,
            status: .failure, output: "error", timestamp: Date()
        )
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test("Entries with different IDs are not equal")
    func inequalityByDifferentId() {
        let first = ActionHistoryEntry(
            id: UUID(), command: "install", arguments: ["install", "wget"],
            packageName: "wget", packageSource: .formula,
            status: .success, output: "", timestamp: Date()
        )
        let second = ActionHistoryEntry(
            id: UUID(), command: "install", arguments: ["install", "wget"],
            packageName: "wget", packageSource: .formula,
            status: .success, output: "", timestamp: Date()
        )
        #expect(first != second)
    }

    @Test("displayCommand formats correctly")
    func displayCommand() {
        let entry = ActionHistoryEntry(
            id: UUID(), command: "install", arguments: ["install", "--cask", "firefox"],
            packageName: "firefox", packageSource: .cask,
            status: .success, output: "", timestamp: Date()
        )
        #expect(entry.displayCommand == "brew install --cask firefox")
    }

    @Test("isRetryable is true for failed entries with arguments")
    func isRetryableForFailure() {
        let entry = ActionHistoryEntry(
            id: UUID(), command: "install", arguments: ["install", "wget"],
            packageName: "wget", packageSource: .formula,
            status: .failure, output: "Error", timestamp: Date()
        )
        #expect(entry.isRetryable == true)
    }

    @Test("isRetryable is false for successful entries")
    func isRetryableForSuccess() {
        let entry = ActionHistoryEntry(
            id: UUID(), command: "install", arguments: ["install", "wget"],
            packageName: "wget", packageSource: .formula,
            status: .success, output: "", timestamp: Date()
        )
        #expect(entry.isRetryable == false)
    }

    @Test("isRetryable is false for empty arguments")
    func isRetryableEmptyArgs() {
        let entry = ActionHistoryEntry(
            id: UUID(), command: "", arguments: [],
            packageName: nil, packageSource: nil,
            status: .failure, output: "", timestamp: Date()
        )
        #expect(entry.isRetryable == false)
    }

    @Test("Status raw values encode correctly")
    func statusRawValues() {
        #expect(ActionHistoryEntry.Status.success.rawValue == "success")
        #expect(ActionHistoryEntry.Status.failure.rawValue == "failure")
    }
}

// MARK: - BrewService History Tests

@Suite("BrewService Action History")
@MainActor
struct BrewServiceHistoryTests {

    @Test("recordAction adds entry to history")
    func recordActionAddsEntry() {
        let service = BrewService()
        service.recordAction(
            arguments: ["install", "wget"],
            packageName: "wget",
            packageSource: .formula,
            success: true,
            output: "Installed wget"
        )
        #expect(service.actionHistory.count == 1)
        #expect(service.actionHistory[0].command == "install")
        #expect(service.actionHistory[0].packageName == "wget")
        #expect(service.actionHistory[0].status == .success)
    }

    @Test("recordAction inserts newest first")
    func newestFirst() {
        let service = BrewService()
        service.recordAction(
            arguments: ["install", "wget"], packageName: "wget",
            packageSource: .formula, success: true, output: ""
        )
        service.recordAction(
            arguments: ["install", "curl"], packageName: "curl",
            packageSource: .formula, success: true, output: ""
        )
        #expect(service.actionHistory[0].packageName == "curl")
        #expect(service.actionHistory[1].packageName == "wget")
    }

    @Test("recordAction caps at maxHistoryEntries")
    func capsAtMax() {
        let service = BrewService()
        for idx in 0..<(BrewService.maxHistoryEntries + 10) {
            service.recordAction(
                arguments: ["install", "pkg\(idx)"], packageName: "pkg\(idx)",
                packageSource: .formula, success: true, output: ""
            )
        }
        #expect(service.actionHistory.count == BrewService.maxHistoryEntries)
    }

    @Test("clearHistory removes all entries")
    func clearHistoryRemovesAll() {
        let service = BrewService()
        service.recordAction(
            arguments: ["install", "wget"], packageName: "wget",
            packageSource: .formula, success: true, output: ""
        )
        service.clearHistory()
        #expect(service.actionHistory.isEmpty)
    }

    @Test("packages(for: .history) returns empty array")
    func packagesForHistoryReturnsEmpty() {
        let service = BrewService()
        #expect(service.packages(for: .history).isEmpty)
    }
}

// MARK: - SidebarCategory History Tests

@Suite("SidebarCategory History")
struct SidebarCategoryHistoryTests {

    @Test("History category has correct properties")
    func historyCategoryProperties() {
        let category = SidebarCategory.history
        #expect(category.rawValue == "History")
        #expect(category.systemImage == "clock.arrow.circlepath")
        #expect(category.id == "History")
    }
}
