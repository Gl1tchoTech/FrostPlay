import Foundation
import SwiftUI

enum MediaKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case movie, tv, anime
    var id: String { rawValue }
    var title: String {
        switch self {
        case .movie: return "Movie"
        case .tv: return "TV"
        case .anime: return "Anime"
        }
    }
}

enum PlaybackFormat: Codable, Equatable {
    case embed(URL)
    case hls(URL)
    case mp4(URL)
}

struct MediaMetadata: Codable, Hashable {
    let genres: [String]
    let score: Int?
    let status: String?
    let format: String?
    let countryOfOrigin: String?
    let durationMinutes: Int?
    let source: String?
    let studios: [String]?

    var hasDetails: Bool {
        !genres.isEmpty || score != nil || status != nil || format != nil || countryOfOrigin != nil ||
        durationMinutes != nil || source != nil || !(studios ?? []).isEmpty
    }

    init(
        genres: [String],
        score: Int?,
        status: String?,
        format: String?,
        countryOfOrigin: String? = nil,
        durationMinutes: Int? = nil,
        source: String? = nil,
        studios: [String]? = nil
    ) {
        self.genres = genres
        self.score = score
        self.status = status
        self.format = format
        self.countryOfOrigin = countryOfOrigin
        self.durationMinutes = durationMinutes
        self.source = source
        self.studios = studios
    }
}

struct MediaItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let overview: String
    let posterURL: URL?
    let backdropURL: URL?
    let kind: MediaKind
    let tmdbID: Int?
    let aniListID: Int?
    let malID: Int?
    let providerNames: [String]
    let year: String?
    let episodeCount: Int?
    var metadata: MediaMetadata? = nil

    static let preview = MediaItem(
        id: "preview-furiosa",
        title: "Furiosa: A Mad Max Saga",
        overview: "As the world falls, young Furiosa is snatched from the Green Place of Many Mothers and into the hands of a great biker horde led by Dementus.",
        posterURL: URL(string: "https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg"),
        backdropURL: URL(string: "https://image.tmdb.org/t/p/w1280/7Zx3wDG5bBtcfk8lcn1d2wVjZQ.jpg"),
        kind: .movie,
        tmdbID: 786892,
        aniListID: nil,
        malID: nil,
        providerNames: [PlaybackSource.moviesAPI.rawValue],
        year: "2024",
        episodeCount: nil
    )
}

struct WatchEntry: Identifiable, Codable, Hashable {
    let id: String
    let media: MediaItem
    var progress: Double
    var lastPlayed: Date
}

struct DownloadEntry: Identifiable, Codable, Hashable {
    let id: String
    let media: MediaItem
    let fileName: String
    let localURL: URL
    let downloadedAt: Date
    let episode: Int?
}

/// One saved title inside a list. `alias` is a per-list display name, so renaming
/// a title inside a list never changes it anywhere else in the app.
struct CollectionEntry: Identifiable, Hashable, Codable {
    let media: MediaItem
    /// Per-list display name. `nil` means "show the title's real name".
    var alias: String?
    var addedAt: Date

    var id: String { media.id }

    /// The name this entry shows inside its own list.
    var displayTitle: String {
        guard let alias, !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return media.title }
        return alias
    }

    /// True when the entry carries a name that only exists inside its list.
    var isRenamed: Bool {
        alias?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    init(media: MediaItem, alias: String? = nil, addedAt: Date = Date()) {
        self.media = media
        self.alias = alias
        self.addedAt = addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        media = try container.decode(MediaItem.self, forKey: .media)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }
}

/// How a list's cover is drawn. `mediaIDs` powers the "four titles" and "one
/// title" styles, `customImageData` the picked-photo style.
struct CollectionArtwork: Hashable, Codable {
    enum Style: String, Codable, CaseIterable, Identifiable {
        /// The first four titles currently in the list.
        case automatic
        /// Up to four titles the user picked, in the order they picked them.
        case mosaic
        /// A single title the user picked.
        case single
        /// A photo the user picked from their library.
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic: return "Automatic"
            case .mosaic: return "Four titles"
            case .single: return "One title"
            case .custom: return "Custom image"
            }
        }

        var subtitle: String {
            switch self {
            case .automatic: return "The first four titles you save"
            case .mosaic: return "Pick up to four titles to show"
            case .single: return "Pick one title to fill the cover"
            case .custom: return "Choose a photo from your library"
            }
        }

        var symbolName: String {
            switch self {
            case .automatic: return "wand.and.stars"
            case .mosaic: return "square.grid.2x2"
            case .single: return "rectangle.portrait"
            case .custom: return "photo"
            }
        }

        /// How many titles this style can draw at once.
        var slotCount: Int {
            switch self {
            case .mosaic: return 4
            case .single: return 1
            case .automatic, .custom: return 0
            }
        }
    }

    var style: Style
    /// Titles used by the `.mosaic` and `.single` styles, in display order.
    var mediaIDs: [String]
    /// Downscaled JPEG data backing the `.custom` style.
    var customImageData: Data?

    init(style: Style = .automatic, mediaIDs: [String] = [], customImageData: Data? = nil) {
        self.style = style
        self.mediaIDs = mediaIDs
        self.customImageData = customImageData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(Style.self, forKey: .style) ?? .automatic
        mediaIDs = try container.decodeIfPresent([String].self, forKey: .mediaIDs) ?? []
        customImageData = try container.decodeIfPresent(Data.self, forKey: .customImageData)
    }
}

/// A user-made list. FrostPlay always keeps at least one (the built-in
/// "My List", which "Add to My List" targets); the rest are created, renamed,
/// re-covered, and deleted by the user.
struct MediaCollection: Identifiable, Hashable, Codable {
    static let builtInID = "my-list"

    var id: String
    var name: String
    var subtitle: String?
    var entries: [CollectionEntry]
    var artwork: CollectionArtwork
    var createdAt: Date
    /// The built-in list cannot be deleted.
    var isBuiltIn: Bool

    static var builtIn: MediaCollection {
        MediaCollection(id: builtInID, name: "My List", entries: [], createdAt: Date(), isBuiltIn: true)
    }

    var items: [MediaItem] { entries.map(\.media) }

    func contains(_ media: MediaItem) -> Bool { entries.contains { $0.media.id == media.id } }

    init(
        id: String,
        name: String,
        subtitle: String? = nil,
        entries: [CollectionEntry] = [],
        artwork: CollectionArtwork = CollectionArtwork(),
        createdAt: Date = Date(),
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.entries = entries
        self.artwork = artwork
        self.createdAt = createdAt
        self.isBuiltIn = isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        entries = try container.decodeIfPresent([CollectionEntry].self, forKey: .entries) ?? []
        artwork = try container.decodeIfPresent(CollectionArtwork.self, forKey: .artwork) ?? CollectionArtwork()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }
}

struct EpisodeInfo: Identifiable, Hashable, Codable {
    let number: Int
    let name: String
    let overview: String
    let airDate: String?
    let imageURL: URL?
    var playbackURL: URL? = nil
    var id: Int { number }
}

struct SeasonEpisodeInfo: Identifiable, Hashable, Codable {
    let season: Int
    let episodeCount: Int
    var episodes: [EpisodeInfo] = []
    var id: Int { season }
}

enum PlaybackSource: String, Codable, CaseIterable, Identifiable, Hashable {
    case vidLink = "VidLink"
    case megaPlay = "MegaPlay"
    case vidAPI = "VidAPI"
    case cineSRC = "CineSRC"
    case autoEmbed = "AutoEmbed"
    case moviesAPI = "MoviesAPI"

    var id: String { rawValue }

    // Only sources with verified identifier contracts are exposed in the app.
    static var implemented: [PlaybackSource] { [.megaPlay, .vidLink, .moviesAPI] }

    var supports: Set<MediaKind> {
        switch self {
        case .megaPlay: return [.anime]
        case .vidLink: return [.movie, .tv]
        case .moviesAPI: return [.movie, .tv]
        default: return []
        }
    }

    /// One-line description shown when choosing a default source.
    var blurb: String {
        switch self {
        case .megaPlay: return "Anime, addressed by AniList or MAL ID"
        case .vidLink: return "Movies and TV, addressed by TMDB ID"
        case .moviesAPI: return "Movies and TV, addressed by TMDB ID"
        case .vidAPI: return "Not available yet"
        case .cineSRC: return "Not available yet"
        case .autoEmbed: return "Not available yet"
        }
    }

    /// The sources that are legal for a title type. MegaPlay is anime-only and the
    /// TMDB embeds are movie/TV-only, so a title can never be routed to a source
    /// that does not support it (a TMDB title can never attempt MegaPlay).
    static func allowed(for kind: MediaKind) -> Set<PlaybackSource> {
        Set(implemented.filter { $0.supports.contains(kind) })
    }

    /// The built-in default when the user has not chosen one or their choice is
    /// incompatible with the title type.
    static func builtInDefault(for kind: MediaKind) -> PlaybackSource {
        kind == .anime ? .megaPlay : .vidLink
    }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .dark: .dark; case .light: .light; case .system: nil }
    }
}

struct FrostPlaySettings: Codable {
    // This default is user-configurable in Settings and is intentionally stored locally.
    // Keep the provided key as the first-run default; users can replace it in Settings.
    var tmdbAPIKey = (Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String) ?? "0cb8d58d39349ca2aa7438f9fd10282a"
    var tmdbReadAccessToken = ""
    var theme: AppTheme = .dark
    var enabledSources: [PlaybackSource] = PlaybackSource.implemented
    // Separate defaults because anime is addressed by AniList/MAL ID while movies
    // and TV are addressed by TMDB ID; one source cannot serve both.
    var defaultAnimeSource: PlaybackSource = .megaPlay
    var defaultMovieTVSource: PlaybackSource = .vidLink
    var preferredAnimeLanguage = "sub"
    var selectedProvider: String?
    var textScale = 1.0
    var boldText = false
    var backgroundOpacity = 0.4
    var backgroundBlur = 18.0
    var lineSpacing = 1.5
    var reduceMotion = false
    var showImageLogos = true
    var backdropTrailers = false
    var autoHideHeader = true
    var autoplayNextEpisode = true
    var autoSkipIntro = false
    var autoSubtitles = false
    var preferredQuality = "1080p"
    var subtitleUseNativePlayer = false
    var subtitleColor = "white"
    var homeSections: [HomeSection] = HomeSection.defaultOrder
    var downloadsEnabled = true

    // MARK: Lists

    /// Cover style applied to newly created lists.
    var listCoverStyle: CollectionArtwork.Style = .automatic
    /// Shows the saved-title count on each list's cover.
    var showListCounts = true
    /// Shows per-list renamed titles inside a list instead of the real title.
    var showListAliases = true
    /// Asks before deleting a list.
    var confirmListDeletion = true

    // MARK: Loading

    /// Shows shimmering placeholders while a surface loads.
    var showLoadingPlaceholders = true
    /// How long the placeholders stay up on a first load, even when the network
    /// answers instantly, so content never flashes in and out.
    var minimumPlaceholderSeconds = 1.2

    // MARK: Home

    /// Picks a different Home feed on every visit instead of the same row.
    var rotateHomeCatalog = true

    // MARK: Anime metadata

    /// Fills AniList's episode rows with Kitsu's per-episode titles, synopses,
    /// air dates, and artwork. AniList stays authoritative for numbering.
    var kitsuEpisodeDetails = true

    enum CodingKeys: String, CodingKey {
        case tmdbAPIKey, tmdbReadAccessToken, theme, enabledSources, defaultAnimeSource, defaultMovieTVSource, preferredAnimeLanguage, selectedProvider, textScale, boldText, backgroundOpacity, backgroundBlur, lineSpacing, reduceMotion, showImageLogos, backdropTrailers, autoHideHeader, autoplayNextEpisode, autoSkipIntro, autoSubtitles, preferredQuality, subtitleUseNativePlayer, subtitleColor, homeSections, downloadsEnabled
        case listCoverStyle, showListCounts, showListAliases, confirmListDeletion
        case showLoadingPlaceholders, minimumPlaceholderSeconds
        case rotateHomeCatalog
        case kitsuEpisodeDetails
    }

    /// The source that should be tried first for a title type, always guaranteed to
    /// be compatible with that type.
    func defaultSource(for kind: MediaKind) -> PlaybackSource {
        let candidate = kind == .anime ? defaultAnimeSource : defaultMovieTVSource
        if PlaybackSource.allowed(for: kind).contains(candidate) { return candidate }
        return PlaybackSource.builtInDefault(for: kind)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FrostPlaySettings()
        tmdbAPIKey = try container.decodeIfPresent(String.self, forKey: .tmdbAPIKey) ?? defaults.tmdbAPIKey
        tmdbReadAccessToken = try container.decodeIfPresent(String.self, forKey: .tmdbReadAccessToken) ?? defaults.tmdbReadAccessToken
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? defaults.theme
        enabledSources = try container.decodeIfPresent([PlaybackSource].self, forKey: .enabledSources) ?? defaults.enabledSources
        defaultAnimeSource = try container.decodeIfPresent(PlaybackSource.self, forKey: .defaultAnimeSource) ?? defaults.defaultAnimeSource
        defaultMovieTVSource = try container.decodeIfPresent(PlaybackSource.self, forKey: .defaultMovieTVSource) ?? defaults.defaultMovieTVSource
        preferredAnimeLanguage = try container.decodeIfPresent(String.self, forKey: .preferredAnimeLanguage) ?? defaults.preferredAnimeLanguage
        selectedProvider = try container.decodeIfPresent(String.self, forKey: .selectedProvider)
        textScale = try container.decodeIfPresent(Double.self, forKey: .textScale) ?? defaults.textScale
        boldText = try container.decodeIfPresent(Bool.self, forKey: .boldText) ?? defaults.boldText
        backgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? defaults.backgroundOpacity
        backgroundBlur = try container.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? defaults.backgroundBlur
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? defaults.lineSpacing
        reduceMotion = try container.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? defaults.reduceMotion
        showImageLogos = try container.decodeIfPresent(Bool.self, forKey: .showImageLogos) ?? defaults.showImageLogos
        backdropTrailers = try container.decodeIfPresent(Bool.self, forKey: .backdropTrailers) ?? defaults.backdropTrailers
        autoHideHeader = try container.decodeIfPresent(Bool.self, forKey: .autoHideHeader) ?? defaults.autoHideHeader
        autoplayNextEpisode = try container.decodeIfPresent(Bool.self, forKey: .autoplayNextEpisode) ?? defaults.autoplayNextEpisode
        autoSkipIntro = try container.decodeIfPresent(Bool.self, forKey: .autoSkipIntro) ?? defaults.autoSkipIntro
        autoSubtitles = try container.decodeIfPresent(Bool.self, forKey: .autoSubtitles) ?? defaults.autoSubtitles
        preferredQuality = try container.decodeIfPresent(String.self, forKey: .preferredQuality) ?? defaults.preferredQuality
        subtitleUseNativePlayer = try container.decodeIfPresent(Bool.self, forKey: .subtitleUseNativePlayer) ?? defaults.subtitleUseNativePlayer
        subtitleColor = try container.decodeIfPresent(String.self, forKey: .subtitleColor) ?? defaults.subtitleColor
        homeSections = try container.decodeIfPresent([HomeSection].self, forKey: .homeSections) ?? defaults.homeSections
        downloadsEnabled = try container.decodeIfPresent(Bool.self, forKey: .downloadsEnabled) ?? defaults.downloadsEnabled
        listCoverStyle = try container.decodeIfPresent(CollectionArtwork.Style.self, forKey: .listCoverStyle) ?? defaults.listCoverStyle
        showListCounts = try container.decodeIfPresent(Bool.self, forKey: .showListCounts) ?? defaults.showListCounts
        showListAliases = try container.decodeIfPresent(Bool.self, forKey: .showListAliases) ?? defaults.showListAliases
        confirmListDeletion = try container.decodeIfPresent(Bool.self, forKey: .confirmListDeletion) ?? defaults.confirmListDeletion
        showLoadingPlaceholders = try container.decodeIfPresent(Bool.self, forKey: .showLoadingPlaceholders) ?? defaults.showLoadingPlaceholders
        minimumPlaceholderSeconds = try container.decodeIfPresent(Double.self, forKey: .minimumPlaceholderSeconds) ?? defaults.minimumPlaceholderSeconds
        rotateHomeCatalog = try container.decodeIfPresent(Bool.self, forKey: .rotateHomeCatalog) ?? defaults.rotateHomeCatalog
        kitsuEpisodeDetails = try container.decodeIfPresent(Bool.self, forKey: .kitsuEpisodeDetails) ?? defaults.kitsuEpisodeDetails
    }
}

enum HomeSection: String, Codable, CaseIterable, Identifiable {
    case continueWatching
    case popular
    case myList

    var id: String { rawValue }
    var title: String {
        switch self {
        case .continueWatching: return "Continue Watching"
        case .popular: return "Popular Right Now"
        case .myList: return "Your List"
        }
    }

    /// Short description shown in the on-Home section editor.
    var subtitle: String {
        switch self {
        case .continueWatching: return "Pick up where you left off"
        case .popular: return "Trending movies and shows"
        case .myList: return "Titles you saved"
        }
    }

    /// SF Symbol shown in the on-Home section editor.
    var symbolName: String {
        switch self {
        case .continueWatching: return "play.circle.fill"
        case .popular: return "flame.fill"
        case .myList: return "bookmark.fill"
        }
    }

    static let defaultOrder: [HomeSection] = [.continueWatching, .popular, .myList]
}
