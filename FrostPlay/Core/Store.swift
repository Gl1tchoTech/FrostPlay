import Foundation
import SwiftUI

@MainActor
final class FrostPlayStore: ObservableObject {
    @Published var settings: FrostPlaySettings { didSet { save(settings, key: "settings") } }
    @Published private(set) var library: [MediaItem] { didSet { save(library, key: "library") } }
    @Published private(set) var history: [WatchEntry] { didSet { save(history, key: "history") } }
    @Published var searchResults: [MediaItem] = []
    @Published var isSearching = false
    @Published var searchError: String?

    private let tmdb = TMDBService(apiKey: Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String ?? "")
    private let anilist = AniListService()

    init() {
        settings = Self.load(FrostPlaySettings.self, key: "settings") ?? FrostPlaySettings()
        library = Self.load([MediaItem].self, key: "library") ?? []
        history = Self.load([WatchEntry].self, key: "history") ?? []
    }

    func search(query: String, kind: MediaKind? = nil) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { searchResults = []; return }
        isSearching = true
        searchError = nil
        do {
            let results: [MediaItem]
            if kind == .anime { results = try await anilist.search(query: query, kind: .anime) }
            else if kind == .movie || kind == .tv { results = try await tmdb.search(query: query, kind: kind) }
            else {
                let movies = try await tmdb.search(query: query, kind: .movie)
                let shows = try await tmdb.search(query: query, kind: .tv)
                let anime = try await anilist.search(query: query, kind: .anime)
                results = movies + shows + anime
            }
            searchResults = results
        } catch {
            searchError = "Search is unavailable right now."
        }
        isSearching = false
    }

    func toggleLibrary(_ media: MediaItem) {
        if let index = library.firstIndex(of: media) { library.remove(at: index) }
        else { library.insert(media, at: 0) }
    }

    func isInLibrary(_ media: MediaItem) -> Bool { library.contains(media) }

    func recordWatch(_ media: MediaItem, progress: Double = 0) {
        let entry = WatchEntry(id: media.id, media: media, progress: progress, lastPlayed: Date())
        history.removeAll { $0.id == entry.id }
        history.insert(entry, at: 0)
    }

    func moveSource(from source: IndexSet, to destination: Int) {
        settings.enabledSources.move(fromOffsets: source, toOffset: destination)
    }

    func toggleSource(_ source: PlaybackSource) {
        if let index = settings.enabledSources.firstIndex(of: source) { settings.enabledSources.remove(at: index) }
        else { settings.enabledSources.append(source) }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
