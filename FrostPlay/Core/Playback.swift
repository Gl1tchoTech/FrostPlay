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

    /// The direct-stream format a URL denotes, if any: an HLS playlist or a
    /// progressive file. Anything else — an embed page, a segment, a key — is not
    /// a stream FrostPlay can play or save on its own.
    static func directFormat(for url: URL) -> PlaybackFormat? {
        let path = url.path.lowercased()
        if path.hasSuffix(".m3u8") { return .hls(url) }
        if path.hasSuffix(".mp4") || path.hasSuffix(".m4v") || path.hasSuffix(".mov") { return .mp4(url) }
        return nil
    }

    /// A direct stream URL reported by an embed's own player. Only HTTPS URLs that
    /// are a playlist or progressive file are believed; the CDN host is unknown in
    /// advance, so it cannot be checked against `trustedHosts`.
    static func reportedStreamURL(from rawValue: String) -> URL? {
        guard let url = URL(string: rawValue), url.scheme?.lowercased() == "https" else { return nil }
        if case .hls(let stream) = directFormat(for: url) { return stream }
        if case .mp4(let stream) = directFormat(for: url) { return stream }
        return nil
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

        // A preferred URL may itself be a direct stream — an .m3u8 playlist or a
        // progressive file — rather than an embed. Those are played directly and,
        // unlike an embed, can be saved for offline playback.
        if let preferredURL, let direct = EmbedURL.directFormat(for: preferredURL) {
            return ResolvedPlayback(source: settings.defaultSource(for: media.kind), format: direct)
        }

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

/// What an embedded third-party player reported. An embed's video lives in a
/// cross-origin iframe, so the sources that publish progress events are listened
/// to through the message bridge and everything else falls back to the player's
/// own close-time estimate.
enum EmbedPlaybackEvent {
    case finished
    case progress(seconds: Double, duration: Double)
    /// The embed's own player requested a direct stream — an HLS playlist or a
    /// progressive file. Forwarded so the title can be saved for offline playback
    /// even though the source only ever handed FrostPlay an embed page.
    case stream(URL)
}

struct HybridPlayer: View {
    let format: PlaybackFormat
    var source: PlaybackSource? = nil
    /// Seconds to resume from, for direct files only (an embed owns its own seek).
    var resumeSeconds: Double = 0
    var onFinished: (() -> Void)? = nil
    var onProgress: ((Double, Double) -> Void)? = nil
    /// Receives a direct stream URL an embed discovered while it was playing.
    var onStream: ((URL) -> Void)? = nil

    var body: some View {
        switch format {
        case .embed(let url):
            EmbedPlayer(
                url: url,
                source: source ?? EmbedURL.source(hosting: url),
                onEvent: { event in
                    switch event {
                    case .finished: onFinished?()
                    case .progress(let seconds, let duration): onProgress?(seconds, duration)
                    case .stream(let streamURL): onStream?(streamURL)
                    }
                }
            )
        case .hls(let url), .mp4(let url):
            DirectVideoPlayer(url: url, resumeSeconds: resumeSeconds, onFinished: onFinished, onProgress: onProgress)
        }
    }
}

final class PlayerController: ObservableObject {
    let player: AVPlayer
    /// Fired when a direct file reaches its end, which is what lets the player
    /// offer the next episode without the user touching anything.
    var onFinished: (() -> Void)?
    /// Fired every few seconds with (position, duration), both in seconds.
    var onProgress: ((Double, Double) -> Void)?

    private let resumeSeconds: Double
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?

    init(url: URL, resumeSeconds: Double = 0) {
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 12
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = false
        self.resumeSeconds = max(resumeSeconds, 0)
    }

    func prepare() {
        installObservers()
        // Ignore a resume point that is only a few seconds in; restarting is
        // better than landing on the opening seconds twice.
        if resumeSeconds > 5 {
            player.seek(to: CMTime(seconds: resumeSeconds, preferredTimescale: 600))
        }
        player.play()
    }

    private func installObservers() {
        guard endObserver == nil else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.onFinished?()
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self,
                  let duration = self.player.currentItem?.duration.seconds,
                  duration.isFinite, duration > 0,
                  time.seconds.isFinite else { return }
            self.onProgress?(time.seconds, duration)
        }
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }
}

struct DirectVideoPlayer: View {
    let url: URL
    var resumeSeconds: Double = 0
    var onFinished: (() -> Void)? = nil
    var onProgress: ((Double, Double) -> Void)? = nil
    @StateObject private var controller: PlayerController

    init(url: URL, resumeSeconds: Double = 0, onFinished: (() -> Void)? = nil, onProgress: ((Double, Double) -> Void)? = nil) {
        self.url = url
        self.resumeSeconds = resumeSeconds
        self.onFinished = onFinished
        self.onProgress = onProgress
        _controller = StateObject(wrappedValue: PlayerController(url: url, resumeSeconds: resumeSeconds))
    }

    var body: some View {
        VideoPlayer(player: controller.player)
            .background(Color.black)
            .onAppear {
                controller.onFinished = onFinished
                controller.onProgress = onProgress
                controller.prepare()
            }
            .onDisappear { controller.player.pause() }
            .ignoresSafeArea()
    }
}

struct EmbedPlayer: UIViewRepresentable {
    let url: URL
    var source: PlaybackSource? = nil
    /// Receives the progress and completion events an embed publishes.
    var onEvent: ((EmbedPlaybackEvent) -> Void)? = nil

    /// Remembers which embed is mounted so a different source reloads the player,
    /// and owns the script bridge that turns embed events into Swift callbacks.
    final class Coordinator {
        var loadedURL: URL?
        let bridge = MessageBridge()
    }

    /// The wrapper page is loaded with the embed's own origin as its base URL, so
    /// `postMessage` from the embed's iframe lands here. Every message is
    /// whitelisted back to the trusted source hosts before it is believed.
    final class MessageBridge: NSObject, WKScriptMessageHandler {
        static let handlerName = "frostplayPlayback"
        var onEvent: ((EmbedPlaybackEvent) -> Void)?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let event = body["event"] as? String else { return }
            switch event {
            case "complete":
                onEvent?(.finished)
            case "progress":
                let seconds = (body["currentTime"] as? NSNumber)?.doubleValue ?? 0
                let duration = (body["duration"] as? NSNumber)?.doubleValue ?? 0
                if seconds.isFinite, duration.isFinite, duration > 0 {
                    onEvent?(.progress(seconds: seconds, duration: duration))
                }
            case "stream":
                if let raw = body["url"] as? String, let streamURL = EmbedURL.reportedStreamURL(from: raw) {
                    onEvent?(.stream(streamURL))
                }
            default:
                break
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator.bridge, name: MessageBridge.handlerName)
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        context.coordinator.bridge.onEvent = onEvent
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        loadEmbed(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.bridge.onEvent = onEvent
        // Reload when the resolved source changes (the in-player source picker)
        // instead of keeping whatever embed was mounted first.
        guard context.coordinator.loadedURL != url else { return }
        loadEmbed(in: webView, coordinator: context.coordinator)
    }

    /// Removes the message handler so a torn-down player does not keep the bridge
    /// (and the closures it holds) alive.
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageBridge.handlerName)
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

    /// Forwarded from the embed to FrostPlay. Embeds cannot be observed directly,
    /// so this listens for the playback events the sources publish and reports only
    /// messages that came from a trusted host.
    private static let bridgeScript: String = {
        let hosts = EmbedURL.trustedHosts.map { "\"\($0)\"" }.joined(separator: ", ")
        return scriptTemplate
            .replacingOccurrences(of: "__HANDLER__", with: MessageBridge.handlerName)
            .replacingOccurrences(of: "__TRUSTED_HOSTS__", with: "[\(hosts)]")
    }()

    private static let scriptTemplate = """
    (function () {
      var TRUSTED = __TRUSTED_HOSTS__;
      function trusted(origin) {
        try {
          var host = new URL(origin).hostname.toLowerCase();
          for (var i = 0; i < TRUSTED.length; i++) {
            var allowed = TRUSTED[i];
            if (host === allowed || host.slice(-(allowed.length + 1)) === '.' + allowed) return true;
          }
        } catch (error) {}
        return false;
      }
      function send(payload) {
        try { window.webkit.messageHandlers.__HANDLER__.postMessage(payload); } catch (error) {}
      }
      // --- Direct stream discovery ------------------------------------------
      // The embed's own player has to request the real media eventually: an HLS
      // playlist (.m3u8) or a progressive file (.mp4). This script is injected
      // into every frame of the embed, so it can watch those requests and forward
      // the URL, letting FrostPlay save the title for offline playback even though
      // the source only ever handed it an embed page.
      var reported = {};
      function report(candidate) {
        if (typeof candidate !== 'string' || !candidate) return;
        var url;
        try { url = new URL(candidate, location.href); } catch (error) { return; }
        if (url.protocol !== 'https:') return;
        var path = url.pathname.toLowerCase();
        var interesting = path.indexOf('.m3u8') !== -1 || path.indexOf('.mp4') !== -1 || path.indexOf('.m4v') !== -1 || path.indexOf('.mov') !== -1;
        if (!interesting || reported[url.href]) return;
        reported[url.href] = true;
        send({ event: 'stream', url: url.href });
      }
      try {
        var originalFetch = window.fetch;
        if (typeof originalFetch === 'function') {
          window.fetch = function (input) {
            try { report(typeof input === 'string' ? input : (input && input.url)); } catch (error) {}
            return originalFetch.apply(this, arguments);
          };
        }
      } catch (error) {}
      try {
        var originalOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function (method, requestURL) {
          try { report(requestURL); } catch (error) {}
          return originalOpen.apply(this, arguments);
        };
      } catch (error) {}
      try {
        var mediaSrc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
        if (mediaSrc && mediaSrc.set) {
          Object.defineProperty(HTMLMediaElement.prototype, 'src', {
            configurable: true,
            enumerable: mediaSrc.enumerable,
            get: mediaSrc.get,
            set: function (value) {
              try { report(value); } catch (error) {}
              return mediaSrc.set.call(this, value);
            }
          });
        }
      } catch (error) {}
      try {
        var originalSetAttribute = Element.prototype.setAttribute;
        Element.prototype.setAttribute = function (name, value) {
          try { if (String(name).toLowerCase() === 'src') report(value); } catch (error) {}
          return originalSetAttribute.apply(this, arguments);
        };
      } catch (error) {}
      // Fallback for players that build the request internally: the resource
      // timing buffer still records every URL this frame fetched.
      function scanResources() {
        try {
          var entries = performance.getEntriesByType ? performance.getEntriesByType('resource') : [];
          for (var i = 0; i < entries.length; i++) { report(entries[i].name); }
        } catch (error) {}
      }
      setInterval(scanResources, 4000);
      function interpret(data) {
        if (typeof data === 'string') {
          try { data = JSON.parse(data); } catch (error) { return; }
        }
        if (!data || typeof data !== 'object') return;
        var name = String(data.event || data.type || data.name || '').toLowerCase();
        var inner = (data.data && typeof data.data === 'object') ? data.data : {};
        if (name === 'complete' || name === 'ended' || name === 'finished' || name === 'video-ended') {
          send({ event: 'complete' });
          return;
        }
        var current = Number(data.currentTime || data.time || inner.currentTime || inner.time || 0);
        var total = Number(data.duration || inner.duration || 0);
        if (isFinite(current) && current >= 0) {
          send({ event: 'progress', currentTime: current, duration: isFinite(total) ? total : 0 });
        }
      }
      window.addEventListener('message', function (event) {
        if (!trusted(event.origin)) return;
        interpret(event.data);
      });
      function attach() {
        var video = document.querySelector('video');
        if (!video) { setTimeout(attach, 1500); return; }
        video.addEventListener('ended', function () { send({ event: 'complete' }); });
        video.addEventListener('timeupdate', function () {
          send({ event: 'progress', currentTime: video.currentTime, duration: video.duration || 0 });
        });
      }
      attach();
    })();
    """
}

struct AuthorizedDownloadManager {
    /// Only a directly addressable stream can be saved. An embed is a third-party
    /// iframe with no downloadable URL, so it is deliberately excluded.
    static func downloadableURL(for format: PlaybackFormat) -> URL? {
        switch format {
        case .mp4(let url), .hls(let url): return url
        case .embed: return nil
        }
    }

    static func canDownload(for format: PlaybackFormat) -> Bool {
        downloadableURL(for: format) != nil
    }

    static func isHLS(_ format: PlaybackFormat) -> Bool {
        if case .hls = format { return true }
        return false
    }

    static func fileName(for media: MediaItem, episode: Int? = nil) -> String {
        let safeTitle = media.title.replacingOccurrences(of: "[^A-Za-z0-9 ]", with: "", options: .regularExpression)
        let suffix = episode.map { " - Episode \($0)" } ?? ""
        return "\(safeTitle)\(suffix).mp4"
    }
}

/// Saves HLS (`.m3u8`) streams for offline playback with Apple's asset download
/// API, the only App Store-safe way to store a segmented stream. A finished asset
/// is an on-disk bundle whose path can change between launches, so it is reopened
/// from a bookmark (see `DownloadEntry.bookmarkData`) instead of a fixed URL.
final class HLSDownloadManager: NSObject, AVAssetDownloadDelegate {
    static let shared = HLSDownloadManager()

    /// Reports 0...1 progress for an in-flight download, keyed by FrostPlay's id.
    var onProgress: ((String, Double) -> Void)?
    /// Reports the on-disk location of a finished asset.
    var onFinish: ((String, URL) -> Void)?
    /// Reports a failed or cancelled download.
    var onFailure: ((String, Error?) -> Void)?

    private var tasks: [String: AVAssetDownloadTask] = [:]

    private lazy var session: AVAssetDownloadURLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.gl1tchotech.frostplay.hls")
        return AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: .main)
    }()

    func start(id: String, url: URL) {
        guard tasks[id] == nil else { return }
        let asset = AVURLAsset(url: url)
        guard let task = session.makeAssetDownloadTask(asset: asset, assetTitle: id, assetArtworkData: nil, options: nil) else {
            onFailure?(id, nil)
            return
        }
        task.taskDescription = id
        tasks[id] = task
        task.resume()
    }

    func cancel(id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
    }

    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        guard let id = assetDownloadTask.taskDescription else { return }
        let expected = timeRangeExpectedToLoad.duration.seconds
        guard expected.isFinite, expected > 0 else { return }
        let loaded = loadedTimeRanges.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds }
        onProgress?(id, min(max(loaded / expected, 0), 1))
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = assetDownloadTask.taskDescription else { return }
        tasks[id] = nil
        onFinish?(id, location)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // A completed task also reaches this point with a nil error; only a real
        // failure (including cancellation) should clear the pending download.
        guard let error, let id = task.taskDescription else { return }
        tasks[id] = nil
        onFailure?(id, error)
    }
}
