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

fileprivate struct AnimeStreamEpisode {
    let number: Int
    let playbackURL: URL?
}

private actor AnikotoRecentPageCache {
    static let shared = AnikotoRecentPageCache()
    private var pages: [String: Data] = [:]

    func data(for key: String) -> Data? { pages[key] }
    func store(_ data: Data, for key: String) { pages[key] = data }
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
            // The API's embed_url is authoritative. Do not manufacture a MegaPlay URL
            // from AniList IDs: MegaPlay requires Anikoto's episode embed ID.
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
        // older catalog entries can be many pages deep. Cache pages per app session and
        // stay below its published 60-requests/120s limit while searching by external ID.
        let providerPage = 1...55
        for page in providerPage {
            if Task.isCancelled { throw CancellationError() }
            if page > 1 { try await Task.sleep(for: .milliseconds(250)) }
            let response = try await fetchRecent(page: page, perPage: 100)
            let matches = response.data.filter { row in
                let aniListMatch = media.aniListID.map { row.aniID?.value == $0 } ?? false
                let malMatch = media.malID.map { row.malID?.value == $0 } ?? false
                let titleMatch = row.aniID == nil && row.malID == nil && [row.title, row.alternative, row.titles, row.native]
                    .compactMap { $0 }
                    .flatMap { $0.split(separator: ",").map(String.init) }
                    .contains { wantedTitles.contains(normalized($0)) }
                if media.aniListID != nil {
                    return aniListMatch || (row.aniID == nil && malMatch) || titleMatch
                }
                return malMatch || titleMatch
            }
            for match in matches {
                if let series = try? await fetchSeries(id: String(match.id)), series.anime.matches(media: media) {
                    return series
                }
            }
            // Anikoto's pagination metadata is calculated before its 100-row cap is
            // applied. Use the effective page size instead of trusting total_pages.
            let total = response.pagination?.total ?? response.data.count
            let pageCount = (total + 99) / 100
            if page >= pageCount || response.data.isEmpty { break }
        }
        throw FrostPlayServiceError.invalidResponse
    }

    private func fetchSeries(id: String) async throws -> AnikotoSeries {
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
        if let requestedAniListID = media.aniListID, let aniID { return aniID.value == requestedAniListID }
        if media.aniListID == nil, let requestedMALID = media.malID, let malID { return malID.value == requestedMALID }
        if aniID != nil || malID != nil { return false }
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
            return try JSONDecoder().decode(AniListMetadataResponse.self, from: data).data.media.metadata
        } catch {
            throw FrostPlayServiceError.decodingFailed
        }
    }

    func episodes(for media: MediaItem, language: String = "sub") async throws -> [EpisodeInfo] {
        guard let aniListID = media.aniListID else { return [] }

        // AniList's streamingEpisodes are presentation metadata only; their URLs
        // are intentionally ignored because playback must always resolve via MegaPlay.
        let queryText = """
        query ($id: Int) {
          Media(id: $id, type: ANIME) {
            episodes
            streamingEpisodes { title thumbnail url }
          }
        }
        """
        var request = URLRequestBuilder.postJSON(url: endpoint, body: [
            "query": queryText,
            "variables": ["id": aniListID]
        ])
        request.timeoutInterval = 20

        var aniListMedia: AniListEpisodesResponse.Media?
        var anilistError: Error?
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw FrostPlayServiceError.invalidResponse
            }
            let payload = try JSONDecoder().decode(AniListEpisodesResponse.self, from: data)
            aniListMedia = payload.data?.media
            if aniListMedia == nil { throw FrostPlayServiceError.decodingFailed }
        } catch {
            anilistError = error
        }

        // Resolve streams regardless of AniList's streamingEpisodes response. AniList
        // owns display metadata; Anikoto contributes only the MegaPlay episode URLs.
        let anikotoEpisodes = (try? await AnikotoService().episodes(
            for: media,
            language: language
        )) ?? []
        guard aniListMedia != nil else {
            if anikotoEpisodes.isEmpty { throw anilistError ?? FrostPlayServiceError.invalidResponse }
            // Don't display Anikoto's episode labels/art as metadata. Keep its streams
            // usable while clearly marking AniList-only fields absent.
            return anikotoEpisodes.map { stream in
                EpisodeInfo(number: stream.number, name: "Episode \(stream.number)", overview: "", airDate: nil, imageURL: nil, playbackURL: stream.playbackURL)
            }
        }
        guard let aniListMedia else { return [] }

        // AniList can return several streaming links for the same episode. Keep one
        // metadata row per episode instead of trapping in Dictionary(uniqueKeysWithValues:).
        var anilistByNumber: [Int: AniListEpisodesResponse.Episode] = [:]
        for (index, item) in (aniListMedia?.streamingEpisodes ?? []).enumerated() {
            let number = episodeNumber(from: item.title, fallback: index + 1)
            if let existing = anilistByNumber[number], existing.thumbnail != nil || item.thumbnail == nil { continue }
            anilistByNumber[number] = item
        }
        let streamsByNumber = Dictionary(anikotoEpisodes.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        var episodeNumbers = Set(anilistByNumber.keys).union(streamsByNumber.keys)
        if let episodeCount = aniListMedia.episodes ?? media.episodeCount, episodeCount > 0 {
            episodeNumbers.formUnion(1...min(episodeCount, 1_000))
        }

        // AniList supplies every visible field and the canonical episode count;
        // Anikoto contributes only stream URLs.
        return episodeNumbers.sorted().map { number in
            let metadataEpisode = anilistByNumber[number]
            let streamEpisode = streamsByNumber[number]
            let title = metadataEpisode?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return EpisodeInfo(
                number: number,
                name: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Episode \(number)",
                // AniList exposes series synopsis, not an episode synopsis field.
                overview: "",
                airDate: nil,
                imageURL: metadataEpisode?.thumbnail.flatMap(URL.init),
                playbackURL: streamEpisode?.playbackURL
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
                    metadata: MediaMetadata(genres: anime.genres ?? [], score: anime.averageScore, status: anime.status, format: anime.format)
                )
            }
        } catch {
            throw FrostPlayServiceError.decodingFailed
        }
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
        // MegaPlay URLs are resolved by Anikoto's episode mapping. Never derive a
        // stream from an AniList ID or let an anime fall through to TMDB sources.
        guard media.kind == .anime, media.tmdbID == nil, episode != nil else { return nil }
        return nil
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
        let streamingEpisodes: [Episode]?
    }

    struct Episode: Decodable {
        let title: String?
        let thumbnail: String?
        let url: String?
    }
}

private struct AniListMetadataResponse: Decodable {
    let data: DataContainer

    struct DataContainer: Decodable {
        let media: Media

        enum CodingKeys: String, CodingKey {
            case media = "Media"
        }
    }

    struct Media: Decodable {
        let genres: [String]?
        let averageScore: Int?
        let status: String?
        let format: String?

        var metadata: MediaMetadata {
            MediaMetadata(genres: genres ?? [], score: averageScore, status: status, format: format)
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
