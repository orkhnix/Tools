import XCTest

final class ReaderUITests: XCTestCase {
    private func openReader() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let document = app.buttons["document-Welcome to Folio.pdf"]
        XCTAssertTrue(document.waitForExistence(timeout: 10))
        document.tap()
        XCTAssertTrue(app.buttons["reader-page"].waitForExistence(timeout: 5))
        return app
    }

    func testTapHidesAndRestoresControlsWhileSwipingPages() {
        let app = openReader()
        let page = app.images["book-page"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let hidden = NSPredicate(format: "exists == false")
        expectation(for: hidden, evaluatedWith: app.buttons["Close"])
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["reader-page"].exists)
        page.swipeLeft()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Focused reading full screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.images["book-page"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["reader-page"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Close"].exists)
        XCTAssertTrue(app.buttons["reader-page"].label.contains("Page 2"))
    }

    func testAppearanceAndBookmarkNavigation() {
        let app = openReader()
        app.buttons["Document actions"].tap()
        app.buttons["Bookmark page"].tap()
        app.buttons["Document actions"].tap()
        app.buttons["Bookmarks"].tap()
        XCTAssertTrue(app.buttons["Page 1"].waitForExistence(timeout: 5))
        app.buttons["Page 1"].tap()
        app.buttons["Document actions"].tap()
        app.buttons["Appearance"].tap()
        let dark = app.buttons["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5))
        dark.tap()
        app.buttons["Done"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Dark controls with white paper"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.buttons["reader-page"].waitForExistence(timeout: 5))
    }
}
