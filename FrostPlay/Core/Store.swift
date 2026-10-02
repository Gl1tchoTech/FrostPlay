import Foundation
import SwiftUI
import WebKit

enum CacheCategory: String, CaseIterable, Identifiable {
    case networkAndImages = "Network & images"
    case webKit = "WebKit data"
    case temporaryFiles = "Other cache & temp"
    case animeCatalog = "Anime catalog"
    case episodeDetails = "Episode details"

    var id: String { rawValue }
}

@MainActor
final class FrostPlayStore: ObservableObject {
    @Published var settings: FrostPlaySettings { didSet { save(settings, key: "settings") } }
    /// Every list the user has, including the built-in "My List". This is the
    /// single source of truth for saved titles; `library` below is a flat view of it.
    @Published private(set) var collections: [MediaCollection] { didSet { save(collections, key: "collections") } }
    @Published private(set) var history: [WatchEntry] { didSet { save(history, key: "history") } }
    @Published private(set) var downloads: [DownloadEntry] { didSet { save(downloads, key: "downloads") } }
    /// Transient 0...1 progress for in-flight HLS downloads, keyed by download id.
    /// Never persisted: it only drives the player's offline button while saving.
    @Published private(set) var downloadProgress: [String: Double] = [:]
    /// Titles waiting on an in-flight HLS download so the finished asset can be
    /// recorded against the right movie or episode.
    private var pendingHLSDownloads: [String: (media: MediaItem, episode: Int?)] = [:]
    /// Per-episode watch state, keyed by "mediaID|season|episode". Titles store
    /// their own coarse history; this remembers each episode's watched flag, its
    /// progress, and where to resume.
    @Published private(set) var episodeStates: [String: EpisodeWatchState] { didSet { save(episodeStates, key: "episodeStates") } }
    /// The user's manual corrections to episode titles, synopses, and artwork,
    /// keyed the same way. Applied on top of whatever the providers published.
    @Published private(set) var episodeOverrides: [String: EpisodeMetadataOverride] { didSet { save(episodeOverrides, key: "episodeOverrides") } }
    /// Which metadata pipeline each anime title uses. Only titles the user has
    /// switched are stored, so everything else keeps following AniList.
    @Published private(set) var metadataSources: [String: MetadataSourceMode] { didSet { save(metadataSources, key: "metadataSources") } }
    @Published var searchResults: [MediaItem] = []
    @Published private(set) var animeResults: [MediaItem] = []
    @Published private(set) var animeError: String?
    @Published private(set) var episodeError: String?
    @Published private(set) var cacheBreakdown: [CacheCategory: Int] = [:]
    @Published var homeItems: [MediaItem] = []
    @Published var providerItems: [MediaItem] = []
    @Published var isSearching = false
    @Published var isLoadingHome = false
    @Published var isLoadingProvider = false
    @Published var searchError: String?
    @Published var homeError: String?
    @Published var providerError: String?
    @Published var isLoadingMore = false
    @Published private(set) var hasMoreResults = true
    /// Official service logos keyed by TMDB watch-provider ID, used by the Home
    /// Browse-by-Service tiles and the service rail headings.
    @Published private(set) var providerLogos: [Int: URL] = [:]
    /// Which Home feed is currently on screen, so the rail can name its pick.
    @Published private(set) var homeFeed: HomeFeed = .pinned

    private let anilist = AniListService()
    private let kitsu = KitsuService()
    /// The alternate provider chain (Jikan + AniDB) behind Fallback mode.
    private let animeFallback = AnimeFallbackService()
    private var searchPage = 1
    private var homePage = 1
    private var providerPage = 1
    private var activeSearchQuery = ""
    private var activeSearchKind: MediaKind?
    private var activeProviderID: String?
    /// Random first AniList page for the current browse session so the anime
    /// catalog does not show the same 20 popularity-sorted titles every visit.
    private var catalogAnimeStartPage = 1
    /// Identifies the newest catalog request so a slower, superseded one cannot
    /// overwrite the results of the tab the user actually selected.
    private var catalogRequestID = 0

    private var tmdb: TMDBService {
        TMDBService(apiKey: settings.tmdbAPIKey, readAccessToken: settings.tmdbReadAccessToken)
    }

    var isTMDBConfigured: Bool { tmdb.isConfigured }

    /// Every saved title across all lists, newest first and de-duplicated. Kept
    /// computed so the Home rail, poster grids, and long-press menus keep working
    /// unchanged now that storage is multi-list.
    var library: [MediaItem] {
        var seen = Set<String>()
        return collections
            .flatMap(\.entries)
            .sorted { $0.addedAt > $1.addedAt }
            .compactMap { entry in
                seen.insert(entry.media.id).inserted ? entry.media : nil
            }
    }

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
        collections = Self.restoredCollections()
        history = Self.load([WatchEntry].self, key: "history") ?? []
        downloads = Self.load([DownloadEntry].self, key: "downloads") ?? []
        episodeStates = Self.load([String: EpisodeWatchState].self, key: "episodeStates") ?? [:]
        episodeOverrides = Self.load([String: EpisodeMetadataOverride].self, key: "episodeOverrides") ?? [:]
        metadataSources = Self.load([String: MetadataSourceMode].self, key: "metadataSources") ?? [:]

        // HLS downloads finish asynchronously on a shared session, so route its
        // progress and completion back into this store once, here.
        HLSDownloadManager.shared.onProgress = { [weak self] id, value in
            Task { @MainActor in self?.downloadProgress[id] = value }
        }
        HLSDownloadManager.shared.onFinish = { [weak self] id, location in
            Task { @MainActor in self?.finishHLSDownload(id: id, location: location) }
        }
        HLSDownloadManager.shared.onFailure = { [weak self] id, _ in
            Task { @MainActor in
                self?.pendingHLSDownloads[id] = nil
                self?.downloadProgress[id] = nil
            }
        }
    }

    func loadHome() async {
        guard !isLoadingHome else { return }
        isLoadingHome = true
        homeError = nil
        let started = Date()
        let hadContent = !homeItems.isEmpty
        do {
            homePage = 1
            // A different feed on every visit, so Home is never the same row of
            // titles twice in a row.
            homeFeed = settings.rotateHomeCatalog
                ? (HomeFeed.allCases.randomElement() ?? .pinned)
                : .pinned
            let results = try await tmdb.homeFeed(homeFeed, page: homePage)
            if !results.isEmpty { homeItems = results }
            await loadProviderLogosIfNeeded()
        } catch {
            homeError = error.localizedDescription
        }
        await holdPlaceholders(since: started, hadContent: hadContent)
        isLoadingHome = false
    }

    func loadMoreHome() async {
        guard !isLoadingMore, isTMDBConfigured else { return }
        isLoadingMore = true
        homePage += 1
        do {
            let more = try await tmdb.homeFeed(homeFeed, page: homePage)
            homeItems.append(contentsOf: more)
        } catch {
            homePage -= 1
        }
        isLoadingMore = false
    }

    /// Keeps the shimmering placeholders up for a beat even when the network
    /// answers instantly, so content never flashes in and out. Only the first load
    /// of a surface pays this cost: once content is on screen, a refresh resolves
    /// as fast as the network allows.
    private func holdPlaceholders(since start: Date, hadContent: Bool) async {
        guard !hadContent, settings.showLoadingPlaceholders else { return }
        let minimum = settings.minimumPlaceholderSeconds
        guard minimum > 0 else { return }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed < minimum else { return }
        try? await Task.sleep(nanoseconds: UInt64((minimum - elapsed) * 1_000_000_000))
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
        // Switching services must never leave the previous service's titles on
        // screen behind the new service's name.
        if activeProviderID != provider.id { providerItems = [] }
        let started = Date()
        let hadContent = !providerItems.isEmpty
        do {
            providerPage = 1
            activeProviderID = provider.id
            let items = try await tmdb.catalog(for: providerID, providerName: provider.name, page: providerPage)
            await holdPlaceholders(since: started, hadContent: hadContent)
            // A slower, superseded request must not overwrite the service the user
            // actually selected.
            if settings.selectedProvider == provider.name {
                providerItems = items
                hasMoreResults = items.count >= 20
                if items.isEmpty { providerError = "No titles were returned for this service in the US region." }
            }
        } catch {
            if settings.selectedProvider == provider.name {
                providerItems = []
                providerError = error.localizedDescription
            }
        }
        isLoadingProvider = false
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
        guard media.kind == .anime else { return media.metadata }
        // Fallback mode is remembered per title, so this only ever changes the
        // title the user switched.
        if metadataSource(for: media) == .fallback {
            return await animeFallback.metadata(malID: media.malID) ?? media.metadata
        }
        guard let aniListID = media.aniListID else { return media.metadata }
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
            var episodes: [EpisodeInfo] = []
            var resolvedCount = media.episodeCount ?? 0
            var anilistFailure: String?
            do {
                episodes = try await anilist.episodes(for: media)
                resolvedCount = max(resolvedCount, episodes.count)
            } catch {
                anilistFailure = error.localizedDescription
            }

            // AniList owns the numbering, the row order, and the MegaPlay URL.
            // The selected provider chain only adds the per-episode titles,
            // synopses, air dates, and artwork it publishes, and is skipped
            // entirely if it has nothing.
            let details: AnimeEpisodeDetails
            if metadataSource(for: media) == .fallback {
                details = await animeFallback.episodeDetails(malID: media.malID, title: media.title)
            } else if settings.kitsuEpisodeDetails {
                let kitsuDetails = await kitsu.episodeDetails(aniListID: media.aniListID, malID: media.malID, title: media.title)
                details = AnimeEpisodeDetails(episodes: kitsuDetails.episodes, reportedCount: kitsuDetails.reportedCount)
            } else {
                details = AnimeEpisodeDetails(episodes: [], reportedCount: nil)
            }
            if !details.episodes.isEmpty || (details.reportedCount ?? 0) > 0 {
                let expected = max(resolvedCount, max(details.reportedCount ?? 0, details.episodes.count))
                episodes = EpisodeDetailsMerger.merge(base: episodes, details: details.episodes, expectedCount: expected)
                resolvedCount = max(resolvedCount, episodes.count)
            }

            guard resolvedCount > 0 || !episodes.isEmpty else {
                episodeError = anilistFailure ?? "AniList returned no episode information for this title."
                return []
            }
            return [SeasonEpisodeInfo(season: 1, episodeCount: max(resolvedCount, episodes.count), episodes: episodes)]
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

    /// Loads page one of a browsable catalog for a Search/Discover tab. No query
    /// is required: movies and TV come from TMDB's popularity discover feed, anime
    /// from a different random AniList page on every visit, and "All" mixes
    /// trending movies/TV with anime.
    func loadCatalog(kind: MediaKind?) async {
        // Tab switches can overlap; the newest request wins and only it clears the
        // spinner, so tapping tabs quickly always lands on the right catalog.
        catalogRequestID += 1
        let requestID = catalogRequestID
        isSearching = true
        searchError = nil
        let started = Date()
        let hadContent = !searchResults.isEmpty
        if kind == nil || kind == .anime { animeError = nil }
        searchPage = 1
        activeSearchQuery = ""
        activeSearchKind = kind
        // AniList's empty-query search is always popularity page 1, so pick a
        // random page to keep the anime catalog varied between visits.
        catalogAnimeStartPage = Int.random(in: 1...80)
        hasMoreResults = true
        var results: [MediaItem] = []
        var failures: [String] = []

        if kind == nil {
            do { results += try await tmdb.trending(page: searchPage) }
            catch { failures.append(error.localizedDescription) }
            do { results += try await anilist.search(query: "", kind: .anime, page: catalogAnimeStartPage) }
            catch { failures.append("AniList: \(error.localizedDescription)") }
        } else if kind == .anime {
            do { results = try await anilist.search(query: "", kind: .anime, page: catalogAnimeStartPage) }
            catch { failures.append("AniList: \(error.localizedDescription)") }
        } else if let kind {
            do { results = try await tmdb.popular(kind: kind, page: searchPage) }
            catch { failures.append(error.localizedDescription) }
        }

        await loadProviderLogosIfNeeded()
        guard requestID == catalogRequestID else { return }
        searchResults = results
        if kind == .anime {
            animeResults = results.filter { $0.kind == .anime && $0.aniListID != nil && $0.tmdbID == nil }
            animeError = animeResults.isEmpty ? (failures.first ?? "AniList returned no titles.") : nil
        } else if kind == nil {
            animeResults = results.filter { $0.kind == .anime && $0.aniListID != nil && $0.tmdbID == nil }
            animeError = nil
        }
        if results.isEmpty {
            searchError = failures.first ?? "No titles were found for this catalog."
        }
        hasMoreResults = results.count >= 20
        await holdPlaceholders(since: started, hadContent: hadContent)
        isSearching = false
    }

    func loadAnimeCatalog() async {
        await loadCatalog(kind: .anime)
    }

    /// Fetches TMDB's official service logos once per launch. Failures are
    /// ignored so the tiles simply fall back to their monogram/asset logo.
    func loadProviderLogosIfNeeded() async {
        guard providerLogos.isEmpty else { return }
        guard let logos = try? await tmdb.providerLogos(), !logos.isEmpty else { return }
        providerLogos = logos
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
        guard !isLoadingMore, hasMoreResults else { return }
        isLoadingMore = true
        searchPage += 1
        var more: [MediaItem] = []
        do {
            if activeSearchQuery.isEmpty {
                // Browsing a catalog rather than running a typed query.
                if let kind = activeSearchKind, kind != .anime {
                    more = try await tmdb.popular(kind: kind, page: searchPage)
                } else {
                    if activeSearchKind == nil {
                        more += (try? await tmdb.trending(page: searchPage)) ?? []
                    }
                    more += try await anilist.search(query: "", kind: .anime, page: min(catalogAnimeStartPage + searchPage - 1, 240))
                }
            } else if activeSearchKind == .anime {
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

    // MARK: - Lists

    /// The list "Add to My List" targets: the built-in list when it exists.
    private var defaultCollectionID: String {
        collections.first(where: { $0.isBuiltIn })?.id ?? collections.first?.id ?? MediaCollection.builtInID
    }

    func collection(id: String) -> MediaCollection? { collections.first { $0.id == id } }

    @discardableResult
    func createCollection(named name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let collection = MediaCollection(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? "New List" : trimmed,
            artwork: CollectionArtwork(style: settings.listCoverStyle)
        )
        collections.append(collection)
        return collection.id
    }

    func renameCollection(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = trimmed
    }

    func deleteCollection(_ id: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }), !collections[index].isBuiltIn else { return }
        collections.remove(at: index)
    }

    func setArtworkStyle(_ style: CollectionArtwork.Style, for id: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].artwork.style = style
        // An automatic cover follows the list itself, so any pinned titles go.
        if style == .automatic { collections[index].artwork.mediaIDs = [] }
    }

    /// Adds or removes a title from a list's cover, honoring the style's slots.
    func toggleCoverMedia(_ mediaID: String, for id: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        let slots = max(collections[index].artwork.style.slotCount, 1)
        var ids = collections[index].artwork.mediaIDs
        if let position = ids.firstIndex(of: mediaID) {
            ids.remove(at: position)
        } else {
            ids.append(mediaID)
            if ids.count > slots { ids = Array(ids.suffix(slots)) }
        }
        collections[index].artwork.mediaIDs = ids
    }

    func setCustomArtwork(_ data: Data?, for id: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].artwork.customImageData = data
        if data != nil { collections[index].artwork.style = .custom }
    }

    /// Resets every cover to the style chosen in Settings → Lists.
    func resetAllCovers() {
        for index in collections.indices {
            collections[index].artwork = CollectionArtwork(style: settings.listCoverStyle)
        }
    }

    /// The titles a cover should draw, honoring the list's artwork style.
    func coverMedia(for collection: MediaCollection) -> [MediaItem] {
        switch collection.artwork.style {
        case .custom:
            return []
        case .automatic:
            return Array(collection.items.prefix(4))
        case .mosaic, .single:
            let byID = Dictionary(collection.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let chosen = collection.artwork.mediaIDs.compactMap { byID[$0] }
            guard !chosen.isEmpty else { return Array(collection.items.prefix(4)) }
            return collection.artwork.style == .single ? Array(chosen.prefix(1)) : Array(chosen.prefix(4))
        }
    }

    func reorderCollection(_ id: String, from source: IndexSet, to destination: Int) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].entries.move(fromOffsets: source, toOffset: destination)
    }

    func add(_ media: MediaItem, to collectionID: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        guard !collections[index].contains(media) else { return }
        collections[index].entries.insert(CollectionEntry(media: media), at: 0)
    }

    func remove(_ media: MediaItem, from collectionID: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[index].entries.removeAll { $0.media.id == media.id }
    }

    func toggle(_ media: MediaItem, in collectionID: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        if collections[index].contains(media) {
            collections[index].entries.removeAll { $0.media.id == media.id }
        } else {
            collections[index].entries.insert(CollectionEntry(media: media), at: 0)
        }
    }

    func isSaved(_ media: MediaItem, in collectionID: String) -> Bool {
        collection(id: collectionID)?.contains(media) ?? false
    }

    /// Renames a title inside one list only. `nil` restores its real name.
    func setAlias(_ alias: String?, for mediaID: String, in collectionID: String) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }),
              let entryIndex = collections[index].entries.firstIndex(where: { $0.media.id == mediaID }) else { return }
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        collections[index].entries[entryIndex].alias = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    func collectionsContaining(_ media: MediaItem) -> [MediaCollection] {
        collections.filter { $0.contains(media) }
    }

    /// Short "where is this saved" line used by the detail screen's list button.
    func librarySummary(for media: MediaItem) -> String {
        let names = collectionsContaining(media).map(\.name)
        switch names.count {
        case 0: return "Save for later"
        case 1: return "In \(names[0])"
        default: return "In \(names.count) lists"
        }
    }

    func toggleLibrary(_ media: MediaItem) { toggle(media, in: defaultCollectionID) }

    func isInLibrary(_ media: MediaItem) -> Bool { library.contains(media) }

    /// One download per movie or episode, so the same title can never be saved
    /// twice under a different key.
    static func downloadID(for media: MediaItem, episode: Int?) -> String {
        "\(media.id)-\(episode.map(String.init) ?? "movie")"
    }

    func isDownloaded(media: MediaItem, episode: Int? = nil) -> Bool {
        downloads.contains { $0.id == Self.downloadID(for: media, episode: episode) }
    }

    func isDownloading(media: MediaItem, episode: Int? = nil) -> Bool {
        downloadProgress[Self.downloadID(for: media, episode: episode)] != nil
    }

    /// Saves a directly addressable stream for offline playback. A direct MP4 is
    /// fetched to a file; an HLS stream is handed to AVAssetDownloadTask and
    /// recorded when it finishes. Embeds have no downloadable URL and return early.
    func download(media: MediaItem, format: PlaybackFormat, episode: Int? = nil) async throws {
        guard settings.downloadsEnabled,
              let sourceURL = AuthorizedDownloadManager.downloadableURL(for: format) else { return }
        let id = Self.downloadID(for: media, episode: episode)

        if AuthorizedDownloadManager.isHLS(format) {
            pendingHLSDownloads[id] = (media, episode)
            downloadProgress[id] = 0
            HLSDownloadManager.shared.start(id: id, url: sourceURL)
            return
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return }
        let fileName = AuthorizedDownloadManager.fileName(for: media, episode: episode)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        let entry = DownloadEntry(id: id, media: media, fileName: fileName, localURL: destination, downloadedAt: Date(), episode: episode)
        downloads.removeAll { $0.id == entry.id }
        downloads.insert(entry, at: 0)
    }

    /// Records a finished HLS asset, keeping a bookmark because Apple's downloader
    /// relocates the bundle. Called from HLSDownloadManager's completion callback.
    private func finishHLSDownload(id: String, location: URL) {
        defer {
            pendingHLSDownloads[id] = nil
            downloadProgress[id] = nil
        }
        guard let pending = pendingHLSDownloads[id] else { return }
        let bookmark = try? location.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let entry = DownloadEntry(
            id: id,
            media: pending.media,
            fileName: AuthorizedDownloadManager.fileName(for: pending.media, episode: pending.episode),
            localURL: location,
            downloadedAt: Date(),
            episode: pending.episode,
            isHLS: true,
            bookmarkData: bookmark
        )
        downloads.removeAll { $0.id == id }
        downloads.insert(entry, at: 0)
    }

    func removeDownload(_ entry: DownloadEntry) {
        if entry.isHLS == true { HLSDownloadManager.shared.cancel(id: entry.id) }
        try? FileManager.default.removeItem(at: entry.localURL)
        pendingHLSDownloads[entry.id] = nil
        downloadProgress[entry.id] = nil
        downloads.removeAll { $0.id == entry.id }
    }

    func recordWatch(_ media: MediaItem, progress: Double = 0) {
        let entry = WatchEntry(id: media.id, media: media, progress: progress, lastPlayed: Date())
        history.removeAll { $0.id == entry.id }
        history.insert(entry, at: 0)
    }

    /// Records a title in Continue Watching and remembers which episode is being
    /// watched, so Continue Watching can name it and offer the right resume point.
    func recordWatch(_ media: MediaItem, season: Int, episode: Int) {
        // A film has no episodes, so it only gets the title-level entry; otherwise
        // Continue Watching would label it "S1 · Episode 1".
        guard media.isEpisodic else {
            recordWatch(media)
            return
        }
        // Touch the episode first: it becomes the title's latest, so the title-level
        // progress recorded below describes the episode that is actually playing.
        updateEpisodeState(mediaID: media.id, season: season, episode: episode)
        recordWatch(media, progress: resumeProgress(for: media))
    }

    func isInHistory(_ media: MediaItem) -> Bool {
        history.contains { $0.id == media.id }
    }

    // MARK: - Episode watch state

    func episodeState(mediaID: String, season: Int, episode: Int) -> EpisodeWatchState? {
        episodeStates[EpisodeWatchState.key(mediaID: mediaID, season: season, episode: episode)]
    }

    func episodeState(media: MediaItem, season: Int, episode: Int) -> EpisodeWatchState? {
        episodeState(mediaID: media.id, season: season, episode: episode)
    }

    func isWatched(media: MediaItem, season: Int, episode: Int) -> Bool {
        episodeState(media: media, season: season, episode: episode)?.watched ?? false
    }

    /// 0...1 progress of one episode, used by its row and its detail screen.
    func episodeProgress(media: MediaItem, season: Int, episode: Int) -> Double {
        episodeState(media: media, season: season, episode: episode)?.progress ?? 0
    }

    /// The seconds the player should resume from, or 0 when the episode is fresh
    /// or was already finished.
    func resumeSeconds(for media: MediaItem, season: Int, episode: Int) -> Double {
        guard let state = episodeState(media: media, season: season, episode: episode), state.isResumable else { return 0 }
        return state.resumeSeconds
    }

    func setWatched(_ watched: Bool, media: MediaItem, season: Int, episode: Int) {
        updateEpisodeState(
            mediaID: media.id,
            season: season,
            episode: episode,
            watched: watched,
            progress: watched ? 1 : 0,
            resumeSeconds: 0
        )
    }

    func toggleWatched(media: MediaItem, season: Int, episode: Int) {
        setWatched(!isWatched(media: media, season: season, episode: episode), media: media, season: season, episode: episode)
    }

    /// Marks this episode and every earlier one in the season watched, so catching
    /// up on a long-running show is one long-press instead of a hundred taps.
    func markPreviousWatched(media: MediaItem, season: Int, episode: Int, in episodes: [EpisodeInfo]) {
        for row in episodes where row.number <= episode {
            updateEpisodeState(mediaID: media.id, season: season, episode: row.number, watched: true, progress: 1, resumeSeconds: 0)
        }
    }

    func watchedCount(media: MediaItem, season: Int, episodes: [EpisodeInfo]) -> Int {
        episodes.reduce(0) { $0 + (isWatched(media: media, season: season, episode: $1.number) ? 1 : 0) }
    }

    /// Stores where playback is, both as a fraction (for the UI) and in seconds
    /// (so the player can resume mid-episode instead of restarting it). A duration
    /// of 0 means the embed reported a position but no length, which is still
    /// enough to resume from.
    func recordEpisodeProgress(seconds: Double, duration: Double, media: MediaItem, season: Int, episode: Int) {
        // Films keep title-level history only: there is no "S1 · Episode 1" to resume.
        guard media.isEpisodic else { return }
        guard seconds.isFinite, seconds >= 0 else { return }
        let fraction = (duration.isFinite && duration > 0) ? min(max(seconds / duration, 0), 1) : nil
        updateEpisodeState(
            mediaID: media.id,
            season: season,
            episode: episode,
            progress: fraction,
            resumeSeconds: seconds
        )
    }

    /// Called when an episode finishes. Honors the "mark watched when finished"
    /// setting so someone who prefers manual tracking is never overruled.
    func markEpisodeFinished(media: MediaItem, season: Int, episode: Int) {
        guard media.isEpisodic, settings.autoMarkWatchedOnFinish else { return }
        setWatched(true, media: media, season: season, episode: episode)
    }

    /// The episode a title was last touched on, which is what Continue Watching
    /// names and resumes.
    func latestEpisodeState(for mediaID: String) -> EpisodeWatchState? {
        episodeStates.values.filter { $0.mediaID == mediaID }.max { $0.updatedAt < $1.updatedAt }
    }

    /// 0...1 progress of a title's most recent episode, for Continue Watching. A
    /// film falls back to its title-level entry, which is all it has.
    func resumeProgress(for media: MediaItem) -> Double {
        if let state = latestEpisodeState(for: media.id) {
            return state.watched ? 1 : state.progress
        }
        return history.first { $0.id == media.id }?.progress ?? 0
    }

    /// "S1 · Episode 4" for a title with a remembered episode, so a rail can say
    /// what "Continue" actually continues.
    func resumeLabel(for media: MediaItem) -> String? {
        guard let state = latestEpisodeState(for: media.id) else { return nil }
        return "S\(state.season) · Episode \(state.episode)"
    }

    func hasResumePosition(for media: MediaItem) -> Bool {
        episodeStates.values.contains { $0.mediaID == media.id && $0.isResumable }
    }

    private func updateEpisodeState(
        mediaID: String,
        season: Int,
        episode: Int,
        watched: Bool? = nil,
        progress: Double? = nil,
        resumeSeconds: Double? = nil
    ) {
        let key = EpisodeWatchState.key(mediaID: mediaID, season: season, episode: episode)
        var state = episodeStates[key] ?? EpisodeWatchState(mediaID: mediaID, season: season, episode: episode)
        if let watched { state.watched = watched }
        if let progress { state.progress = min(max(progress, 0), 1) }
        if let resumeSeconds { state.resumeSeconds = max(resumeSeconds, 0) }
        // Finishing an episode clears its resume point; it is the one state that
        // always agrees with itself.
        if state.watched {
            state.progress = 1
            state.resumeSeconds = 0
        }
        state.updatedAt = Date()
        episodeStates[key] = state
    }

    // MARK: - Episode metadata overrides

    func hasOverride(media: MediaItem, season: Int, episode: Int) -> Bool {
        episodeOverrides[EpisodeWatchState.key(mediaID: media.id, season: season, episode: episode)] != nil
    }

    var episodeOverrideCount: Int { episodeOverrides.count }

    func episodeOverrideCount(for media: MediaItem) -> Int {
        episodeOverrides.values.filter { $0.mediaID == media.id }.count
    }

    /// Saves the user's edits to one episode. Passing blanks (or clearing every
    /// field) removes the override so the provider's own data shows again.
    func setOverride(media: MediaItem, season: Int, episode: Int, name: String?, overview: String?, imageURL: URL?) {
        let key = EpisodeWatchState.key(mediaID: media.id, season: season, episode: episode)
        let override = EpisodeMetadataOverride(
            mediaID: media.id,
            season: season,
            episode: episode,
            name: Self.trimmedOrNil(name),
            overview: Self.trimmedOrNil(overview),
            imageURL: imageURL
        )
        if override.isEmpty {
            episodeOverrides.removeValue(forKey: key)
        } else {
            episodeOverrides[key] = override
        }
    }

    func clearOverride(media: MediaItem, season: Int, episode: Int) {
        episodeOverrides.removeValue(forKey: EpisodeWatchState.key(mediaID: media.id, season: season, episode: episode))
    }

    /// Drops every edit for one title and reports how many were removed.
    @discardableResult
    func clearOverrides(for media: MediaItem) -> Int {
        let keys = episodeOverrides.filter { $0.value.mediaID == media.id }.map(\.key)
        keys.forEach { episodeOverrides.removeValue(forKey: $0) }
        return keys.count
    }

    func clearAllEpisodeOverrides() {
        episodeOverrides.removeAll()
    }

    /// Applies the user's saved edits to one episode row.
    func applyOverride(to episode: EpisodeInfo, media: MediaItem, season: Int) -> EpisodeInfo {
        guard let override = episodeOverrides[EpisodeWatchState.key(mediaID: media.id, season: season, episode: episode.number)] else { return episode }
        return episode.applying(name: override.name, overview: override.overview, imageURL: override.imageURL)
    }

    /// Applies the user's saved edits to a whole catalog.
    func applyOverrides(to seasons: [SeasonEpisodeInfo], media: MediaItem) -> [SeasonEpisodeInfo] {
        guard !episodeOverrides.isEmpty else { return seasons }
        return seasons.map { season in
            var updated = season
            updated.episodes = season.episodes.map { applyOverride(to: $0, media: media, season: season.season) }
            return updated
        }
    }

    private static func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Per-title metadata source

    func metadataSource(for media: MediaItem) -> MetadataSourceMode {
        metadataSources[media.id] ?? .aniList
    }

    /// Switches one title between AniList and the fallback provider chain. The
    /// choice is remembered for that title only, so the rest of the library is
    /// untouched, and it is sticky until the user changes it again.
    @discardableResult
    func setMetadataSource(_ mode: MetadataSourceMode, for media: MediaItem) -> MetadataSourceMode {
        if mode == .aniList {
            metadataSources.removeValue(forKey: media.id)
        } else {
            metadataSources[media.id] = mode
        }
        return mode
    }

    @discardableResult
    func toggleMetadataSource(for media: MediaItem) -> MetadataSourceMode {
        setMetadataSource(metadataSource(for: media) == .aniList ? .fallback : .aniList, for: media)
    }

    // MARK: - AI-assisted metadata

    /// True when the user has finished configuring an OpenAI-compatible provider.
    var isAIConfigured: Bool {
        settings.aiMetadataEnabled
            && !settings.aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.aiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && AIMetadataService.endpoint(baseURL: settings.aiBaseURL) != nil
    }

    /// Asks the configured model for a whole season's episode metadata and stores
    /// it as local overrides — the exact mechanism the manual editor uses, just
    /// automated. Provider rows keep any field they already published, and an
    /// episode the user edited by hand is never overwritten.
    @discardableResult
    func generateSeasonMetadata(media: MediaItem, season: Int, episodes providerEpisodes: [EpisodeInfo]) async throws -> Int {
        let numbers = providerEpisodes.map(\.number)
        guard !numbers.isEmpty else { return 0 }
        let generated = try await AIMetadataService().episodes(
            settings: settings,
            media: media,
            season: season,
            episodeNumbers: numbers
        )
        let byNumber = Dictionary(generated.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        var applied = 0
        for provider in providerEpisodes {
            guard let generated = byNumber[provider.number] else { continue }
            let key = EpisodeWatchState.key(mediaID: media.id, season: season, episode: provider.number)
            guard episodeOverrides[key] == nil else { continue }
            let publishedName = provider.hasPublishedName ? provider.name : nil
            let publishedOverview = Self.trimmedOrNil(provider.overview)
            let name = Self.trimmedOrNil(generated.name)
            let overview = Self.trimmedOrNil(generated.overview)
            let nameValue = name == publishedName ? nil : name
            let overviewValue = overview == publishedOverview ? nil : overview
            let imageValue = generated.imageURL == provider.imageURL ? nil : generated.imageURL
            guard nameValue != nil || overviewValue != nil || imageValue != nil else { continue }
            setOverride(media: media, season: season, episode: provider.number, name: nameValue, overview: overviewValue, imageURL: imageValue)
            applied += 1
        }
        return applied
    }

    /// Removes a title from Continue Watching / watch history only. It stays in My List.
    func removeFromHistory(_ media: MediaItem) {
        history.removeAll { $0.id == media.id }
    }

    func clearHistory() {
        history.removeAll()
    }

    func addToLibrary(_ media: MediaItem) { add(media, to: defaultCollectionID) }

    func removeFromLibrary(_ media: MediaItem) { remove(media, from: defaultCollectionID) }

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
            .animeCatalog: await AnikotoCache.cachedByteCount(),
            .episodeDetails: await KitsuCacheInfo.approximateByteCount()
        ]
    }

    func clearAllCache() async {
        // Keep removal scoped to transient caches so Documents/downloads and Library/preferences survive.
        URLCache.shared.removeAllCachedResponses()
        await AnikotoCache.clear()
        await KitsuCacheInfo.clear()
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

    /// Restores the saved lists, migrating the pre-multi-list single "library"
    /// value into the built-in list the first time the app runs after the update.
    private static func restoredCollections() -> [MediaCollection] {
        if let stored = load([MediaCollection].self, key: "collections"), !stored.isEmpty {
            var restored = stored
            if !restored.contains(where: { $0.isBuiltIn }) {
                restored.insert(MediaCollection.builtIn, at: 0)
            }
            return restored
        }
        let legacy = load([MediaItem].self, key: "library") ?? []
        var builtIn = MediaCollection.builtIn
        builtIn.entries = legacy.map { CollectionEntry(media: $0) }
        return [builtIn]
    }
}
