import SwiftUI

private let frostBackground = Color(red: 0.025, green: 0.025, blue: 0.03)
private let frostPanel = Color.white.opacity(0.075)
private let frostOrange = Color.orange

struct StreamingProvider: Identifiable {
    let id: String
    let name: String
    let accent: Color
    let logoURL: URL?
    let tmdbProviderID: Int?
}

private enum ProviderCatalog {
    static let providers: [StreamingProvider] = [
        StreamingProvider(id: "all", name: "All", accent: .orange, logoURL: nil, tmdbProviderID: nil),
        StreamingProvider(id: "netflix", name: "Netflix", accent: Color(red: 0.85, green: 0.02, blue: 0.04), logoURL: URL(string: "https://cdn.simpleicons.org/netflix/FFFFFF"), tmdbProviderID: 8),
        StreamingProvider(id: "disney", name: "Disney+", accent: Color(red: 0.08, green: 0.25, blue: 0.65), logoURL: URL(string: "https://cdn.simpleicons.org/disneyplus/FFFFFF"), tmdbProviderID: 337),
        StreamingProvider(id: "hulu", name: "Hulu", accent: Color(red: 0.15, green: 0.65, blue: 0.42), logoURL: URL(string: "https://cdn.simpleicons.org/hulu/FFFFFF"), tmdbProviderID: 15),
        StreamingProvider(id: "max", name: "Max", accent: Color(red: 0.28, green: 0.18, blue: 0.65), logoURL: URL(string: "https://cdn.simpleicons.org/max/FFFFFF"), tmdbProviderID: 1899),
        StreamingProvider(id: "prime", name: "Prime Video", accent: Color(red: 0.05, green: 0.35, blue: 0.7), logoURL: URL(string: "https://cdn.simpleicons.org/primevideo/FFFFFF"), tmdbProviderID: 9)
    ]
}

enum DiscoverFilter: String, CaseIterable, Identifiable {
    case popular = "Most Popular"
    case newest = "Recently Added"
    case movies = "Movies"
    case shows = "Shows"
    case anime = "Anime"
    var id: String { rawValue }
}

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "house") }
            DiscoverView().tabItem { Label("Discover", systemImage: "safari") }
            SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
            LibraryView().tabItem { Label("My List", systemImage: "bookmark") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.white)
    }
}

struct AdaptiveBackdrop<Content: View>: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem?
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            frostBackground.ignoresSafeArea()
            if let url = media?.posterURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill().blur(radius: store.settings.backgroundBlur)
                } placeholder: { Color.clear }
                .opacity(store.settings.backgroundOpacity)
                .ignoresSafeArea()
            }
            LinearGradient(colors: [frostBackground.opacity(0.78), frostBackground, frostBackground], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            content
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: FrostPlayStore
    @State private var selectedProvider: StreamingProvider = ProviderCatalog.providers[0]

    private var hero: MediaItem { (selectedProvider.id == "all" ? store.homeItems : store.providerItems).first ?? .preview }
    private var visibleItems: [MediaItem] { selectedProvider.id == "all" ? store.homeItems : store.providerItems }

    @ViewBuilder
    private func homeSectionView(_ section: HomeSection) -> some View {
        switch section {
        case .continueWatching:
            ContentRail(title: section.title, items: store.history.map(\.media), progress: true)
        case .popular:
            ContentRail(title: section.title, items: visibleItems, onReachedEnd: { Task { if selectedProvider.id == "all" { await store.loadMoreHome() } else { await store.loadMoreProviderCatalog(selectedProvider) } } })
        case .myList:
            ContentRail(title: section.title, items: store.library)
        }
    }

    var body: some View {
        NavigationStack {
            AdaptiveBackdrop(media: hero) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 25) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FROSTPLAY").font(.caption.bold()).tracking(3).foregroundStyle(frostOrange)
                            Text("Find your next watch.").font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text("Browse services, save favorites, and pick up where you left off.").font(.subheadline).foregroundStyle(.white.opacity(0.58))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeading(title: "Browse by Service", eyebrow: "EXPLORE")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 9) {
                                    ForEach(ProviderCatalog.providers) { provider in
                                        ProviderChip(provider: provider, selected: selectedProvider.id == provider.id, isLoading: selectedProvider.id == provider.id && store.isLoadingProvider) {
                                            selectedProvider = provider
                                            store.settings.selectedProvider = provider.id == "all" ? nil : provider.name
                                            Task { await store.loadProviderCatalog(provider) }
                                        }
                                    }
                                }
                            }
                        }

                        if !store.isTMDBConfigured {
                            NoticeCard(title: "Catalog connection needed", message: "Add a TMDB key in Settings to load live movies and shows.", systemImage: "exclamationmark.triangle.fill")
                        }

                        if store.isLoadingHome { ProgressView("Loading catalog…").tint(frostOrange) }
                        if let error = store.homeError, store.isTMDBConfigured { NoticeCard(title: "Catalog unavailable", message: error, systemImage: "wifi.exclamationmark") }
                        if selectedProvider.id != "all", let error = store.providerError { NoticeCard(title: "\(selectedProvider.name) unavailable", message: error, systemImage: "wifi.exclamationmark") }
                        if selectedProvider.id != "all", !store.isLoadingProvider, store.providerItems.isEmpty, store.providerError == nil { NoticeCard(title: "No titles found", message: "TMDB did not return titles for this service in the US catalog.", systemImage: "film") }

                        HeroCard(media: hero)
                        ForEach(store.settings.homeSections) { section in
                            homeSectionView(section)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink(destination: SettingsView()) { Image(systemName: "gearshape") } } }
            .task { await store.loadHome() }
        }
        .preferredColorScheme(.dark)
    }
}

struct ProviderChip: View {
    let provider: StreamingProvider
    let selected: Bool
    let isLoading: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ProviderLogo(provider: provider, size: 34)
                    Spacer()
                    if isLoading { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Image(systemName: selected ? "checkmark.circle.fill" : "arrow.up.right").font(.caption.bold()) }
                }
                Text(provider.name).font(.subheadline.weight(.bold)).lineLimit(1)
                Text(provider.id == "all" ? "All titles" : "Open catalog").font(.caption2).foregroundStyle(.white.opacity(0.58))
            }
            .foregroundStyle(.white)
            .padding(13)
            .frame(width: 132, height: 104, alignment: .leading)
            .background(
                LinearGradient(colors: [provider.accent.opacity(selected ? 0.92 : 0.52), frostPanel], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(selected ? 0.7 : 0.14), lineWidth: selected ? 1.5 : 1))
            .shadow(color: provider.accent.opacity(selected ? 0.32 : 0.08), radius: selected ? 12 : 5, y: 5)
        }
        .buttonStyle(.plain)
    }
}

struct ProviderLogo: View {
    let provider: StreamingProvider
    let size: CGFloat
    var body: some View {
        Group {
            if let url = provider.logoURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFit().padding(5) } placeholder: { Text(String(provider.name.prefix(1))).font(.caption.bold()) }
            } else { Image(systemName: "square.grid.2x2.fill").font(.caption) }
        }
        .frame(width: size, height: size)
        .background(provider.accent.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct HeroCard: View {
    let media: MediaItem
    var body: some View {
        NavigationLink(destination: DetailView(media: media)) {
            ZStack(alignment: .bottomLeading) {
                Poster(url: media.backdropURL ?? media.posterURL, width: nil, height: 255).frame(maxWidth: .infinity)
                LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 7) {
                    Text(media.kind.title.uppercased()).font(.caption2.bold()).tracking(2).foregroundStyle(frostOrange)
                    Text(media.title).font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                    Text(media.overview).font(.caption).foregroundStyle(.white.opacity(0.72)).lineLimit(2)
                    Label("View details", systemImage: "arrow.right").font(.caption.bold()).foregroundStyle(.white)
                }
                .padding(17)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var store: FrostPlayStore
    @State private var filter: DiscoverFilter = .popular
    @State private var provider = "All providers"
    @State private var genre = "All genres"
    @State private var selectedTab = "Movies"

    private var items: [MediaItem] {
        switch filter {
        case .anime: return store.searchResults.filter { $0.kind == .anime }
        case .movies: return store.homeItems.filter { $0.kind == .movie }
        case .shows: return store.homeItems.filter { $0.kind == .tv }
        default: return store.homeItems
        }
    }

    var body: some View {
        NavigationStack {
            AdaptiveBackdrop(media: items.first) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Discover").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text("Filter and find your next watch.").foregroundStyle(.white.opacity(0.6))
                        }
                        Picker("Category", selection: $selectedTab) {
                            Text("Movies").tag("Movies")
                            Text("Shows").tag("Shows")
                            Text("Anime").tag("Anime")
                        }
                        .pickerStyle(.segmented)
                        DiscoverMenu(title: filter.rawValue, icon: "line.3.horizontal.decrease.circle") {
                            ForEach(DiscoverFilter.allCases) { value in Button(value.rawValue) { filter = value } }
                        }
                        HStack(spacing: 9) {
                            DiscoverMenu(title: provider, icon: "play.rectangle") { Button("All providers") { provider = "All providers" } }
                            DiscoverMenu(title: genre, icon: "tag") { Button("All genres") { genre = "All genres" } }
                        }
                        if filter == .anime || selectedTab == "Anime" {
                            AnimeIntroCard()
                        }
                        Text("\(items.count) results").font(.headline).foregroundStyle(.white.opacity(0.7))
                        PosterGrid(items: items)
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .task { if store.searchResults.isEmpty { await store.search(query: "popular anime", kind: .anime) } }
        }
        .preferredColorScheme(.dark)
    }
}

struct DiscoverMenu<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        Menu {
            content
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(frostPanel)
                .clipShape(Capsule())
        }
    }
}

struct AnimeIntroCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.title2).foregroundStyle(frostOrange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Anime library").font(.headline).foregroundStyle(.white)
                Text("Browse AniList titles with seasons, episodes, and source availability.").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(14)
        .background(frostPanel)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PosterGrid: View {
    let items: [MediaItem]
    var onReachedEnd: (() -> Void)? = nil
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 18) {
            ForEach(items) { media in
                NavigationLink(destination: DetailView(media: media)) {
                    VStack(alignment: .leading, spacing: 7) {
                        ZStack(alignment: .topTrailing) {
                            Poster(url: media.posterURL, width: nil, height: 220).frame(maxWidth: .infinity)
                            if media.providerNames.isEmpty { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).padding(8).background(.black.opacity(0.7)).clipShape(Circle()).padding(7) }
                        }
                        Text(media.title).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.white)
                        Text(media.kind.title + (media.year.map { " · \($0)" } ?? "") + " · Source info available")
                            .font(.caption2).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
                .onAppear { if media.id == items.last?.id { onReachedEnd?() } }
            }
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var store: FrostPlayStore
    @State private var query = ""
    @State private var kind: MediaKind?
    var body: some View {
        NavigationStack {
            AdaptiveBackdrop(media: store.searchResults.first) {
                VStack(spacing: 14) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.55))
                        TextField("Search movies, TV shows, anime", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search).onSubmit { Task { await store.search(query: query, kind: kind) } }
                        if !query.isEmpty { Button { query = ""; store.searchResults = [] } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.45)) } }
                    }
                    .padding(14).background(frostPanel).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Picker("Type", selection: $kind) { Text("All").tag(MediaKind?.none); ForEach(MediaKind.allCases) { Text($0.title).tag(Optional($0)) } }.pickerStyle(.segmented)
                    if store.isSearching { ProgressView("Searching…").tint(frostOrange).padding(.top, 30) }
                    else if let error = store.searchError { NoticeCard(title: "Search unavailable", message: error, systemImage: "magnifyingglass") }
                    else if store.searchResults.isEmpty { ContentUnavailableView("Start exploring", systemImage: "sparkles", description: Text("Search the TMDB and AniList catalogs.")) }
                    else { ScrollView { PosterGrid(items: store.searchResults, onReachedEnd: { Task { await store.loadMoreSearchResults() } }).padding(.top, 4); if store.isLoadingMore { ProgressView("Loading more…").tint(frostOrange).frame(maxWidth: .infinity).padding() } } }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .padding(.bottom, 36)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        NavigationStack {
            AdaptiveBackdrop(media: store.library.first) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("My List").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        if store.library.isEmpty { ContentUnavailableView("Your list is empty", systemImage: "bookmark", description: Text("Save movies, shows, and anime to find them here.")) }
                        else { PosterGrid(items: store.library) }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("My List")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { AppearanceSettingsView() } label: { SettingsRow(icon: "paintpalette", title: "Appearance", subtitle: "Artwork, blur, text, and motion") }
                NavigationLink { PlaybackSettingsView() } label: { SettingsRow(icon: "play.rectangle", title: "Playback", subtitle: "Quality, autoplay, subtitles, and sources") }
                NavigationLink { SubtitleSettingsView() } label: { SettingsRow(icon: "captions.bubble", title: "Subtitles", subtitle: "Native player, color, and sizing") }
                NavigationLink { CatalogSettingsView() } label: { SettingsRow(icon: "key", title: "Catalog & API", subtitle: store.isTMDBConfigured ? "TMDB connected" : "TMDB key required") }
                NavigationLink { SourceSettingsView() } label: { SettingsRow(icon: "arrow.triangle.2.circlepath", title: "Sources", subtitle: "Priority and availability") }
                NavigationLink { HomeSectionsSettingsView() } label: { SettingsRow(icon: "rectangle.3.group", title: "Home sections", subtitle: "Choose and reorder Home rails") }
            }
            .scrollContentBackground(.hidden)
            .background(frostBackground)
            .navigationTitle("Settings")
        }
        .preferredColorScheme(.dark)
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.title3).foregroundStyle(frostOrange).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline).foregroundStyle(.white); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 7)
        .listRowBackground(frostPanel)
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        Form {
            Section("Display") {
                Toggle("Image logos", isOn: $store.settings.showImageLogos)
                Toggle("Backdrop artwork", isOn: $store.settings.backdropTrailers)
                Toggle("Reduce motion", isOn: $store.settings.reduceMotion)
                Toggle("Auto-hide navigation", isOn: $store.settings.autoHideHeader)
            }
            Section("Text") {
                SliderRow(title: "Text size", value: $store.settings.textScale, range: 0.85...1.25, suffix: "\(Int(store.settings.textScale * 100))%")
                Toggle("Bold text", isOn: $store.settings.boldText)
                Text("System Dynamic Type remains supported throughout the app.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Artwork") {
                SliderRow(title: "Background opacity", value: $store.settings.backgroundOpacity, range: 0...0.8, suffix: "\(Int(store.settings.backgroundOpacity * 100))%")
                SliderRow(title: "Background blur", value: $store.settings.backgroundBlur, range: 0...32, suffix: "\(Int(store.settings.backgroundBlur))")
                SliderRow(title: "Line spacing", value: $store.settings.lineSpacing, range: 1...2, suffix: "\(Int(store.settings.lineSpacing * 100))%")
            }
            .listRowBackground(frostPanel)
        }
        .navigationTitle("Appearance")
        .scrollContentBackground(.hidden)
        .background(frostBackground)
    }
}

struct PlaybackSettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        Form {
            Section("Playback") {
                Picker("Preferred quality", selection: $store.settings.preferredQuality) { Text("Auto").tag("Auto"); Text("1080p").tag("1080p"); Text("720p").tag("720p") }
                Toggle("Autoplay next episode", isOn: $store.settings.autoplayNextEpisode)
                Toggle("Auto skip intro", isOn: $store.settings.autoSkipIntro)
                Toggle("Auto subtitles", isOn: $store.settings.autoSubtitles)
            }
            Section("Anime") { Picker("Preferred language", selection: $store.settings.preferredAnimeLanguage) { Text("Sub").tag("sub"); Text("Dub").tag("dub") } }
        }
        .navigationTitle("Playback")
        .scrollContentBackground(.hidden)
        .background(frostBackground)
    }
}

struct SubtitleSettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        Form {
            Section { Text("The quick brown fox").font(.title3.weight(store.settings.boldText ? .bold : .regular)).foregroundStyle(subtitleColor).frame(maxWidth: .infinity).padding(28).background(Color.black).clipShape(RoundedRectangle(cornerRadius: 16)) }
            Section("Subtitles") { Toggle("Use native player", isOn: $store.settings.subtitleUseNativePlayer) }
            Section("Color") { Picker("Color", selection: $store.settings.subtitleColor) { Text("White").tag("white"); Text("Yellow").tag("yellow"); Text("Cyan").tag("cyan"); Text("Green").tag("green") }.pickerStyle(.segmented) }
            Section("Text size") { Slider(value: $store.settings.textScale, in: 0.85...1.5).tint(frostOrange) }
        }
        .navigationTitle("Subtitles")
        .scrollContentBackground(.hidden)
        .background(frostBackground)
    }
    private var subtitleColor: Color { store.settings.subtitleColor == "yellow" ? .yellow : store.settings.subtitleColor == "cyan" ? .cyan : store.settings.subtitleColor == "green" ? .green : .white }
}

struct CatalogSettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        Form {
            Section("TMDB") {
                SecureField("TMDB API key", text: $store.settings.tmdbAPIKey).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.password)
                Label(store.isTMDBConfigured ? "Connected" : "Not connected", systemImage: store.isTMDBConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(store.isTMDBConfigured ? .green : .orange)
                Text("Stored locally on this device. Changes apply to the next search or catalog refresh.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Catalog & API")
        .scrollContentBackground(.hidden)
        .background(frostBackground)
    }
}

struct HomeSectionsSettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        List {
            Section("Visible sections") {
                ForEach(HomeSection.allCases) { section in
                    Toggle(section.title, isOn: Binding(get: { store.settings.homeSections.contains(section) }, set: { enabled in
                        if enabled {
                            if !store.settings.homeSections.contains(section) { store.settings.homeSections.append(section) }
                        } else {
                            store.settings.homeSections.removeAll { $0 == section }
                        }
                    }))
                }
                Text("Use Edit to drag sections into the order you want on Home.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Order") {
                ForEach(store.settings.homeSections) { section in Text(section.title) }
                    .onMove { store.settings.homeSections.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        .navigationTitle("Home sections")
        .toolbar { EditButton() }
    }
}

struct SourceSettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        Form {
            Section("Enabled sources") {
                ForEach(PlaybackSource.implemented) { source in Toggle(source.rawValue, isOn: Binding(get: { store.settings.enabledSources.contains(source) }, set: { _ in store.toggleSource(source) })) }
                Text("Unavailable sources are not silently used. A warning badge appears when a title has no verified source.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Priority") {
                ForEach(store.settings.enabledSources) { source in Label(source.rawValue, systemImage: source == .megaPlay ? "sparkles" : "play.rectangle.fill") }.onMove { store.moveSource(from: $0, to: $1) }
            }
        }
        .navigationTitle("Sources")
        .toolbar { EditButton() }
        .scrollContentBackground(.hidden)
        .background(frostBackground)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String
    var body: some View { VStack(alignment: .leading, spacing: 6) { HStack { Text(title); Spacer(); Text(suffix).foregroundStyle(.secondary) }; Slider(value: $value, in: range).tint(frostOrange) } }
}

struct MediaRow: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    var progress: Double = 0
    var body: some View {
        NavigationLink(destination: DetailView(media: media)) {
            HStack(spacing: 12) {
                Poster(url: media.posterURL, width: 58, height: 82)
                VStack(alignment: .leading, spacing: 5) { Text(media.title).font(.headline).foregroundStyle(.white); Text(media.kind.title + (media.year.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary); if progress > 0 { ProgressView(value: progress).tint(frostOrange) } }
                Spacer()
                if media.providerNames.isEmpty { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
        }
        .listRowBackground(frostPanel)
        .swipeActions { Button { store.toggleLibrary(media) } label: { Label("Save", systemImage: "bookmark") } }
    }
}

struct SectionHeading: View {
    let title: String
    let eyebrow: String
    var body: some View { VStack(alignment: .leading, spacing: 3) { Text(eyebrow).font(.caption2.bold()).tracking(2).foregroundStyle(frostOrange); Text(title).font(.title3.bold()).foregroundStyle(.white) } }
}

struct NoticeCard: View {
    let title: String
    let message: String
    let systemImage: String
    var body: some View { HStack(alignment: .top, spacing: 11) { Image(systemName: systemImage).foregroundStyle(frostOrange); VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.bold()).foregroundStyle(.white); Text(message).font(.caption).foregroundStyle(.white.opacity(0.62)) } }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(frostPanel).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) }
}

struct ContentRail: View {
    let title: String
    let items: [MediaItem]
    var progress = false
    var onReachedEnd: (() -> Void)? = nil

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.bold()).foregroundStyle(.white)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { media in
                            NavigationLink(destination: DetailView(media: media)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Poster(url: media.posterURL, width: 106, height: 150)
                                    Text(media.title).font(.caption.weight(.semibold)).lineLimit(2).foregroundStyle(.white)
                                    if progress { ProgressView(value: 0.35).tint(frostOrange).frame(width: 106) }
                                }
                            }
                            .buttonStyle(.plain)
                            .onAppear { if media.id == items.last?.id { onReachedEnd?() } }
                        }
                    }
                }
            }
        }
    }
}

struct Poster: View {
    let url: URL?
    let width: CGFloat?
    let height: CGFloat
    var body: some View { AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(Color.white.opacity(0.08)).overlay { Image(systemName: "film").foregroundStyle(.secondary) } }.frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)) }
}

struct DetailView: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    @State private var seasons: [SeasonEpisodeInfo] = []
    @State private var selectedSeason = 1
    @State private var selectedEpisode = 1
    @State private var isLoadingEpisodes = false
    @State private var showingSourcePicker = false
    private var currentSeason: SeasonEpisodeInfo? { seasons.first(where: { $0.season == selectedSeason }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Poster(url: media.backdropURL ?? media.posterURL, width: nil, height: 220).frame(maxWidth: .infinity)
                Text(media.title).font(.largeTitle.bold()).foregroundStyle(.white)
                Text(media.kind.title + (media.year.map { " · \($0)" } ?? "")).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        store.toggleLibrary(media)
                    } label: {
                        Label(store.isInLibrary(media) ? "Saved" : "Add to My List", systemImage: store.isInLibrary(media) ? "checkmark" : "bookmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(frostOrange)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if media.kind == .movie {
                        NavigationLink {
                            PlayerView(media: media)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 10)
                                .background(frostPanel)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showingSourcePicker = true
                    } label: {
                        Image(systemName: "rectangle.2.swap")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(frostPanel)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose source")
                }
                if media.kind == .tv || media.kind == .anime { EpisodePanel(media: media, seasons: $seasons, selectedSeason: $selectedSeason, selectedEpisode: $selectedEpisode, isLoading: $isLoadingEpisodes) }
                Text(media.overview.isEmpty ? "No synopsis is available for this title yet." : media.overview).foregroundStyle(.secondary)
                Text(media.providerNames.isEmpty ? "Source availability is limited for this title." : "Sources: \(media.providerNames.joined(separator: ", "))").font(.caption).foregroundStyle(media.providerNames.isEmpty ? .orange : frostOrange)
            }
            .padding(16)
        }
        .background(frostBackground.ignoresSafeArea())
        .navigationTitle(media.title)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSourcePicker) { SourcePickerView(media: media) }
    }
}

struct EpisodePanel: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    @Binding var seasons: [SeasonEpisodeInfo]
    @Binding var selectedSeason: Int
    @Binding var selectedEpisode: Int
    @Binding var isLoading: Bool

    private var currentSeason: SeasonEpisodeInfo? { seasons.first(where: { $0.season == selectedSeason }) }
    private var episodes: [EpisodeInfo] {
        if let episodes = currentSeason?.episodes, !episodes.isEmpty { return episodes }
        let count = currentSeason?.episodeCount ?? media.episodeCount ?? 0
        return (1...max(count, 1)).map { EpisodeInfo(number: $0, name: "Episode \($0)", overview: "Episode description unavailable.", airDate: nil) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Episodes").font(.headline).foregroundStyle(.white)
                Spacer()
                if isLoading { ProgressView().tint(frostOrange) }
                else { Text("S\(selectedSeason) · \(episodes.count) episodes").font(.caption).foregroundStyle(.secondary) }
            }
            if seasons.count > 1 {
                Picker("Season", selection: $selectedSeason) {
                    ForEach(seasons) { season in Text("Season \(season.season)").tag(season.season) }
                }
                .pickerStyle(.menu)
                .tint(frostOrange)
                .onChange(of: selectedSeason) { _, _ in selectedEpisode = 1 }
            }
            if seasons.isEmpty && !isLoading { Text("Episode data is unavailable. Try another title or source.").font(.caption).foregroundStyle(.orange) }
            LazyVStack(spacing: 9) {
                ForEach(episodes) { episode in
                    NavigationLink(destination: PlayerView(media: media, season: selectedSeason, episode: episode.number)) {
                        HStack(alignment: .top, spacing: 11) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(episode.number == selectedEpisode ? frostOrange : Color.white.opacity(0.12))
                                Text("E\(episode.number)").font(.subheadline.bold()).foregroundStyle(episode.number == selectedEpisode ? .black : .white)
                            }.frame(width: 48, height: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(episode.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                                if let airDate = episode.airDate, !airDate.isEmpty { Text(airDate).font(.caption2).foregroundStyle(.secondary) }
                                Text(episode.overview.isEmpty ? "No description available." : episode.overview).font(.caption).foregroundStyle(.white.opacity(0.58)).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "play.fill").font(.caption).foregroundStyle(frostOrange)
                        }
                        .padding(10)
                        .background(episode.number == selectedEpisode ? frostOrange.opacity(0.14) : Color.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { selectedEpisode = episode.number })
                }
            }
        }
        .padding(14)
        .background(frostPanel)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .task {
            isLoading = true
            seasons = await store.episodeCatalog(for: media)
            if let first = seasons.first, !seasons.contains(where: { $0.season == selectedSeason }) { selectedSeason = first.season }
            isLoading = false
        }
    }
}

struct SourcePickerView: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Available sources") {
                    ForEach(PlaybackSource.implemented) { source in
                        let available = source.supports.contains(media.kind)
                        Button { if available { dismiss() } } label: { HStack { Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(available ? .green : .orange); VStack(alignment: .leading) { Text(source.rawValue).foregroundStyle(.primary); Text(available ? "Compatible with this title type" : "Not compatible with this title").font(.caption).foregroundStyle(.secondary) }; Spacer(); if available { Text("Use").foregroundStyle(frostOrange) } } }
                    }
                }
            }
            .navigationTitle("Sources")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct PlayerView: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    let season: Int
    let episode: Int
    @State private var showingSourcePicker = false
    private let resolver = PlaybackResolver()
    init(media: MediaItem, season: Int = 1, episode: Int = 1) { self.media = media; self.season = season; self.episode = episode }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(media.kind == .movie ? media.title : "S\(season) · Episode \(episode)").font(.headline).lineLimit(1); Spacer(); Button("Source") { showingSourcePicker = true }.font(.caption.bold()).buttonStyle(.bordered) }.padding(.horizontal, 12).padding(.vertical, 8)
            if let format = resolver.resolve(media: media, settings: store.settings, season: season, episode: episode) { HybridPlayer(format: format).frame(maxHeight: .infinity) } else { ContentUnavailableView("No source available", systemImage: "exclamationmark.triangle", description: Text("Choose another source or verify this title's IDs.")) }
        }
        .background(Color.black)
        .onAppear { store.recordWatch(media) }
        .sheet(isPresented: $showingSourcePicker) { SourcePickerView(media: media) }
        .navigationBarTitleDisplayMode(.inline)
    }
}
