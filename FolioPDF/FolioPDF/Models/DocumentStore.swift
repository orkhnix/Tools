import UIKit
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct LibraryDocument: Identifiable, Hashable {
    let url: URL
    let modified: Date
    let bytes: Int64
    var id: String { url.lastPathComponent }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

enum FolioError: LocalizedError {
    case invalidPDF, lockedPDF, protectedPDF, emptyPDF, cannotWrite, invalidSelection, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "This file could not be opened as a PDF."
        case .lockedPDF: return "Unlock this PDF before using this operation."
        case .protectedPDF: return "This operation supports unencrypted PDFs with editing permissions. Protected PDFs are read-only in Folio."
        case .emptyPDF: return "A document must contain at least one page."
        case .cannotWrite: return "The PDF could not be saved. Your changes remain open; try saving again."
        case .invalidSelection: return "Select at least one valid page."
        case .tooLarge: return "This file exceeds the 150 MB import limit. Try a smaller document."
        }
    }
}

@MainActor
final class DocumentStore: ObservableObject {
    @Published private(set) var documents: [LibraryDocument] = []
    @Published var error: String?
    @Published private(set) var isImporting = false
    @Published private(set) var importingName = ""
    private var activeImports = 0
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Folio", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            reload()
        } catch { self.error = error.localizedDescription }
    }

    func reload() {
        do {
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
            documents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
                .filter { $0.pathExtension.lowercased() == "pdf" }
                .compactMap { url in
                    guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
                    return LibraryDocument(url: url, modified: v.contentModificationDate ?? .distantPast,
                                           bytes: Int64(v.fileSize ?? 0))
                }.sorted { $0.modified > $1.modified }
        } catch { self.error = error.localizedDescription }
    }

    static func safeName(_ raw: String) -> String {
        let stem = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".pdf", with: "", options: [.caseInsensitive, .anchored, .backwards])
        let forbidden = CharacterSet(charactersIn: "/\\:\n\r\t").union(.controlCharacters)
        let clean = stem.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = String(clean.prefix(100))
        return truncated.isEmpty || truncated == "." || truncated == ".." ? "Untitled" : truncated
    }

    func availableURL(named name: String) -> URL {
        let stem = Self.safeName(name)
        var candidate = directory.appendingPathComponent(stem).appendingPathExtension("pdf")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem) \(n)").appendingPathExtension("pdf")
            n += 1
        }
        return candidate
    }

    @discardableResult
    func add(data: Data, named name: String) throws -> URL {
        guard let pdf = PDFDocument(data: data) else { throw FolioError.invalidPDF }
        guard pdf.isLocked || pdf.pageCount > 0 else { throw FolioError.emptyPDF }
        let url = availableURL(named: name)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        reload()
        return url
    }

    @discardableResult
    func importURLs(_ urls: [URL]) async -> [URL] {
        guard !urls.isEmpty else { return [] }
        activeImports += 1
        isImporting = true
        error = nil
        defer {
            activeImports -= 1
            isImporting = activeImports > 0
            if !isImporting { importingName = "" }
            reload()
        }
        var failures: [String] = []
        var imported: [URL] = []
        for url in urls {
            importingName = url.lastPathComponent
            do {
                let prepared = try await PDFImportService.prepare(url)
                defer { try? FileManager.default.removeItem(at: prepared.stagedURL) }
                let destination = availableURL(named: prepared.suggestedName)
                try FileManager.default.moveItem(at: prepared.stagedURL, to: destination)
                imported.append(destination)
            } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
        return imported
    }

    func delete(_ item: LibraryDocument) {
        do { try FileManager.default.removeItem(at: item.url); reload() }
        catch { self.error = error.localizedDescription }
    }

    func rename(_ item: LibraryDocument, to name: String) {
        guard Self.safeName(name) != item.name else { return }
        do { try FileManager.default.moveItem(at: item.url, to: availableURL(named: name)); reload() }
        catch { self.error = error.localizedDescription }
    }

    func duplicate(_ item: LibraryDocument) {
        do { try add(data: Data(contentsOf: item.url), named: "\(item.name) copy") }
        catch { self.error = error.localizedDescription }
    }

    func merge(_ items: [LibraryDocument]) {
        do {
            let result = PDFDocument()
            for item in items {
                guard let source = PDFDocument(url: item.url) else { throw FolioError.invalidPDF }
                guard !source.isLocked else { throw FolioError.lockedPDF }
                guard !source.isEncrypted, source.allowsDocumentAssembly else { throw FolioError.protectedPDF }
                for index in 0..<source.pageCount {
                    guard let page = source.page(at: index)?.copy() as? PDFPage else { throw FolioError.invalidPDF }
                    result.insert(page, at: result.pageCount)
                }
            }
            try add(data: PDFOperations.data(for: result), named: "Merged document")
        } catch { self.error = error.localizedDescription }
    }

    func addImages(_ images: [UIImage], name: String = "Scanned document") {
        do { try add(data: PDFOperations.imagesToPDF(images), named: name) }
        catch { self.error = error.localizedDescription }
    }

    func makeWelcomeDocument() {
        do { try add(data: PDFOperations.welcomePDF(), named: "Welcome to Folio") }
        catch { self.error = error.localizedDescription }
    }
}
