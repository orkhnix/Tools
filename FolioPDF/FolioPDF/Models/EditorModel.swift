import UIKit
import SwiftUI
import PDFKit

enum EditorTool: String, CaseIterable {
    case browse = "Read", text = "Text", note = "Note", pen = "Pen", sign = "Sign", erase = "Erase"
    var icon: String {
        switch self {
        case .browse: return "hand.draw"
        case .text: return "textformat"
        case .note: return "note.text"
        case .pen: return "pencil.tip"
        case .sign: return "signature"
        case .erase: return "eraser"
        }
    }
    var hint: String {
        switch self {
        case .browse: return "Scroll and zoom. Long-press text to select it."
        case .text: return "Tap the page to place text."
        case .note: return "Tap the page to place a note."
        case .pen: return "Draw on the page. Switch to Read to scroll."
        case .sign: return "Tap the page to place your signature."
        case .erase: return "Tap an annotation to remove it."
        }
    }
}

struct SignatureDrawing {
    let strokes: [[CGPoint]] // Normalized, top-left origin.
}

@MainActor
final class EditorModel: ObservableObject {
    let url: URL
    @Published var document: PDFDocument
    @Published var tool: EditorTool = .browse
    @Published var pageIndex = 0 { didSet { persistReadingState() } }
    @Published private(set) var bookmarks: Set<Int> = [] { didSet { persistReadingState() } }
    private let readingStore: ReadingStateStore
    private var readingHistory: [ReadingState] = []
    private var changing = false
    @Published var revision = 0
    @Published var hasChanges = false
    @Published var error: String?
    @Published var searchQuery = ""
    @Published var searchResults: [PDFSelection] = []
    @Published var resultIndex = 0
    @Published var color: UIColor = .systemBlue
    @Published var textToPlace = ""
    @Published var signature: SignatureDrawing?
    @Published var recognizedText = ""
    @Published var inspectedNote: String?
    @Published var recognizing = false
    @Published private(set) var history: [Data] = []
    weak var pdfView: PDFView?
    private(set) var loadedSuccessfully = true
    var isEditable: Bool {
        loadedSuccessfully && !document.isLocked && !document.isEncrypted && document.allowsCommenting
            && document.allowsDocumentChanges && document.allowsDocumentAssembly
    }
    var canUndo: Bool { !history.isEmpty }
    var pageCount: Int { document.pageCount }

    init(url: URL, readingStore: ReadingStateStore = ReadingStateStore()) {
        self.url = url
        self.readingStore = readingStore
        if let pdf = PDFDocument(url: url) { document = pdf }
        else {
            document = PDFDocument()
            loadedSuccessfully = false
            error = FolioError.invalidPDF.localizedDescription
        }
        enforceReadOnlyWidgets()
        if !document.isLocked { restoreReadingState() }
    }

    func unlock(_ password: String) -> Bool {
        guard document.unlock(withPassword: password) else { error = "The password is incorrect."; return false }
        enforceReadOnlyWidgets()
        restoreReadingState()
        revision += 1
        return true
    }

    private func enforceReadOnlyWidgets() {
        guard !isEditable, !document.isLocked else { return }
        for index in 0..<document.pageCount {
            for annotation in document.page(at: index)?.annotations ?? [] where annotation.type == "Widget" {
                annotation.isReadOnly = true
            }
        }
    }

    private var readingState: ReadingState { ReadingState(pageIndex: pageIndex, bookmarks: bookmarks) }

    private func restoreReadingState() {
        let state = readingStore.load(url).clamped(pageCount: pageCount)
        changing = true
        pageIndex = state.pageIndex
        bookmarks = state.bookmarks
        changing = false
    }

    private func persistReadingState() {
        guard loadedSuccessfully, !document.isLocked, !changing, !hasChanges else { return }
        readingStore.save(readingState.clamped(pageCount: pageCount), for: url)
    }

    func removeBookmark(at index: Int) { bookmarks.remove(index) }

    func toggleBookmark() {
        guard pageCount > 0, !document.isLocked else { return }
        if bookmarks.contains(pageIndex) { bookmarks.remove(pageIndex) }
        else { bookmarks.insert(pageIndex) }
    }

    private func checkpoint() {
        // A bounded history avoids retaining unlimited full-document snapshots.
        guard let data = document.dataRepresentation(), data.count <= 30 * 1_024 * 1_024 else {
            history.removeAll()
            readingHistory.removeAll()
            return
        }
        history.append(data)
        readingHistory.append(readingState)
        while history.count > 8 || history.reduce(0, { $0 + $1.count }) > 60 * 1_024 * 1_024 {
            history.removeFirst()
            readingHistory.removeFirst()
        }
    }

    func change(_ action: () throws -> Void) {
        guard isEditable else { return }
        checkpoint()
        changing = true
        defer { changing = false }
        do {
            try action()
            hasChanges = true
            searchResults = []
            pdfView?.highlightedSelections = nil
            revision += 1
        } catch {
            if !history.isEmpty { history.removeLast(); readingHistory.removeLast() }
            self.error = error.localizedDescription
        }
    }

    func undo() {
        guard let data = history.last, let restored = PDFDocument(data: data) else { return }
        history.removeLast()
        let state = readingHistory.removeLast().clamped(pageCount: restored.pageCount)
        changing = true
        document = restored
        pageIndex = state.pageIndex
        bookmarks = state.bookmarks
        changing = false
        hasChanges = true
        searchResults = []
        revision += 1
    }

    @discardableResult
    func save() -> Bool {
        guard loadedSuccessfully else { return false }
        // Never rewrite an encrypted or permission-restricted original.
        guard isEditable else { persistReadingState(); return true }
        do {
            try PDFOperations.data(for: document).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            hasChanges = false
            persistReadingState()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func shareCopy(password: String? = nil) throws -> URL {
        if password == nil, !save() { throw FolioError.cannotWrite }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent(url.lastPathComponent)
        if let password {
            guard isEditable, !password.isEmpty else { throw FolioError.lockedPDF }
            let options: [PDFDocumentWriteOption: Any] = [.userPasswordOption: password, .ownerPasswordOption: UUID().uuidString]
            guard document.write(to: output, withOptions: options) else { throw FolioError.cannotWrite }
        } else {
            try FileManager.default.copyItem(at: url, to: output)
        }
        return output
    }

    func go(to index: Int) {
        guard let page = document.page(at: index) else { return }
        pageIndex = index
        pdfView?.go(to: page)
    }

    func search() {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []; pdfView?.highlightedSelections = nil; return
        }
        searchResults = document.findString(searchQuery, withOptions: [.caseInsensitive])
        for selection in searchResults { selection.color = UIColor.systemYellow.withAlphaComponent(0.45) }
        pdfView?.highlightedSelections = searchResults
        resultIndex = 0
        showSearchResult()
    }

    func nextResult(_ offset: Int) {
        guard !searchResults.isEmpty else { return }
        resultIndex = (resultIndex + offset + searchResults.count) % searchResults.count
        showSearchResult()
    }

    private func showSearchResult() {
        guard searchResults.indices.contains(resultIndex) else { return }
        let selection = searchResults[resultIndex]
        pdfView?.setCurrentSelection(selection, animate: true)
        pdfView?.go(to: selection)
    }

    func inspectNote(at point: CGPoint) {
        guard tool == .browse, let view = pdfView,
              let page = view.page(for: point, nearest: false) else { return }
        let location = view.convert(point, to: page)
        if let note = page.annotations.reversed().first(where: {
            $0.type == "Text" && $0.bounds.insetBy(dx: -4, dy: -4).contains(location)
        }), let text = note.contents, !text.isEmpty {
            inspectedNote = text
        }
    }

    func highlightSelection() {
        guard let selection = pdfView?.currentSelection, !(selection.string ?? "").isEmpty else {
            error = "In Read mode, long-press and select some text first."; return
        }
        change {
            for line in selection.selectionsByLine() {
                for page in line.pages {
                    let bounds = line.bounds(for: page)
                    guard !bounds.isEmpty else { continue }
                    let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                    annotation.color = .systemYellow
                    annotation.userName = "Folio"
                    page.addAnnotation(annotation)
                }
            }
        }
    }

    func handleTap(_ point: CGPoint) {
        guard isEditable, let view = pdfView, let page = view.page(for: point, nearest: false) else { return }
        let location = view.convert(point, to: page)
        switch tool {
        case .text, .note:
            let content = textToPlace.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return }
            let type: PDFAnnotationSubtype = tool == .note ? .text : .freeText
            change {
                // Convert a screen-space rectangle so placement also works on rotated pages.
                let display = CGRect(x: point.x, y: point.y, width: tool == .note ? 24 : 180,
                                     height: tool == .note ? 24 : 72)
                let bounds = view.convert(display, to: page).intersection(page.bounds(for: .cropBox))
                guard !bounds.isNull, !bounds.isEmpty else { return }
                let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
                annotation.contents = content
                annotation.userName = "Folio"
                if type == .freeText {
                    annotation.font = .systemFont(ofSize: 14)
                    annotation.fontColor = color
                    annotation.color = .clear
                    let border = PDFBorder(); border.lineWidth = 0; annotation.border = border
                } else { annotation.color = .systemYellow }
                page.addAnnotation(annotation)
            }
            tool = .browse
        case .erase:
            // Widgets and links are never erased by the annotation eraser.
            let removable = page.annotations.reversed().first {
                $0.bounds.insetBy(dx: -3, dy: -3).contains(location) && $0.type != "Widget" && $0.type != "Link"
            }
            if let annotation = removable { change { page.removeAnnotation(annotation) } }
        case .sign:
            guard let signature else { return }
            let width = min(180.0, max(80.0, view.bounds.width - point.x - 12))
            let height = width * 0.4
            let strokes = signature.strokes.map { stroke in
                stroke.map { view.convert(CGPoint(x: point.x + $0.x * width, y: point.y + $0.y * height), to: page) }
            }
            addInk(strokes, on: page, width: 1.5, inkColor: .black)
            tool = .browse
        default: break
        }
    }

    func addStroke(_ screenPoints: [CGPoint]) {
        guard let view = pdfView, let first = screenPoints.first,
              let page = view.page(for: first, nearest: false) else { return }
        let bounds = page.bounds(for: .cropBox)
        var strokes: [[CGPoint]] = []
        var current: [CGPoint] = []
        for point in screenPoints {
            let converted = view.convert(point, to: page)
            if view.page(for: point, nearest: false) === page, bounds.contains(converted) {
                current.append(converted)
            } else if !current.isEmpty { strokes.append(current); current = [] }
        }
        if !current.isEmpty { strokes.append(current) }
        addInk(strokes, on: page, width: 2, inkColor: color)
    }

    private func addInk(_ strokes: [[CGPoint]], on page: PDFPage, width: CGFloat, inkColor: UIColor) {
        let points = strokes.flatMap { $0 }
        guard let first = points.first else { return }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        var bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        bounds = bounds.insetBy(dx: -width * 2, dy: -width * 2)
        change {
            let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            annotation.color = inkColor
            annotation.userName = "Folio"
            let border = PDFBorder(); border.lineWidth = width; annotation.border = border
            for stroke in strokes where !stroke.isEmpty {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: stroke[0].x - bounds.minX, y: stroke[0].y - bounds.minY))
                if stroke.count == 1 { path.addLine(to: CGPoint(x: stroke[0].x - bounds.minX + 0.1, y: stroke[0].y - bounds.minY + 0.1)) }
                for point in stroke.dropFirst() { path.addLine(to: CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)) }
                annotation.add(path)
            }
            page.addAnnotation(annotation)
        }
    }

    func rotatePage(at index: Int) {
        guard let page = document.page(at: index) else { return }
        change { page.rotation = (page.rotation + 90) % 360 }
    }

    func movePage(from: Int, to: Int) {
        guard (0..<pageCount).contains(from), (0..<pageCount).contains(to), from != to else { return }
        change {
            document.exchangePage(at: from, withPageAt: to)
            bookmarks = Set(bookmarks.map { $0 == from ? to : ($0 == to ? from : $0) })
        }
        pageIndex = to
    }

    func deletePages(_ indices: Set<Int>) {
        change {
            try PDFOperations.deletePages(document, indices: indices)
            bookmarks = Set(bookmarks.filter { !indices.contains($0) }.map { index in
                index - indices.filter { $0 < index }.count
            })
        }
        pageIndex = min(pageIndex, max(0, pageCount - 1))
    }

    func recognizePage() async {
        guard !recognizing, let page = document.page(at: pageIndex) else { return }
        recognizing = true
        defer { recognizing = false }
        let image = page.thumbnail(of: CGSize(width: 1600, height: 2200), for: .cropBox)
        guard let cgImage = image.cgImage else { error = "This page could not be rendered."; return }
        do { recognizedText = try await PDFOperations.recognizeText(in: cgImage) }
        catch { self.error = error.localizedDescription }
    }
}
