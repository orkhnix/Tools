import UIKit
import SwiftUI
import VisionKit

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct DocumentScanner: UIViewControllerRepresentable {
    let completion: (Result<[UIImage], Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: (Result<[UIImage], Error>) -> Void
        init(completion: @escaping (Result<[UIImage], Error>) -> Void) { self.completion = completion }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            completion(.success((0..<scan.pageCount).map { scan.imageOfPage(at: $0) }))
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { completion(.success([])) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { completion(.failure(error)) }
    }
}

struct TextEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let prompt: String
    let secure: Bool
    let actionTitle: String
    let completion: (String) -> Void
    @State private var value = ""

    init(title: String, prompt: String, secure: Bool = false, actionTitle: String = "Place on page", completion: @escaping (String) -> Void) {
        self.title = title; self.prompt = prompt; self.secure = secure
        self.actionTitle = actionTitle; self.completion = completion
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if secure { SecureField("Password", text: $value).textContentType(.newPassword) }
                    else { TextEditor(text: $value).frame(minHeight: 140) }
                } footer: { Text(prompt) }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) { dismiss(); completion(value) }
                        .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.presentationDetents([.medium, .large])
    }
}

struct SignatureSheet: View {
    @Environment(\.dismiss) private var dismiss
    let completion: (SignatureDrawing) -> Void
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var canvasSize = CGSize(width: 1, height: 1)

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Make it yours.").font(.system(.title, design: .serif, weight: .bold))
                Text("Sign below with your finger or Apple Pencil.").font(.subheadline).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    Canvas { context, _ in
                        for points in strokes + [current] {
                            guard let first = points.first else { continue }
                            var path = Path(); path.move(to: first)
                            for point in points.dropFirst() { path.addLine(to: point) }
                            context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.gray.opacity(0.25)))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        canvasSize = geometry.size
                        current.append(CGPoint(x: min(max(value.location.x, 0), geometry.size.width),
                                               y: min(max(value.location.y, 0), geometry.size.height)))
                    }.onEnded { _ in if current.count > 1 { strokes.append(current) }; current = [] })
                }.frame(height: 180)
                Button("Clear signature", role: .destructive) { strokes = []; current = [] }
                Text("This creates a handwritten ink signature. It is not a certificate-backed digital signature.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(24)
                .navigationTitle("Signature").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use") {
                            let points = strokes.flatMap { $0 }
                            guard let first = points.first else { return }
                            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
                            for point in points {
                                minX = min(minX, point.x); maxX = max(maxX, point.x)
                                minY = min(minY, point.y); maxY = max(maxY, point.y)
                            }
                            let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                            let width = max(bounds.width, 1), height = max(bounds.height, 1)
                            // Preserve the signature's aspect ratio inside a 2.5:1 placement box.
                            let scale = min(1 / width, 0.4 / height)
                            let normalized = strokes.map { $0.map {
                                CGPoint(x: ($0.x - bounds.minX) * scale, y: ($0.y - bounds.minY) * scale / 0.4)
                            } }
                            completion(SignatureDrawing(strokes: normalized)); dismiss()
                        }.disabled(strokes.isEmpty)
                    }
                }
        }.preferredColorScheme(.light)
    }
}
