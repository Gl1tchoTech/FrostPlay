import Foundation
import SwiftUI

enum MediaKind: String, Codable, CaseIterable, Identifiable {
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
        year: "2024"
    )
}

struct WatchEntry: Identifiable, Codable, Hashable {
    let id: String
    let media: MediaItem
    var progress: Double
    var lastPlayed: Date
}

enum PlaybackSource: String, Codable, CaseIterable, Identifiable {
    case vidLink = "VidLink"
    case megaPlay = "MegaPlay"
    case vidAPI = "VidAPI"
    case cineSRC = "CineSRC"
    case autoEmbed = "AutoEmbed"

    var id: String { rawValue }

    static var implemented: [PlaybackSource] { [.vidLink, .megaPlay] }

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
    var theme: AppTheme = .dark
    var enabledSources: [PlaybackSource] = PlaybackSource.implemented
    var preferredAnimeLanguage = "sub"
    var selectedProvider: String?
}
