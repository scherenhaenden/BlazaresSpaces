//
//  BlazaresSpacesUITests.swift
//  BlazaresSpacesUITests
//
//  Created by Edward Flores on 15.09.26.
//

import XCTest

final class BlazaresSpacesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDailyDriverLaunchesWithoutExternalMutationActions() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["dailyDriverTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["accessibilityStatus"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["activeDesktopStatus"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["dailyDriverDesktopManager"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["dailyDriverWindowsSection"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testDesktopManagerShowsSafeNonDestructiveControls() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["dailyDriverDesktopManager"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["addWorkspaceButton"].exists)

        // Enabling switching may be disabled when Accessibility is unavailable,
        // but the explicit opt-in control must remain visible.
        XCTAssertTrue(app.buttons["enableDesktopSwitchingButton"].exists)
        XCTAssertTrue(app.buttons["Refresh"].exists)
    }

    @MainActor
    func testAdvancedDiagnosticsAreSecondary() throws {
        let app = XCUIApplication()
        app.launch()

        let disclosure = app.disclosureTriangles["Advanced Diagnostics"]
        if disclosure.exists {
            disclosure.click()
        } else {
            app.staticTexts["Advanced Diagnostics"].click()
        }

        XCTAssertTrue(app.buttons["Open Inspector"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Window Control Lab"].exists)
        XCTAssertTrue(app.buttons["Capture Read-Only Desktop Snapshot"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
