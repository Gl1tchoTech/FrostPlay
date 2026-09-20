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
        providerNames: ["VidLink", "TMDB"],
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

struct SeasonEpisodeInfo: Identifiable, Hashable {
    let season: Int
    let episodeCount: Int
    var id: Int { season }
}

enum PlaybackSource: String, Codable, CaseIterable, Identifiable {
    case vidLink = "VidLink"
    case megaPlay = "MegaPlay"
    case vidAPI = "VidAPI"
    case cineSRC = "CineSRC"
    case autoEmbed = "AutoEmbed"
    case moviesAPI = "MoviesAPI"

    var id: String { rawValue }

    static var implemented: [PlaybackSource] { [.megaPlay, .vidLink, .moviesAPI] }

    var supports: Set<MediaKind> {
        switch self {
        case .megaPlay: return [.anime]
        default: return [.movie, .tv]
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
    var tmdbAPIKey = (Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String) ?? ""
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
}
