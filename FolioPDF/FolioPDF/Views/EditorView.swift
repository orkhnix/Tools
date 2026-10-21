import UIKit
import SwiftUI
import PDFKit

private enum EditorSheet: Identifiable {
    case pages, bookmarks, jump, appearance, signature, text, note, comment, recognized, password, share(URL)
    var id: String {
        switch self {
        case .pages: return "pages"
        case .bookmarks: return "bookmarks"
        case .jump: return "jump"
        case .appearance: return "appearance"
        case .signature: return "signature"
        case .text: return "text"
        case .note: return "note"
        case .comment: return "comment"
        case .recognized: return "recognized"
        case .password: return "password"
        case .share(let url): return url.absoluteString
        }
    }
}

struct EditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: EditorModel
    @State private var sheet: EditorSheet?
    @State private var pendingShare: URL?
    @AppStorage("bookReadingMode") private var reading = true
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("nightPages") private var nightPages = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focused = false
    @State private var jumpPage = ""
    @State private var searching = false
    @State private var password = ""
    @State private var discardPrompt = false

    init(url: URL) { _model = StateObject(wrappedValue: EditorModel(url: url)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.document.isLocked { lockedView }
                else if !model.loadedSuccessfully {
                    ContentUnavailableView("Unable to open PDF", systemImage: "exclamationmark.triangle")
                } else {
                    if searching { searchBar }
                    if !model.isEditable && !focused {
                        Text(model.document.isEncrypted ? "Encrypted PDF · read-only" : "Document permissions · read-only")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(8)
                    }
                    if reading {
                        BookReader(model: model, onToggleControls: toggleFocus)
                            .id(reduceMotion)
                    } else {
                        PDFCanvas(model: model)
                    }

                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background((reading ? (nightPages ? Color.black : Color.white) : Theme.paper).ignoresSafeArea())
            .navigationTitle(model.url.deletingPathExtension().lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(focused ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(focused)
            .persistentSystemOverlays(focused ? .hidden : .automatic)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { if !model.loadedSuccessfully || model.save() { dismiss() } }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        reading.toggle()
                        focused = false
                        searching = false
                        model.tool = .browse
                    } label: {
                        Image(systemName: reading ? "pencil.and.outline" : "book")
                    }
                    .accessibilityLabel(reading ? "Edit PDF" : "Book reading mode")
                    .disabled(model.document.isLocked || !model.loadedSuccessfully)
                    if model.isEditable && !reading {
                        Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                            .disabled(!model.canUndo).accessibilityLabel("Undo annotation or page edit")
                        Button(model.hasChanges ? "Save •" : "Save") { model.save() }
                    }
                    Menu {
                        Button("Focus reading", systemImage: "arrow.up.left.and.arrow.down.right") {
                            reading = true; model.tool = .browse; searching = false
                            setFocus(true)
                        }
                        Button(model.bookmarks.contains(model.pageIndex) ? "Remove bookmark" : "Bookmark page",
                               systemImage: model.bookmarks.contains(model.pageIndex) ? "bookmark.fill" : "bookmark") { model.toggleBookmark() }
                        Button("Bookmarks", systemImage: "bookmark") { sheet = .bookmarks }
                        Button("Go to page", systemImage: "number") { openJump() }
                        Button("Appearance", systemImage: "circle.lefthalf.filled") { sheet = .appearance }
                        Divider()
                        Button("Search text", systemImage: "magnifyingglass") { reading = false; model.tool = .browse; searching.toggle() }
                        Button("Pages", systemImage: "square.grid.2x2") { sheet = .pages }
                        Button("Share PDF", systemImage: "square.and.arrow.up") { share() }
                        Button("Recognize current page", systemImage: "text.viewfinder") {
                            Task {
                                model.recognizedText = ""
                                await model.recognizePage()
                                if !model.recognizedText.isEmpty { sheet = .recognized }
                            }
                        }.disabled(model.recognizing)
                        if model.isEditable {
                            Button("Password-protected copy", systemImage: "lock.doc") { sheet = .password }
                            Button("Discard changes and close", systemImage: "xmark", role: .destructive) { discardPrompt = true }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Document actions").disabled(model.document.isLocked || !model.loadedSuccessfully)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !focused && !model.document.isLocked && model.loadedSuccessfully {
                    VStack(spacing: 8) {
                        if reading { readingControls }
                        else {
                            HStack {
                                Text("\(min(model.pageIndex + 1, model.pageCount)) / \(model.pageCount)")
                                    .font(.caption.monospacedDigit())
                                Spacer()
                                Text(model.tool.hint).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(.horizontal, 16)
                            if model.isEditable { editingToolbar }
                        }
                    }.padding(.vertical, 8)
                }
            }
            .overlay {
                if model.recognizing { ProgressView("Reading this page…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
            }
            .sheet(item: $sheet, onDismiss: {
                model.inspectedNote = nil
                if let url = pendingShare { pendingShare = nil; sheet = .share(url) }
            }) { route in
                switch route {
                case .pages: PageOrganizer(model: model)
                case .bookmarks: bookmarksView
                case .jump: jumpView
                case .appearance: AppearanceSettingsView()
                case .signature: SignatureSheet { model.signature = $0; model.tool = .sign }
                case .text:
                    TextEntrySheet(title: "Add text", prompt: "This adds a text annotation. After tapping Place, tap the page where it should appear.") {
                        model.textToPlace = $0; model.tool = .text
                    }
                case .note:
                    TextEntrySheet(title: "Add note", prompt: "Tap a page to place the note. In Read mode, tap its icon to view the comment.") {
                        model.textToPlace = $0; model.tool = .note
                    }
                case .recognized: recognizedTextView
                case .comment:
                    NavigationStack {
                        ScrollView {
                            Text(model.inspectedNote ?? "").textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        }.navigationTitle("Note").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
                    }.presentationDetents([.medium, .large])
                case .password:
                    TextEntrySheet(title: "Protect a copy", prompt: "Remember this password. Anyone opening the exported copy will need it. Your working document stays unchanged.", secure: true, actionTitle: "Export") { value in
                        do { pendingShare = try model.shareCopy(password: value) }
                        catch { model.error = error.localizedDescription }
                    }
                case .share(let url): ActivitySheet(items: [url])
                }
            }
            .alert("Folio PDF", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .confirmationDialog("Discard unsaved changes?", isPresented: $discardPrompt, titleVisibility: .visible) {
                Button("Discard and close", role: .destructive) { dismiss() }
            } message: { Text("Changes since your last save will be lost.") }
            .onChange(of: scenePhase) { _, phase in
                if phase == .inactive, model.isEditable { model.save() }
            }
            .onChange(of: model.inspectedNote) { _, value in
                if value != nil { sheet = .comment }
            }
        }
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .interactiveDismissDisabled()
    }

    private var lockedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.doc").font(.system(size: 56)).foregroundStyle(Theme.accent)
            Text("A private document").font(.title2.bold())
            Text("Enter its password to read this PDF.").foregroundStyle(.secondary)
            SecureField("PDF password", text: $password).textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320).onSubmit { unlock() }
            Button("Unlock PDF") { unlock() }.buttonStyle(.borderedProminent)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.paper)
    }

    private var searchBar: some View {
        HStack {
            TextField("Search in PDF", text: $model.searchQuery).textFieldStyle(.roundedBorder)
                .submitLabel(.search).onSubmit { model.search() }
            Button { model.search() } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Find text")
            if !model.searchResults.isEmpty {
                Text("\(model.resultIndex + 1)/\(model.searchResults.count)").font(.caption).monospacedDigit()
                Button { model.nextResult(-1) } label: { Image(systemName: "chevron.up") }.accessibilityLabel("Previous result")
                Button { model.nextResult(1) } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Next result")
            } else if !model.searchQuery.isEmpty { Text("0 found").font(.caption) }
        }.padding(12).background(.bar)
    }

    private var editingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(EditorTool.allCases, id: \.self) { tool in
                    Button { choose(tool) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tool.icon).font(.system(size: 19))
                            Text(tool.rawValue).font(.system(size: 10, weight: .medium))
                        }.frame(width: 54, height: 54)
                            .foregroundStyle(model.tool == tool ? Theme.accent : Color.primary)
                            .background(model.tool == tool ? Theme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
                Button { model.highlightSelection() } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "highlighter").font(.system(size: 19))
                        Text("Highlight").font(.system(size: 10, weight: .medium))
                    }.frame(width: 60, height: 54)
                }.buttonStyle(.plain)
                Menu {
                    ForEach(Array(inkColors.enumerated()), id: \.offset) { _, ink in
                        Button(ink.0) { model.color = ink.1 }
                    }
                } label: {
                    Circle().fill(Color(uiColor: model.color)).frame(width: 24, height: 24).padding(14)
                }.accessibilityLabel("Ink color")
            }.padding(.horizontal, 10).padding(.vertical, 8)
        }.folioGlass(cornerRadius: 28).padding(.horizontal, 10)
    }

    private var readingControls: some View {
        HStack(spacing: 24) {
            Button { model.go(to: model.pageIndex - 1) } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 40)
            }.disabled(model.pageIndex == 0).accessibilityLabel("Previous page")
            Button { openJump() } label: {
                VStack(spacing: 2) {
                    Text("\(model.pageIndex + 1) / \(model.pageCount)")
                        .font(.subheadline.weight(.medium).monospacedDigit())
                    Text("\(Int(Double(model.pageIndex + 1) / Double(max(1, model.pageCount)) * 100))%")
                        .font(.caption2).foregroundStyle(.secondary)
                }.frame(minWidth: 70)
            }.accessibilityLabel("Page \(model.pageIndex + 1) of \(model.pageCount). Go to page")
                .accessibilityIdentifier("reader-page")
            Button { model.go(to: model.pageIndex + 1) } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 40)
            }.disabled(model.pageIndex + 1 >= model.pageCount).accessibilityLabel("Next page")
        }.buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 4)
            .folioGlass(cornerRadius: 28, interactive: true)
    }

    private func toggleFocus() { setFocus(!focused) }

    private func setFocus(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { focused = value }
    }

    private func openJump() { jumpPage = String(model.pageIndex + 1); sheet = .jump }

    private var jumpView: some View {
        NavigationStack {
            Form {
                Section("Page 1–\(model.pageCount)") {
                    TextField("Page number", text: $jumpPage).keyboardType(.numberPad)
                        .accessibilityIdentifier("jump-page-input")
                    Button("Go") {
                        if let number = Int(jumpPage), (1...max(1, model.pageCount)).contains(number) {
                            model.go(to: number - 1); sheet = nil
                        }
                    }.disabled(Int(jumpPage).map { !(1...max(1, model.pageCount)).contains($0) } ?? true)
                }
            }.navigationTitle("Go to page").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { sheet = nil } } }
        }.presentationDetents([.medium])
    }

    private var bookmarksView: some View {
        NavigationStack {
            Group {
                if model.bookmarks.isEmpty {
                    ContentUnavailableView("No bookmarks", systemImage: "bookmark",
                                           description: Text("Bookmark a page from the document menu."))
                } else {
                    List {
                        ForEach(model.bookmarks.sorted(), id: \.self) { index in
                            Button {
                                model.go(to: index); sheet = nil
                            } label: {
                                Label("Page \(index + 1)", systemImage: "bookmark.fill")
                            }.swipeActions {
                                Button("Remove", role: .destructive) {
                                    model.removeBookmark(at: index)
                                }
                            }
                        }
                    }
                }
            }.navigationTitle("Bookmarks").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
        }
    }

    private var inkColors: [(String, UIColor)] { [("Blue", .systemBlue), ("Black", .black), ("Red", .systemRed), ("Green", .systemGreen)] }

    private var recognizedTextView: some View {
        NavigationStack {
            ScrollView { Text(model.recognizedText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(20) }
                .navigationTitle("Recognized text").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { sheet = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        ShareLink(item: model.recognizedText) { Image(systemName: "square.and.arrow.up") }
                    }
                }
        }
    }

    private func choose(_ tool: EditorTool) {
        switch tool {
        case .text: sheet = .text
        case .note: sheet = .note
        case .sign: sheet = .signature
        default: model.tool = tool
        }
    }

    private func share() {
        do { sheet = .share(try model.shareCopy()) }
        catch { model.error = error.localizedDescription }
    }

    private func unlock() { if model.unlock(password) { password = "" } }
}
