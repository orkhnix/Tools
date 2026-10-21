import UIKit
import XCTest
import PDFKit
@testable import FolioPDF

@MainActor
final class PDFOperationsTests: XCTestCase {
    private func sample() throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: PDFOperations.welcomePDF()))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testExtractionSortsAndDeduplicatesPagesWithoutMutatingSource() throws {
        let source = try sample()
        let result = try XCTUnwrap(PDFDocument(data: PDFOperations.extract(source, indices: [1, 1, 0])))
        XCTAssertEqual(result.pageCount, 2)
        XCTAssertEqual(source.pageCount, 2)
        XCTAssertTrue(result.page(at: 0)?.string?.contains("Your documents.") == true)
        XCTAssertTrue(result.page(at: 1)?.string?.contains("A little more order.") == true)
    }

    func testInvalidExtractionFailsInsteadOfSilentlyDroppingPages() throws {
        let source = try sample()
        XCTAssertThrowsError(try PDFOperations.extract(source, indices: [99]))
        XCTAssertThrowsError(try PDFOperations.extract(source, indices: []))
        XCTAssertThrowsError(try PDFOperations.extract(source, indices: [-1]))
        XCTAssertEqual(source.pageCount, 2)
    }

    func testDeletingEveryPageIsRejectedBeforeMutation() throws {
        let source = try sample()
        XCTAssertThrowsError(try PDFOperations.deletePages(source, indices: [0, 1]))
        XCTAssertEqual(source.pageCount, 2)
        try PDFOperations.deletePages(source, indices: [0])
        XCTAssertEqual(source.pageCount, 1)
        XCTAssertTrue(source.page(at: 0)?.string?.contains("A little more order.") == true)
    }

    func testAnnotationsSurvivePDFRoundTrip() throws {
        let source = try sample()
        let page = try XCTUnwrap(source.page(at: 0))
        let annotation = PDFAnnotation(bounds: CGRect(x: 40, y: 100, width: 180, height: 28), forType: .freeText, withProperties: nil)
        annotation.contents = "Persisted annotation"
        annotation.font = .systemFont(ofSize: 14)
        page.addAnnotation(annotation)
        let restored = try XCTUnwrap(PDFDocument(data: PDFOperations.data(for: source)))
        XCTAssertTrue(restored.page(at: 0)?.annotations.contains { $0.contents == "Persisted annotation" } == true)
    }

    func testImagesBecomeOnePageEach() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let output = try XCTUnwrap(PDFDocument(data: PDFOperations.imagesToPDF([image, image])))
        XCTAssertEqual(output.pageCount, 2)
        XCTAssertEqual(output.page(at: 0)?.bounds(for: .mediaBox).width, 595)
        XCTAssertThrowsError(try PDFOperations.imagesToPDF([]))
    }

    func testImportCopiesAndDoesNotOverwriteOriginal() async throws {
        let root = try temporaryDirectory()
        let store = DocumentStore(directory: root.appendingPathComponent("Library"))
        let original = root.appendingPathComponent("Original.pdf")
        let data = PDFOperations.welcomePDF()
        try data.write(to: original)
        await store.importURLs([original, original])
        XCTAssertNil(store.error)
        XCTAssertEqual(store.documents.count, 2)
        XCTAssertEqual(Set(store.documents.map(\.name)), ["Original", "Original 2"])
        XCTAssertEqual(try Data(contentsOf: original), data)
        XCTAssertTrue(store.documents.allSatisfy { $0.url != original })
        XCTAssertFalse(store.isImporting)
    }

    func testImportFailureShowsErrorAndClearsProgress() async throws {
        let root = try temporaryDirectory()
        let store = DocumentStore(directory: root.appendingPathComponent("Library"))
        let original = root.appendingPathComponent("Broken.pdf")
        let bytes = Data("not a PDF".utf8)
        try bytes.write(to: original)
        let imported = await store.importURLs([original])
        XCTAssertTrue(imported.isEmpty)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertFalse(store.isImporting)
        XCTAssertTrue(store.error?.contains("Broken.pdf") == true)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
    }

    func testProviderReadDoesNotBlockMainThread() async throws {
        let bytes = PDFOperations.welcomePDF()
        let readerStarted = expectation(description: "Background reader started")
        let mainThreadResponded = expectation(description: "Main thread stayed responsive")
        let releaseReader = DispatchSemaphore(value: 0)
        let task = Task {
            try await PDFImportService.prepare(URL(fileURLWithPath: "/test.pdf"), timeout: 3) { _ in
                XCTAssertFalse(Thread.isMainThread)
                readerStarted.fulfill()
                _ = releaseReader.wait(timeout: .now() + 2)
                return bytes
            }
        }
        await fulfillment(of: [readerStarted], timeout: 2)
        DispatchQueue.main.async {
            mainThreadResponded.fulfill()
            releaseReader.signal()
        }
        await fulfillment(of: [mainThreadResponded], timeout: 2)
        let prepared = try await task.value
        defer { try? FileManager.default.removeItem(at: prepared.stagedURL) }
        XCTAssertEqual(try Data(contentsOf: prepared.stagedURL), bytes)
    }

    func testProviderTimeoutReturnsInsteadOfWaitingForever() async throws {
        let bytes = PDFOperations.welcomePDF()
        let releaseReader = DispatchSemaphore(value: 0)
        defer { releaseReader.signal() }
        do {
            _ = try await PDFImportService.prepare(URL(fileURLWithPath: "/slow.pdf"), timeout: 0.05) { _ in
                _ = releaseReader.wait(timeout: .now() + 2)
                return bytes
            }
            XCTFail("A stalled provider must time out")
        } catch { XCTAssertTrue(error is PDFImportError) }
    }

    func testImportContinuesAfterOneInvalidFile() async throws {
        let root = try temporaryDirectory()
        let store = DocumentStore(directory: root.appendingPathComponent("Library"))
        let bad = root.appendingPathComponent("Bad.pdf")
        let good = root.appendingPathComponent("Good.pdf")
        try Data("not a PDF".utf8).write(to: bad)
        try PDFOperations.welcomePDF().write(to: good)
        let imported = await store.importURLs([bad, good])
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(store.documents.first?.name, "Good")
        XCTAssertFalse(store.isImporting)
        XCTAssertNotNil(store.error)
    }

    func testUnsafeNamesStayInsideDocumentDirectory() throws {
        let directory = try temporaryDirectory()
        let store = DocumentStore(directory: directory)
        let url = try store.add(data: PDFOperations.welcomePDF(), named: "../../report\\name.pdf")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertFalse(url.lastPathComponent.contains("/"))
        XCTAssertEqual(DocumentStore.safeName("\n\t"), "Untitled")
    }

    func testMergeUsesChosenOrder() throws {
        let store = DocumentStore(directory: try temporaryDirectory())
        let source = try sample()
        let one = try store.add(data: PDFOperations.extract(source, indices: [0]), named: "One")
        let two = try store.add(data: PDFOperations.extract(source, indices: [1]), named: "Two")
        let first = try XCTUnwrap(store.documents.first { $0.url == one })
        let second = try XCTUnwrap(store.documents.first { $0.url == two })
        store.merge([second, first])
        XCTAssertNil(store.error)
        let mergedURL = try XCTUnwrap(store.documents.first { $0.name == "Merged document" }?.url)
        let merged = try XCTUnwrap(PDFDocument(url: mergedURL))
        XCTAssertEqual(merged.pageCount, 2)
        XCTAssertTrue(merged.page(at: 0)?.string?.contains("A little more order.") == true)
    }

    func testUndoAndSavePersistPageChanges() throws {
        let url = try temporaryDirectory().appendingPathComponent("Working.pdf")
        try PDFOperations.welcomePDF().write(to: url)
        let editor = EditorModel(url: url)
        editor.rotatePage(at: 0)
        XCTAssertEqual(editor.document.page(at: 0)?.rotation, 90)
        editor.undo()
        XCTAssertEqual(editor.document.page(at: 0)?.rotation, 0)
        editor.deletePages([1])
        XCTAssertEqual(editor.pageCount, 1)
        XCTAssertTrue(editor.save())
        XCTAssertEqual(PDFDocument(url: url)?.pageCount, 1)
    }

    func testPasswordExportDoesNotEncryptWorkingDocument() throws {
        let url = try temporaryDirectory().appendingPathComponent("Working.pdf")
        let original = PDFOperations.welcomePDF()
        try original.write(to: url)
        let editor = EditorModel(url: url)
        let exportedURL = try editor.shareCopy(password: "test-password")
        defer { try? FileManager.default.removeItem(at: exportedURL.deletingLastPathComponent()) }
        let copy = try XCTUnwrap(PDFDocument(url: exportedURL))
        XCTAssertTrue(copy.isLocked)
        XCTAssertFalse(copy.unlock(withPassword: "incorrect"))
        XCTAssertTrue(copy.unlock(withPassword: "test-password"))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertFalse(editor.document.isEncrypted)
    }

    func testUnlockedEncryptedPDFRemainsReadOnlyAndSharesOriginalBytes() throws {
        let url = try temporaryDirectory().appendingPathComponent("Private.pdf")
        XCTAssertTrue(try sample().write(to: url, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]))
        let original = try Data(contentsOf: url)
        let editor = EditorModel(url: url)
        XCTAssertTrue(editor.unlock("secret"))
        XCTAssertFalse(editor.isEditable)
        editor.rotatePage(at: 0)
        XCTAssertEqual(editor.document.page(at: 0)?.rotation, 0)
        let shared = try editor.shareCopy()
        defer { try? FileManager.default.removeItem(at: shared.deletingLastPathComponent()) }
        XCTAssertEqual(try Data(contentsOf: shared), original)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testInvalidInputIsNotOverwrittenBySave() throws {
        let url = try temporaryDirectory().appendingPathComponent("Invalid.pdf")
        let bytes = Data("not a PDF".utf8)
        try bytes.write(to: url)
        let editor = EditorModel(url: url)
        XCTAssertFalse(editor.loadedSuccessfully)
        XCTAssertFalse(editor.save())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
}
