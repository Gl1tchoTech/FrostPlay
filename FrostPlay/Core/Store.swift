import Foundation
import SwiftUI

@MainActor
final class FrostPlayStore: ObservableObject {
    @Published var settings: FrostPlaySettings { didSet { save(settings, key: "settings") } }
    @Published private(set) var library: [MediaItem] { didSet { save(library, key: "library") } }
    @Published private(set) var history: [WatchEntry] { didSet { save(history, key: "history") } }
    @Published var searchResults: [MediaItem] = []
    @Published var homeItems: [MediaItem] = [.preview]
    @Published var providerItems: [MediaItem] = []
    @Published var isSearching = false
    @Published var isLoadingHome = false
    @Published var isLoadingProvider = false
    @Published var searchError: String?
    @Published var homeError: String?
    @Published var providerError: String?

    private let anilist = AniListService()

    private var tmdb: TMDBService {
        TMDBService(apiKey: settings.tmdbAPIKey, readAccessToken: settings.tmdbReadAccessToken)
    }

    var isTMDBConfigured: Bool { tmdb.isConfigured }

    init() {
        var restoredSettings = Self.load(FrostPlaySettings.self, key: "settings") ?? FrostPlaySettings()
        let enabledSources = Set(restoredSettings.enabledSources)
        restoredSettings.enabledSources = PlaybackSource.implemented.filter { enabledSources.contains($0) }
        if restoredSettings.enabledSources.isEmpty { restoredSettings.enabledSources = PlaybackSource.implemented }
        settings = restoredSettings
        library = Self.load([MediaItem].self, key: "library") ?? []
        history = Self.load([WatchEntry].self, key: "history") ?? []
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

    func loadProviderCatalog(_ provider: StreamingProvider) async {
        guard provider.id != "all", let providerID = provider.tmdbProviderID else {
            providerItems = []
            providerError = nil
            isLoadingProvider = false
            return
        }
        isLoadingProvider = true
        providerError = nil
        do {
            let items = try await tmdb.catalog(for: providerID, providerName: provider.name)
            guard settings.selectedProvider == provider.name else { return }
            providerItems = items
            if providerItems.isEmpty { providerError = "No titles were returned for this service in the US region." }
        } catch {
            guard settings.selectedProvider == provider.name else { return }
            providerItems = []
            providerError = error.localizedDescription
        }
        if settings.selectedProvider == provider.name { isLoadingProvider = false }
    }

    func episodeCatalog(for media: MediaItem) async -> [SeasonEpisodeInfo] {
        if media.kind == .anime {
            guard let count = media.episodeCount, count > 0 else { return [] }
            return [SeasonEpisodeInfo(season: 1, episodeCount: count)]
        }
        guard media.kind == .tv, let tmdbID = media.tmdbID else { return [] }
        return (try? await tmdb.seasons(for: tmdbID)) ?? []
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
