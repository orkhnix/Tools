import SwiftUI

@main
struct FolioPDFApp: App {
    @StateObject private var store = DocumentStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .tint(Theme.accent)
                .onOpenURL { url in Task { await store.importURLs([url]) } }
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.31, green: 0.27, blue: 0.81)
    static let paper = Color(uiColor: .systemGroupedBackground)
}
