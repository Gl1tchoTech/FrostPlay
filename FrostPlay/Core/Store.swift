import Foundation
import SwiftUI
import WebKit

enum CacheCategory: String, CaseIterable, Identifiable {
    case networkAndImages = "Network & images"
    case webKit = "WebKit data"
    case temporaryFiles = "Other cache & temp"
    case animeCatalog = "Anime catalog"

    var id: String { rawValue }
}

@MainActor
final class FrostPlayStore: ObservableObject {
    @Published var settings: FrostPlaySettings { didSet { save(settings, key: "settings") } }
    @Published private(set) var library: [MediaItem] { didSet { save(library, key: "library") } }
    @Published private(set) var history: [WatchEntry] { didSet { save(history, key: "history") } }
    @Published private(set) var downloads: [DownloadEntry] { didSet { save(downloads, key: "downloads") } }
    @Published var searchResults: [MediaItem] = []
    @Published private(set) var animeResults: [MediaItem] = []
    @Published private(set) var animeError: String?
    @Published private(set) var episodeError: String?
    @Published private(set) var cacheBreakdown: [CacheCategory: Int] = [:]
    @Published var homeItems: [MediaItem] = [.preview]
    @Published var providerItems: [MediaItem] = []
    @Published var isSearching = false
    @Published var isLoadingHome = false
    @Published var isLoadingProvider = false
    @Published var searchError: String?
    @Published var homeError: String?
    @Published var providerError: String?
    @Published var isLoadingMore = false
    @Published private(set) var hasMoreResults = true

    private let anilist = AniListService()
    private var searchPage = 1
    private var homePage = 1
    private var providerPage = 1
    private var activeSearchQuery = ""
    private var activeSearchKind: MediaKind?
    private var activeProviderID: String?

    private var tmdb: TMDBService {
        TMDBService(apiKey: settings.tmdbAPIKey, readAccessToken: settings.tmdbReadAccessToken)
    }

    var isTMDBConfigured: Bool { tmdb.isConfigured }

    init() {
        var restoredSettings = Self.load(FrostPlaySettings.self, key: "settings") ?? FrostPlaySettings()
        let enabledSources = Set(restoredSettings.enabledSources)
        // Keep the user's saved order, while migrating older installs that predate VidLink's active adapter.
        restoredSettings.enabledSources = PlaybackSource.implemented.filter { enabledSources.contains($0) }
        let missingSources = PlaybackSource.implemented.filter { !restoredSettings.enabledSources.contains($0) }
        restoredSettings.enabledSources.append(contentsOf: missingSources)
        if restoredSettings.enabledSources.isEmpty { restoredSettings.enabledSources = PlaybackSource.implemented }
        // Keep the per-kind defaults compatible with their title types.
        if !PlaybackSource.allowed(for: .anime).contains(restoredSettings.defaultAnimeSource) {
            restoredSettings.defaultAnimeSource = .megaPlay
        }
        if !PlaybackSource.allowed(for: .movie).contains(restoredSettings.defaultMovieTVSource) {
            restoredSettings.defaultMovieTVSource = .vidLink
        }
        restoredSettings.homeSections = restoredSettings.homeSections.filter { HomeSection.allCases.contains($0) }
        if restoredSettings.homeSections.isEmpty { restoredSettings.homeSections = HomeSection.defaultOrder }
        settings = restoredSettings
        library = Self.load([MediaItem].self, key: "library") ?? []
        history = Self.load([WatchEntry].self, key: "history") ?? []
        downloads = Self.load([DownloadEntry].self, key: "downloads") ?? []
    }

    func loadHome() async {
        guard !isLoadingHome else { return }
        isLoadingHome = true
        homeError = nil
        do {
            homePage = 1
            let results = try await tmdb.trending(page: homePage)
            if !results.isEmpty { homeItems = results }
        } catch {
            homeError = error.localizedDescription
        }
        isLoadingHome = false
    }

    func loadMoreHome() async {
        guard !isLoadingMore, isTMDBConfigured else { return }
        isLoadingMore = true
        homePage += 1
        do {
            let more = try await tmdb.trending(page: homePage)
            homeItems.append(contentsOf: more)
        } catch {
            homePage -= 1
        }
        isLoadingMore = false
    }

    func loadProviderCatalog(_ provider: StreamingProvider) async {
        guard provider.id != "all", let providerID = provider.tmdbProviderID else {
            providerItems = []
            providerError = nil
            isLoadingProvider = false
            return
        }
        isLoadingProvider = true
        defer { isLoadingProvider = false }
        providerError = nil
        do {
            providerPage = 1
            activeProviderID = provider.id
            let items = try await tmdb.catalog(for: providerID, providerName: provider.name, page: providerPage)
            guard settings.selectedProvider == provider.name else { return }
            providerItems = items
            hasMoreResults = items.count >= 20
            if providerItems.isEmpty { providerError = "No titles were returned for this service in the US region." }
        } catch {
            guard settings.selectedProvider == provider.name else { return }
            providerItems = []
            providerError = error.localizedDescription
        }
    }

    func loadMoreProviderCatalog(_ provider: StreamingProvider) async {
        guard !isLoadingMore, settings.selectedProvider == provider.name, let providerID = provider.tmdbProviderID else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        providerPage += 1
        do {
            let items = try await tmdb.catalog(for: providerID, providerName: provider.name, page: providerPage)
            guard activeProviderID == provider.id else { return }
            providerItems.append(contentsOf: items)
            hasMoreResults = items.count >= 20
        } catch {
            providerPage -= 1
        }
    }

    func animeMetadata(for media: MediaItem) async -> MediaMetadata? {
        guard media.kind == .anime, let aniListID = media.aniListID else { return media.metadata }
        guard let refreshed = try? await anilist.metadata(for: aniListID), refreshed.hasDetails else {
            return media.metadata
        }
        guard let existing = media.metadata else { return refreshed }
        return MediaMetadata(
            genres: refreshed.genres.isEmpty ? existing.genres : refreshed.genres,
            score: refreshed.score ?? existing.score,
            status: refreshed.status ?? existing.status,
            format: refreshed.format ?? existing.format,
            countryOfOrigin: refreshed.countryOfOrigin ?? existing.countryOfOrigin,
            durationMinutes: refreshed.durationMinutes ?? existing.durationMinutes,
            source: refreshed.source ?? existing.source,
            studios: (refreshed.studios?.isEmpty ?? true) ? existing.studios : refreshed.studios
        )
    }

    func animePlaybackEpisodes(for media: MediaItem, episodeNumbers: [Int]? = nil) async throws -> [EpisodeInfo] {
        let numbers: [Int]
        if let episodeNumbers {
            numbers = episodeNumbers
        } else {
            // Fall back to the catalog's episode numbers when a caller does not
            // already hold them.
            numbers = try await anilist.episodes(for: media).map(\.number)
        }
        return try await anilist.playbackEpisodes(for: media, episodeNumbers: numbers, language: settings.preferredAnimeLanguage)
    }

    func episodeCatalog(for media: MediaItem) async -> [SeasonEpisodeInfo] {
        episodeError = nil
        if media.kind == .anime {
            guard media.aniListID != nil else {
                episodeError = "AniList ID is missing for this title."
                return []
            }
            do {
                let episodes = try await anilist.episodes(for: media)
                let count = media.episodeCount ?? episodes.count
                guard count > 0 || !episodes.isEmpty else {
                    episodeError = "AniList returned no episode information for this title."
                    return []
                }
                return [SeasonEpisodeInfo(season: 1, episodeCount: max(count, episodes.count), episodes: episodes)]
            } catch {
                episodeError = error.localizedDescription
                return []
            }
        }
        guard media.kind == .tv, let tmdbID = media.tmdbID else { return [] }
        do {
            let seasons = try await tmdb.seasons(for: tmdbID)
            if seasons.isEmpty { episodeError = "Episode data is unavailable for this title." }
            return seasons
        } catch {
            episodeError = error.localizedDescription
            return []
        }
    }

    func loadAnimeCatalog() async {
        guard !isSearching else { return }
        await search(query: "", kind: .anime)
    }

    func search(query: String, kind: MediaKind? = nil) async {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty || kind == .anime else {
            searchResults = []
            searchError = nil
            return
        }

        isSearching = true
        defer { isSearching = false }
        searchError = nil
        if kind == .anime { animeError = nil }
        searchPage = 1
        activeSearchQuery = cleanQuery
        activeSearchKind = kind
        hasMoreResults = true
        var results: [MediaItem] = []
        var failures: [String] = []

        if kind == .anime {
            do { results = try await anilist.search(query: cleanQuery, kind: .anime, page: searchPage) }
            catch { failures.append("AniList: \(error.localizedDescription)") }
        } else if let kind {
            do { results = try await tmdb.search(query: cleanQuery, kind: kind, page: searchPage) }
            catch { failures.append(error.localizedDescription) }
        } else {
            do { results += try await tmdb.searchMulti(query: cleanQuery, page: searchPage) }
            catch { failures.append(error.localizedDescription) }
            do { results += try await anilist.search(query: cleanQuery, kind: .anime, page: searchPage) }
            catch { failures.append("AniList: \(error.localizedDescription)") }
        }

        searchResults = results
        if kind == .anime {
            animeResults = results.filter { $0.kind == .anime && $0.aniListID != nil && $0.tmdbID == nil }
            animeError = animeResults.isEmpty ? (failures.first ?? "AniList returned no titles.") : nil
        } else if kind == nil {
            animeResults = results.filter { $0.kind == .anime && $0.aniListID != nil && $0.tmdbID == nil }
            animeError = nil
        }
        if results.isEmpty {
            searchError = failures.first ?? "No matching titles were found."
        }
        hasMoreResults = results.count >= 20
    }

    func loadMoreSearchResults() async {
        guard !isLoadingMore, hasMoreResults, (!activeSearchQuery.isEmpty || activeSearchKind == .anime) else { return }
        isLoadingMore = true
        searchPage += 1
        var more: [MediaItem] = []
        do {
            if activeSearchKind == .anime {
                more = try await anilist.search(query: activeSearchQuery, kind: .anime, page: searchPage)
            } else if let kind = activeSearchKind {
                more = try await tmdb.search(query: activeSearchQuery, kind: kind, page: searchPage)
            } else {
                more = (try? await tmdb.searchMulti(query: activeSearchQuery, page: searchPage)) ?? []
                more += (try? await anilist.search(query: activeSearchQuery, kind: .anime, page: searchPage)) ?? []
            }
            searchResults.append(contentsOf: more)
            if activeSearchKind == .anime {
                animeResults.append(contentsOf: more.filter { $0.kind == .anime && $0.aniListID != nil && $0.tmdbID == nil })
            } else if activeSearchKind == nil {
                animeResults.append(contentsOf: more.filter { $0.kind == .anime && $0.aniListID != nil && $0.tmdbID == nil })
            }
            hasMoreResults = more.count >= 20
        } catch {
            searchPage -= 1
        }
        isLoadingMore = false
    }

    func toggleLibrary(_ media: MediaItem) {
        if let index = library.firstIndex(of: media) { library.remove(at: index) }
        else { library.insert(media, at: 0) }
    }

    func isInLibrary(_ media: MediaItem) -> Bool { library.contains(media) }

    func download(media: MediaItem, format: PlaybackFormat, episode: Int? = nil) async throws {
        guard settings.downloadsEnabled, let sourceURL = AuthorizedDownloadManager.downloadableURL(for: format) else { return }
        let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return }
        let fileName = AuthorizedDownloadManager.fileName(for: media, episode: episode)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        let entry = DownloadEntry(id: "\(media.id)-\(episode.map(String.init) ?? "movie")", media: media, fileName: fileName, localURL: destination, downloadedAt: Date(), episode: episode)
        downloads.removeAll { $0.id == entry.id }
        downloads.insert(entry, at: 0)
    }

    func removeDownload(_ entry: DownloadEntry) {
        try? FileManager.default.removeItem(at: entry.localURL)
        downloads.removeAll { $0.id == entry.id }
    }

    func recordWatch(_ media: MediaItem, progress: Double = 0) {
        let entry = WatchEntry(id: media.id, media: media, progress: progress, lastPlayed: Date())
        history.removeAll { $0.id == entry.id }
        history.insert(entry, at: 0)
    }

    func isInHistory(_ media: MediaItem) -> Bool {
        history.contains { $0.id == media.id }
    }

    /// Removes a title from Continue Watching / watch history only. It stays in My List.
    func removeFromHistory(_ media: MediaItem) {
        history.removeAll { $0.id == media.id }
    }

    func clearHistory() {
        history.removeAll()
    }

    func addToLibrary(_ media: MediaItem) {
        guard !library.contains(media) else { return }
        library.insert(media, at: 0)
    }

    func removeFromLibrary(_ media: MediaItem) {
        library.removeAll { $0 == media }
    }

    func moveSource(from source: IndexSet, to destination: Int) {
        settings.enabledSources.move(fromOffsets: source, toOffset: destination)
    }

    func moveHomeSection(from source: IndexSet, to destination: Int) {
        settings.homeSections.move(fromOffsets: source, toOffset: destination)
    }

    /// Drag-and-drop reorder used by the on-Home section editor: moves `section`
    /// so it sits directly before `target` in the visible order.
    func moveHomeSection(_ section: HomeSection, before target: HomeSection) {
        guard section != target,
              let from = settings.homeSections.firstIndex(of: section),
              let to = settings.homeSections.firstIndex(of: target) else { return }
        settings.homeSections.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    /// Moves a section one slot up (-1) or down (+1); used by the arrow buttons in
    /// the on-Home section editor.
    func nudgeHomeSection(_ section: HomeSection, by offset: Int) {
        guard let index = settings.homeSections.firstIndex(of: section) else { return }
        let target = index + offset
        guard settings.homeSections.indices.contains(target) else { return }
        settings.homeSections.swapAt(index, target)
    }

    func addHomeSection(_ section: HomeSection) {
        guard !settings.homeSections.contains(section) else { return }
        settings.homeSections.append(section)
    }

    func removeHomeSection(_ section: HomeSection) {
        settings.homeSections.removeAll { $0 == section }
    }

    func setSource(_ source: PlaybackSource, enabled: Bool) {
        if enabled {
            if !settings.enabledSources.contains(source) { settings.enabledSources.append(source) }
        } else {
            settings.enabledSources.removeAll { $0 == source }
        }
    }

    func toggleSource(_ source: PlaybackSource) {
        setSource(source, enabled: !settings.enabledSources.contains(source))
    }

    /// Sets the default source for a title type. Movies and TV share one default;
    /// anime has its own because it is addressed by AniList/MAL ID.
    func setDefaultSource(_ source: PlaybackSource, for kind: MediaKind) {
        guard PlaybackSource.allowed(for: kind).contains(source) else { return }
        if kind == .anime {
            settings.defaultAnimeSource = source
        } else {
            settings.defaultMovieTVSource = source
        }
        setSource(source, enabled: true)
    }

    func refreshCacheBreakdown() async {
        let fileManager = FileManager.default
        let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        let temporaryDirectory = fileManager.temporaryDirectory
        let webKitDirectory = library?.appendingPathComponent("WebKit", isDirectory: true)
        let fileBytes = await Task.detached(priority: .utility) {
            func size(of directory: URL?) -> Int {
                guard let directory,
                      let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
                return files.compactMap { $0 as? URL }.reduce(0) { total, url in
                    total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }
            return (size(of: webKitDirectory), size(of: cacheDirectory), size(of: temporaryDirectory))
        }.value
        let urlCacheBytes = URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
        cacheBreakdown = [
            .networkAndImages: urlCacheBytes,
            .webKit: fileBytes.0,
            .temporaryFiles: max(0, fileBytes.1 + fileBytes.2 - URLCache.shared.currentDiskUsage),
            .animeCatalog: await AnikotoCache.cachedByteCount()
        ]
    }

    func clearAllCache() async {
        // Keep removal scoped to transient caches so Documents/downloads and Library/preferences survive.
        URLCache.shared.removeAllCachedResponses()
        await AnikotoCache.clear()
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            for directory in [
                fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
                Optional(fileManager.temporaryDirectory)
            ].compactMap({ $0 }) {
                guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
                for url in contents { try? fileManager.removeItem(at: url) }
            }
        }.value
        await refreshCacheBreakdown()
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
