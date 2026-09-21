//
//  SwiftStoreUITests.swift
//  toolboxUITests
//
//  Created by Deerio on 2026/9/18.
//

import XCTest

/// Uses the local fixture server (scripts/range_server.py, /apps.json);
/// SwiftStoreLiveTests covers the real API.
final class SwiftStoreUITests: XCTestCase {

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-storeEndpoint", "http://127.0.0.1:18743/apps.json"]
        app.launch()
        return app
    }

    /// Waits for an element, retrying with a pull-to-refresh once — the
    /// first network request on a cold simulator clone can fail.
    @MainActor
    private func waitForStoreContent(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 20) { return true }
        app.swipeDown()
        return element.waitForExistence(timeout: 20)
    }

    @MainActor
    func testStoreListAndDetail() throws {
        let app = launchApp()

        app.tabBars.buttons["Swift Store"].tap()
        let firstApp = app.staticTexts["lanlu-iOS"]
        XCTAssertTrue(waitForStoreContent(firstApp, in: app))

        let listShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        listShot.lifetime = .keepAlways
        add(listShot)

        firstApp.tap()
        XCTAssertTrue(app.staticTexts["作者"].waitForExistence(timeout: 5))

        let detailShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detailShot.lifetime = .keepAlways
        add(detailShot)
    }

    /// PiliPod currently has one extra source ("DeeChael 源"); its versions
    /// must appear as a separate section at the bottom of the detail page.
    @MainActor
    func testSourceSections() throws {
        let app = launchApp()

        app.tabBars.buttons["Swift Store"].tap()
        let piliPod = app.staticTexts["PiliPod"]
        XCTAssertTrue(waitForStoreContent(piliPod, in: app))
        piliPod.tap()

        let sourceHeader = app.staticTexts["DeeChael 源"]
        for _ in 0..<6 where !sourceHeader.exists {
            app.swipeUp()
        }
        XCTAssertTrue(sourceHeader.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["0.3.6-newui"].exists)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }
}
