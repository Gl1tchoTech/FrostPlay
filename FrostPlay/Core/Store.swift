import Foundation
import SwiftUI

@MainActor
final class FrostPlayStore: ObservableObject {
    @Published var settings: FrostPlaySettings { didSet { save(settings, key: "settings") } }
    @Published private(set) var library: [MediaItem] { didSet { save(library, key: "library") } }
    @Published private(set) var history: [WatchEntry] { didSet { save(history, key: "history") } }
    @Published var searchResults: [MediaItem] = []
    @Published var homeItems: [MediaItem] = [.preview]
    @Published var isSearching = false
    @Published var isLoadingHome = false
    @Published var searchError: String?
    @Published var homeError: String?

    private let tmdb: TMDBService
    private let anilist = AniListService()

    var isTMDBConfigured: Bool { tmdb.isConfigured }

    init() {
        settings = Self.load(FrostPlaySettings.self, key: "settings") ?? FrostPlaySettings()
        library = Self.load([MediaItem].self, key: "library") ?? []
        history = Self.load([WatchEntry].self, key: "history") ?? []
        let info = Bundle.main
        tmdb = TMDBService(
            apiKey: info.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String ?? "",
            readAccessToken: info.object(forInfoDictionaryKey: "TMDB_API_READ_ACCESS_TOKEN") as? String ?? ""
        )
    }

    func loadHome() async {
        guard !isLoadingHome else { return }
        isLoadingHome = true
        homeError = nil
        do {
            let results = try await tmdb.trending()
            if !results.isEmpty { homeItems = results }
        } catch {
            homeError = error.localizedDescription
        }
        isLoadingHome = false
    }

    func search(query: String, kind: MediaKind? = nil) async {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            searchResults = []
            searchError = nil
            return
        }

        isSearching = true
        searchError = nil
        var results: [MediaItem] = []
        var failures: [String] = []

        if kind == .anime {
            do { results = try await anilist.search(query: cleanQuery, kind: .anime) }
            catch { failures.append("AniList: \(error.localizedDescription)") }
        } else if let kind {
            do { results = try await tmdb.search(query: cleanQuery, kind: kind) }
            catch { failures.append(error.localizedDescription) }
        } else {
            do { results += try await tmdb.searchMulti(query: cleanQuery) }
            catch { failures.append(error.localizedDescription) }
            do { results += try await anilist.search(query: cleanQuery, kind: .anime) }
            catch { failures.append("AniList: \(error.localizedDescription)") }
        }

        searchResults = results
        if results.isEmpty {
            searchError = failures.first ?? "No matching titles were found."
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
