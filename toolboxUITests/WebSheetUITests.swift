//
//  WebSheetUITests.swift
//  toolboxUITests
//
//  Created by Deerio on 2026/9/18.
//

import XCTest

final class WebSheetUITests: XCTestCase {

    @MainActor
    func testWebSheetAddressBar() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["下载"].tap()
        app.buttons["添加下载"].tap()
        app.buttons["访问网页"].tap()

        let field = app.textFields["输入网址"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
