import PDFKit
import UIKit
import Vision

enum PDFOperations {
    static func data(for document: PDFDocument) throws -> Data {
        guard !document.isLocked else { throw FolioError.lockedPDF }
        guard !document.isEncrypted else { throw FolioError.protectedPDF }
        guard document.pageCount > 0 else { throw FolioError.emptyPDF }
        guard let data = document.dataRepresentation() else { throw FolioError.cannotWrite }
        return data
    }

    static func extract(_ document: PDFDocument, indices: [Int]) throws -> Data {
        guard !document.isLocked else { throw FolioError.lockedPDF }
        guard !document.isEncrypted, document.allowsDocumentAssembly else { throw FolioError.protectedPDF }
        let selected = Array(Set(indices)).sorted()
        guard !selected.isEmpty, selected.allSatisfy({ (0..<document.pageCount).contains($0) }) else {
            throw FolioError.invalidSelection
        }
        let output = PDFDocument()
        for index in selected {
            guard let copy = document.page(at: index)?.copy() as? PDFPage else { throw FolioError.invalidPDF }
            output.insert(copy, at: output.pageCount)
        }
        return try data(for: output)
    }

    static func deletePages(_ document: PDFDocument, indices: Set<Int>) throws {
        guard !document.isLocked else { throw FolioError.lockedPDF }
        guard !document.isEncrypted, document.allowsDocumentAssembly else { throw FolioError.protectedPDF }
        guard !indices.isEmpty, indices.allSatisfy({ (0..<document.pageCount).contains($0) }) else {
            throw FolioError.invalidSelection
        }
        guard indices.count < document.pageCount else { throw FolioError.emptyPDF }
        for index in indices.sorted(by: >) { document.removePage(at: index) }
    }

    static func imagesToPDF(_ images: [UIImage]) throws -> Data {
        guard !images.isEmpty else { throw FolioError.emptyPDF }
        let rect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: rect)
        return renderer.pdfData { context in
            for image in images {
                context.beginPage()
                UIColor.white.setFill()
                context.cgContext.fill(rect)
                guard image.size.width > 0, image.size.height > 0 else { continue }
                let scale = min(rect.width / image.size.width, rect.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2,
                                      width: size.width, height: size.height))
            }
        }
    }

    static func welcomePDF() -> Data {
        let rect = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: rect).pdfData { context in
            let pages: [(String, String)] = [
                ("Your documents.\nYour workspace.",
                 "Welcome to Folio PDF.\n\nImport a PDF from Files, scan with the camera, or turn photos into a document. Everything stays on this device.\n\nOpen this sample and long-press a sentence to select text. Tap Highlight to mark it. Use Add text, Note, Pen, and Sign from the bottom toolbar.\n\nSave commits your edits to the app's private copy. Share sends a separate PDF copy to the destination you choose."),
                ("A little more order.",
                 "Open Pages to rotate, reorder, extract, or delete pages. In the library, use Select to merge documents in the order you tap them.\n\nUse Recognize text to read a scanned page on-device. Recognition returns plain text; it does not replace the PDF's existing text.\n\nHandwritten signatures are ink annotations, not certificate-backed digital signatures.\n\nPractice here before editing an important document. Keep a backup of your original PDF.")
            ]
            for (index, page) in pages.enumerated() {
                context.beginPage()
                UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
                context.cgContext.fill(rect)
                let accent = UIColor(red: 0.31, green: 0.27, blue: 0.81, alpha: 1)
                ("FOLIO / GETTING STARTED" as NSString).draw(at: CGPoint(x: 48, y: 54), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: accent])
                (page.0 as NSString).draw(in: CGRect(x: 48, y: 124, width: 495, height: 150), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 38, weight: .bold), .foregroundColor: UIColor.black])
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 7
                (page.1 as NSString).draw(in: CGRect(x: 48, y: 300, width: 490, height: 450), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.darkGray,
                    .paragraphStyle: paragraph])
                ("\(index + 1) / 2" as NSString).draw(at: CGPoint(x: 48, y: 790), withAttributes: [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: accent])
            }
        }
    }

    static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    continuation.resume(returning: text.isEmpty ? "No readable text was found on this page." : text)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
