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

    func episodes(for aniListID: Int, count: Int?, fallbackOverview: String) async throws -> [EpisodeInfo] {
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
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw FrostPlayServiceError.invalidResponse
        }
        do {
            let payload = try JSONDecoder().decode(AniListEpisodesResponse.self, from: data)
            let mapped = (payload.data.media.streamingEpisodes ?? []).enumerated().map { index, item in
                let title = item.title ?? ""
                let number = title.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first ?? index + 1
                return EpisodeInfo(
                    number: number,
                    name: title.isEmpty ? "Episode \(number)" : title,
                    overview: fallbackOverview.isEmpty ? "Episode details provided by AniList." : fallbackOverview,
                    airDate: nil,
                    imageURL: item.thumbnail.flatMap(URL.init),
                    playbackURL: item.url.flatMap(URL.init).flatMap { $0.host?.contains("megaplay.buzz") == true ? $0 : nil }
                )
            }
            if !mapped.isEmpty { return mapped }
            guard let count, count > 0 else { return [] }
            return (1...count).map { EpisodeInfo(number: $0, name: "Episode \($0)", overview: "Episode metadata is not available from AniList.", airDate: nil, imageURL: nil) }
        } catch {
            throw FrostPlayServiceError.decodingFailed
        }
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
        // MegaPlay accepts the AniList identifier for anime episodes only.
        guard media.kind == .anime, media.tmdbID == nil, let aniListID = media.aniListID, let episode else { return nil }
        let languageCode = language.lowercased() == "dub" ? "dub" : "sub"
        return URL(string: "https://megaplay.buzz/stream/ani/\(aniListID)/\(episode)/\(languageCode)").map(PlaybackFormat.embed)
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
    let data: DataContainer

    struct DataContainer: Decodable {
        let media: Media
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
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}
