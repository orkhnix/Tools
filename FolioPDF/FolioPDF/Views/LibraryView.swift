import UIKit
import SwiftUI
import PDFKit
import PhotosUI
import VisionKit
import ImageIO

private enum LibrarySheet: String, Identifiable {
    case importPDF, scan, appearance
    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject private var store: DocumentStore
    @State private var query = ""
    @State private var librarySheet: LibrarySheet?
    @State private var pendingImport: [URL] = []
    @State private var importNotice: String?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var choosingPhotos = false
    @State private var importingPhotos = false
    @State private var opened: LibraryDocument?
    @State private var selecting = false
    @State private var selected: [String] = []
    @State private var renaming: LibraryDocument?
    @State private var newName = ""
    @State private var deleting: LibraryDocument?

    private var visible: [LibraryDocument] {
        query.isEmpty ? store.documents : store.documents.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        quickAction("Import PDF", icon: "square.and.arrow.down", color: Theme.accent) { librarySheet = .importPDF }
                        quickAction("Scan pages", icon: "viewfinder", color: Color.teal) { librarySheet = .scan }
                            .disabled(!VNDocumentCameraViewController.isSupported)
                    }
                    .disabled(store.isImporting || importingPhotos)
                    if let importNotice {
                        Label(importNotice, systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(.green)
                            .accessibilityIdentifier("import-status")
                    }
                    if store.documents.isEmpty {
                        ContentUnavailableView {
                            Label("No documents", systemImage: "doc.text")
                        } description: {
                            Text("Import a PDF to get started.")
                        } actions: {
                            Button("Create sample PDF") { store.makeWelcomeDocument() }.buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 24)
                    } else if visible.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        HStack {
                            Text(selecting ? "Tap documents in merge order" : "Your documents")
                                .font(.headline)
                            Spacer()
                            Text("\(visible.count)").foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 16)], spacing: 20) {
                            ForEach(visible) { item in
                                documentCard(item)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background {
                LinearGradient(colors: [Theme.accent.opacity(0.09), Theme.paper, Color.teal.opacity(0.07)],
                               startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            }
            .navigationTitle("Folio")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find a document")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selecting ? "Done" : "Select") { selecting.toggle(); selected = [] }
                        .disabled(store.documents.isEmpty)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { librarySheet = .appearance } label: { Image(systemName: "circle.lefthalf.filled") }
                        .accessibilityLabel("Appearance").accessibilityIdentifier("library-appearance")
                    Menu {
                        Button("Import PDF", systemImage: "doc.badge.plus") { librarySheet = .importPDF }
                        Button("Photos to PDF", systemImage: "photo.on.rectangle") { choosingPhotos = true }
                        Button("Scan document", systemImage: "viewfinder") { librarySheet = .scan }
                            .disabled(!VNDocumentCameraViewController.isSupported)
                        Button("Create sample", systemImage: "sparkles") { store.makeWelcomeDocument() }
                    } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .accessibilityLabel("Add document")
                    .disabled(store.isImporting || importingPhotos)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    Button {
                        let items = selected.compactMap { id in store.documents.first { $0.id == id } }
                        store.merge(items)
                        selecting = false; selected = []
                    } label: {
                        Label("Merge \(selected.count) PDFs", systemImage: "square.stack.3d.up")
                            .frame(maxWidth: .infinity).padding(10)
                    }
                    .buttonStyle(.borderedProminent).disabled(selected.count < 2).padding().background(.bar)
                }
            }
            .overlay {
                if store.isImporting || importingPhotos {
                    VStack(spacing: 10) {
                        ProgressView(store.isImporting ? "Importing PDF…" : "Creating PDF…")
                        if store.isImporting { Text(store.importingName).font(.caption).lineLimit(2) }
                    }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .photosPicker(isPresented: $choosingPhotos, selection: $photoItems, maxSelectionCount: 20,
                          selectionBehavior: .ordered, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
            .sheet(item: $librarySheet, onDismiss: {
                let urls = pendingImport
                pendingImport = []
                guard !urls.isEmpty else { return }
                importNotice = nil
                Task {
                    let imported = await store.importURLs(urls)
                    if !imported.isEmpty {
                        query = ""
                        importNotice = imported.count == 1 ? "PDF imported" : "\(imported.count) PDFs imported"
                    }
                }
            }) { route in
                switch route {
                case .appearance: AppearanceSettingsView()
                case .importPDF:
                    PDFDocumentPicker { urls in
                        pendingImport = urls
                        librarySheet = nil
                    }.ignoresSafeArea()
                case .scan:
                    DocumentScanner { result in
                        librarySheet = nil
                        switch result {
                        case .success(let images): if !images.isEmpty { store.addImages(images) }
                        case .failure(let error): store.error = error.localizedDescription
                        }
                    }.ignoresSafeArea()
                }
            }
            .fullScreenCover(item: $opened, onDismiss: { store.reload() }) { item in
                EditorView(url: item.url)
            }
            .alert(renaming != nil ? "Rename document" : deleting != nil ? "Delete this PDF?" : "Folio PDF",
                   isPresented: Binding(get: { renaming != nil || deleting != nil || store.error != nil }, set: {
                       if !$0 { renaming = nil; deleting = nil; store.error = nil }
                   })) {
                if let item = renaming {
                    TextField("Name", text: $newName)
                    Button("Cancel", role: .cancel) { renaming = nil }
                    Button("Rename") { store.rename(item, to: newName); renaming = nil }
                } else if let item = deleting {
                    Button("Cancel", role: .cancel) { deleting = nil }
                    Button("Delete", role: .destructive) { store.delete(item); deleting = nil }
                } else { Button("OK") { store.error = nil } }
            } message: {
                Text(deleting != nil ? "This deletes the app's copy. The original file you imported is unchanged." : store.error ?? "")
            }
        }
    }

    private func quickAction(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.subheadline.weight(.semibold))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .foregroundStyle(color).folioGlass(cornerRadius: 24, interactive: true)
        }.buttonStyle(.plain)
    }

    private func documentCard(_ item: LibraryDocument) -> some View {
        Button {
            if selecting {
                if selected.contains(item.id) { selected.removeAll { $0 == item.id } }
                else { selected.append(item.id) }
            } else { opened = item }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    DocumentThumbnail(url: item.url, modified: item.modified)
                        .frame(height: 185).frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    if selecting {
                        Text(selected.firstIndex(of: item.id).map { String($0 + 1) } ?? "")
                            .font(.caption.bold()).frame(width: 26, height: 26)
                            .background(selected.contains(item.id) ? Theme.accent : Color(uiColor: .systemGray4), in: Circle())
                            .foregroundStyle(.white).padding(10)
                    }
                }
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("document-" + item.id)
            .contextMenu {
                Button("Rename", systemImage: "pencil") { newName = item.name; renaming = item }
                Button("Duplicate", systemImage: "doc.on.doc") { store.duplicate(item) }
                ShareLink(item: item.url) { Label("Share PDF", systemImage: "square.and.arrow.up") }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
            }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        importingPhotos = true
        defer { importingPhotos = false; photoItems = [] }
        var images: [UIImage] = []
        do {
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2500,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else { throw FolioError.invalidPDF }
                images.append(UIImage(cgImage: thumbnail))
            }
            store.addImages(images, name: "Photo document")
        } catch { store.error = error.localizedDescription }
    }
}

private struct DocumentThumbnail: View {
    let url: URL
    let modified: Date
    @State private var image: UIImage?
    @State private var locked = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().padding(12) }
            else { Image(systemName: locked ? "lock.doc" : "doc.text").font(.largeTitle).foregroundStyle(.tertiary) }
        }
        .task(id: modified) {
            // Each thumbnail owns a separate document; never send the editor's PDFDocument across queues.
            let result = await Task.detached(priority: .utility) { () -> (UIImage?, Bool) in
                guard let pdf = PDFDocument(url: url) else { return (nil, false) }
                return (pdf.isLocked ? nil : pdf.page(at: 0)?.thumbnail(of: CGSize(width: 280, height: 360), for: .cropBox), pdf.isLocked)
            }.value
            guard !Task.isCancelled else { return }
            image = result.0; locked = result.1
        }
    }
}
