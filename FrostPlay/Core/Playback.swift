import AVKit
import SwiftUI
import WebKit

struct PlaybackResolver {
    private let adapters: [PlaybackSourceAdapter] = [VidLinkAdapter(), MegaPlayAdapter()]

    func resolve(media: MediaItem, settings: FrostPlaySettings, season: Int? = 1, episode: Int? = 1) -> PlaybackFormat? {
        for source in settings.enabledSources {
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

struct DirectVideoPlayer: View {
    let url: URL
    var body: some View { VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea() }
}

struct EmbedPlayer: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.load(URLRequest(url: url))
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
