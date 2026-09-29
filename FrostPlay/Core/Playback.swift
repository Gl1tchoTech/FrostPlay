import AVFoundation
import AVKit
import SwiftUI
import WebKit

struct ResolvedPlayback {
    let source: PlaybackSource
    let format: PlaybackFormat
}

/// The hosts FrostPlay is allowed to load inside the in-app player, one per
/// implemented source: MegaPlay (anime), VidLink and MoviesAPI (movies/TV).
///
/// The web view is source-agnostic, so this allowlist — not MegaPlay alone —
/// decides what may render. Checking every embed against megaplay.buzz rejected
/// each VidLink/MoviesAPI movie and TV embed and blamed MegaPlay for it.
enum EmbedURL {
    static let trustedHosts = ["megaplay.buzz", "vidlink.pro", "moviesapi.to"]

    static func validated(_ url: URL?) -> URL? {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return nil }
        let trusted = trustedHosts.contains(host)
            || trustedHosts.contains { host.hasSuffix(".\($0)") }
        return trusted ? url : nil
    }

    /// True when a resolved format can actually play: direct streams always can,
    /// embeds only from a trusted source host.
    static func isPlayable(_ format: PlaybackFormat) -> Bool {
        switch format {
        case .embed(let url): return validated(url) != nil
        case .hls, .mp4: return true
        }
    }

    /// The source an embed belongs to, so the player can name the right one.
    static func source(hosting url: URL) -> PlaybackSource? {
        guard let host = url.host?.lowercased() else { return nil }
        if host == "megaplay.buzz" || host.hasSuffix(".megaplay.buzz") { return .megaPlay }
        if host == "vidlink.pro" || host.hasSuffix(".vidlink.pro") { return .vidLink }
        if host == "moviesapi.to" || host.hasSuffix(".moviesapi.to") { return .moviesAPI }
        return nil
    }
}

struct PlaybackResolver {
    private let adapters: [PlaybackSourceAdapter] = [VidLinkAdapter(), MegaPlayAdapter(), MoviesAPIAdapter()]

    /// Resolves a playable format, returning the source that produced it so the UI
    /// can show what is actually playing.
    func resolveSource(
        media: MediaItem,
        settings: FrostPlaySettings,
        season: Int? = 1,
        episode: Int? = 1,
        preferredURL: URL? = nil,
        forcedSource: PlaybackSource? = nil
    ) -> ResolvedPlayback? {
        // Sources are strictly keyed to the title type: anime -> MegaPlay,
        // movies/TV -> VidLink/MoviesAPI. A TMDB title can never attempt MegaPlay.
        let allowed = PlaybackSource.allowed(for: media.kind)
        guard !allowed.isEmpty else { return nil }

        // A prefilled MegaPlay URL is only trusted for anime titles.
        if media.kind == .anime,
           media.tmdbID == nil,
           let preferredURL = MegaPlayURL.validated(preferredURL) {
            return ResolvedPlayback(source: .megaPlay, format: .embed(preferredURL))
        }

        // The user's default source for this title type is always tried first,
        // then the remaining enabled sources in their saved order.
        let preferred: PlaybackSource?
        if let forcedSource, allowed.contains(forcedSource) {
            preferred = forcedSource
        } else {
            preferred = settings.defaultSource(for: media.kind)
        }
        var ordered = settings.enabledSources.filter { allowed.contains($0) }
        if let preferred {
            ordered.removeAll { $0 == preferred }
            ordered.insert(preferred, at: 0)
        }

        for source in ordered {
            guard allowed.contains(source), source.supports.contains(media.kind) else { continue }
            guard let adapter = adapters.first(where: { $0.source == source }) else { continue }
            guard let result = adapter.playback(for: media, season: season, episode: episode, language: settings.preferredAnimeLanguage),
                  EmbedURL.isPlayable(result) else { continue }
            return ResolvedPlayback(source: source, format: result)
        }
        return nil
    }

    func resolve(
        media: MediaItem,
        settings: FrostPlaySettings,
        season: Int? = 1,
        episode: Int? = 1,
        preferredURL: URL? = nil,
        forcedSource: PlaybackSource? = nil
    ) -> PlaybackFormat? {
        resolveSource(media: media, settings: settings, season: season, episode: episode, preferredURL: preferredURL, forcedSource: forcedSource)?.format
    }
}

struct HybridPlayer: View {
    let format: PlaybackFormat
    var source: PlaybackSource? = nil
    var body: some View {
        switch format {
        case .embed(let url): EmbedPlayer(url: url, source: source ?? EmbedURL.source(hosting: url))
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
        player.play()
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
    var source: PlaybackSource? = nil

    /// Remembers which embed is mounted so a different source reloads the player.
    final class Coordinator {
        var loadedURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        loadEmbed(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload when the resolved source changes (the in-player source picker)
        // instead of keeping whatever embed was mounted first.
        guard context.coordinator.loadedURL != url else { return }
        loadEmbed(in: webView, coordinator: context.coordinator)
    }

    private func loadEmbed(in webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadedURL = url
        guard let trustedURL = EmbedURL.validated(url) else {
            let label = source.map { "\($0.rawValue) embed" } ?? "This embed"
            webView.loadHTMLString("<html><body style='margin:0;background:#000;color:#fff;font:16px -apple-system;display:grid;place-items:center;height:100vh;text-align:center;padding:24px'>\(label) could not be loaded: unsupported source host</body></html>", baseURL: nil)
            return
        }
        let iframeURL = trustedURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><style>html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}iframe{border:0;width:100%;height:100%;display:block}</style></head><body><iframe src="\(iframeURL)" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen referrerpolicy="origin"></iframe></body></html>
        """
        // The embed's own origin, so each source keeps its referrer rules.
        webView.loadHTMLString(html, baseURL: trustedURL)
    }
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
