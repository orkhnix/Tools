import Foundation
import PDFKit

enum PDFImportError: LocalizedError {
    case timedOut
    var errorDescription: String? {
        "The file provider did not finish opening this PDF. Download it in Files first, then try again."
    }
}

struct PreparedPDFImport: Sendable {
    let stagedURL: URL
    let suggestedName: String
}

/// File-provider coordination, PDF parsing, and staging must never block the UI thread.
enum PDFImportService {
    typealias Reader = @Sendable (URL) throws -> Data
    static let maximumBytes = 150 * 1_024 * 1_024

    static func prepare(_ url: URL, timeout: TimeInterval = 30,
                        reader: Reader? = nil) async throws -> PreparedPDFImport {
        try await withCheckedThrowingContinuation { continuation in
            let request = ImportRequest(continuation)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                request.finish(.failure(PDFImportError.timedOut))
            }
            DispatchQueue.global(qos: .userInitiated).async {
                var stagingURL: URL?
                do {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try (reader ?? readCoordinatedFile)(url)
                    guard !request.isFinished else { return }
                    guard data.count <= maximumBytes else { throw FolioError.tooLarge }
                    guard let pdf = PDFDocument(data: data) else { throw FolioError.invalidPDF }
                    guard pdf.isLocked || pdf.pageCount > 0 else { throw FolioError.emptyPDF }
                    guard !request.isFinished else { return }
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FolioImports", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let staged = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
                    stagingURL = staged
                    try data.write(to: staged, options: [.atomic, .completeFileProtectionUnlessOpen])
                    let result = PreparedPDFImport(stagedURL: staged, suggestedName: url.deletingPathExtension().lastPathComponent)
                    // A timed-out request must not produce a late import or leave its staged copy behind.
                    if !request.finish(.success(result)) { try? FileManager.default.removeItem(at: staged) }
                } catch {
                    if let stagingURL { try? FileManager.default.removeItem(at: stagingURL) }
                    request.finish(.failure(error))
                }
            }
        }
    }

    private static func readCoordinatedFile(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            result = Result {
                let size = try readable.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= maximumBytes else { throw FolioError.tooLarge }
                let data = try Data(contentsOf: readable)
                guard data.count <= maximumBytes else { throw FolioError.tooLarge }
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw FolioError.invalidPDF }
        return try result.get()
    }

    private final class ImportRequest: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<PreparedPDFImport, Error>?
        init(_ continuation: CheckedContinuation<PreparedPDFImport, Error>) { self.continuation = continuation }
        var isFinished: Bool {
            lock.lock(); defer { lock.unlock() }
            return continuation == nil
        }
        @discardableResult
        func finish(_ result: Result<PreparedPDFImport, Error>) -> Bool {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            guard let pending else { return false }
            pending.resume(with: result)
            return true
        }
    }
}
