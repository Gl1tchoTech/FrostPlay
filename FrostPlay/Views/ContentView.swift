import SwiftUI
import UIKit
import Darwin

private let frostBackground = Color(red: 0.025, green: 0.025, blue: 0.03)
private let frostPanel = Color.white.opacity(0.075)
private let frostOrange = Color.orange

private func displayTitle(_ title: String, maxCharacters: Int = 24) -> String {
    guard title.count > maxCharacters else { return title }
    return String(title.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
}

private func displaySynopsis(_ synopsis: String, maxCharacters: Int = 96) -> String {
    guard synopsis.count > maxCharacters else { return synopsis }
    return String(synopsis.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
}

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
        .toolbarBackground(Color.black.opacity(0.94), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        // Keep the compact iPhone layout readable while still honoring Dynamic Type.
        .dynamicTypeSize(.xSmall ... .large)
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
                .padding(14)
                .background(frostPanel.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        case .popular:
            ContentRail(title: section.title, items: visibleItems, onReachedEnd: { Task { if selectedProvider.id == "all" { await store.loadMoreHome() } else { await store.loadMoreProviderCatalog(selectedProvider) } } })
                .padding(14)
                .background(frostPanel.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        case .myList:
            ContentRail(title: section.title, items: store.library)
                .padding(14)
                .background(frostPanel.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    var body: some View {
        NavigationStack {
            AdaptiveBackdrop(media: hero) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 25) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("FROSTPLAY").font(.caption.bold()).tracking(3).foregroundStyle(frostOrange)
                                Spacer()
                                Text("PRIVATE LIBRARY").font(.caption2.bold()).tracking(1.2).foregroundStyle(.white.opacity(0.38))
                            }
                            Text("Find your next watch.").font(.system(size: 31, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text("Browse services, save favorites, and pick up where you left off.").font(.subheadline).foregroundStyle(.white.opacity(0.58)).fixedSize(horizontal: false, vertical: true)
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
                    .padding(.bottom, 160)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 108)
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: HomeSectionsSettingsView()) {
                        Image(systemName: "rectangle.3.group")
                    }
                    .accessibilityLabel("Customize Home sections")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) { Image(systemName: "gearshape") }
                }
            }
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
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(5)
                    } else {
                        Text(String(provider.name.prefix(1))).font(.caption.bold())
                    }
                }
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
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width, 0)
            NavigationLink(destination: DetailView(media: media)) {
                ZStack(alignment: .bottomLeading) {
                    Poster(url: media.backdropURL ?? media.posterURL, width: contentWidth, height: 255)
                    LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(media.kind.title.uppercased()).font(.caption2.bold()).tracking(2).foregroundStyle(frostOrange)
                        Text(displayTitle(media.title, maxCharacters: 34))
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(displaySynopsis(media.overview))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Label("View details", systemImage: "arrow.right").font(.caption.bold()).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(17)
                }
                .frame(width: contentWidth, height: 255)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 255)
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var store: FrostPlayStore
    @State private var filter: DiscoverFilter = .popular
    @State private var provider = "All providers"
    @State private var genre = "All genres"
    @State private var selectedTab = "Movies"

    private var items: [MediaItem] {
        let anime = store.animeResults
        let movies = store.homeItems.filter { $0.kind == .movie }
        let shows = store.homeItems.filter { $0.kind == .tv }
        let categoryItems: [MediaItem]
        switch selectedTab {
        case "Anime": categoryItems = anime
        case "Movies": categoryItems = movies
        case "Shows": categoryItems = shows
        default: categoryItems = movies + shows + anime
        }
        switch filter {
        case .anime: return selectedTab == "Movies" || selectedTab == "Shows" ? [] : anime
        case .movies: return selectedTab == "Anime" ? [] : movies
        case .shows: return selectedTab == "Anime" ? [] : shows
        default: return categoryItems
        }
    }

    var body: some View {
        NavigationStack {
            AdaptiveBackdrop(media: items.first) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Discover").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                            Text("Filter and find your next watch.").foregroundStyle(.white.opacity(0.6))
                        }
                        Picker("Category", selection: $selectedTab) {
                            Text("All").tag("All")
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
                            if let error = store.animeError {
                                NoticeCard(title: "Anime catalog unavailable", message: error, systemImage: "wifi.exclamationmark")
                            }
                        }
                        if store.isSearching && (selectedTab == "Anime" || selectedTab == "All") {
                            ProgressView("Loading AniList…")
                                .tint(frostOrange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        Text("\(items.count) results").font(.headline).foregroundStyle(.white.opacity(0.7))
                        if items.isEmpty && (selectedTab == "Anime" || filter == .anime) && !store.isSearching && store.animeError == nil {
                            Button {
                                Task { await store.loadAnimeCatalog() }
                            } label: {
                                Label("Retry AniList", systemImage: "arrow.clockwise")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(frostOrange)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        PosterGrid(items: items)
                    }
                    .padding(16)
                    .padding(.bottom, 140)
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: selectedTab) {
                guard selectedTab == "Anime" || selectedTab == "All" else { return }
                await store.loadAnimeCatalog()
            }
            .onAppear {
                Task { await store.loadAnimeCatalog() }
            }
            .onChange(of: selectedTab) { _, tab in
                guard tab == "Anime" || tab == "All" else { return }
                Task { await store.loadAnimeCatalog() }
            }
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
                        Text(displayTitle(media.title))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clipped()
                            .foregroundStyle(.white)
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
    @State private var section = "My List"

    var body: some View {
        NavigationStack {
            AdaptiveBackdrop(media: section == "My List" ? store.library.first : store.downloads.first?.media) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Library").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text(section == "My List" ? "Your saved titles, ready when you are." : "Offline files stored on this device.").font(.subheadline).foregroundStyle(.white.opacity(0.58))
                        }
                        Picker("Library", selection: $section) {
                            Text("My List").tag("My List")
                            Text("Downloads").tag("Downloads")
                        }
                        .pickerStyle(.segmented)
                        if section == "My List" {
                            if store.library.isEmpty { ContentUnavailableView("Your list is empty", systemImage: "bookmark", description: Text("Save movies, shows, and anime to find them here.")) }
                            else { PosterGrid(items: store.library) }
                        } else {
                            DownloadsList()
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

struct DownloadsList: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        if store.downloads.isEmpty {
            ContentUnavailableView("No downloads", systemImage: "arrow.down.circle", description: Text("Direct MP4 files appear here when a source explicitly permits downloading."))
        } else {
            LazyVStack(spacing: 10) {
                ForEach(store.downloads) { entry in
                    NavigationLink(destination: DirectVideoPlayer(url: entry.localURL).navigationTitle(entry.media.title)) {
                        HStack(spacing: 12) {
                            Poster(url: entry.media.posterURL, width: 60, height: 82)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.media.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(.white)
                                Text(entry.episode.map { "Episode \($0)" } ?? "Movie").font(.caption).foregroundStyle(.secondary)
                                Text(entry.fileName).font(.caption2).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "play.fill").foregroundStyle(frostOrange)
                        }
                        .padding(12)
                        .background(frostPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button(role: .destructive) { store.removeDownload(entry) } label: { Label("Delete download", systemImage: "trash") } }
                }
            }
        }
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
                NavigationLink { CacheSettingsView() } label: { SettingsRow(icon: "internaldrive", title: "Cache", subtitle: "View storage and clear temporary data") }
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

struct MediaRow: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    var progress: Double = 0
    var body: some View {
        NavigationLink(destination: DetailView(media: media)) {
            HStack(spacing: 12) {
                Poster(url: media.posterURL, width: 58, height: 82)
                VStack(alignment: .leading, spacing: 5) {                        Text(media.title).font(.headline).lineLimit(1).truncationMode(.tail).foregroundStyle(.white); Text(media.kind.title + (media.year.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary); if progress > 0 { ProgressView(value: progress).tint(frostOrange) } }
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
                                    Text(displayTitle(media.title, maxCharacters: 20))
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(width: 106, height: 32, alignment: .leading)
                                        .foregroundStyle(.white)
                                        .clipped()
                                    if progress { ProgressView(value: 0.35).tint(frostOrange).frame(width: 106) }
                                }
                                .frame(width: 106, alignment: .leading)
                                .clipped()
                            }
                            .frame(width: 106, height: progress ? 192 : 182, alignment: .topLeading)
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
    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(Color.white.opacity(0.08)).overlay { Image(systemName: "film").foregroundStyle(.secondary) }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct DetailView: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    @State private var seasons: [SeasonEpisodeInfo] = []
    @State private var selectedSeason = 1
    @State private var selectedEpisode = 1
    @State private var isLoadingEpisodes = false
    @State private var showingSourcePicker = false
    @State private var refreshedAnimeMetadata: MediaMetadata?
    @State private var isLoadingAnimeMetadata = false
    private var currentSeason: SeasonEpisodeInfo? { seasons.first(where: { $0.season == selectedSeason }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Poster(url: media.backdropURL ?? media.posterURL, width: nil, height: 220).frame(maxWidth: .infinity)
                Text(displayTitle(media.title, maxCharacters: 32))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.white)
                Text(media.kind.title + (media.year.map { " · \($0)" } ?? "")).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    DetailBadge(label: media.kind == .anime ? "AniList" : "TMDB", icon: "checkmark.seal.fill")
                    if let episodeCount = media.episodeCount, episodeCount > 0,
                       media.kind != .anime || (refreshedAnimeMetadata ?? media.metadata)?.format?.uppercased() != "MOVIE" {
                        DetailBadge(label: "\(episodeCount) episodes", icon: "list.number")
                    }
                    if let source = media.providerNames.first {
                        DetailBadge(label: source, icon: "play.circle.fill")
                    }
                }
                if media.kind == .anime, isLoadingAnimeMetadata, (refreshedAnimeMetadata ?? media.metadata)?.hasDetails != true {
                    ProgressView("Loading AniList details…")
                        .font(.caption)
                        .tint(frostOrange)
                } else if media.kind == .anime,
                   let metadata = refreshedAnimeMetadata ?? media.metadata,
                   metadata.hasDetails {
                    if metadata.format != nil || metadata.score != nil || metadata.status != nil {
                        HStack(spacing: 8) {
                            if let format = metadata.format { DetailBadge(label: format.capitalized, icon: "tv") }
                            if let score = metadata.score { DetailBadge(label: "Score \(score)%", icon: "star.fill") }
                            if let status = metadata.status { DetailBadge(label: status.capitalized, icon: "info.circle") }
                        }
                    }
                    if metadata.countryOfOrigin != nil || metadata.durationMinutes != nil || metadata.source != nil {
                        HStack(spacing: 8) {
                            if let country = metadata.countryOfOrigin { DetailBadge(label: country, icon: "globe") }
                            if let duration = metadata.durationMinutes, duration > 0 {
                                DetailBadge(label: "\(duration) min\(metadata.format?.uppercased() == "MOVIE" ? "" : " / ep")", icon: "clock")
                            }
                            if let source = metadata.source { DetailBadge(label: source.replacingOccurrences(of: "_", with: " ").capitalized, icon: "book") }
                        }
                    }
                    if !metadata.genres.isEmpty {
                        Text(metadata.genres.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(2)
                    }
                    if let studios = metadata.studios, !studios.isEmpty {
                        Text("Studio · \(studios.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(2)
                    }
                } else if media.kind == .anime {
                    Text("No additional AniList details are available for this title.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                }
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Button {
                            store.toggleLibrary(media)
                        } label: {
                            Label(store.isInLibrary(media) ? "Saved" : "Add to My List", systemImage: store.isInLibrary(media) ? "checkmark" : "bookmark")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 10)
                                .background(frostOrange)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if media.kind == .movie || (media.kind == .anime && (refreshedAnimeMetadata ?? media.metadata)?.format?.uppercased() == "MOVIE") {
                            NavigationLink {
                                PlayerView(media: media)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 10)
                                    .background(frostPanel)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.18)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        showingSourcePicker = true
                    } label: {
                        Label("Choose source", systemImage: "rectangle.2.swap")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(frostPanel)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose source")
                }
                if media.kind == .tv || (media.kind == .anime && (refreshedAnimeMetadata ?? media.metadata)?.format?.uppercased() != "MOVIE") {
                    EpisodePanel(media: media, seasons: $seasons, selectedSeason: $selectedSeason, selectedEpisode: $selectedEpisode, isLoading: $isLoadingEpisodes)
                }
                Text(media.overview.isEmpty ? "No synopsis is available for this title yet." : media.overview).foregroundStyle(.secondary)
                Text(media.providerNames.isEmpty ? "Source availability is limited for this title." : "Sources: \(media.providerNames.joined(separator: ", "))").font(.caption).foregroundStyle(media.providerNames.isEmpty ? .orange : frostOrange)
            }
            .frame(width: UIScreen.main.bounds.width, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 180)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(frostBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 150)
        }
        .navigationTitle(media.title)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task(id: media.id) {
            guard media.kind == .anime else { return }
            isLoadingAnimeMetadata = true
            refreshedAnimeMetadata = await store.animeMetadata(for: media)
            isLoadingAnimeMetadata = false
        }
        .sheet(isPresented: $showingSourcePicker) { SourcePickerView(media: media) }
    }
}

struct DetailBadge: View {
    let label: String
    let icon: String
    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
    }
}

struct EpisodePanel: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    @Binding var seasons: [SeasonEpisodeInfo]
    @Binding var selectedSeason: Int
    @Binding var selectedEpisode: Int
    @Binding var isLoading: Bool
    @State private var streamURLs: [Int: URL] = [:]
    @State private var isLoadingStreams = false
    @State private var streamError: String?

    private var currentSeason: SeasonEpisodeInfo? { seasons.first(where: { $0.season == selectedSeason }) }
    private var episodes: [EpisodeInfo] {
        guard let currentSeason else { return [] }
        let catalogEpisodes = currentSeason.episodes.isEmpty
            ? (1...max(currentSeason.episodeCount, 1)).map { EpisodeInfo(number: $0, name: "Episode \($0)", overview: "", airDate: nil, imageURL: nil) }
            : currentSeason.episodes
        return catalogEpisodes.map { episode in
            var updated = episode
            updated.playbackURL = streamURLs[episode.number] ?? episode.playbackURL
            return updated
        }
    }

    private func loadAnimeStreams() async { // resolves MegaPlay URLs for anime episodes
        guard media.kind == .anime else { return }
        let numbers = episodes.map(\.number)
        guard !numbers.isEmpty else {
            streamURLs = [:]
            streamError = "This title has no episode list, so there are no streams to resolve."
            return
        }
        isLoadingStreams = true
        streamError = nil
        do {
            let streams = try await store.animePlaybackEpisodes(for: media, episodeNumbers: numbers)
            streamURLs = Dictionary(streams.compactMap { episode in
                episode.playbackURL.map { (episode.number, $0) }
            }, uniquingKeysWith: { first, _ in first })
            if streamURLs.isEmpty { streamError = "MegaPlay has no mapped stream for this title yet." }
        } catch {
            streamError = "MegaPlay streams could not be resolved. Try again later."
        }
        isLoadingStreams = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Episodes").font(.headline).foregroundStyle(.white)
                Spacer()
                if isLoading || isLoadingStreams { ProgressView().tint(frostOrange) }
                else { Text("S\(selectedSeason) · \(episodes.count) episodes").font(.caption).foregroundStyle(.secondary) }
            }
            if media.kind == .anime && isLoadingStreams {
                Text("Finding MegaPlay streams…").font(.caption).foregroundStyle(.secondary)
            } else if media.kind == .anime, let streamError {
                HStack(spacing: 8) {
                    Text(streamError).font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button("Retry") { Task { await loadAnimeStreams() } }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(frostOrange)
                }
            }
            if seasons.count > 1 {
                Picker("Season", selection: $selectedSeason) {
                    ForEach(seasons) { season in Text("Season \(season.season)").tag(season.season) }
                }
                .pickerStyle(.menu)
                .tint(frostOrange)
                .onChange(of: selectedSeason) { _, _ in selectedEpisode = 1 }
            }
            if seasons.isEmpty && !isLoading {
                Text(store.episodeError ?? "Episode data is unavailable. Try another title or source.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let selected = episodes.first(where: { $0.number == selectedEpisode }) {
                VStack(alignment: .leading, spacing: 9) {
                    if let imageURL = selected.imageURL {
                        Poster(url: imageURL, width: nil, height: 170)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Text("Episode \(selected.number) · \(selected.name)").font(.subheadline.bold()).foregroundStyle(.white)
                    Text(selected.overview.isEmpty ? "No episode-specific details are published by AniList for this title." : selected.overview).font(.caption).foregroundStyle(.white.opacity(0.62)).lineLimit(3)
                    if media.kind == .anime && selected.playbackURL == nil && !isLoadingStreams {
                        Label("MegaPlay stream unavailable", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    if let airDate = selected.airDate, !airDate.isEmpty { Text(airDate).font(.caption2).foregroundStyle(.secondary) }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            LazyVStack(spacing: 9) {
                ForEach(episodes) { episode in
                    NavigationLink(destination: PlayerView(media: media, season: selectedSeason, episode: episode.number, preferredPlaybackURL: episode.playbackURL)) {
                        HStack(alignment: .top, spacing: 11) {
                            if let imageURL = episode.imageURL {
                                Poster(url: imageURL, width: 92, height: 58)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(episode.number == selectedEpisode ? frostOrange : Color.white.opacity(0.12))
                                    Text("E\(episode.number)").font(.subheadline.bold()).foregroundStyle(episode.number == selectedEpisode ? .black : .white)
                                }.frame(width: 48, height: 40)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(episode.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(.white)
                                if let airDate = episode.airDate, !airDate.isEmpty { Text(airDate).font(.caption2).foregroundStyle(.secondary) }
                                Text(episode.overview.isEmpty ? (media.kind == .anime ? "No episode-specific details on AniList." : "No description available.") : episode.overview).font(.caption).foregroundStyle(.white.opacity(0.58)).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: media.kind == .anime && episode.playbackURL == nil ? "exclamationmark.circle" : "play.fill")
                                .font(.caption)
                                .foregroundStyle(media.kind == .anime && episode.playbackURL == nil ? .orange : frostOrange)
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
        .task(id: media.id) {
            streamURLs = [:]
            streamError = nil
            isLoading = true
            seasons = await store.episodeCatalog(for: media)
            if let first = seasons.first, !seasons.contains(where: { $0.season == selectedSeason }) { selectedSeason = first.season }
            isLoading = false

            guard media.kind == .anime, !seasons.isEmpty else { return }
            await loadAnimeStreams()
        }
        .onChange(of: store.settings.preferredAnimeLanguage) { _, _ in
            guard media.kind == .anime else { return }
            Task { await loadAnimeStreams() }
        }
    }
}

struct SourcePickerView: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    @Environment(\.dismiss) private var dismiss

    private var compatibleSources: [PlaybackSource] {
        PlaybackSource.implemented.filter { $0.supports.contains(media.kind) }
    }
    private var selectedSource: PlaybackSource { store.settings.defaultSource(for: media.kind) }
    private var kindLabel: String { media.kind == .anime ? "anime" : "movies & TV" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(compatibleSources) { source in
                        Button {
                            store.setDefaultSource(source, for: media.kind)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: source == selectedSource ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(source == selectedSource ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.rawValue).foregroundStyle(.primary)
                                    Text(source == selectedSource ? "Current default for \(kindLabel)" : "Use for \(kindLabel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if compatibleSources.isEmpty {
                        Text("No verified source is available for this title type.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Available sources")
                } footer: {
                    Text("Selecting a source makes it the default for \(kindLabel) titles, and this title starts playing with it right away.")
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
    @Environment(\.dismiss) private var dismiss
    let media: MediaItem
    let season: Int
    let episode: Int
    let preferredPlaybackURL: URL?
    @State private var showingSourcePicker = false
    private let resolver = PlaybackResolver()
    private var resolvedPlayback: ResolvedPlayback? {
        resolver.resolveSource(media: media, settings: store.settings, season: season, episode: episode, preferredURL: preferredPlaybackURL)
    }
    init(media: MediaItem, season: Int = 1, episode: Int = 1, preferredPlaybackURL: URL? = nil) {
        self.media = media
        self.season = season
        self.episode = episode
        self.preferredPlaybackURL = preferredPlaybackURL
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.kind == .movie ? media.title : "S\(season) · Episode \(episode)").font(.headline).lineLimit(1)
                    Text(resolvedPlayback?.source.rawValue.uppercased() ?? "FROSTPLAY PLAYER").font(.caption2.bold()).tracking(1.5).foregroundStyle(frostOrange)
                }
                Spacer()
                Button("Source") { showingSourcePicker = true }.font(.caption.bold()).buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if let format = resolver.resolve(media: media, settings: store.settings, season: season, episode: episode, preferredURL: preferredPlaybackURL) {
                HybridPlayer(format: format).frame(maxHeight: .infinity)
                if AuthorizedDownloadManager.downloadableURL(for: format) != nil {
                    Button { Task { try? await store.download(media: media, format: format, episode: media.kind == .movie ? nil : episode) } } label: {
                        Label("Download MP4", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(frostOrange)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            } else { ContentUnavailableView("No source available", systemImage: "exclamationmark.triangle", description: Text("Pick a different source for this title type.")) }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { store.recordWatch(media) }
        .sheet(isPresented: $showingSourcePicker) { SourcePickerView(media: media) }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
    }
}
