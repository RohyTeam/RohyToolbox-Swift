//
//  TabBadgeUITests.swift
//  toolboxUITests
//
//  Created by Deerio on 2026/9/18.
//

import XCTest

/// Requires scripts/range_server.py to be running.
final class TabBadgeUITests: XCTestCase {

    @MainActor
    func testDownloadsTabBadgeWhileDownloading() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()

        app.tabBars.buttons["下载"].tap()
        app.buttons["添加下载"].tap()
        app.buttons["URL"].tap()

        let field = app.textFields["URL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("http://127.0.0.1:18743/test.bin")
        // The sheet's confirm button (checkmark) in its navigation bar.
        let confirm = app.navigationBars.buttons.element(boundBy: 1)
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        // Capture immediately, while the download is still running.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(app.staticTexts["test.bin"].waitForExistence(timeout: 10))
    }
}
