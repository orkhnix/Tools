import UIKit
import SwiftUI
import PDFKit

struct PageOrganizer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DocumentStore
    @ObservedObject var model: EditorModel
    @State private var selected: Set<Int> = []
    @State private var deleting = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(0..<model.pageCount, id: \.self) { index in
                        HStack(spacing: 14) {
                            if model.isEditable {
                                Button {
                                    if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
                                } label: {
                                    Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(Theme.accent)
                                }.buttonStyle(.borderless).accessibilityLabel("Select page \(index + 1)")
                            }
                            Button { model.go(to: index); dismiss() } label: {
                                HStack(spacing: 14) {
                                    if let page = model.document.page(at: index) {
                                        Image(uiImage: page.thumbnail(of: CGSize(width: 100, height: 140), for: .cropBox))
                                            .resizable().scaledToFit().frame(width: 52, height: 72)
                                    }
                                    Text("Page \(index + 1)").foregroundStyle(.primary)
                                }
                            }.buttonStyle(.borderless)
                            Spacer(minLength: 2)
                            if model.isEditable {
                                Menu {
                                    Button("Rotate clockwise", systemImage: "rotate.right") { model.rotatePage(at: index) }
                                    Button("Move up", systemImage: "arrow.up") { model.movePage(from: index, to: index - 1); selected = [] }.disabled(index == 0)
                                    Button("Move down", systemImage: "arrow.down") { model.movePage(from: index, to: index + 1); selected = [] }.disabled(index == model.pageCount - 1)
                                } label: { Image(systemName: "ellipsis.circle").padding(8) }
                            }
                        }.padding(.vertical, 4)
                    }
                } footer: { Text(model.isEditable ? "Select pages to extract or delete them. Use each page's menu to rotate or reorder." : "This document is read-only.") }
            }
            .navigationTitle("Pages").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if model.isEditable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(selected.count == model.pageCount ? "Deselect" : "Select all") {
                            selected = selected.count == model.pageCount ? [] : Set(0..<model.pageCount)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.isEditable {
                    HStack {
                        Button("Extract \(selected.count)", systemImage: "square.on.square") { extract() }
                            .disabled(selected.isEmpty)
                        Spacer()
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }
                            .disabled(selected.isEmpty || selected.count == model.pageCount)
                    }.padding(20).background(.bar)
                }
            }
            .confirmationDialog("Delete \(selected.count) pages?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete pages", role: .destructive) { model.deletePages(selected); selected = [] }
            }
            .alert("Folio PDF", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private func extract() {
        do {
            let data = try PDFOperations.extract(model.document, indices: selected.sorted())
            try store.add(data: data, named: model.url.deletingPathExtension().lastPathComponent + " extracted")
            message = "Selected pages were saved as a new PDF in your document list."
        } catch { message = error.localizedDescription }
    }
}
