import XCTest
import PDFKit
import UIKit
@testable import FolioPDF

@MainActor
final class BookReaderTests: XCTestCase {
    private func sample() throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: PDFOperations.welcomePDF()))
    }

    func testHorizontalCurlAndDocumentBoundaries() throws {
        let document = try sample()
        let reader = BookReaderController(reduceMotion: false)
        reader.update(document: document, index: 0, revision: 0)
        XCTAssertEqual(reader.transitionStyle, .pageCurl)
        XCTAssertEqual(reader.navigationOrientation, .horizontal)
        let first = try XCTUnwrap(reader.viewControllers?.first)
        XCTAssertNil(reader.pageViewController(reader, viewControllerBefore: first))
        let last = try XCTUnwrap(reader.pageViewController(reader, viewControllerAfter: first))
        XCTAssertEqual((last as? BookPageController)?.index, 1)
        XCTAssertNil(reader.pageViewController(reader, viewControllerAfter: last))
    }

    func testJumpClampsToDocumentAndRefreshesEditedPage() throws {
        let document = try sample()
        let reader = BookReaderController(reduceMotion: true)
        reader.update(document: document, index: 999, revision: 0)
        XCTAssertEqual(reader.currentIndex, document.pageCount - 1)
        let before = try XCTUnwrap(reader.viewControllers?.first)
        document.page(at: reader.currentIndex)?.rotation = 90
        reader.update(document: document, index: reader.currentIndex, revision: 1)
        XCTAssertFalse(before === reader.viewControllers?.first)
        XCTAssertEqual((reader.viewControllers?.first as? BookPageController)?.page.rotation, 90)
        reader.update(document: document, index: -1, revision: 1)
        XCTAssertEqual(reader.currentIndex, 0)
        XCTAssertEqual(reader.transitionStyle, .scroll)
    }

    func testCancelledTurnKeepsPageAndCompletedTurnReportsVisiblePage() throws {
        let document = try sample()
        let reader = BookReaderController(reduceMotion: false)
        var reported: [Int] = []
        reader.onPageChanged = { reported.append($0) }
        reader.update(document: document, index: 0, revision: 0)
        let first = try XCTUnwrap(reader.viewControllers?.first)
        let next = try XCTUnwrap(reader.pageViewController(reader, viewControllerAfter: first))
        reader.pageViewController(reader, willTransitionTo: [next])
        reader.pageViewController(reader, didFinishAnimating: true, previousViewControllers: [first], transitionCompleted: false)
        XCTAssertEqual(reader.currentIndex, 0)
        XCTAssertTrue(reported.isEmpty)
        reader.pageViewController(reader, willTransitionTo: [next])
        // SwiftUI can refresh the old page while the user's curl is in progress.
        reader.update(document: document, index: 0, revision: 0)
        reader.setViewControllers([next], direction: .forward, animated: false)
        reader.pageViewController(reader, didFinishAnimating: true, previousViewControllers: [first], transitionCompleted: true)
        XCTAssertEqual(reader.currentIndex, 1)
        XCTAssertEqual(reported, [1])
    }

    func testEmptyDocumentDoesNotCreatePage() {
        let reader = BookReaderController(reduceMotion: false)
        reader.update(document: PDFDocument(), index: 0, revision: 0)
        XCTAssertTrue(reader.viewControllers?.isEmpty ?? true)
    }
}
