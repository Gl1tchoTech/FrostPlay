import SwiftUI

private let frostBackground = Color(red: 0.025, green: 0.025, blue: 0.03)
private let frostPanel = Color.white.opacity(0.075)
private let frostOrange = Color.orange

struct StreamingProvider: Identifiable {
    let id: String
    let name: String
    let caption: String
    let accent: Color
    let logoURL: URL?
}

private enum ProviderCatalog {
    static let providers: [StreamingProvider] = [
        StreamingProvider(id: "all", name: "All providers", caption: "Browse everything", accent: .orange, logoURL: nil),
        StreamingProvider(id: "netflix", name: "Netflix", caption: "Series & films", accent: Color(red: 0.85, green: 0.02, blue: 0.04), logoURL: URL(string: "https://cdn.simpleicons.org/netflix/FFFFFF")),
        StreamingProvider(id: "disney", name: "Disney+", caption: "Stories worth sharing", accent: Color(red: 0.08, green: 0.25, blue: 0.65), logoURL: URL(string: "https://cdn.simpleicons.org/disneyplus/FFFFFF")),
        StreamingProvider(id: "hulu", name: "Hulu", caption: "Only on Hulu", accent: Color(red: 0.15, green: 0.65, blue: 0.42), logoURL: URL(string: "https://cdn.simpleicons.org/hulu/FFFFFF")),
        StreamingProvider(id: "max", name: "Max", caption: "See it all", accent: Color(red: 0.28, green: 0.18, blue: 0.65), logoURL: URL(string: "https://cdn.simpleicons.org/max/FFFFFF")),
        StreamingProvider(id: "prime", name: "Prime Video", caption: "Included with Prime", accent: Color(red: 0.05, green: 0.35, blue: 0.7), logoURL: URL(string: "https://cdn.simpleicons.org/primevideo/FFFFFF"))
    ]
}

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "sparkles") }
            SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
            LibraryView().tabItem { Label("Library", systemImage: "bookmark") }
            HistoryView().tabItem { Label("Recent", systemImage: "clock") }
            SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(frostOrange)
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: FrostPlayStore

    private var visibleItems: [MediaItem] {
        guard let selected = store.settings.selectedProvider else { return store.homeItems }
        return store.homeItems.filter { $0.providerNames.contains(selected) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FROSTPLAY")
                            .font(.caption.weight(.bold))
                            .tracking(4)
                            .foregroundStyle(frostOrange)
                        Text("Your world of stories.")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Choose a service, then find your next obsession.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "Browse by service", eyebrow: "STREAMING NOW")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(ProviderCatalog.providers) { provider in
                                    ProviderCard(provider: provider, isSelected: selectedProviderID == provider.id) {
                                        store.settings.selectedProvider = provider.id == "all" ? nil : provider.name
                                    }
                                }
                            }
                        }
                    }

                    if !store.isTMDBConfigured {
                        NoticeCard(
                            title: "Catalog connection needed",
                            message: "Home is showing a local preview. Add TMDB_API_KEY or TMDB_API_READ_ACCESS_TOKEN to load live movie and TV catalogs.",
                            systemImage: "key.fill"
                        )
                    }

                    if store.isLoadingHome {
                        ProgressView("Loading your catalog…")
                            .tint(frostOrange)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    if let error = store.homeError, store.isTMDBConfigured {
                        NoticeCard(title: "Catalog unavailable", message: error, systemImage: "wifi.exclamationmark")
                    }

                    if let hero = visibleItems.first {
                        MediaCard(media: hero, featured: true)
                    } else if store.settings.selectedProvider != nil {
                        NoticeCard(title: "No titles for this service yet", message: "Provider availability will appear here once the catalog returns matching streaming-service data.", systemImage: "line.3.horizontal.decrease.circle")
                    }

                    ContentRail(title: "Continue watching", items: store.history.map(\.media))
                    ContentRail(title: "Your library", items: store.library)
                    ContentRail(title: "Popular right now", items: Array(visibleItems.dropFirst()))
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(frostBackground.ignoresSafeArea())
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .task { await store.loadHome() }
        }
        .preferredColorScheme(.dark)
    }

    private var selectedProviderID: String {
        ProviderCatalog.providers.first(where: { $0.name == store.settings.selectedProvider })?.id ?? "all"
    }
}

struct ProviderCard: View {
    let provider: StreamingProvider
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ProviderLogo(provider: provider, size: 42)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "arrow.up.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(isSelected ? 1 : 0.55))
                }
                Spacer(minLength: 2)
                Text(provider.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(provider.caption)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(16)
            .frame(width: 214, height: 132, alignment: .leading)
            .background(provider.accent.gradient.opacity(isSelected ? 0.95 : 0.72))
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 88, height: 88)
                    .offset(x: 24, y: 26)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(isSelected ? 0.8 : 0.12), lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: provider.accent.opacity(isSelected ? 0.32 : 0.12), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }
}

struct ProviderLogo: View {
    let provider: StreamingProvider
    let size: CGFloat

    var body: some View {
        Group {
            if let logoURL = provider.logoURL {
                AsyncImage(url: logoURL) { image in
                    image.resizable().scaledToFit().padding(8)
                } placeholder: {
                    Text(String(provider.name.prefix(1)))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
            } else {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(.white.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SearchView: View {
    @EnvironmentObject private var store: FrostPlayStore
    @State private var query = ""
    @State private var kind: MediaKind?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.55))
                    TextField("Search movies, shows, anime", text: $query)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { Task { await store.search(query: query, kind: kind) } }
                    if !query.isEmpty {
                        Button { query = ""; store.searchResults = []; store.searchError = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                .padding(15)
                .background(frostPanel)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Picker("Type", selection: $kind) {
                    Text("All").tag(MediaKind?.none)
                    ForEach(MediaKind.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)

                if store.isSearching {
                    ProgressView("Searching…").tint(frostOrange).padding(.top, 24)
                } else if let error = store.searchError {
                    NoticeCard(title: "Search needs attention", message: error, systemImage: "magnifyingglass")
                        .padding(.top, 24)
                } else if store.searchResults.isEmpty {
                    ContentUnavailableView("Start exploring", systemImage: "sparkles", description: Text("Search the TMDB and AniList catalogs."))
                        .padding(.top, 40)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.searchResults) { media in MediaRow(media: media) }
                        }
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .background(frostBackground.ignoresSafeArea())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        NavigationStack {
            List {
                ForEach(MediaKind.allCases) { kind in
                    let items = store.library.filter { $0.kind == kind }
                    if !items.isEmpty {
                        Section(kind.title) { ForEach(items) { MediaRow(media: $0) } }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(frostBackground)
            .navigationTitle("Library")
            .overlay { if store.library.isEmpty { ContentUnavailableView("Your library is empty", systemImage: "bookmark", description: Text("Save something you want to watch.")) } }
        }
        .preferredColorScheme(.dark)
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        NavigationStack {
            List(store.history) { entry in MediaRow(media: entry.media, progress: entry.progress) }
                .scrollContentBackground(.hidden)
                .background(frostBackground)
                .navigationTitle("Recently Watched")
                .overlay { if store.history.isEmpty { ContentUnavailableView("Nothing watched yet", systemImage: "clock", description: Text("Your local watch history will appear here.")) } }
        }
        .preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $store.settings.theme) { ForEach(AppTheme.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                }
                Section("Anime") {
                    Picker("Preferred streams", selection: $store.settings.preferredAnimeLanguage) {
                        Text("Sub").tag("sub")
                        Text("Dub").tag("dub")
                    }
                }
                Section("Playback sources") {
                    ForEach(PlaybackSource.implemented) { source in
                        Toggle(source.rawValue, isOn: Binding(get: { store.settings.enabledSources.contains(source) }, set: { _ in store.toggleSource(source) }))
                    }
                    Text("Sources are tried in the order shown. VidLink and MegaPlay currently use their documented embed players.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Source priority") {
                    ForEach(store.settings.enabledSources) { source in
                        Label(source.rawValue, systemImage: source == .megaPlay ? "sparkles" : "play.rectangle.fill")
                    }
                    .onMove { source, destination in store.moveSource(from: source, to: destination) }
                }
                Section("Catalog") {
                    SecureField("TMDB API key", text: $store.settings.tmdbAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                    Label(store.isTMDBConfigured ? "TMDB connected" : "TMDB key not configured", systemImage: store.isTMDBConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(store.isTMDBConfigured ? .green : .orange)
                    Text("This key is stored locally on this device and used for direct TMDB requests. Changing it takes effect on the next home load or search.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section { Text("FrostPlay stores library, settings, and watch history only on this device.").font(.footnote).foregroundStyle(.secondary) }
            }
            .scrollContentBackground(.hidden)
            .background(frostBackground)
            .navigationTitle("Settings")
            .toolbar { EditButton() }
        }
    }
}

struct MediaRow: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    var progress: Double = 0

    var body: some View {
        NavigationLink(destination: DetailView(media: media)) {
            HStack(spacing: 12) {
                Poster(url: media.posterURL, width: 58, height: 82)
                VStack(alignment: .leading, spacing: 5) {
                    Text(media.title).font(.headline).foregroundStyle(.white)
                    Text(media.kind.title + (media.year.map { " · \($0)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if progress > 0 { ProgressView(value: progress).tint(frostOrange) }
                }
                Spacer()
            }
            .padding(.vertical, 5)
        }
        .swipeActions { Button { store.toggleLibrary(media) } label: { Label("Save", systemImage: "bookmark") } }
        .listRowBackground(frostPanel)
    }
}

struct SectionHeading: View {
    let title: String
    let eyebrow: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow).font(.caption2.weight(.bold)).tracking(2).foregroundStyle(frostOrange)
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.white)
        }
    }
}

struct NoticeCard: View {
    let title: String
    let message: String
    let systemImage: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(frostOrange).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Text(message).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(frostPanel)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ContentRail: View {
    let title: String
    let items: [MediaItem]
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title3.bold()).foregroundStyle(.white)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { media in
                            NavigationLink(destination: DetailView(media: media)) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Poster(url: media.posterURL, width: 116, height: 166)
                                    Text(media.title).font(.caption.weight(.semibold)).lineLimit(2).foregroundStyle(.white)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct MediaCard: View {
    let media: MediaItem
    var featured = false
    var body: some View {
        NavigationLink(destination: DetailView(media: media)) {
            ZStack(alignment: .bottomLeading) {
                Poster(url: media.backdropURL ?? media.posterURL, width: nil, height: featured ? 300 : 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 7) {
                    Text(media.kind.title.uppercased()).font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(frostOrange)
                    Text(media.title).font(.system(size: featured ? 28 : 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(media.overview).font(.caption).lineLimit(2).foregroundStyle(.white.opacity(0.7))
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct Poster: View {
    let url: URL?
    let width: CGFloat?
    let height: CGFloat
    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(Color.white.opacity(0.08)).overlay { Image(systemName: "film").foregroundStyle(.secondary) }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct DetailView: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Poster(url: media.backdropURL ?? media.posterURL, width: nil, height: 260).frame(maxWidth: .infinity)
                Text(media.title).font(.largeTitle.bold()).foregroundStyle(.white)
                Text(media.kind.title + (media.year.map { " · \($0)" } ?? "")).foregroundStyle(.secondary)
                HStack {
                    Button(store.isInLibrary(media) ? "Saved" : "Add to Library") { store.toggleLibrary(media) }.buttonStyle(.borderedProminent)
                    NavigationLink("Watch", destination: PlayerView(media: media)).buttonStyle(.bordered)
                }
                Text(media.overview.isEmpty ? "No synopsis is available for this title yet." : media.overview).foregroundStyle(.secondary)
                if !media.providerNames.isEmpty { Text("Sources: \(media.providerNames.joined(separator: ", "))").font(.caption).foregroundStyle(frostOrange) }
            }
            .padding()
        }
        .background(frostBackground.ignoresSafeArea())
        .navigationTitle(media.title)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

struct PlayerView: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    private let resolver = PlaybackResolver()
    var body: some View {
        Group {
            if let format = resolver.resolve(media: media, settings: store.settings) {
                HybridPlayer(format: format)
            } else {
                ContentUnavailableView("No source available", systemImage: "exclamationmark.triangle", description: Text("Enable a compatible source in Settings, or verify this title has the required ID."))
            }
        }
        .background(Color.black)
        .onAppear { store.recordWatch(media) }
        .navigationTitle(media.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
