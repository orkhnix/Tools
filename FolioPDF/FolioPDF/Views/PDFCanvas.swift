import UIKit
import SwiftUI
import PDFKit

struct PDFCanvas: UIViewRepresentable {
    @ObservedObject var model: EditorModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> PDFContainer {
        let container = PDFContainer()
        let pdf = container.pdf
        pdf.autoScales = true
        pdf.displayMode = .singlePageContinuous
        pdf.displayDirection = .vertical
        pdf.backgroundColor = .secondarySystemBackground
        pdf.document = model.document
        if let page = model.document.page(at: model.pageIndex) { pdf.go(to: page) }
        model.pdfView = pdf
        container.capture.onTap = { [weak model] in model?.handleTap($0) }
        container.capture.onStroke = { [weak model] in model?.addStroke($0) }
        context.coordinator.observe(pdf)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        pdf.addGestureRecognizer(tap)
        return container
    }

    func updateUIView(_ container: PDFContainer, context: Context) {
        model.pdfView = container.pdf
        if container.pdf.document !== model.document || context.coordinator.revision != model.revision {
            context.coordinator.revision = model.revision
            container.pdf.document = nil
            container.pdf.document = model.document
            if let page = model.document.page(at: model.pageIndex) { container.pdf.go(to: page) }
        }
        container.capture.isHidden = model.tool == .browse || !model.isEditable
        container.capture.isDrawing = model.tool == .pen
        container.capture.inkColor = model.color
    }

    @MainActor
    final class Coordinator: NSObject {
        let model: EditorModel
        var revision = 0
        init(model: EditorModel) { self.model = model }
        func observe(_ pdf: PDFView) {
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged(_:)), name: .PDFViewPageChanged, object: pdf)
        }
        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let pdf = recognizer.view as? PDFView else { return }
            model.inspectNote(at: recognizer.location(in: pdf))
        }
        @objc private func pageChanged(_ notification: Notification) {
            guard let pdf = notification.object as? PDFView, let page = pdf.currentPage else { return }
            let index = model.document.index(for: page)
            guard index != NSNotFound else { return }
            // PDFKit may publish during a SwiftUI view update.
            DispatchQueue.main.async { [weak self] in
                guard let self, index < self.model.pageCount else { return }
                self.model.pageIndex = index
            }
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

final class PDFContainer: UIView {
    let pdf = PDFView()
    let capture = InkCaptureView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        for child in [pdf, capture] {
            addSubview(child)
            child.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: leadingAnchor), child.trailingAnchor.constraint(equalTo: trailingAnchor),
                child.topAnchor.constraint(equalTo: topAnchor), child.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        capture.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class InkCaptureView: UIView {
    var isDrawing = false
    var inkColor: UIColor = .systemBlue
    var onTap: ((CGPoint) -> Void)?
    var onStroke: (([CGPoint]) -> Void)?
    private var points: [CGPoint] = []
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        points = [point]
        setNeedsDisplay()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawing, let touch = touches.first else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] { points.append(sample.location(in: self)) }
        setNeedsDisplay()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isDrawing { onStroke?(points) }
        else if let point = touches.first?.location(in: self) { onTap?(point) }
        points = []
        setNeedsDisplay()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { points = []; setNeedsDisplay() }
    override func draw(_ rect: CGRect) {
        guard isDrawing, let first = points.first else { return }
        let path = UIBezierPath(); path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.lineWidth = 2; path.lineCapStyle = .round; path.lineJoinStyle = .round
        inkColor.setStroke(); path.stroke()
    }
}
