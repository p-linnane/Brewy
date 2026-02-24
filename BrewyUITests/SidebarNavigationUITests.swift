import XCTest

@MainActor
final class SidebarNavigationUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints", "YES"]
        app.launch()
    }

    override func tearDown() async throws {
        app = nil
    }

    // MARK: - Sidebar Category Navigation

    func testAllSidebarCategoriesRender() throws {
        let categories = [
            "Installed", "Formulae", "Casks", "Outdated",
            "Pinned", "Leaves", "Taps", "Discover", "Maintenance"
        ]

        let sidebar = app.outlines.firstMatch

        for category in categories {
            let row = sidebar.staticTexts[category]
            XCTAssertTrue(
                row.waitForExistence(timeout: 5),
                "Sidebar category '\(category)' should exist"
            )
            row.click()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        }
    }

    func testSidebarContainsAllCategories() throws {
        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5), "Sidebar should exist")

        let expectedCategories = [
            "Installed", "Formulae", "Casks", "Outdated",
            "Pinned", "Leaves", "Taps", "Discover", "Maintenance"
        ]

        for category in expectedCategories {
            XCTAssertTrue(
                sidebar.staticTexts[category].exists,
                "Sidebar should contain '\(category)' category"
            )
        }
    }

    // MARK: - Maintenance View (Regression: Layout Constraints)

    func testMaintenanceViewTransition() throws {
        let sidebar = app.outlines.firstMatch

        let installed = sidebar.staticTexts["Installed"]
        XCTAssertTrue(installed.waitForExistence(timeout: 5))
        installed.click()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

        let maintenance = sidebar.staticTexts["Maintenance"]
        maintenance.click()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

        installed.click()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
    }

    // MARK: - Refresh Button

    func testRefreshButtonExists() throws {
        let refreshButton = app.buttons["Refresh"]
        XCTAssertTrue(
            refreshButton.waitForExistence(timeout: 5),
            "Refresh button should exist in sidebar footer"
        )
    }
}
