import XCTest
import PDFKit
import UIKit
@testable import FolioPDF

@MainActor
final class ReadingStateTests: XCTestCase {
    private let suite = "FolioReadingTests-" + UUID().uuidString
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private lazy var store = ReadingStateStore(defaults: UserDefaults(suiteName: suite)!)

    private func makeEditor() throws -> EditorModel {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("reading.pdf")
        try PDFOperations.welcomePDF().write(to: url)
        return EditorModel(url: url, readingStore: store)
    }

    func testPositionAndBookmarksSurviveReopenWithoutModifyingPDF() throws {
        let editor = try makeEditor()
        let original = try Data(contentsOf: editor.url)
        editor.go(to: 1)
        editor.toggleBookmark()
        let reopened = EditorModel(url: editor.url, readingStore: store)
        XCTAssertEqual(reopened.pageIndex, 1)
        XCTAssertEqual(reopened.bookmarks, [1])
        XCTAssertFalse(reopened.hasChanges)
        XCTAssertEqual(try Data(contentsOf: editor.url), original)
    }

    func testRenameMigrationAndDeletionCleanup() throws {
        let old = folder.appendingPathComponent("old.pdf")
        let renamed = folder.appendingPathComponent("renamed.pdf")
        store.save(ReadingState(pageIndex: 5, bookmarks: [2, 5]), for: old)
        store.move(from: old, to: renamed)
        XCTAssertEqual(store.load(renamed).pageIndex, 5)
        XCTAssertEqual(store.load(old), ReadingState())
        store.remove(renamed)
        XCTAssertEqual(store.load(renamed), ReadingState())
    }

    func testOutdatedStateClampsAndFiltersBookmarks() throws {
        let editor = try makeEditor()
        store.save(ReadingState(pageIndex: 99, bookmarks: [-1, 0, 1, 99]), for: editor.url)
        let reopened = EditorModel(url: editor.url, readingStore: store)
        XCTAssertEqual(reopened.pageIndex, 1)
        XCTAssertEqual(reopened.bookmarks, [0, 1])
    }

    func testPageMovesDeletionAndUndoKeepBookmarksAttached() throws {
        let editor = try makeEditor()
        editor.toggleBookmark()
        editor.movePage(from: 0, to: 1)
        XCTAssertEqual(editor.bookmarks, [1])
        editor.undo()
        XCTAssertEqual(editor.bookmarks, [0])
        editor.deletePages([0])
        XCTAssertTrue(editor.bookmarks.isEmpty)
        editor.undo()
        XCTAssertEqual(editor.bookmarks, [0])
        XCTAssertEqual(editor.pageCount, 2)
    }

    func testDiscardedPageEditsDoNotPersistRemappedBookmarks() throws {
        let editor = try makeEditor()
        editor.toggleBookmark()
        editor.movePage(from: 0, to: 1)
        XCTAssertEqual(store.load(editor.url).bookmarks, [0])
        XCTAssertEqual(EditorModel(url: editor.url, readingStore: store).bookmarks, [0])
        XCTAssertTrue(editor.save())
        XCTAssertEqual(EditorModel(url: editor.url, readingStore: store).bookmarks, [1])
    }

    func testSingleTapWaitsForDoubleTapZoom() {
        let reader = BookReaderController(reduceMotion: false)
        let single = UITapGestureRecognizer()
        let double = UITapGestureRecognizer()
        double.numberOfTapsRequired = 2
        XCTAssertTrue(reader.gestureRecognizer(single, shouldRequireFailureOf: double))
        XCTAssertFalse(reader.gestureRecognizer(single, shouldRequireFailureOf: UIPanGestureRecognizer()))
    }

    func testDarkAppearanceKeepsPaperWhiteAndNightModeDoesNotAlterPDF() throws {
        let editor = try makeEditor()
        let original = try Data(contentsOf: editor.url)
        let page = try XCTUnwrap(editor.document.page(at: 0))
        let reader = BookPageController(page: page, index: 0, count: 2)
        reader.overrideUserInterfaceStyle = .dark
        reader.loadViewIfNeeded()
        reader.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        reader.view.layoutIfNeeded()
        let render = UIGraphicsImageRenderer(size: reader.view.bounds.size).image {
            reader.view.layer.render(in: $0.cgContext)
        }
        let cg = try XCTUnwrap(render.cgImage)
        let colors = try XCTUnwrap(cg.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(colors))
        // Both letterbox corners must contain white paper even with a dark app theme.
        let last = (cg.height - 1) * cg.bytesPerRow
        XCTAssertGreaterThan(bytes[0], 240)
        XCTAssertGreaterThan(bytes[last], 240)
        let night = BookPageController(page: page, index: 0, count: 2, nightPages: true)
        night.loadViewIfNeeded()
        night.view.frame = reader.view.frame
        night.view.layoutIfNeeded()
        XCTAssertEqual(try Data(contentsOf: editor.url), original)
    }
}
