import SwiftUI

@main
struct FolioPDFApp: App {
    @StateObject private var store: DocumentStore
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FolioUITests")
            try? FileManager.default.removeItem(at: directory)
            UserDefaults.standard.set(true, forKey: "bookReadingMode")
            UserDefaults.standard.set(false, forKey: "nightPages")
            UserDefaults.standard.set(AppAppearance.light.rawValue, forKey: "appAppearance")
            let testStore = DocumentStore(directory: directory)
            ReadingStateStore().remove(directory.appendingPathComponent("Welcome to Folio.pdf"))
            testStore.makeWelcomeDocument()
            _store = StateObject(wrappedValue: testStore)
            return
        }
        #endif
        _store = StateObject(wrappedValue: DocumentStore())
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .tint(Theme.accent)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .onOpenURL { url in Task { await store.importURLs([url]) } }
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.31, green: 0.27, blue: 0.81)
    static let paper = Color(uiColor: .systemGroupedBackground)
}
