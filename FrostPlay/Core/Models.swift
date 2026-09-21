import Foundation
import SwiftUI

enum MediaKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case movie, tv, anime
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PlaybackFormat: Codable, Equatable {
    case embed(URL)
    case hls(URL)
    case mp4(URL)
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

struct EpisodeInfo: Identifiable, Hashable, Codable {
    let number: Int
    let name: String
    let overview: String
    let airDate: String?
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
    static var implemented: [PlaybackSource] { [.megaPlay, .moviesAPI] }

    var supports: Set<MediaKind> {
        switch self {
        case .megaPlay: return [.anime]
        case .moviesAPI: return [.movie, .tv]
        default: return []
        }
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

    enum CodingKeys: String, CodingKey {
        case tmdbAPIKey, tmdbReadAccessToken, theme, enabledSources, preferredAnimeLanguage, selectedProvider, textScale, boldText, backgroundOpacity, backgroundBlur, lineSpacing, reduceMotion, showImageLogos, backdropTrailers, autoHideHeader, autoplayNextEpisode, autoSkipIntro, autoSubtitles, preferredQuality, subtitleUseNativePlayer, subtitleColor, homeSections
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FrostPlaySettings()
        tmdbAPIKey = try container.decodeIfPresent(String.self, forKey: .tmdbAPIKey) ?? defaults.tmdbAPIKey
        tmdbReadAccessToken = try container.decodeIfPresent(String.self, forKey: .tmdbReadAccessToken) ?? defaults.tmdbReadAccessToken
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? defaults.theme
        enabledSources = try container.decodeIfPresent([PlaybackSource].self, forKey: .enabledSources) ?? defaults.enabledSources
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

    static let defaultOrder: [HomeSection] = [.continueWatching, .popular, .myList]
}
