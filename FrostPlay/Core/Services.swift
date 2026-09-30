import Foundation

enum FrostPlayServiceError: LocalizedError {
    case missingTMDBCredential
    case invalidResponse
    case decodingFailed
    case unsupportedMediaKind

    var errorDescription: String? {
        switch self {
        case .missingTMDBCredential:
            return "TMDB is not configured. Add or replace the key in Settings → Catalog & API to browse movies and TV."
        case .invalidResponse:
            return "The service returned an invalid response."
        case .decodingFailed:
            return "The service returned data FrostPlay could not read."
        case .unsupportedMediaKind:
            return "This catalog only handles movies and TV shows."
        }
    }
}

protocol MetadataService {
    func search(query: String, kind: MediaKind?, page: Int) async throws -> [MediaItem]
}

/// The Home catalog feeds. Home picks one at random on every visit (unless
/// rotation is turned off in Settings) so the screen is never the same row of
/// titles twice in a row.
enum HomeFeed: String, CaseIterable, Identifiable {
    case trendingToday
    case trendingThisWeek
    case popularMovies
    case popularShows
    case topRatedMovies
    case topRatedShows

    var id: String { rawValue }

    /// Shown above the rail so the current pick is never a mystery.
    var title: String {
        switch self {
        case .trendingToday: return "Trending Today"
        case .trendingThisWeek: return "Trending This Week"
        case .popularMovies: return "Popular Movies"
        case .popularShows: return "Popular Shows"
        case .topRatedMovies: return "Top Rated Movies"
        case .topRatedShows: return "Top Rated Shows"
        }
    }

    var path: String {
        switch self {
        case .trendingToday: return "trending/all/day"
        case .trendingThisWeek: return "trending/all/week"
        case .popularMovies, .topRatedMovies: return "discover/movie"
        case .popularShows, .topRatedShows: return "discover/tv"
        }
    }

    var sortBy: String? {
        switch self {
        case .trendingToday, .trendingThisWeek: return nil
        case .popularMovies, .popularShows: return "popularity.desc"
        case .topRatedMovies, .topRatedShows: return "vote_average.desc"
        }
    }

    var fallbackKind: MediaKind? {
        switch self {
        case .trendingToday, .trendingThisWeek: return nil
        case .popularMovies, .topRatedMovies: return .movie
        case .popularShows, .topRatedShows: return .tv
        }
    }

    /// What Home uses when rotation is switched off, so the pinned default is
    /// still a sensible catalog.
    static let pinned: HomeFeed = .trendingThisWeek
}

struct TMDBService: MetadataService {
    let apiKey: String
    let readAccessToken: String
    let session: URLSession = .shared

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !readAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func search(query: String, kind: MediaKind?, page: Int = 1) async throws -> [MediaItem] {
        guard kind != .anime else { throw FrostPlayServiceError.unsupportedMediaKind }
        guard isConfigured else { throw FrostPlayServiceError.missingTMDBCredential }
        let endpoint: String
        if let kind {
            guard kind == .movie || kind == .tv else { throw FrostPlayServiceError.unsupportedMediaKind }
            endpoint = kind == .tv ? "search/tv" : "search/movie"
        } else {
            return try await searchMulti(query: query, page: page)
        }

        let data = try await request(path: endpoint, query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "page", value: String(page))
        ])
        let payload = try decode(TMDBSearchResponse.self, from: data)
        return payload.results.compactMap { makeMediaItem($0, fallbackKind: kind) }
    }

    func searchMulti(query: String, page: Int = 1) async throws -> [MediaItem] {
        guard isConfigured else { throw FrostPlayServiceError.missingTMDBCredential }
        let data = try await request(path: "search/multi", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "page", value: String(page))
        ])
        let payload = try decode(TMDBSearchResponse.self, from: data)
        return payload.results.compactMap { makeMediaItem($0, fallbackKind: nil) }
    }

    func trending(page: Int = 1) async throws -> [MediaItem] {
        guard isConfigured else { throw FrostPlayServiceError.missingTMDBCredential }
        let data = try await request(path: "trending/all/week", query: [URLQueryItem(name: "page", value: String(page))])
        let payload = try decode(TMDBSearchResponse.self, from: data)
        return payload.results.compactMap { makeMediaItem($0, fallbackKind: nil) }
    }

    /// One of the rotating Home feeds. The trending feeds already report a media
    /// type per result, so only the discover feeds need a fallback kind.
    func homeFeed(_ feed: HomeFeed, page: Int = 1) async throws -> [MediaItem] {
        guard isConfigured else { throw FrostPlayServiceError.missingTMDBCredential }
        var query = [URLQueryItem(name: "page", value: String(page))]
        if let sortBy = feed.sortBy {
            query.append(URLQueryItem(name: "sort_by", value: sortBy))
            query.append(URLQueryItem(name: "include_adult", value: "false"))
            if feed == .topRatedMovies || feed == .topRatedShows {
                // Without a vote floor "top rated" surfaces titles with one vote.
                query.append(URLQueryItem(name: "vote_count.gte", value: "500"))
            }
        }
        let data = try await request(path: feed.path, query: query)
        return try decode(TMDBSearchResponse.self, from: data).results.compactMap { makeMediaItem($0, fallbackKind: feed.fallbackKind) }
    }

    /// Popular titles for one kind with no query and no service filter. Backs the
    /// browsable Search and Discover tabs, which must load a catalog on tap
    /// instead of requiring a typed query.
    func popular(kind: MediaKind, page: Int = 1) async throws -> [MediaItem] {
        guard kind == .movie || kind == .tv else { throw FrostPlayServiceError.unsupportedMediaKind }
        guard isConfigured else { throw FrostPlayServiceError.missingTMDBCredential }
        let data = try await request(path: kind == .tv ? "discover/tv" : "discover/movie", query: [
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "page", value: String(page))
        ])
        return try decode(TMDBSearchResponse.self, from: data).results.compactMap { makeMediaItem($0, fallbackKind: kind) }
    }

    /// Maps TMDB's regional watch-provider IDs to the official service logos TMDB
    /// hosts, so every Browse-by-Service tile shows the real logo instead of a
    /// monogram. Both the movie and TV provider lists are merged because some
    /// services only appear in one of them.
    func providerLogos(region: String = "US") async throws -> [Int: URL] {
        guard isConfigured else { throw FrostPlayServiceError.missingTMDBCredential }
        var logos: [Int: URL] = [:]
        for path in ["watch/providers/movie", "watch/providers/tv"] {
            guard let data = try? await request(path: path, query: [URLQueryItem(name: "watch_region", value: region)]),
                  let payload = try? decode(TMDBProviderResponse.self, from: data) else { continue }
            for provider in payload.results {
                guard logos[provider.providerID] == nil,
                      let logoPath = provider.logoPath,
                      let url = URL(string: "https://image.tmdb.org/t/p/w185\(logoPath)") else { continue }
                logos[provider.providerID] = url
            }
        }
        return logos
    }

    func catalog(for providerID: Int, providerName: String, region: String = "US", page: Int = 1) async throws -> [MediaItem] {
        guard isConfigured else { throw FrostPlayServiceError.missingTMDBCredential }
        async let movies = discover(path: "discover/movie", providerID: providerID, region: region, page: page)
        async let shows = discover(path: "discover/tv", providerID: providerID, region: region, page: page)
        let movieResults = try await movies
        let showResults = try await shows
        let movieItems = movieResults.compactMap { makeMediaItem($0, fallbackKind: .movie, providerName: providerName) }
        let showItems = showResults.compactMap { makeMediaItem($0, fallbackKind: .tv, providerName: providerName) }
        return movieItems + showItems
    }

    private func discover(path: String, providerID: Int, region: String, page: Int) async throws -> [TMDBResult] {
        let data = try await request(path: path, query: [
            URLQueryItem(name: "with_watch_providers", value: String(providerID)),
            URLQueryItem(name: "watch_region", value: region),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "page", value: String(page))
        ])
        return try decode(TMDBSearchResponse.self, from: data).results
    }

    func seasons(for tvID: Int) async throws -> [SeasonEpisodeInfo] {
        guard isConfigured else { throw FrostPlayServiceError.missingTMDBCredential }
        let data = try await request(path: "tv/\(tvID)", query: [])
        let payload = try decode(TMDBTVDetailsResponse.self, from: data)
        var seasons: [SeasonEpisodeInfo] = []
        for season in payload.seasons where season.seasonNumber > 0 && season.episodeCount > 0 {
            let episodeData = try? await request(path: "tv/\(tvID)/season/\(season.seasonNumber)", query: [])
            let episodePayload = episodeData.flatMap { try? decode(TMDBSeasonDetailResponse.self, from: $0) }
            let episodes = episodePayload?.episodes.map { episode in
                EpisodeInfo(number: episode.episodeNumber, name: episode.name, overview: episode.overview ?? "", airDate: episode.airDate, imageURL: episode.stillPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w300\($0)") })
            } ?? []
            seasons.append(SeasonEpisodeInfo(season: season.seasonNumber, episodeCount: season.episodeCount, episodes: episodes))
        }
        return seasons
    }

    private func request(path: String, query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(string: "https://api.themoviedb.org/3/\(path)")!
        var queryItems = query
        if !apiKey.isEmpty {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        if !readAccessToken.isEmpty {
            request.setValue("Bearer \(readAccessToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw FrostPlayServiceError.invalidResponse
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw FrostPlayServiceError.decodingFailed }
    }

    private func makeMediaItem(_ result: TMDBResult, fallbackKind: MediaKind?, providerName: String? = nil) -> MediaItem? {
        let kind: MediaKind
        let mediaType = result.mediaType ?? fallbackKind?.rawValue ?? ""
        switch mediaType {
        case "movie": kind = .movie
        case "tv": kind = .tv
        default: return nil
        }
        return MediaItem(
            id: "tmdb-\(result.id)-\(kind.rawValue)",
            title: result.title ?? result.name ?? "Untitled",
            overview: result.overview ?? "",
            posterURL: result.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") },
            backdropURL: result.backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280\($0)") },
            kind: kind,
            tmdbID: result.id,
            aniListID: nil,
            malID: nil,
            providerNames: providerName.map { [$0] } ?? [PlaybackSource.moviesAPI.rawValue],
            year: (result.releaseDate ?? result.firstAirDate)?.prefix(4).description,
            episodeCount: nil
        )
    }
}

enum MegaPlayURL {
    static func validated(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "megaplay.buzz" || host.hasSuffix(".megaplay.buzz") else { return nil }
        return url
    }

    static func validated(_ url: URL?) -> URL? {
        guard let url else { return nil }
        return validated(url.absoluteString)
    }
}

/// Builds the documented MegaPlay embed URLs FrostPlay plays anime with.
///
/// MegaPlay publishes three embed routes: a catalog/episode-id route
/// (`/stream/s-2/{embed-id}/{language}`) plus AniList- and MAL-addressed routes.
/// FrostPlay addresses MegaPlay with the AniList ID first and the MAL ID second,
/// so playback is derived straight from the IDs AniList already gave us instead
/// of resolving Anikoto's internal catalog ID out of its bounded "recent" feed.
/// See https://megaplay.buzz/api.
enum MegaPlayEmbed {
    static func url(media: MediaItem, episode: Int, language: String) -> URL? {
        let languagePath = language.lowercased() == "dub" ? "dub" : "sub"
        let number = max(episode, 1)
        if let aniListID = media.aniListID {
            return MegaPlayURL.validated("https://megaplay.buzz/stream/ani/\(aniListID)/\(number)/\(languagePath)")
        }
        if let malID = media.malID {
            return MegaPlayURL.validated("https://megaplay.buzz/stream/mal/\(malID)/\(number)/\(languagePath)")
        }
        return nil
    }
}

fileprivate struct AnimeStreamEpisode {
    let number: Int
    let playbackURL: URL?
}

private actor AnikotoRecentPageCache {
    static let shared = AnikotoRecentPageCache()
    private var pages: [String: Data] = [:]

    func data(for key: String) -> Data? { pages[key] }
    func store(_ data: Data, for key: String) { pages[key] = data }
    func cachedByteCount() -> Int { pages.values.reduce(0) { $0 + $1.count } }
    func clear() { pages.removeAll() }
}

enum AnikotoCache {
    static func cachedByteCount() async -> Int {
        await AnikotoRecentPageCache.shared.cachedByteCount()
    }

    static func clear() async {
        await AnikotoRecentPageCache.shared.clear()
    }
}

private actor AnikotoRequestThrottle {
    static let shared = AnikotoRequestThrottle()
    private var nextRequestAt = Date.distantPast

    func waitForTurn() async throws {
        let now = Date()
        let delay = max(0, nextRequestAt.timeIntervalSince(now))
        nextRequestAt = max(now, nextRequestAt).addingTimeInterval(2.1)
        if delay > 0 {
            try await Task.sleep(for: .milliseconds(Int64((delay * 1_000).rounded(.up))))
        }
    }
}

struct AnikotoService {
    private let session: URLSession = .shared
    private let baseURL = URL(string: "https://anikotoapi.site")!

    // Anikoto resolves only the MegaPlay URL; AniList owns anime display metadata.
    fileprivate func episodes(for media: MediaItem, language: String = "sub") async throws -> [AnimeStreamEpisode] {
        guard media.kind == .anime else { return [] }
        let series = try await resolveSeries(for: media)
        let preferredLanguage = language.lowercased() == "dub" ? "dub" : "sub"
        return series.episodes.compactMap { episode in
            guard let number = episode.number else { return nil }
            // Last-resort path for titles with no AniList/MAL ID. FrostPlay normally
            // addresses MegaPlay directly by ID (see MegaPlayEmbed), so Anikoto's
            // catalog embed id is only needed when neither external ID is known.
            let languageURL = preferredLanguage == "dub"
                ? (episode.embedURL?.dub ?? episode.embedURL?.sub)
                : (episode.embedURL?.sub ?? episode.embedURL?.dub)
            return AnimeStreamEpisode(
                number: number,
                playbackURL: MegaPlayURL.validated(languageURL)
            )
        }
    }

    private func resolveSeries(for media: MediaItem) async throws -> AnikotoSeries {
        // Anikoto's documented series endpoint uses its own catalog ID, not the
        // AniList or MAL ID. Resolve the internal ID from its catalog's external IDs.
        let wantedTitles = Set([
            media.title,
            media.title.replacingOccurrences(of: "&amp;", with: "&")
        ].map(normalized))
        // The endpoint caps per_page at 100. Recent titles are near the front, while
        // older catalog entries can be many pages deep. This is only a last-resort
        // fallback for titles with no AniList/MAL ID, so keep it tightly bounded.
        // Cache pages per app session and throttle all Anikoto requests to remain
        // under its published request limit.
        let providerPage = 1...10
        for page in providerPage {
            if Task.isCancelled { throw CancellationError() }
            let response = try await fetchRecent(page: page, perPage: 100)
            let matches = response.data.filter { row in
                let aniListMatch = media.aniListID.map { row.aniID?.value == $0 } ?? false
                let malMatch = media.malID.map { row.malID?.value == $0 } ?? false
                let titleMatch = media.aniListID == nil && media.malID == nil && row.aniID == nil && row.malID == nil && [row.title, row.alternative, row.titles, row.native]
                    .compactMap { $0 }
                    .flatMap { $0.split(separator: ",").map(String.init) }
                    .contains { wantedTitles.contains(normalized($0)) }
                if media.aniListID != nil {
                    return aniListMatch || (row.aniID == nil && malMatch)
                }
                if media.malID != nil {
                    return malMatch
                }
                return titleMatch
            }
            for match in matches {
                if let series = try? await fetchSeries(id: String(match.id)), series.anime.matches(media: media) {
                    return series
                }
            }
            // The recent endpoint exposes a bounded feed, not a reliable full-catalog
            // search. Stop when this page has no records rather than stalling UI flows
            // behind dozens of throttled requests for older titles.
            if response.data.isEmpty { break }
            // Continue through its reported pages, but keep stream lookup bounded.
            let total = response.pagination?.total ?? response.data.count
            let pageCount = min((total + 99) / 100, 10)
            if page >= pageCount { break }
        }
        throw FrostPlayServiceError.invalidResponse
    }

    private func fetchSeries(id: String) async throws -> AnikotoSeries {
        try await AnikotoRequestThrottle.shared.waitForTurn()
        let data = try await request(path: "series/\(id)")
        let response = try JSONDecoder().decode(AnikotoSeriesResponse.self, from: data)
        guard response.ok else { throw FrostPlayServiceError.invalidResponse }
        return response.data
    }

    private func fetchRecent(page: Int, perPage: Int = 100) async throws -> AnikotoRecentResponse {
        let cacheKey = "\(page):\(perPage)"
        if let cached = await AnikotoRecentPageCache.shared.data(for: cacheKey) {
            return try JSONDecoder().decode(AnikotoRecentResponse.self, from: cached)
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("recent-anime"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        try await AnikotoRequestThrottle.shared.waitForTurn()
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw FrostPlayServiceError.invalidResponse
        }
        await AnikotoRecentPageCache.shared.store(data, for: cacheKey)
        return try JSONDecoder().decode(AnikotoRecentResponse.self, from: data)
    }

    private func request(path: String, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw FrostPlayServiceError.invalidResponse
        }
        return data
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}

private struct AnikotoSeriesResponse: Decodable {
    let ok: Bool
    let data: AnikotoSeries
}

private struct AnikotoRecentResponse: Decodable {
    let data: [AnikotoRecentAnime]
    let pagination: Pagination?

    enum CodingKeys: String, CodingKey {
        case data, pagination
    }

    struct Pagination: Decodable {
        let total: Int?

        enum CodingKeys: String, CodingKey {
            case total
        }
    }
}

private struct AnikotoRecentAnime: Decodable {
    let id: Int
    let title: String
    let alternative: String?
    let titles: String?
    let native: String?
    let aniID: FlexibleInt?
    let malID: FlexibleInt?

    enum CodingKeys: String, CodingKey {
        case id, title, alternative, titles, native
        case aniID = "ani_id"
        case malID = "mal_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        alternative = try container.decodeIfPresent(String.self, forKey: .alternative)
        titles = try container.decodeIfPresent(String.self, forKey: .titles)
        native = try container.decodeIfPresent(String.self, forKey: .native)
        // Anikoto uses empty strings for missing external IDs. Treat those as nil
        // instead of failing to decode the entire page of otherwise valid records.
        aniID = try? container.decode(FlexibleInt.self, forKey: .aniID)
        malID = try? container.decode(FlexibleInt.self, forKey: .malID)
    }
}

private struct AnikotoAnime: Decodable {
    let id: Int?
    let aniID: FlexibleInt?
    let malID: FlexibleInt?
    let title: String?
    let alternative: String?
    let titles: String?
    let native: String?

    enum CodingKeys: String, CodingKey {
        case id, title, alternative, titles, native
        case aniID = "ani_id"
        case malID = "mal_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        aniID = try? container.decode(FlexibleInt.self, forKey: .aniID)
        malID = try? container.decode(FlexibleInt.self, forKey: .malID)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        alternative = try container.decodeIfPresent(String.self, forKey: .alternative)
        titles = try container.decodeIfPresent(String.self, forKey: .titles)
        native = try container.decodeIfPresent(String.self, forKey: .native)
    }

    func matches(media: MediaItem) -> Bool {
        if let requestedAniListID = media.aniListID {
            if let aniID { return aniID.value == requestedAniListID }
            return media.malID.map { malID?.value == $0 } ?? false
        }
        if let requestedMALID = media.malID {
            return malID?.value == requestedMALID
        }
        let wanted = normalized(media.title)
        return [title, alternative, titles, native].compactMap { $0 }
            .flatMap { $0.split(separator: ",").map(String.init) }
            .contains { normalized($0) == wanted }
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}

private struct AnikotoSeries: Decodable {
    let anime: AnikotoAnime
    let episodes: [AnikotoEpisode]
}

private struct AnikotoEpisode: Decodable {
    let number: Int?
    let embedURL: AnikotoEmbedURL?

    enum CodingKeys: String, CodingKey {
        case number
        case embedURL = "embed_url"
    }
}

private struct AnikotoEmbedURL: Decodable {
    let sub: String?
    let dub: String?
}

private struct FlexibleInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) { self.value = value; return }
        if let string = try? container.decode(String.self), let value = Int(string) { self.value = value; return }
        throw FrostPlayServiceError.decodingFailed
    }
}

private actor AniListEpisodeCache {
    static let shared = AniListEpisodeCache()
    private var rowsByAnimeID: [Int: [EpisodeInfo]] = [:]

    func rows(for aniListID: Int) -> [EpisodeInfo]? { rowsByAnimeID[aniListID] }
    func store(_ value: [EpisodeInfo], for aniListID: Int) { rowsByAnimeID[aniListID] = value }
}

struct AniListService: MetadataService {

    let session: URLSession = .shared
    let endpoint = URL(string: "https://graphql.anilist.co")!

    func metadata(for aniListID: Int) async throws -> MediaMetadata {
        let queryText = """
        query ($id: Int) {
          Media(id: $id, type: ANIME) {
            genres
            averageScore
            status
            format
            countryOfOrigin
            duration
            source
            studios(isMain: true) { nodes { name } }
          }
        }
        """
        var request = URLRequestBuilder.postJSON(url: endpoint, body: [
            "query": queryText,
            "variables": ["id": aniListID]
        ])
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw FrostPlayServiceError.invalidResponse
        }
        do {
            let payload = try JSONDecoder().decode(AniListMetadataResponse.self, from: data)
            guard let media = payload.data?.media else { throw FrostPlayServiceError.decodingFailed }
            return media.metadata
        } catch {
            throw FrostPlayServiceError.decodingFailed
        }
    }

    func episodes(for media: MediaItem) async throws -> [EpisodeInfo] {
        guard media.kind == .anime, let aniListID = media.aniListID else { return [] }

        // The detail screen resolves the catalog and then the playback URLs for the
        // same title. Reuse one AniList response so that stays a single request.
        if let cached = await AniListEpisodeCache.shared.rows(for: aniListID) {
            return cached
        }

        // Always ask AniList for the authoritative episode data. The count cached in
        // the search result is only a hint: `episodes` is null for long-running and
        // still-airing titles (One Piece, Detective Conan, ...), which previously
        // produced an empty episode list. `nextAiringEpisode` and `streamingEpisodes`
        // fill those cases, and published streaming titles/artwork enrich the rows we
        // can map without fabricating the rest.
        let queryText = """
        query ($id: Int) {
          Media(id: $id, type: ANIME) {
            episodes
            nextAiringEpisode { episode }
            streamingEpisodes { title thumbnail }
          }
        }
        """
        var request = URLRequestBuilder.postJSON(url: endpoint, body: [
            "query": queryText,
            "variables": ["id": aniListID]
        ])
        request.timeoutInterval = 20

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw FrostPlayServiceError.invalidResponse
            }
            let payload = try JSONDecoder().decode(AniListEpisodesResponse.self, from: data)
            guard let aniListMedia = payload.data?.media else {
                throw FrostPlayServiceError.decodingFailed
            }
            let rows = makeEpisodeRows(
                count: resolvedEpisodeCount(
                    episodes: aniListMedia.episodes,
                    nextAiringEpisode: aniListMedia.nextAiringEpisode?.episode,
                    streamingEpisodeCount: aniListMedia.streamingEpisodes?.count ?? 0,
                    fallback: media.episodeCount
                ),
                streamingEpisodes: aniListMedia.streamingEpisodes ?? []
            )
            await AniListEpisodeCache.shared.store(rows, for: aniListID)
            return rows
        } catch {
            // Stay usable when AniList is unreachable but the search response already
            // carried an episode count.
            if let fallback = media.episodeCount, fallback > 0 {
                return makeEpisodeRows(count: fallback)
            }
            throw error
        }
    }

    private func resolvedEpisodeCount(episodes: Int?, nextAiringEpisode: Int?, streamingEpisodeCount: Int, fallback: Int?) -> Int {
        if let episodes, episodes > 0 { return episodes }
        if let nextAiringEpisode, nextAiringEpisode > 1 { return nextAiringEpisode - 1 }
        if streamingEpisodeCount > 0 { return streamingEpisodeCount }
        if let fallback, fallback > 0 { return fallback }
        return 0
    }

    private func makeEpisodeRows(
        count: Int,
        streamingEpisodes: [AniListEpisodesResponse.Media.StreamingEpisode] = []
    ) -> [EpisodeInfo] {
        guard count > 0 else { return [] }
        // AniList only publishes titles/artwork for a subset of episodes and its
        // titles sometimes carry no episode number. Parse the number when present
        // and otherwise fall back to the entry's position in the ordered list, so
        // real titles and thumbnails reach the episode rows we already show.
        var details: [Int: AniListEpisodesResponse.Media.StreamingEpisode] = [:]
        for (index, episode) in streamingEpisodes.enumerated() {
            let parsed = episodeNumber(from: episode.title, fallback: 0)
            let number = parsed > 0 ? parsed : index + 1
            if details[number] == nil { details[number] = episode }
        }
        return (1...min(count, 2_000)).map { number in
            let detail = details[number]
            return EpisodeInfo(
                number: number,
                name: detail?.title ?? "Episode \(number)",
                overview: "",
                airDate: nil,
                imageURL: detail?.thumbnail.flatMap(URL.init),
                playbackURL: nil
            )
        }
    }

    func playbackEpisodes(for media: MediaItem, episodeNumbers: [Int], language: String = "sub") async throws -> [EpisodeInfo] {
        guard media.kind == .anime else { return [] }
        let languagePath = language.lowercased() == "dub" ? "dub" : "sub"

        // MegaPlay publishes AniList- and MAL-addressed embed routes, so playable
        // URLs come straight from the IDs we already hold: no catalog scan, no
        // dependency on Anikoto's bounded "recent" feed, and no request latency.
        if media.aniListID != nil || media.malID != nil {
            return episodeNumbers.map { number in
                EpisodeInfo(
                    number: number,
                    name: "Episode \(number)",
                    overview: "",
                    airDate: nil,
                    imageURL: nil,
                    playbackURL: MegaPlayEmbed.url(media: media, episode: number, language: languagePath)
                )
            }
        }

        // Last resort for titles with no external ID to address MegaPlay directly.
        let streams = try await AnikotoService().episodes(for: media, language: languagePath)
        return streams.map { stream in
            EpisodeInfo(
                number: stream.number,
                name: "Episode \(stream.number)",
                overview: "",
                airDate: nil,
                imageURL: nil,
                playbackURL: stream.playbackURL
            )
        }
    }

    private func episodeNumber(from title: String?, fallback: Int) -> Int {
        guard let title, !title.isEmpty else { return fallback }
        let patterns = [#"(?i)\b(?:episode|ep)\s*#?\s*(\d+)\b"#, #"(?i)^\s*(\d{1,3})(?:\s|[.:\-–])"#]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: title),
                  let number = Int(title[range]), number > 0 else { continue }
            return number
        }
        return fallback
    }

    func search(query: String, kind: MediaKind?, page: Int = 1) async throws -> [MediaItem] {
        guard kind == .anime else { throw FrostPlayServiceError.unsupportedMediaKind }
        let queryText: String
        let variables: [String: Any]
        if query.isEmpty {
            queryText = """
            query ($page: Int) {
              Page(page: $page, perPage: 20) {
                media(type: ANIME, sort: POPULARITY_DESC) {
                  id
                  idMal
                  title { romaji english native }
                  description
                  seasonYear
                  episodes
                  genres
                  averageScore
                  status
                  format
                  countryOfOrigin
                  duration
                  source
                  studios(isMain: true) { nodes { name } }
                  coverImage { large }
                  bannerImage
                }
              }
            }
            """
            variables = ["page": page]
        } else {
            queryText = """
            query ($search: String, $page: Int) {
              Page(page: $page, perPage: 20) {
                media(search: $search, type: ANIME, sort: POPULARITY_DESC) {
                  id
                  idMal
                  title { romaji english native }
                  description
                  seasonYear
                  episodes
                  genres
                  averageScore
                  status
                  format
                  countryOfOrigin
                  duration
                  source
                  studios(isMain: true) { nodes { name } }
                  coverImage { large }
                  bannerImage
                }
              }
            }
            """
            variables = ["search": query, "page": page]
        }
        var request = URLRequestBuilder.postJSON(url: endpoint, body: [
            "query": queryText,
            "variables": variables
        ])
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw FrostPlayServiceError.invalidResponse
        }
        do {
            let payload = try JSONDecoder().decode(AniListResponse.self, from: data)
            return payload.data.page.media.map { anime in
                MediaItem(
                    id: "anilist-\(anime.id)",
                    title: anime.title.english ?? anime.title.romaji ?? anime.title.native ?? "Untitled",
                    overview: anime.description?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) ?? "",
                    posterURL: anime.coverImage?.large.flatMap(URL.init),
                    backdropURL: anime.bannerImage.flatMap(URL.init),
                    kind: .anime,
                    tmdbID: nil,
                    aniListID: anime.id,
                    malID: anime.idMal,
                    providerNames: ["MegaPlay"],
                    year: anime.seasonYear.map(String.init),
                    episodeCount: anime.episodes,
                    metadata: anime.metadata
                )
            }
        } catch {
            throw FrostPlayServiceError.decodingFailed
        }
    }
}

// MARK: - Fallback anime metadata (Jikan + AniDB)

/// One provider's answer to "what does this title's episode list look like".
/// Shared by the fallback chain so it can be merged into AniList's rows exactly
/// the way Kitsu's details already are.
struct AnimeEpisodeDetails {
    let episodes: [EpisodeInfo]
    /// The provider's own episode total when it publishes one, which fills the
    /// gap AniList leaves for still-airing and long-running titles.
    let reportedCount: Int?
}

/// The alternate provider chain behind a title the user switched to Fallback
/// mode. Jikan supplies the series details and its episode list; AniDB then
/// relabels anything Jikan left as a placeholder and adds air dates. AniList
/// still owns numbering and the MegaPlay playback URL, so this chain only ever
/// contributes display metadata.
struct AnimeFallbackService {
    private let jikan = JikanService()
    private let anidb = AniDBService()

    func metadata(malID: Int?) async -> MediaMetadata? {
        guard let malID else { return nil }
        return await jikan.metadata(malID: malID)
    }

    func episodeDetails(malID: Int?, title: String?) async -> AnimeEpisodeDetails {
        let jikanRows: [EpisodeInfo]
        if let malID {
            jikanRows = await jikan.episodes(malID: malID)
        } else {
            jikanRows = []
        }
        let anidbRows = await anidb.episodes(title: title)

        // Jikan is authoritative for the rows it published; AniDB only fills the
        // gaps and never overwrites a title Jikan already has.
        var byNumber: [Int: EpisodeInfo] = [:]
        for row in jikanRows { byNumber[row.number] = row }
        for row in anidbRows {
            if let existing = byNumber[row.number] {
                byNumber[row.number] = existing.merged(with: row)
            } else {
                byNumber[row.number] = row
            }
        }
        return AnimeEpisodeDetails(episodes: byNumber.values.sorted { $0.number < $1.number }, reportedCount: nil)
    }
}

/// Jikan is a free, keyless mirror of MyAnimeList, and FrostPlay already holds
/// every anime's MAL ID, so it can be addressed directly. See
/// https://docs.api.jikan.moe.
struct JikanService {
    let session: URLSession = .shared

    private static let base = "https://api.jikan.moe/v4"
    /// Jikan paginates at 100 rows a page; this bounds a long-running title the
    /// same way Kitsu enrichment is bounded.
    private static let maximumEpisodePages = 4

    func metadata(malID: Int) async -> MediaMetadata? {
        guard let url = URL(string: "\(Self.base)/anime/\(malID)/full") else { return nil }
        guard let data = try? await fetch(url),
              let payload = try? JSONDecoder().decode(JikanAnimeResponse.self, from: data),
              let anime = payload.data else { return nil }
        return anime.metadata
    }

    func episodes(malID: Int) async -> [EpisodeInfo] {
        var rows: [EpisodeInfo] = []
        for page in 1...Self.maximumEpisodePages {
            guard let url = URL(string: "\(Self.base)/anime/\(malID)/episodes?page=\(page)"),
                  let data = try? await fetch(url),
                  let payload = try? JSONDecoder().decode(JikanEpisodeListResponse.self, from: data) else { break }
            rows.append(contentsOf: payload.data.compactMap(\.episodeInfo))
            guard payload.pagination?.hasNextPage == true else { break }
        }
        return rows
    }

    private func fetch(_ url: URL) async throws -> Data {
        // Jikan allows roughly three requests a second; serializing a page sweep
        // keeps it inside that budget.
        await AnimeFallbackThrottle.shared.wait(minimumInterval: 0.4)
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw FrostPlayServiceError.invalidResponse
        }
        return data
    }
}

/// AniDB publishes the deepest per-episode titles and air dates of any anime
/// database, but it needs a registered client and rate-limits hard, so it is only
/// consulted for a title the user explicitly switched to Fallback mode.
///
/// Note: AniDB's HTTP API is plain HTTP on port 9001, so an app using it needs an
/// App Transport Security exception for `api.anidb.net`. Without one the request
/// fails and the chain simply falls through to Jikan.
struct AniDBService {
    let session: URLSession = .shared

    private static let base = "http://api.anidb.net:9001/httpapi"
    /// AniDB asks every app to identify itself; a registered client name/version
    /// goes here if this default one is ever refused.
    private static let client = "frostplay"
    private static let clientVersion = 1
    /// AniDB bans clients that poll faster than one request every two seconds.
    private static let minimumInterval: TimeInterval = 2.0

    func episodes(title: String?) async -> [EpisodeInfo] {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        guard let url = animeURL(title: title), let data = try? await fetch(url) else { return [] }
        let parser = AniDBAnimeParser()
        guard parser.parse(data) else { return [] }
        return parser.episodes.map { row in
            let name = row.titleEnglish ?? row.titleRomaji ?? ""
            return EpisodeInfo(
                number: row.number,
                name: name.isEmpty ? "Episode \(row.number)" : name,
                overview: "",
                airDate: row.airDate,
                imageURL: nil
            )
        }
    }

    private func animeURL(title: String) -> URL? {
        var components = URLComponents(string: Self.base)
        components?.queryItems = [
            URLQueryItem(name: "request", value: "anime"),
            URLQueryItem(name: "client", value: Self.client),
            URLQueryItem(name: "clientver", value: String(Self.clientVersion)),
            URLQueryItem(name: "protover", value: "1"),
            URLQueryItem(name: "aname", value: title),
            URLQueryItem(name: "fuzzy", value: "1")
        ]
        return components?.url
    }

    private func fetch(_ url: URL) async throws -> Data {
        await AnimeFallbackThrottle.shared.wait(minimumInterval: Self.minimumInterval)
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw FrostPlayServiceError.invalidResponse
        }
        return data
    }
}

/// Pulls the episode list out of AniDB's anime XML. Only the first matching
/// `<anime>` element is read, so a fuzzy title search cannot mix the numbering of
/// two different series.
private final class AniDBAnimeParser: NSObject, XMLParserDelegate {
    struct Row {
        let number: Int
        let titleEnglish: String?
        let titleRomaji: String?
        let airDate: String?
    }

    private(set) var episodes: [Row] = []
    private var animeElementsSeen = 0
    private var currentNumber: Int?
    private var currentEnglish: String?
    private var currentRomaji: String?
    private var currentAirDate: String?
    private var currentLanguage = ""
    private var buffer = ""

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        buffer = ""
        switch elementName {
        case "anime":
            animeElementsSeen += 1
        case "episode":
            currentNumber = nil
            currentEnglish = nil
            currentRomaji = nil
            currentAirDate = nil
        case "title":
            currentLanguage = attributeDict["xml:lang"] ?? attributeDict["lang"] ?? ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "epno":
            currentNumber = Int(text)
        case "title":
            if currentLanguage == "en" {
                currentEnglish = text
            } else if currentLanguage == "x-jat" {
                currentRomaji = text
            }
        case "airdate":
            currentAirDate = text.isEmpty ? nil : text
        case "episode":
            // Only the first fuzzy match is trusted, so numbering stays coherent.
            if animeElementsSeen == 1, let number = currentNumber, number > 0 {
                episodes.append(
                    Row(
                        number: number,
                        titleEnglish: currentEnglish.flatMap { $0.isEmpty ? nil : $0 },
                        titleRomaji: currentRomaji.flatMap { $0.isEmpty ? nil : $0 },
                        airDate: currentAirDate
                    )
                )
            }
        default:
            break
        }
        buffer = ""
    }
}

/// Serializes fallback-provider requests. Both providers rate-limit aggressively
/// and will ban a client that bursts, so every request waits its provider's gap.
private actor AnimeFallbackThrottle {
    static let shared = AnimeFallbackThrottle()
    private var lastRequest = Date.distantPast

    func wait(minimumInterval: TimeInterval) async {
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minimumInterval {
            try? await Task.sleep(nanoseconds: UInt64((minimumInterval - elapsed) * 1_000_000_000))
        }
        lastRequest = Date()
    }
}

private struct JikanAnimeResponse: Decodable {
    let data: JikanAnime?
}

private struct JikanAnime: Decodable {
    let score: Double?
    let status: String?
    let type: String?
    let duration: String?
    let source: String?
    let genres: [JikanNamed]?
    let studios: [JikanNamed]?

    struct JikanNamed: Decodable { let name: String }

    var metadata: MediaMetadata {
        MediaMetadata(
            genres: (genres ?? []).map(\.name),
            score: score.map { Int(($0 * 10).rounded()) },
            status: status,
            format: type,
            durationMinutes: Self.minutes(from: duration),
            source: source?.uppercased(),
            studios: (studios ?? []).map(\.name)
        )
    }

    /// Jikan's `duration` is free text such as "24 min per ep".
    static func minutes(from duration: String?) -> Int? {
        guard let duration else { return nil }
        let digits = duration.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}

private struct JikanEpisodeListResponse: Decodable {
    let data: [JikanEpisode]
    let pagination: Pagination?

    struct Pagination: Decodable {
        let hasNextPage: Bool?

        enum CodingKeys: String, CodingKey {
            case hasNextPage = "has_next_page"
        }
    }
}

private struct JikanEpisode: Decodable {
    let malID: Int?
    let title: String?
    let aired: String?

    enum CodingKeys: String, CodingKey {
        case malID = "mal_id"
        case title, aired
    }

    var episodeInfo: EpisodeInfo? {
        guard let malID, malID > 0 else { return nil }
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return EpisodeInfo(
            number: malID,
            name: trimmed.isEmpty ? "Episode \(malID)" : trimmed,
            overview: "",
            airDate: aired.map { String($0.prefix(10)) },
            imageURL: nil
        )
    }
}

// MARK: - AI metadata

enum AIMetadataError: LocalizedError {
    case notConfigured
    case invalidConfiguration
    case requestFailed(String)
    case emptyResponse
    case noEpisodesFound

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add an API key in Settings → AI metadata first."
        case .invalidConfiguration:
            return "The AI base URL or model is not valid. Check Settings → AI metadata."
        case .requestFailed(let message):
            return "The AI provider rejected the request: \(message)"
        case .emptyResponse:
            return "The AI model returned an empty response."
        case .noEpisodesFound:
            return "The AI model returned no usable episode data."
        }
    }
}

/// Calls an OpenAI-compatible chat-completions endpoint with the key the user
/// stored locally. The same request shape works for OpenAI, OpenRouter, and any
/// custom host, so only the base URL and model slug change.
struct AIMetadataService {
    struct GeneratedEpisode {
        let number: Int
        let name: String?
        let overview: String?
        let imageURL: URL?
    }

    let session: URLSession = .shared

    func episodes(
        settings: FrostPlaySettings,
        media: MediaItem,
        season: Int,
        episodeNumbers: [Int]
    ) async throws -> [GeneratedEpisode] {
        let key = settings.aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.aiMetadataEnabled, !key.isEmpty else { throw AIMetadataError.notConfigured }
        let model = settings.aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, let url = Self.endpoint(baseURL: settings.aiBaseURL) else {
            throw AIMetadataError.invalidConfiguration
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.render(settings.aiSystemPrompt, media: media, season: season, episodeNumbers: episodeNumbers)],
                ["role": "user", "content": Self.render(settings.aiEpisodePrompt, media: media, season: season, episodeNumbers: episodeNumbers)]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.2
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300 ~= http.statusCode) {
            throw AIMetadataError.requestFailed(Self.errorMessage(from: data) ?? "HTTP \(http.statusCode)")
        }
        guard let payload = try? JSONDecoder().decode(AIChatResponse.self, from: data),
              let content = payload.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIMetadataError.emptyResponse
        }
        let episodes = Self.decodeEpisodes(from: content)
        guard !episodes.isEmpty else { throw AIMetadataError.noEpisodesFound }
        return episodes
    }

    /// Accepts either the API root ("https://api.openai.com/v1") or a full
    /// completions path, so a custom host can paste whichever it documents.
    static func endpoint(baseURL: String) -> URL? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else { return nil }
        if url.path.lowercased().hasSuffix("/chat/completions") { return url }
        return url.appendingPathComponent("chat/completions")
    }

    /// Replaces every documented `{placeholder}` the prompt carries.
    static func render(_ template: String, media: MediaItem, season: Int, episodeNumbers: [Int]) -> String {
        let replacements: [String: String] = [
            "{title}": media.title,
            "{year}": media.year ?? "unknown year",
            "{format}": media.metadata?.format ?? media.kind.title,
            "{season}": String(season),
            "{episode_count}": String(episodeNumbers.count),
            "{episode_numbers}": episodeNumbers.isEmpty ? "unknown" : episodeNumbers.map(String.init).joined(separator: ", "),
            "{genres}": media.metadata?.genres.joined(separator: ", ") ?? "",
            "{overview}": media.overview
        ]
        var output = template
        for (token, value) in replacements {
            output = output.replacingOccurrences(of: token, with: value)
        }
        return output
    }

    /// Providers wrap JSON in prose or code fences often enough that parsing
    /// tolerates both: skip to the first `{` or `[` and read from there.
    static func decodeEpisodes(from content: String) -> [GeneratedEpisode] {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fence = text.range(of: "```") {
            text = String(text[fence.upperBound...])
            if let end = text.range(of: "```") { text = String(text[..<end.lowerBound]) }
            if let newline = text.firstIndex(of: "\n") { text = String(text[text.index(after: newline)...]) }
        }
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let data = String(text[start...]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let array = object as? [[String: Any]] { return array.compactMap(episode(from:)) }
        if let dictionary = object as? [String: Any] {
            for key in ["episodes", "episode_metadata", "data", "items", "results"] {
                if let array = dictionary[key] as? [[String: Any]] { return array.compactMap(episode(from:)) }
            }
        }
        return []
    }

    private static func episode(from object: [String: Any]) -> GeneratedEpisode? {
        let number = (object["episode"] as? Int)
            ?? (object["episode"] as? String).flatMap { Int($0) }
            ?? (object["number"] as? Int)
            ?? (object["number"] as? String).flatMap { Int($0) }
        guard let number, number > 0 else { return nil }
        let name = string(object["title"]) ?? string(object["name"])
        let overview = string(object["synopsis"]) ?? string(object["overview"]) ?? string(object["description"])
        let imageURL = (string(object["image_url"]) ?? string(object["image"]) ?? string(object["thumbnail"]))
            .flatMap { URL(string: $0) }
        return GeneratedEpisode(number: number, name: name, overview: overview, imageURL: imageURL)
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return object["message"] as? String
    }
}

private struct AIChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable { let message: Message }
    struct Message: Decodable { let content: String? }
}

// MARK: - Kitsu

private struct KitsuAnime: Hashable {
    let id: Int
    let episodeCount: Int?
}

/// Kitsu is a free, keyless anime database. AniList stays authoritative for
/// FrostPlay's anime catalog, episode numbering, and MegaPlay playback URLs, but
/// AniList publishes no per-episode titles, synopses, air dates, or artwork for
/// most titles. Kitsu fills exactly that gap, and it publishes `anilist/anime` and
/// `myanimelist/anime` mappings, so it can be addressed with the IDs FrostPlay
/// already holds. See https://kitsu.io/api/edge.
struct KitsuService {
    let session: URLSession = .shared

    private static let base = "https://kitsu.io/api/edge"
    /// Kitsu is community-run and rate-limits aggressively, so enrichment is
    /// bounded: at most this many episodes are described for any one title.
    private static let pageSize = 20
    private static let maximumEpisodePages = 5

    struct EpisodeDetails {
        let episodes: [EpisodeInfo]
        /// Kitsu's own total episode count, which is populated for some titles
        /// where AniList reports `null`.
        let reportedCount: Int?
    }

    /// Resolves the title through Kitsu's published ID mappings and returns its
    /// per-episode details. Any failure means "Kitsu has nothing to add", so anime
    /// still loads from AniList alone.
    func episodeDetails(aniListID: Int?, malID: Int?, title: String?) async -> EpisodeDetails {
        guard let match = await resolveAnime(aniListID: aniListID, malID: malID, title: title) else {
            return EpisodeDetails(episodes: [], reportedCount: nil)
        }
        let rows = (try? await episodes(kitsuID: match.id)) ?? []
        return EpisodeDetails(episodes: rows, reportedCount: match.episodeCount)
    }

    private func resolveAnime(aniListID: Int?, malID: Int?, title: String?) async -> KitsuAnime? {
        if let aniListID, let cached = await KitsuCache.shared.anime(aniListID: aniListID) { return cached }
        if let malID, let cached = await KitsuCache.shared.anime(malID: malID) { return cached }

        if let aniListID, let match = try? await anime(mapping: "anilist/anime", externalID: aniListID) {
            await KitsuCache.shared.store(match, aniListID: aniListID, malID: malID)
            return match
        }
        if let malID, let match = try? await anime(mapping: "myanimelist/anime", externalID: malID) {
            await KitsuCache.shared.store(match, aniListID: aniListID, malID: malID)
            return match
        }
        if let title, !title.isEmpty, let match = try? await anime(matchingTitle: title) {
            await KitsuCache.shared.store(match, aniListID: aniListID, malID: malID)
            return match
        }
        return nil
    }

    /// One request resolves an AniList or MAL ID to Kitsu's anime record, whose
    /// `included` payload already carries the attributes we need.
    private func anime(mapping site: String, externalID: Int) async throws -> KitsuAnime {
        let path = "mappings?filter%5BexternalSite%5D=\(site)&filter%5BexternalId%5D=\(externalID)&include=item&page%5Blimit%5D=1"
        guard let url = URL(string: "\(Self.base)/\(path)") else { throw FrostPlayServiceError.invalidResponse }
        let payload = try JSONDecoder().decode(KitsuMappingResponse.self, from: try await fetch(url))
        guard let mapping = payload.data.first,
              let id = mapping.relationships?.item?.data?.id,
              let kitsuID = Int(id) else { throw FrostPlayServiceError.decodingFailed }
        let resource = payload.included?.first { $0.id == id }
        return KitsuAnime(id: kitsuID, episodeCount: resource?.attributes?.episodeCount)
    }

    /// Last resort for a title that reaches Kitsu with no external ID at all.
    private func anime(matchingTitle title: String) async throws -> KitsuAnime {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+")
        let query = title.addingPercentEncoding(withAllowedCharacters: allowed) ?? title
        let path = "anime?filter%5Btext%5D=\(query)&page%5Blimit%5D=1"
        guard let url = URL(string: "\(Self.base)/\(path)") else { throw FrostPlayServiceError.invalidResponse }
        let payload = try JSONDecoder().decode(KitsuAnimeListResponse.self, from: try await fetch(url))
        guard let first = payload.data.first, let kitsuID = Int(first.id) else {
            throw FrostPlayServiceError.decodingFailed
        }
        return KitsuAnime(id: kitsuID, episodeCount: first.attributes?.episodeCount)
    }

    private func episodes(kitsuID: Int) async throws -> [EpisodeInfo] {
        if let cached = await KitsuCache.shared.rows(forKitsuID: kitsuID) { return cached }
        var rows: [EpisodeInfo] = []
        for page in 0..<Self.maximumEpisodePages {
            let offset = page * Self.pageSize
            let path = "anime/\(kitsuID)/episodes?page%5Blimit%5D=\(Self.pageSize)&page%5Boffset%5D=\(offset)"
            guard let url = URL(string: "\(Self.base)/\(path)"),
                  let data = try? await fetch(url),
                  let payload = try? JSONDecoder().decode(KitsuEpisodeListResponse.self, from: data) else { break }
            rows.append(contentsOf: payload.data.compactMap(\.episodeInfo))
            if payload.data.count < Self.pageSize { break }
        }
        if !rows.isEmpty { await KitsuCache.shared.store(rows, forKitsuID: kitsuID) }
        return rows
    }

    private func fetch(_ url: URL) async throws -> Data {
        // Serializing Kitsu requests keeps a burst of detail screens from tripping
        // its rate limit.
        await KitsuRequestThrottle.shared.wait()
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw FrostPlayServiceError.invalidResponse
        }
        return data
    }
}

/// Merges Kitsu's per-episode details into the episode rows AniList owns.
enum EpisodeDetailsMerger {
    /// AniList stays authoritative for episode numbers, row order, and the
    /// MegaPlay playback URL. Kitsu only contributes display data it actually has,
    /// and never replaces a title AniList already published.
    static func merge(base: [EpisodeInfo], details: [EpisodeInfo], expectedCount: Int?) -> [EpisodeInfo] {
        guard !details.isEmpty else { return padded(base, expectedCount: expectedCount).sorted { $0.number < $1.number } }

        var detailByNumber: [Int: EpisodeInfo] = [:]
        for detail in details where detailByNumber[detail.number] == nil {
            detailByNumber[detail.number] = detail
        }

        var merged: [EpisodeInfo] = []
        var usedDetailNumbers = Set<Int>()
        for row in base {
            guard let detail = detailByNumber[row.number] else {
                merged.append(row)
                continue
            }
            usedDetailNumbers.insert(detail.number)
            merged.append(row.merged(with: detail))
        }

        // Second pass: Kitsu numbers its own episodes, and that numbering does not
        // always line up with AniList's (absolute vs. per-season counts, specials,
        // split cours). Every row still carrying FrostPlay's generated label takes
        // the next unclaimed Kitsu row in order, so a numbering mismatch enriches
        // the list instead of leaving a whole season as "Episode N".
        var spare = details.filter { !usedDetailNumbers.contains($0.number) }
        for index in merged.indices where merged[index].hasNoDetails {
            // Only spend a Kitsu row that actually published something.
            guard let position = spare.firstIndex(where: { !$0.hasNoDetails }) else { break }
            let detail = spare.remove(at: position)
            usedDetailNumbers.insert(detail.number)
            merged[index] = merged[index].merged(with: detail)
        }

        // Kitsu sometimes describes episodes beyond the count AniList reported.
        var covered = Set(merged.map(\.number))
        for detail in details where !usedDetailNumbers.contains(detail.number) && !covered.contains(detail.number) {
            merged.append(detail)
            covered.insert(detail.number)
        }

        return padded(merged, expectedCount: expectedCount).sorted { $0.number < $1.number }
    }

    /// Fills the gaps up to the count the catalog owner reported, so a title with
    /// 1,100 episodes still lists 1,100 rows.
    private static func padded(_ rows: [EpisodeInfo], expectedCount: Int?) -> [EpisodeInfo] {
        guard let expectedCount, expectedCount > rows.count else { return rows }
        let target = min(max(expectedCount, rows.count), 2_000)
        guard target > rows.count else { return rows }
        var padded = rows
        var covered = Set(padded.map(\.number))
        for number in 1...target where !covered.contains(number) {
            padded.append(EpisodeInfo(number: number, name: "Episode \(number)", overview: "", airDate: nil, imageURL: nil))
            covered.insert(number)
        }
        return padded
    }
}

/// Caches Kitsu lookups so revisiting a title never re-requests it.
private actor KitsuCache {
    static let shared = KitsuCache()
    private var animeByAniListID: [Int: KitsuAnime] = [:]
    private var animeByMALID: [Int: KitsuAnime] = [:]
    private var rowsByKitsuID: [Int: [EpisodeInfo]] = [:]

    func anime(aniListID: Int) -> KitsuAnime? { animeByAniListID[aniListID] }
    func anime(malID: Int) -> KitsuAnime? { animeByMALID[malID] }

    func store(_ value: KitsuAnime, aniListID: Int?, malID: Int?) {
        if let aniListID { animeByAniListID[aniListID] = value }
        if let malID { animeByMALID[malID] = value }
    }

    func rows(forKitsuID id: Int) -> [EpisodeInfo]? { rowsByKitsuID[id] }
    func store(_ value: [EpisodeInfo], forKitsuID id: Int) { rowsByKitsuID[id] = value }

    /// Approximate footprint reported by the Cache screen.
    func approximateByteCount() -> Int {
        var total = 0
        for rows in rowsByKitsuID.values {
            for row in rows {
                total += 220 + row.name.utf8.count + row.overview.utf8.count
            }
        }
        return total
    }

    func clear() {
        animeByAniListID.removeAll()
        animeByMALID.removeAll()
        rowsByKitsuID.removeAll()
    }
}

/// Kitsu is community-run; requests are serialized with a small gap so a burst of
/// detail screens cannot trip its rate limit. The gap is deliberately short so a
/// multi-page episode lookup still finishes in about a second.
private actor KitsuRequestThrottle {
    static let shared = KitsuRequestThrottle()
    private var lastRequest = Date.distantPast
    private let minimumInterval: TimeInterval = 0.4

    func wait() async {
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minimumInterval {
            try? await Task.sleep(nanoseconds: UInt64((minimumInterval - elapsed) * 1_000_000_000))
        }
        lastRequest = Date()
    }
}

/// Type-erased access to the Kitsu caches for the Cache screen.
enum KitsuCacheInfo {
    static func approximateByteCount() async -> Int {
        await KitsuCache.shared.approximateByteCount()
    }

    static func clear() async {
        await KitsuCache.shared.clear()
    }
}

private struct KitsuMappingResponse: Decodable {
    let data: [Mapping]
    let included: [KitsuAnimeResource]?

    struct Mapping: Decodable {
        let relationships: Relationships?

        struct Relationships: Decodable {
            let item: Item?

            struct Item: Decodable {
                let data: ItemData?

                struct ItemData: Decodable {
                    let id: String
                }
            }
        }
    }
}

private struct KitsuAnimeListResponse: Decodable {
    let data: [KitsuAnimeResource]
}

private struct KitsuAnimeResource: Decodable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable {
        let episodeCount: Int?
    }
}

private struct KitsuEpisodeListResponse: Decodable {
    let data: [KitsuEpisodeResource]
}

private struct KitsuEpisodeResource: Decodable {
    let attributes: Attributes

    struct Attributes: Decodable {
        let canonicalTitle: String?
        let synopsis: String?
        let airdate: String?
        let number: Int?
        let relativeNumber: Int?
        let thumbnail: Thumbnail?
        let titles: Titles?

        struct Thumbnail: Decodable {
            let original: String?
        }

        struct Titles: Decodable {
            let english: String?
            let romaji: String?

            enum CodingKeys: String, CodingKey {
                case english = "en_us"
                case romaji = "en_jp"
            }
        }
    }

    /// Kitsu numbers its own episodes and publishes a title per episode, which is
    /// exactly what AniList omits.
    var episodeInfo: EpisodeInfo? {
        guard let number = attributes.number ?? attributes.relativeNumber, number > 0 else { return nil }
        let candidate = attributes.canonicalTitle ?? attributes.titles?.english ?? attributes.titles?.romaji
        let name: String
        if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = candidate
        } else {
            name = "Episode \(number)"
        }
        return EpisodeInfo(
            number: number,
            name: name,
            overview: attributes.synopsis ?? "",
            airDate: attributes.airdate,
            imageURL: attributes.thumbnail?.original.flatMap(URL.init)
        )
    }
}

protocol PlaybackSourceAdapter {
    var source: PlaybackSource { get }
    func playback(for media: MediaItem, season: Int?, episode: Int?, language: String) -> PlaybackFormat?
}

struct VidLinkAdapter: PlaybackSourceAdapter {
    let source = PlaybackSource.vidLink

    func playback(for media: MediaItem, season: Int?, episode: Int?, language: String) -> PlaybackFormat? {
        // VidLink is deliberately TMDB-only. AniList IDs must never be sent here.
        let path: String
        if media.kind == .movie {
            guard let tmdbID = media.tmdbID else { return nil }
            path = "movie/\(tmdbID)"
        } else {
            guard let tmdbID = media.tmdbID, let season, let episode else { return nil }
            path = "tv/\(tmdbID)/\(season)/\(episode)"
        }
        guard let baseURL = URL(string: "https://vidlink.pro/\(path)") else { return nil }
        if media.kind == .movie || media.kind == .tv,
           let fallbackURL = MoviesAPIAdapter.url(for: media, season: season, episode: episode) {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "fallback_url", value: fallbackURL.absoluteString)]
            return components?.url.map(PlaybackFormat.embed)
        }
        return PlaybackFormat.embed(baseURL)
    }
}

struct MoviesAPIAdapter: PlaybackSourceAdapter {
    let source = PlaybackSource.moviesAPI

    func playback(for media: MediaItem, season: Int?, episode: Int?, language: String) -> PlaybackFormat? {
        Self.url(for: media, season: season, episode: episode).map(PlaybackFormat.embed)
    }

    static func url(for media: MediaItem, season: Int?, episode: Int?) -> URL? {
        guard let tmdbID = media.tmdbID else { return nil }
        let path: String
        if media.kind == .movie {
            path = "movie/\(tmdbID)"
        } else {
            guard media.kind == .tv, let season, let episode else { return nil }
            path = "tv/\(tmdbID)/\(season)/\(episode)"
        }
        return URL(string: "https://moviesapi.to/\(path)")
    }
}

struct MegaPlayAdapter: PlaybackSourceAdapter {
    let source = PlaybackSource.megaPlay

    func playback(for media: MediaItem, season: Int?, episode: Int?, language: String) -> PlaybackFormat? {
        // Address MegaPlay with the AniList/MAL ID so every anime resolves,
        // including films (which have no episode list). Never let anime fall
        // through to the TMDB-only sources.
        guard media.kind == .anime, media.tmdbID == nil else { return nil }
        return MegaPlayEmbed.url(media: media, episode: episode ?? 1, language: language).map(PlaybackFormat.embed)
    }
}

private struct TMDBSearchResponse: Decodable {
    let results: [TMDBResult]
}

private struct TMDBTVDetailsResponse: Decodable {
    let seasons: [TMDBSeason]
}

private struct TMDBSeasonDetailResponse: Decodable {
    let episodes: [TMDBEpisode]
}

private struct TMDBSeason: Decodable {
    let seasonNumber: Int
    let episodeCount: Int

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
    }
}

private struct TMDBEpisode: Decodable {
    let episodeNumber: Int
    let name: String
    let overview: String?
    let airDate: String?
    let stillPath: String?

    enum CodingKeys: String, CodingKey {
        case episodeNumber = "episode_number"
        case name, overview
        case airDate = "air_date"
        case stillPath = "still_path"
    }
}

private struct TMDBResult: Decodable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case mediaType = "media_type"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
    }
}

private struct TMDBProviderResponse: Decodable {
    let results: [TMDBProvider]

    struct TMDBProvider: Decodable {
        let providerID: Int
        let logoPath: String?

        enum CodingKeys: String, CodingKey {
            case providerID = "provider_id"
            case logoPath = "logo_path"
        }
    }
}

private struct AniListEpisodesResponse: Decodable {
    let data: DataContainer?

    struct DataContainer: Decodable {
        let media: Media?

        enum CodingKeys: String, CodingKey {
            case media = "Media"
        }
    }

    struct Media: Decodable {
        let episodes: Int?
        let nextAiringEpisode: NextAiringEpisode?
        let streamingEpisodes: [StreamingEpisode]?

        struct NextAiringEpisode: Decodable {
            let episode: Int?
        }

        struct StreamingEpisode: Decodable {
            let title: String?
            let thumbnail: String?
        }
    }
}

private struct AniListMetadataResponse: Decodable {
    let data: DataContainer?

    struct DataContainer: Decodable {
        let media: Media?

        enum CodingKeys: String, CodingKey {
            case media = "Media"
        }
    }

    struct Media: Decodable {
        let genres: [String]?
        let averageScore: Int?
        let status: String?
        let format: String?
        let countryOfOrigin: String?
        let duration: Int?
        let source: String?
        let studios: StudioConnection?

        var metadata: MediaMetadata {
            MediaMetadata(
                genres: genres ?? [],
                score: averageScore,
                status: status,
                format: format,
                countryOfOrigin: countryOfOrigin,
                durationMinutes: duration,
                source: source,
                studios: (studios?.nodes ?? []).map { $0.name }
            )
        }

        struct StudioConnection: Decodable {
            let nodes: [Studio]?
        }

        struct Studio: Decodable {
            let name: String
        }
    }
}

private struct AniListResponse: Decodable {
    let data: AniListData

    struct AniListData: Decodable {
        let page: Page

        private enum CodingKeys: String, CodingKey {
            case upperPage = "Page"
            case lowerPage = "page"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            page = try container.decodeIfPresent(Page.self, forKey: .upperPage)
                ?? container.decode(Page.self, forKey: .lowerPage)
        }
    }
    struct Page: Decodable { let media: [Anime] }
    struct Anime: Decodable {
        let id: Int
        let idMal: Int?
        let title: Title
        let description: String?
        let seasonYear: Int?
        let episodes: Int?
        let genres: [String]?
        let averageScore: Int?
        let status: String?
        let format: String?
        let coverImage: Cover?
        let bannerImage: String?
        let countryOfOrigin: String?
        let duration: Int?
        let source: String?
        let studios: StudioConnection?

        var metadata: MediaMetadata {
            MediaMetadata(
                genres: genres ?? [],
                score: averageScore,
                status: status,
                format: format,
                countryOfOrigin: countryOfOrigin,
                durationMinutes: duration,
                source: source,
                studios: (studios?.nodes ?? []).map { $0.name }
            )
        }

        struct StudioConnection: Decodable { let nodes: [Studio]? }
        struct Studio: Decodable { let name: String }
    }
    struct Title: Decodable { let romaji: String?; let english: String?; let native: String? }
    struct Cover: Decodable { let large: String? }
}

private enum URLRequestBuilder {
    static func postJSON(url: URL, body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}
