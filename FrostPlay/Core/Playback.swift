import AVFoundation
import AVKit
import SwiftUI
import WebKit

struct PlaybackResolver {
    private let adapters: [PlaybackSourceAdapter] = [VidLinkAdapter(), MegaPlayAdapter(), MoviesAPIAdapter()]

    func resolve(media: MediaItem, settings: FrostPlaySettings, season: Int? = 1, episode: Int? = 1) -> PlaybackFormat? {
        let allowed: Set<PlaybackSource> = media.kind == .anime ? [.megaPlay] : [.vidLink, .moviesAPI]
        let orderedSources = settings.enabledSources.filter { allowed.contains($0) }
        for source in orderedSources {
            guard source.supports.contains(media.kind) else { continue }
            guard let adapter = adapters.first(where: { $0.source == source }) else { continue }
            if let result = adapter.playback(for: media, season: season, episode: episode, language: settings.preferredAnimeLanguage) {
                return result
            }
        }
        return nil
    }
}

struct HybridPlayer: View {
    let format: PlaybackFormat
    var body: some View {
        switch format {
        case .embed(let url): EmbedPlayer(url: url)
        case .hls(let url), .mp4(let url): DirectVideoPlayer(url: url)
        }
    }
}

final class PlayerController: ObservableObject {
    let player: AVPlayer

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 12
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = false
    }

    func prepare() {
        player.playImmediatelyIfPossible()
    }
}

struct DirectVideoPlayer: View {
    let url: URL
    @StateObject private var controller: PlayerController

    init(url: URL) {
        self.url = url
        _controller = StateObject(wrappedValue: PlayerController(url: url))
    }

    var body: some View {
        VideoPlayer(player: controller.player)
            .background(Color.black)
            .onAppear { controller.prepare() }
            .onDisappear { controller.player.pause() }
            .ignoresSafeArea()
    }
}

struct EmbedPlayer: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30))
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}

struct AuthorizedDownloadManager {
    static func downloadableURL(for format: PlaybackFormat) -> URL? {
        switch format {
        case .mp4(let url): return url
        case .hls, .embed: return nil
        }
    }

    static func fileName(for media: MediaItem, episode: Int? = nil) -> String {
        let safeTitle = media.title.replacingOccurrences(of: "[^A-Za-z0-9 ]", with: "", options: .regularExpression)
        let suffix = episode.map { " - Episode \($0)" } ?? ""
        return "\(safeTitle)\(suffix).mp4"
    }
}
