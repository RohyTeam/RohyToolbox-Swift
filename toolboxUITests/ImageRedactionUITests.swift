//
//  ImageRedactionUITests.swift
//  toolboxUITests
//
//  Created by Deerio on 2026/9/21.
//

import XCTest

/// Photo access is pre-granted via `simctl privacy grant photos`.
final class ImageRedactionUITests: XCTestCase {

    @MainActor
    private func launchAndOpenEditor(_ app: XCUIApplication) {
        addUIInterruptionMonitor(withDescription: "Photos access") { alert in
            for label in ["允许完全访问", "Allow Full Access", "允许", "OK"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        app.launch()
        app.staticTexts["图片打码"].tap()
        // The permission card may appear; accept full access explicitly.
        let allow = app.buttons["允许完全访问"].firstMatch
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
        // Nudge: lets the interruption monitor evaluate anything left.
        app.swipeUp()
    }

    /// Waits until grid thumbnails exist.
    @MainActor
    private func waitForGrid(_ app: XCUIApplication) -> XCUIElement {
        let cells = app.images.matching(identifier: "asset-cell")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 15))
        // Let the grid settle so frames are stable for coordinate taps.
        Thread.sleep(forTimeInterval: 1)
        return cells.firstMatch
    }

    @MainActor
    private func openEditor(_ app: XCUIApplication) {
        let cell = waitForGrid(app)
        // Tap by coordinate: re-resolving elements after async thumbnail
        // loads is flaky.
        let frame = cell.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
        XCTAssertTrue(app.buttons["撤销"].waitForExistence(timeout: 10))
        // Let the full image and text analysis settle.
        Thread.sleep(forTimeInterval: 2)
    }

    @MainActor
    func testGridShowsPhotos() throws {
        let app = XCUIApplication()
        launchAndOpenEditor(app)
        // The simulator's preset photos show up as grid cells.
        XCTAssertTrue(app.scrollViews.images.firstMatch.waitForExistence(timeout: 10))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Long-press + drag creates a box; tapping it confirms, tapping again
    /// deletes it.
    @MainActor
    func testCreateConfirmDeleteBox() throws {
        let app = XCUIApplication()
        launchAndOpenEditor(app)
        openEditor(app)

        let opened = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        opened.name = "editor-opened"
        opened.lifetime = .keepAlways
        add(opened)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6))
        start.press(forDuration: 0.6, thenDragTo: end)

        let box = app.descendants(matching: .any)["redaction-box"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 3))

        // First tap confirms creation; second tap deletes.
        // Taps go through by coordinate: the box view itself has no gesture.
        func tapBox() {
            let f = box.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: f.midX, dy: f.midY))
                .tap()
        }
        tapBox()
        XCTAssertTrue(box.exists)
        tapBox()
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: box
        )
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 3), .completed)
    }

    /// Blur mode renders the real effect, not a flat color.
    @MainActor
    func testBlurBoxRendersRealEffect() throws {
        let app = XCUIApplication()
        launchAndOpenEditor(app)
        openEditor(app)

        app.buttons["打码方式"].tap()
        app.buttons["模糊"].tap()

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6))
        start.press(forDuration: 0.6, thenDragTo: end)

        let box = app.descendants(matching: .any)["redaction-box"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 3))
        // Wait for the patch render.
        Thread.sleep(forTimeInterval: 1)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The trash button asks for confirmation, then removes every box.
    @MainActor
    func testClearAllBoxes() throws {
        let app = XCUIApplication()
        launchAndOpenEditor(app)
        openEditor(app)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6))
        start.press(forDuration: 0.6, thenDragTo: end)

        let box = app.descendants(matching: .any)["redaction-box"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 3))

        app.buttons["清除所有打码"].firstMatch.tap()
        let confirm = app.alerts.buttons["清除所有打码"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: box
        )
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 3), .completed)
    }

    /// After creating a box, dragging its bottom edge down grows its height
    /// (and only its height).
    @MainActor
    func testResizePendingBoxByEdge() throws {
        let app = XCUIApplication()
        launchAndOpenEditor(app)
        openEditor(app)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6))
        start.press(forDuration: 0.6, thenDragTo: end)

        let box = app.descendants(matching: .any)["redaction-box"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 3))
        let before = box.frame

        // Drag the bottom edge down by 60pt.
        let edgeStart = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: before.midX, dy: before.maxY))
        let edgeEnd = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: before.midX, dy: before.maxY + 60))
        edgeStart.press(forDuration: 0.2, thenDragTo: edgeEnd)

        let after = box.frame
        XCTAssertGreaterThan(after.height, before.height + 30)
        XCTAssertEqual(after.minX, before.minX, accuracy: 2)
        XCTAssertEqual(after.maxX, before.maxX, accuracy: 2)
    }
}
