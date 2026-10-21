import Foundation

struct ReadingState: Codable, Equatable {
    var pageIndex = 0
    var bookmarks: Set<Int> = []

    func clamped(pageCount: Int) -> ReadingState {
        ReadingState(pageIndex: min(max(0, pageIndex), max(0, pageCount - 1)),
                     bookmarks: bookmarks.filter { $0 >= 0 && $0 < pageCount })
    }
}

struct ReadingStateStore {
    var defaults: UserDefaults = .standard
    private func key(_ url: URL) -> String {
        // Container paths can change after an app update. Document names remain stable.
        "folio.reading." + Data(url.lastPathComponent.utf8).base64EncodedString()
    }
    func load(_ url: URL) -> ReadingState {
        guard let data = defaults.data(forKey: key(url)),
              let state = try? JSONDecoder().decode(ReadingState.self, from: data) else { return ReadingState() }
        return state
    }
    func save(_ state: ReadingState, for url: URL) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key(url))
    }
    func move(from: URL, to: URL) {
        if let data = defaults.data(forKey: key(from)) { defaults.set(data, forKey: key(to)) }
        remove(from)
    }
    func remove(_ url: URL) { defaults.removeObject(forKey: key(url)) }
}
