//
//  WebDownloadInterceptionUITests.swift
//  toolboxUITests
//
//  Created by Deerio on 2026/9/18.
//

import XCTest

/// Requires scripts/range_server.py to be running.
final class WebDownloadInterceptionUITests: XCTestCase {

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        return app
    }

    @MainActor
    private func openWebSheet(at url: String, in app: XCUIApplication) throws {
        app.tabBars.buttons["下载"].tap()
        app.buttons["添加下载"].tap()
        app.buttons["访问网页"].tap()

        let field = app.textFields["输入网址"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        // The sheet restores the last visited URL, so clear the field first.
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(url + "\n")
    }

    @MainActor
    func testInterceptsDownloadFromWebPage() throws {
        let app = launchApp()
        try openWebSheet(at: "http://127.0.0.1:18743", in: app)

        let link = app.links["下载文件"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()

        // The sheet dismisses and the intercepted task shows in the list.
        XCTAssertTrue(app.staticTexts["test.bin"].waitForExistence(timeout: 10))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A target="_blank" link whose file is Referer-protected: without the
    /// Referer header the server redirects to the homepage. Exercises both
    /// the in-place load of new-window links and the Referer replay.
    @MainActor
    func testInterceptsBlankTargetDownloadWithReferer() throws {
        let app = launchApp()
        try openWebSheet(at: "http://127.0.0.1:18743", in: app)

        let link = app.links["新标签下载"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()

        XCTAssertTrue(app.staticTexts["protected.bin"].waitForExistence(timeout: 10))
    }
}
