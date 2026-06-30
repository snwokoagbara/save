//
//  save_aiUITests.swift
//  save.aiUITests
//
//  Created by Chris on 9/15/25.
//

import XCTest

final class save_aiUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLaunchShowsAssistantNativePrototypeShell() throws {
        let app = XCUIApplication()
        app.launchArguments = ["RESET_SAVE_MVP_PROGRESS"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Kai finds medical money you can claim back."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["savePrimaryButton"].exists)
        app.buttons["Start with demo sources"].tap()

        XCTAssertTrue(app.staticTexts["Kai is working"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Ask Kai or drop a receipt"].exists)
        XCTAssertTrue(app.otherElements["saveGlassCommandBar"].exists)
        XCTAssertTrue(app.staticTexts["Active tasks"].exists)
        XCTAssertTrue(app.otherElements["saveTaskLedger"].exists)
        XCTAssertTrue(app.buttons["Review item"].exists)
        XCTAssertTrue(app.buttons["Prepare claim"].exists)
    }

    @MainActor
    func testWorkflowSheetsUseSharedLightDesignSystem() throws {
        let app = XCUIApplication()
        app.launchArguments = ["RESET_SAVE_MVP_PROGRESS"]
        app.launch()
        app.buttons["Start with demo sources"].tap()

        app.buttons["Add receipt"].tap()
        XCTAssertTrue(app.otherElements["saveReceiptIntakeSheet"].waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments = []
        app.launch()

        app.swipeUp()
        app.buttons["Review item"].tap()
        XCTAssertTrue(app.otherElements["saveReceiptReviewSheet"].waitForExistence(timeout: 3))

        app.terminate()
        app.launch()

        app.swipeUp()
        app.buttons["Prepare claim"].tap()
        XCTAssertTrue(app.otherElements["saveClaimPacketSheet"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
