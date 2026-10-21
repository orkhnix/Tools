import SwiftUI
import UIKit
import PDFKit
import CoreImage

struct BookReader: UIViewControllerRepresentable {
    @ObservedObject var model: EditorModel
    var onToggleControls: (() -> Void)?
    @AppStorage("nightPages") private var nightPages = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIViewController(context: Context) -> BookReaderController {
        let controller = BookReaderController(reduceMotion: reduceMotion)
        controller.onToggleControls = onToggleControls
        controller.onPageChanged = { [weak model] index in model?.pageIndex = index }
        controller.update(document: model.document, index: model.pageIndex, revision: model.revision, nightPages: nightPages)
        return controller
    }

    func updateUIViewController(_ controller: BookReaderController, context: Context) {
        // Reading pages never mutate the editor's PDFView or the underlying document.
        model.pdfView = nil
        controller.onToggleControls = onToggleControls
        controller.update(document: model.document, index: model.pageIndex, revision: model.revision, nightPages: nightPages)
    }
}

@MainActor
final class BookReaderController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
    private(set) var document: PDFDocument?
    private(set) var currentIndex = 0
    private var revision = -1
    private var turning = false
    private var pending: (PDFDocument, Int, Int, Bool)?
    private var nightPages = false
    var onToggleControls: (() -> Void)?
    private let reduceMotion: Bool
    var onPageChanged: ((Int) -> Void)?

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        super.init(transitionStyle: reduceMotion ? .scroll : .pageCurl,
                   navigationOrientation: .horizontal,
                   options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
        dataSource = self
        delegate = self
        isDoubleSided = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Page turns use swipes. A single page tap belongs exclusively to focus mode.
        for recognizer in gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    @objc private func toggleControls() { onToggleControls?() }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (otherGestureRecognizer as? UITapGestureRecognizer)?.numberOfTapsRequired == 2
    }

    func update(document: PDFDocument, index: Int, revision: Int, nightPages: Bool = false) {
        guard document.pageCount > 0 else { return }
        let target = min(max(0, index), document.pageCount - 1)
        if turning { pending = (document, target, revision, nightPages); return }
        let changed = self.document !== document || self.revision != revision || self.nightPages != nightPages
        guard changed || target != currentIndex || viewControllers?.isEmpty != false else { return }
        let direction: UIPageViewController.NavigationDirection = target >= currentIndex ? .forward : .reverse
        self.document = document
        self.revision = revision
        self.nightPages = nightPages
        view.backgroundColor = nightPages ? .black : .white
        let animated = !changed && !reduceMotion && view.window != nil
        currentIndex = target
        guard let page = page(at: target) else { return }
        turning = animated
        setViewControllers([page], direction: direction, animated: animated) { [weak self] _ in
            self?.turning = false
            self?.applyPending()
        }
    }

    private func page(at index: Int) -> BookPageController? {
        guard let document, let page = document.page(at: index) else { return nil }
        return BookPageController(page: page, index: index, count: document.pageCount, nightPages: nightPages,
                                  onToggleControls: { [weak self] in self?.onToggleControls?() })
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let current = viewController as? BookPageController, current.index > 0 else { return nil }
        return page(at: current.index - 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let current = viewController as? BookPageController,
              current.index + 1 < (document?.pageCount ?? 0) else { return nil }
        return page(at: current.index + 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController,
                            willTransitionTo pendingViewControllers: [UIViewController]) {
        turning = true
    }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        turning = false
        if completed, let visible = viewControllers?.first as? BookPageController {
            currentIndex = visible.index
            // Ignore stale SwiftUI updates queued during the user's turn.
            if let queued = pending, queued.0 === document, queued.2 == revision, queued.3 == nightPages,
               queued.1 == (previousViewControllers.first as? BookPageController)?.index { pending = nil }
            onPageChanged?(currentIndex)
        }
        applyPending()
    }
    private func applyPending() {
        guard let queued = pending else { return }
        pending = nil
        update(document: queued.0, index: queued.1, revision: queued.2, nightPages: queued.3)
    }
}

@MainActor
final class BookPageController: UIViewController, UIScrollViewDelegate {
    let index: Int
    let page: PDFPage
    let count: Int
    private let scroll = UIScrollView()
    private let image = UIImageView()
    private var renderedSize = CGSize.zero
    let nightPages: Bool
    private let onToggleControls: (() -> Void)?
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    init(page: PDFPage, index: Int, count: Int, nightPages: Bool = false, onToggleControls: (() -> Void)? = nil) {
        self.page = page; self.index = index; self.count = count
        self.nightPages = nightPages
        self.onToggleControls = onToggleControls
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = nightPages ? .black : .white
        scroll.delegate = self
        scroll.maximumZoomScale = 3
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.isScrollEnabled = false
        view.addSubview(scroll)
        scroll.addSubview(image)
        image.contentMode = .scaleAspectFit
        image.isAccessibilityElement = true
        image.accessibilityIdentifier = "book-page"
        image.accessibilityLabel = "Page \(index + 1) of \(count)"
        image.accessibilityValue = page.string
        image.accessibilityIgnoresInvertColors = true
        image.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Show or hide reading controls") { [weak self] _ in
            self?.onToggleControls?()
            return true
        }]
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.size != renderedSize, view.bounds.width > 0, view.bounds.height > 0 else { return }
        renderedSize = view.bounds.size
        scroll.setZoomScale(1, animated: false)
        scroll.frame = view.bounds
        image.frame = scroll.bounds
        scroll.contentSize = scroll.bounds.size
        // Only the visible page and its neighbors are rendered. PDFKit handles crop and rotation.
        let density = min(4, view.window?.screen.scale ?? 2)
        let rendered = page.thumbnail(of: CGSize(width: min(4096, renderedSize.width * density),
                                               height: min(4096, renderedSize.height * density)), for: .cropBox)
        if nightPages, let input = CIImage(image: rendered),
           let output = Self.imageContext.createCGImage(input.applyingFilter("CIColorInvert"), from: input.extent) {
            image.image = UIImage(cgImage: output)
        } else { image.image = rendered }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { scrollView.isScrollEnabled = scrollView.zoomScale > 1.01 }
    @objc private func toggleZoom(_ recognizer: UITapGestureRecognizer) {
        scroll.setZoomScale(scroll.zoomScale > 1.01 ? 1 : 2, animated: !UIAccessibility.isReduceMotionEnabled)
    }
}
