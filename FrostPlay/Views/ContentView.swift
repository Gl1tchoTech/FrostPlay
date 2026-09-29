import SwiftUI
import UIKit
import Darwin
import PhotosUI

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
    /// `tmdbProviderID` is the TMDB watch-provider ID, which is what both the
    /// service catalog and the official logo lookup key off of. `logoURL` is an
    /// optional bundled-by-URL fallback for services TMDB cannot supply.
    static let providers: [StreamingProvider] = [
        StreamingProvider(id: "all", name: "All", accent: .orange, logoURL: nil, tmdbProviderID: nil),
        StreamingProvider(id: "netflix", name: "Netflix", accent: Color(red: 0.85, green: 0.02, blue: 0.04), logoURL: URL(string: "https://cdn.simpleicons.org/netflix/FFFFFF"), tmdbProviderID: 8),
        StreamingProvider(id: "disney", name: "Disney+", accent: Color(red: 0.08, green: 0.25, blue: 0.65), logoURL: nil, tmdbProviderID: 337),
        StreamingProvider(id: "hulu", name: "Hulu", accent: Color(red: 0.15, green: 0.65, blue: 0.42), logoURL: nil, tmdbProviderID: 15),
        StreamingProvider(id: "max", name: "Max", accent: Color(red: 0.28, green: 0.18, blue: 0.65), logoURL: URL(string: "https://cdn.simpleicons.org/max/FFFFFF"), tmdbProviderID: 1899),
        StreamingProvider(id: "prime", name: "Prime Video", accent: Color(red: 0.05, green: 0.35, blue: 0.7), logoURL: nil, tmdbProviderID: 9),
        StreamingProvider(id: "crunchyroll", name: "Crunchyroll", accent: Color(red: 0.96, green: 0.42, blue: 0.09), logoURL: URL(string: "https://cdn.simpleicons.org/crunchyroll/FFFFFF"), tmdbProviderID: 283)
    ]
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
    @StateObject private var navigator = MediaNavigator()
    @State private var selectedProvider: StreamingProvider = ProviderCatalog.providers[0]
    @State private var isEditingSections = false
    @State private var targetedSection: HomeSection?

    private var hero: MediaItem? { (selectedProvider.id == "all" ? store.homeItems : store.providerItems).first }
    private var visibleItems: [MediaItem] { selectedProvider.id == "all" ? store.homeItems : store.providerItems }

    /// True until the first catalog for the current service is on screen, which is
    /// exactly when the placeholder animation should be showing.
    private var isInitialLoad: Bool {
        selectedProvider.id == "all"
            ? store.isLoadingHome && store.homeItems.isEmpty
            : store.isLoadingProvider && store.providerItems.isEmpty
    }

    /// Streaming-service style placeholders: a hero block plus a couple of rails.
    private var loadingPlaceholders: some View {
        VStack(alignment: .leading, spacing: 25) {
            SkeletonHero()
            SkeletonRail()
            SkeletonRail(cardCount: 3, cardWidth: 120, cardHeight: 170)
        }
    }

    /// The live rail for a section. Kept free of padding/glass so the same rail
    /// renders inside the editable container below.
    @ViewBuilder
    private func railContent(_ section: HomeSection) -> some View {
        switch section {
        case .continueWatching:
            ContentRail(title: section.title, items: store.history.map(\.media), progress: true)
        case .popular:
            ContentRail(
                // Naming the rotating feed makes the fresh pick visible instead of
                // looking like the catalog silently changed.
                title: selectedProvider.id == "all" ? store.homeFeed.title : section.title,
                items: visibleItems,
                // Show the selected service's real logo on its rail heading.
                provider: selectedProvider.id == "all" ? nil : selectedProvider,
                onReachedEnd: { Task { if selectedProvider.id == "all" { await store.loadMoreHome() } else { await store.loadMoreProviderCatalog(selectedProvider) } } }
            )
        case .myList:
            ContentRail(title: section.title, items: store.library)
        }
    }

    /// A live Home rail. In edit mode the same rail gains a drag bar
    /// (long-press to reorder), up/down nudges, and a remove button — so sections
    /// are reordered directly on the rails instead of on detached cards.
    private func sectionContainer(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditingSections {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal").font(.footnote.weight(.bold)).foregroundStyle(.white.opacity(0.5))
                    Text(section.title).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { store.nudgeHomeSection(section, by: -1) }
                    } label: {
                        Image(systemName: "chevron.up").font(.caption.bold()).foregroundStyle(.white.opacity(0.72))
                    }
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { store.nudgeHomeSection(section, by: 1) }
                    } label: {
                        Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.white.opacity(0.72))
                    }
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { store.removeHomeSection(section) }
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.title3).foregroundStyle(Color.red.opacity(0.88))
                    }
                    .accessibilityLabel("Remove \(section.title)")
                }
                .buttonStyle(FrostPressStyle())
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frostGlass(cornerRadius: 13, opacity: 0.9)
                // Long-press the bar, then drag the rail over another one to move it.
                .draggable(section.rawValue) {
                    HStack(spacing: 8) {
                        Image(systemName: section.symbolName)
                        Text(section.title).font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(frostOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityHint("Long-press, then drag to reorder this section")
            }
            railContent(section)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostGlass(cornerRadius: 20, opacity: 0.85, highlighted: targetedSection == section)
        .dropDestination(for: String.self) { payloads, _ in
            guard let raw = payloads.first, let dragged = HomeSection(rawValue: raw) else { return false }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                store.moveHomeSection(dragged, before: section)
            }
            return true
        } isTargeted: { targeted in
            targetedSection = targeted ? section : nil
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
                                .accessibilityAddTraits(.isHeader)
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

                        if isEditingSections {
                            HomeSectionsEditor()
                        }

                        if !store.isTMDBConfigured {
                            NoticeCard(title: "Catalog connection needed", message: "Add a TMDB key in Settings to load live movies and shows.", systemImage: "exclamationmark.triangle.fill")
                        }

                        if let error = store.homeError, store.isTMDBConfigured { NoticeCard(title: "Catalog unavailable", message: error, systemImage: "wifi.exclamationmark") }
                        if selectedProvider.id != "all", let error = store.providerError { NoticeCard(title: "\(selectedProvider.name) unavailable", message: error, systemImage: "wifi.exclamationmark") }
                        if selectedProvider.id != "all", !store.isLoadingProvider, store.providerItems.isEmpty, store.providerError == nil { NoticeCard(title: "No titles found", message: "TMDB did not return titles for this service in the US catalog.", systemImage: "film") }

                        if isInitialLoad {
                            loadingPlaceholders
                                .frostSwapTransition(reduceMotion: store.settings.reduceMotion)
                        } else {
                            if let hero { HeroCard(media: hero) }
                            ForEach(store.settings.homeSections) { section in
                                sectionContainer(section)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.28), value: store.isLoadingHome)
                    .animation(.easeInOut(duration: 0.28), value: store.isLoadingProvider)
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
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { isEditingSections.toggle() }
                    } label: {
                        Image(systemName: isEditingSections ? "checkmark.circle.fill" : "slider.horizontal.3")
                    }
                    .accessibilityLabel(isEditingSections ? "Done editing Home" : "Edit Home sections")
                }
            }
            .task { await store.loadHome() }
            .navigationDestination(item: $navigator.detail) { DetailView(media: $0) }
        }
        .fullScreenCover(item: $navigator.player) { PlayerView(media: $0) }
        .environmentObject(navigator)
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
    @EnvironmentObject private var store: FrostPlayStore
    let provider: StreamingProvider
    let size: CGFloat

    /// TMDB's official logo for the service when it has been fetched, otherwise
    /// the provider's own bundled-by-URL fallback.
    private var logoURL: URL? {
        guard let providerID = provider.tmdbProviderID else { return provider.logoURL }
        return store.providerLogos[providerID] ?? provider.logoURL
    }

    var body: some View {
        Group {
            if provider.tmdbProviderID == nil {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: size * 0.42))
            } else if let url = logoURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(size * 0.13)
                    } else {
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .background(provider.accent.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.21, style: .continuous))
    }

    private var monogram: some View {
        Text(String(provider.name.prefix(1)))
            .font(.system(size: size * 0.44, weight: .heavy))
            .foregroundStyle(.white)
    }
}

struct HeroCard: View {
    let media: MediaItem
    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width, 0)
            MediaLink(media: media) {
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
    @StateObject private var navigator = MediaNavigator()
    @State private var selectedProvider: StreamingProvider = ProviderCatalog.providers[0]
    @State private var selectedTab = "All"
    @State private var didRestoreProvider = false

    private var kind: MediaKind? {
        switch selectedTab {
        case "Movies": return .movie
        case "Shows": return .tv
        case "Anime": return .anime
        default: return nil
        }
    }

    /// Service sorting lives on the service cards: "All services" browses the
    /// whole TMDB/AniList catalog, any other card browses only that service's
    /// TMDB catalog. The tab then narrows the list to a single kind.
    private var items: [MediaItem] {
        let base = selectedProvider.id == "all" ? store.searchResults : store.providerItems
        guard let kind else { return base }
        return base.filter { $0.kind == kind }
    }

    private var isLoading: Bool { selectedProvider.id == "all" ? store.isSearching : store.isLoadingProvider }

    private func loadCatalog() async {
        if selectedProvider.id == "all" {
            await store.loadCatalog(kind: kind)
        } else {
            await store.loadProviderCatalog(selectedProvider)
        }
    }

    private func select(_ provider: StreamingProvider) {
        selectedProvider = provider
        store.settings.selectedProvider = provider.id == "all" ? nil : provider.name
        Task { await loadCatalog() }
    }

    var body: some View {
        NavigationStack {
            AdaptiveBackdrop(media: items.first) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Discover").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                            Text("Pick a service, then browse its movies, shows, and anime.").foregroundStyle(.white.opacity(0.6))
                        }
                        FrostSegmentedControl(items: ["All", "Movies", "Shows", "Anime"], selection: $selectedTab)
                        DiscoverMenu(title: selectedProvider.id == "all" ? "All services" : selectedProvider.name, icon: "play.rectangle", provider: selectedProvider) {
                            ForEach(ProviderCatalog.providers) { provider in
                                Button {
                                    select(provider)
                                } label: {
                                    Label(provider.name, systemImage: provider.id == selectedProvider.id ? "checkmark" : "play.rectangle")
                                }
                            }
                        }
                        if kind == .anime {
                            AnimeIntroCard()
                            if selectedProvider.id != "all" {
                                NoticeCard(
                                    title: "Anime lives in the All catalog",
                                    message: "\(selectedProvider.name)'s catalog covers movies and shows. Switch to All services to browse anime from AniList.",
                                    systemImage: "sparkles"
                                )
                            }
                            if let error = store.animeError {
                                NoticeCard(title: "Anime catalog unavailable", message: error, systemImage: "wifi.exclamationmark")
                            }
                        }
                        if isLoading && items.isEmpty {
                            SkeletonGrid(count: 6)
                                .frostSwapTransition(reduceMotion: store.settings.reduceMotion)
                        } else if isLoading {
                            ProgressView(selectedProvider.id == "all" ? "Refreshing catalog…" : "Refreshing \(selectedProvider.name)…")
                                .tint(frostOrange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        if selectedProvider.id != "all", let error = store.providerError {
                            NoticeCard(title: "\(selectedProvider.name) unavailable", message: error, systemImage: "wifi.exclamationmark")
                        }
                        if selectedProvider.id == "all", let error = store.searchError {
                            NoticeCard(title: "Catalog unavailable", message: error, systemImage: "wifi.exclamationmark")
                        }
                        if !(isLoading && items.isEmpty) {
                            Text("\(items.count) results").font(.headline).foregroundStyle(.white.opacity(0.7))
                        }
                        if items.isEmpty && !isLoading {
                            Button {
                                Task { await loadCatalog() }
                            } label: {
                                FrostActionLabel(title: "Reload catalog", systemImage: "arrow.clockwise", subtitle: "Fetch this list again")
                            }
                            .buttonStyle(FrostPressStyle())
                        }
                        PosterGrid(items: items, onReachedEnd: {
                            Task {
                                if selectedProvider.id == "all" { await store.loadMoreSearchResults() }
                                else { await store.loadMoreProviderCatalog(selectedProvider) }
                            }
                        })
                    }
                    .animation(.easeInOut(duration: 0.28), value: isLoading)
                    .padding(16)
                    .padding(.bottom, 140)
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if !didRestoreProvider {
                    didRestoreProvider = true
                    if let name = store.settings.selectedProvider,
                       let saved = ProviderCatalog.providers.first(where: { $0.name == name }) {
                        selectedProvider = saved
                    }
                }
                await loadCatalog()
            }
            .onChange(of: selectedTab) { _, _ in Task { await loadCatalog() } }
            .navigationDestination(item: $navigator.detail) { DetailView(media: $0) }
        }
        .fullScreenCover(item: $navigator.player) { PlayerView(media: $0) }
        .environmentObject(navigator)
        .preferredColorScheme(.dark)
    }
}

struct DiscoverMenu<Content: View>: View {
    let title: String
    let icon: String
    /// When set, the menu label shows the service's real logo instead of an icon.
    var provider: StreamingProvider? = nil
    @ViewBuilder let content: Content
    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 9) {
                if let provider {
                    ProviderLogo(provider: provider, size: 24)
                } else {
                    Image(systemName: icon).font(.subheadline)
                }
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.caption2.bold()).foregroundStyle(.white.opacity(0.42))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .frostGlass(cornerRadius: 14, opacity: 0.85)
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
                MediaLink(media: media) {
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
                        Text(media.kind.title + (media.year.map { " · \($0)" } ?? "") + (media.episodeCount.map { " · \($0) episodes" } ?? ""))
                            .font(.caption2).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
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
    @StateObject private var navigator = MediaNavigator()
    @State private var query = ""
    @State private var kind: MediaKind?

    /// Each tab browses a catalog on tap with no query needed; typing a query
    /// switches the same tab over to real search results.
    private func loadKind(_ newKind: MediaKind?) async {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanQuery.isEmpty {
            await store.loadCatalog(kind: newKind)
        } else {
            await store.search(query: cleanQuery, kind: newKind)
        }
    }

    var body: some View {
        NavigationStack {
            AdaptiveBackdrop(media: store.searchResults.first) {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Search").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                        Text("Browse a catalog, or look up any title.").font(.subheadline).foregroundStyle(.white.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.55))
                        TextField("Browse a catalog or search a title", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search).onSubmit { Task { await loadKind(kind) } }
                        if !query.isEmpty { Button { query = ""; Task { await store.loadCatalog(kind: kind) } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.45)) } }
                    }
                    .padding(14).background(frostPanel).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    FrostSegmentedControl<MediaKind?>(items: [nil, .movie, .tv, .anime], title: { $0?.title ?? "All" }, selection: $kind)
                    if store.isSearching && store.searchResults.isEmpty {
                        ScrollView { SkeletonGrid(count: 6) }
                            .frostSwapTransition(reduceMotion: store.settings.reduceMotion)
                    }
                    else if store.isSearching { ProgressView(query.isEmpty ? "Refreshing catalog…" : "Searching…").tint(frostOrange).padding(.top, 30) }
                    else if let error = store.searchError, !store.searchResults.isEmpty { NoticeCard(title: "Some results are unavailable", message: error, systemImage: "magnifyingglass") }
                    else if store.searchResults.isEmpty {
                        ContentUnavailableView(
                            "Nothing here yet",
                            systemImage: "sparkles",
                            description: Text(store.searchError ?? "Browse another tab or search for a title.")
                        )
                    }
                    else { ScrollView { PosterGrid(items: store.searchResults, onReachedEnd: { Task { await store.loadMoreSearchResults() } }).padding(.top, 4); if store.isLoadingMore { ProgressView("Loading more…").tint(frostOrange).frame(maxWidth: .infinity).padding() } } }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .padding(.bottom, 36)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            // Re-runs on every visit, so a typed query is re-issued and a
            // browsed tab picks a fresh (random) AniList page.
            .task { await loadKind(kind) }
            // Switching title type re-runs whatever is on screen: a typed query is
            // re-issued for the new kind, an empty one reloads that kind's catalog.
            .onChange(of: kind) { _, newKind in
                Task { await loadKind(newKind) }
            }
            .navigationDestination(item: $navigator.detail) { DetailView(media: $0) }
        }
        .fullScreenCover(item: $navigator.player) { PlayerView(media: $0) }
        .environmentObject(navigator)
        .preferredColorScheme(.dark)
    }
}

/// The Library tab: every list, plus offline downloads.
struct LibraryView: View {
    @EnvironmentObject private var store: FrostPlayStore
    @State private var section = "Lists"
    @State private var showingNewList = false

    private var backdrop: MediaItem? {
        section == "Lists" ? store.library.first : store.downloads.first?.media
    }

    var body: some View {
        NavigationStack {
            AdaptiveBackdrop(media: backdrop) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Library").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text(section == "Lists" ? "A list for every mood, with the cover you choose." : "Offline files stored on this device.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.58))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        FrostSegmentedControl(items: ["Lists", "Downloads"], selection: $section)
                        if section == "Lists" { listsSection } else { DownloadsList() }
                    }
                    .animation(.easeInOut(duration: 0.25), value: section)
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        LibrarySettingsView()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Lists and covers settings")
                }
            }
            .sheet(isPresented: $showingNewList) { NewCollectionSheet() }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var listsSection: some View {
        if store.collections.isEmpty {
            ContentUnavailableView(
                "No lists yet",
                systemImage: "rectangle.stack.badge.plus",
                description: Text("Create a list to start saving movies, shows, and anime.")
            )
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
            ForEach(store.collections) { collection in
                NavigationLink {
                    CollectionDetailView(collectionID: collection.id)
                } label: {
                    CollectionCard(collection: collection)
                }
                .buttonStyle(FrostPressStyle(scale: 0.985))
            }
            Button { showingNewList = true } label: { NewCollectionCard() }
                .buttonStyle(FrostPressStyle(scale: 0.985))
        }
    }
}

/// One list's tile in the Library grid.
struct CollectionCard: View {
    @EnvironmentObject private var store: FrostPlayStore
    let collection: MediaCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            CollectionCover(collection: collection)
                .frame(height: 150)
            VStack(alignment: .leading, spacing: 3) {
                Text(collection.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                if store.settings.showListCounts {
                    Text(collection.entries.count == 1 ? "1 title" : "\(collection.entries.count) titles")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A list's cover. Draws the user's chosen photo, or one to four titles' posters,
/// and falls back to an empty-list glyph.
struct CollectionCover: View {
    @EnvironmentObject private var store: FrostPlayStore
    let collection: MediaCollection

    var body: some View {
        Group {
            if collection.artwork.style == .custom,
               let data = collection.artwork.customImageData,
               let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                let tiles = store.coverMedia(for: collection)
                if tiles.isEmpty {
                    emptyCover
                } else if tiles.count == 1 {
                    tile(tiles[0])
                } else {
                    mosaic(tiles)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
    }

    /// Shown when a list has nothing to draw yet.
    private var emptyCover: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func mosaic(_ tiles: [MediaItem]) -> some View {
        let slots = Array(tiles.prefix(4))
        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                slot(at: 0, in: slots)
                slot(at: 1, in: slots)
            }
            HStack(spacing: 2) {
                slot(at: 2, in: slots)
                slot(at: 3, in: slots)
            }
        }
    }

    private func slot(at index: Int, in slots: [MediaItem]) -> some View {
        Group {
            if slots.indices.contains(index) {
                tile(slots[index])
            } else {
                Color.white.opacity(0.06)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func tile(_ media: MediaItem) -> some View {
        AsyncImage(url: media.posterURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            FrostShimmer(cornerRadius: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

/// Dashed "add a list" tile at the end of the Library grid.
struct NewCollectionCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus").font(.title2.weight(.semibold))
            Text("New list").font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.8))
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        }
    }
}

struct NewCollectionSheet: View {
    @EnvironmentObject private var store: FrostPlayStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("List name", text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frostGlass(cornerRadius: 14)
                Text("You can rename the list and change its cover whenever you like.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(frostBackground.ignoresSafeArea())
            .navigationTitle("New list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        store.createCollection(named: trimmedName)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(frostBackground)
        .preferredColorScheme(.dark)
    }
}

enum CollectionArtworkProcessor {
    /// Downscales a picked photo before it is stored, so list covers never bloat
    /// the locally saved data.
    static func downscaledJPEGData(from data: Data, maximumDimension: CGFloat = 900) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > maximumDimension else { return image.jpegData(compressionQuality: 0.82) }
        let scale = maximumDimension / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.82)
    }
}

/// One list's detail screen: cover, rename, per-list title names, and removal.
struct CollectionDetailView: View {
    @EnvironmentObject private var store: FrostPlayStore
    let collectionID: String
    @State private var showingArtwork = false
    @State private var showingRename = false
    @State private var nameDraft = ""
    @State private var renameTarget: CollectionEntry?
    @State private var aliasDraft = ""
    @State private var showingDelete = false
    @State private var showingAdd = false

    private var collection: MediaCollection? { store.collection(id: collectionID) }

    /// Drives the per-title rename alert off the entry it is renaming.
    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    var body: some View {
        Group {
            if let collection {
                content(for: collection)
            } else {
                ContentUnavailableView(
                    "List unavailable",
                    systemImage: "rectangle.stack",
                    description: Text("This list was deleted.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(frostBackground.ignoresSafeArea())
            }
        }
        .navigationTitle(collection?.name ?? "List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if collection != nil {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add titles to this list")
                }
            }
        }
        // Presented from the screen root so it never competes with the cover
        // sheet, which belongs to the scrolling content below.
        .sheet(isPresented: $showingAdd) { CollectionAddTitlesSheet(collectionID: collectionID) }
        .preferredColorScheme(.dark)
    }

    private func content(for collection: MediaCollection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(for: collection)
                if collection.entries.isEmpty {
                    ContentUnavailableView(
                        "Nothing saved yet",
                        systemImage: "bookmark",
                        description: Text("Save titles from a title's long-press menu or its detail screen.")
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(collection.entries) { entry in
                            row(entry, in: collection)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.28), value: collection.entries.count)
            .padding(16)
            .padding(.bottom, 60)
        }
        .background(frostBackground.ignoresSafeArea())
        .sheet(isPresented: $showingArtwork) { CollectionArtworkPicker(collectionID: collectionID) }
        .alert("Rename list", isPresented: $showingRename) {
            TextField("List name", text: $nameDraft)
            Button("Save") { store.renameCollection(collectionID, to: nameDraft) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename in this list", isPresented: renameAlertBinding, presenting: renameTarget) { entry in
            TextField("Name", text: $aliasDraft)
            Button("Save") { store.setAlias(aliasDraft, for: entry.media.id, in: collectionID) }
            Button("Use original title", role: .destructive) { store.setAlias(nil, for: entry.media.id, in: collectionID) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This name only appears inside \(collection.name).")
        }
        .confirmationDialog("Delete this list?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    store.deleteCollection(collectionID)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its titles stay in your other lists and in your watch history.")
        }
    }

    private func header(for collection: MediaCollection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { showingArtwork = true } label: {
                CollectionCover(collection: collection)
                    .frame(height: 190)
                    .overlay(alignment: .bottomTrailing) {
                        Label("Edit cover", systemImage: "photo.on.rectangle.angled")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .padding(10)
                    }
            }
            .buttonStyle(FrostPressStyle(scale: 0.99))

            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(collection.entries.count == 1 ? "1 title" : "\(collection.entries.count) titles")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 10) {
                Button { showingArtwork = true } label: {
                    FrostActionLabel(
                        title: "Edit cover",
                        systemImage: "photo.on.rectangle.angled",
                        subtitle: collection.artwork.style.title,
                        compact: true
                    )
                }
                .buttonStyle(FrostPressStyle())
                Button {
                    nameDraft = collection.name
                    showingRename = true
                } label: {
                    FrostActionLabel(
                        title: "Rename",
                        systemImage: "textformat",
                        subtitle: "Just this list",
                        compact: true
                    )
                }
                .buttonStyle(FrostPressStyle())
                if !collection.isBuiltIn {
                    Button {
                        if store.settings.confirmListDeletion { showingDelete = true } else { store.deleteCollection(collectionID) }
                    } label: {
                        FrostActionLabel(
                            title: "Delete",
                            systemImage: "trash",
                            subtitle: "Remove list",
                            compact: true
                        )
                    }
                    .buttonStyle(FrostPressStyle())
                }
            }
        }
    }

    private func row(_ entry: CollectionEntry, in collection: MediaCollection) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                DetailView(media: entry.media)
            } label: {
                HStack(spacing: 12) {
                    Poster(url: entry.media.posterURL, width: 54, height: 78)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.settings.showListAliases ? entry.displayTitle : entry.media.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if store.settings.showListAliases, entry.isRenamed {
                            Text(entry.media.title)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Text(entry.media.kind.title + (entry.media.year.map { " · \($0)" } ?? ""))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    aliasDraft = entry.alias ?? entry.media.title
                    renameTarget = entry
                } label: {
                    Label("Rename in this list", systemImage: "pencil")
                }
                if entry.isRenamed {
                    Button {
                        store.setAlias(nil, for: entry.media.id, in: collection.id)
                    } label: {
                        Label("Use original title", systemImage: "arrow.uturn.backward")
                    }
                }
                Button(role: .destructive) {
                    store.remove(entry.media, from: collection.id)
                } label: {
                    Label("Remove from list", systemImage: "minus.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.leading, 2)
            }
        }
        .padding(11)
        .frostGlass(cornerRadius: 16, opacity: 0.85)
    }
}

/// Chooses a list's cover: automatic, four picked titles, one picked title, or a
/// photo from the user's library.
struct CollectionArtworkPicker: View {
    @EnvironmentObject private var store: FrostPlayStore
    let collectionID: String
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var importFailed = false

    private var collection: MediaCollection? { store.collection(id: collectionID) }
    private var style: CollectionArtwork.Style { collection?.artwork.style ?? .automatic }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let collection {
                        CollectionCover(collection: collection)
                            .frame(height: 170)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Text("COVER STYLE")
                            .font(.caption2.bold())
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.45))
                        ForEach(CollectionArtwork.Style.allCases) { option in
                            Button {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    store.setArtworkStyle(option, for: collectionID)
                                }
                            } label: {
                                FrostActionLabel(
                                    title: option.title,
                                    systemImage: style == option ? "checkmark.circle.fill" : option.symbolName,
                                    subtitle: option.subtitle,
                                    trailingChevron: false
                                )
                            }
                            .buttonStyle(FrostPressStyle())
                        }
                    }
                    if style == .mosaic || style == .single {
                        titlePicker
                    }
                    if style == .custom {
                        customImagePicker
                    }
                }
                .padding(16)
            }
            .background(frostBackground.ignoresSafeArea())
            .navigationTitle("List cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationBackground(frostBackground)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var titlePicker: some View {
        let entries = collection?.entries ?? []
        VStack(alignment: .leading, spacing: 9) {
            Text(style == .single ? "PICK ONE TITLE" : "PICK UP TO FOUR TITLES")
                .font(.caption2.bold())
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.45))
            if entries.isEmpty {
                Text("Save a few titles to this list first.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                ForEach(entries) { entry in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            store.toggleCoverMedia(entry.media.id, for: collectionID)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                Poster(url: entry.media.posterURL, width: nil, height: 104)
                                if isSelected(entry.media.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(.black)
                                        .padding(5)
                                        .background(Circle().fill(frostOrange))
                                        .padding(5)
                                }
                            }
                            Text(entry.displayTitle)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var customImagePicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("CUSTOM IMAGE")
                .font(.caption2.bold())
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.45))
            PhotosPicker(selection: $pickerItem, matching: .images) {
                FrostActionLabel(
                    title: "Choose from Photos",
                    systemImage: "photo",
                    subtitle: isImporting ? "Importing…" : "Stored on this device only",
                    trailingChevron: true
                )
            }
            .buttonStyle(FrostPressStyle())
            if collection?.artwork.customImageData != nil {
                Button {
                    store.setCustomArtwork(nil, for: collectionID)
                } label: {
                    FrostActionLabel(
                        title: "Remove custom image",
                        systemImage: "trash",
                        subtitle: "Falls back to a title cover"
                    )
                }
                .buttonStyle(FrostPressStyle())
            }
        }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            isImporting = true
            Task {
                if let loaded = try? await newValue.loadTransferable(type: Data.self),
                   let processed = CollectionArtworkProcessor.downscaledJPEGData(from: loaded) {
                    store.setCustomArtwork(processed, for: collectionID)
                } else {
                    importFailed = true
                }
                isImporting = false
                pickerItem = nil
            }
        }
        .alert("That image could not be used", isPresented: $importFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func isSelected(_ mediaID: String) -> Bool {
        collection?.artwork.mediaIDs.contains(mediaID) ?? false
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
                NavigationLink { HomeSectionsSettingsView() } label: { SettingsRow(icon: "rectangle.3.group", title: "Home sections", subtitle: "Edit in place on the Home screen") }
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
    /// When set, the rail heading carries the service's real logo and name, so a
    /// "Popular Right Now" rail clearly belongs to the selected service.
    var provider: StreamingProvider? = nil
    var progress = false
    var onReachedEnd: (() -> Void)? = nil

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let provider {
                        ProviderLogo(provider: provider, size: 22)
                        Text(provider.name.uppercased()).font(.caption2.bold()).tracking(1.1).foregroundStyle(frostOrange)
                    }
                    Text(title).font(.title3.bold()).foregroundStyle(.white)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { media in
                            MediaLink(media: media) {
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
            FrostShimmer(cornerRadius: 14)
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
    /// Movies (and anime films) play straight from the detail screen.
    private var isPlayable: Bool {
        media.kind == .movie || (media.kind == .anime && (refreshedAnimeMetadata ?? media.metadata)?.format?.uppercased() == "MOVIE")
    }
    private var currentSource: PlaybackSource { store.settings.defaultSource(for: media.kind) }

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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        if isPlayable {
                            NavigationLink {
                                PlayerView(media: media)
                            } label: {
                                FrostActionLabel(title: "Play", systemImage: "play.fill", subtitle: "Start streaming", prominent: true)
                            }
                            .buttonStyle(FrostPressStyle())
                        }
                        Button {
                            store.toggleLibrary(media)
                        } label: {
                            FrostActionLabel(
                                title: store.isInLibrary(media) ? "Saved" : "My List",
                                systemImage: store.isInLibrary(media) ? "checkmark" : "bookmark",
                                subtitle: store.isInLibrary(media) ? "In your list" : "Save for later"
                            )
                        }
                        .buttonStyle(FrostPressStyle())
                    }
                    Button {
                        showingSourcePicker = true
                    } label: {
                        FrostActionLabel(
                            title: currentSource.rawValue,
                            systemImage: "rectangle.2.swap",
                            subtitle: "Playback source · tap to change",
                            trailingChevron: true
                        )
                    }
                    .buttonStyle(FrostPressStyle())
                    .accessibilityLabel("Change playback source, currently \(currentSource.rawValue)")
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
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
                    Button { Task { await loadAnimeStreams() } } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(frostOrange)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .frostGlass(cornerRadius: 11, opacity: 0.8)
                    }
                    .buttonStyle(FrostPressStyle())
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
            if isLoading && seasons.isEmpty {
                SkeletonEpisodeRows()
                    .frostSwapTransition(reduceMotion: store.settings.reduceMotion)
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
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(episode.number == selectedEpisode ? frostOrange : Color.white.opacity(0.09))
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                                    Text("E\(episode.number)").font(.subheadline.bold()).foregroundStyle(episode.number == selectedEpisode ? Color.black : Color.white)
                                }
                                .frame(width: 48, height: 40)
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
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(episode.number == selectedEpisode ? frostOrange.opacity(0.12) : Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(episode.number == selectedEpisode ? frostOrange.opacity(0.45) : Color.white.opacity(0.07), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { selectedEpisode = episode.number })
                }
            }
        }
        .padding(14)
        .frostGlass(cornerRadius: 20, opacity: 0.9)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This becomes the default for \(kindLabel) titles, and this title starts playing with it right away.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(compatibleSources) { source in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                store.setDefaultSource(source, for: media.kind)
                            }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: source == selectedSource ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(source == selectedSource ? frostOrange : Color.white.opacity(0.32))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text(source == selectedSource ? "Current default for \(kindLabel)" : source.blurb)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frostGlass(cornerRadius: 15, highlighted: source == selectedSource, opacity: 0.9)
                        }
                        .buttonStyle(FrostPressStyle())
                    }
                    if compatibleSources.isEmpty {
                        Text("No verified source is available for this title type.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(16)
            }
            .background(frostBackground.ignoresSafeArea())
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(frostBackground)
        .preferredColorScheme(.dark)
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
                        .frame(width: 36, height: 36)
                        .frostGlass(cornerRadius: 12, opacity: 0.9)
                }
                .buttonStyle(FrostPressStyle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.kind == .movie ? media.title : "S\(season) · Episode \(episode)").font(.headline).lineLimit(1)
                    Text(resolvedPlayback?.source.rawValue.uppercased() ?? "FROSTPLAY PLAYER").font(.caption2.bold()).tracking(1.5).foregroundStyle(frostOrange)
                }
                Spacer()
                Button { showingSourcePicker = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.2.swap").font(.caption2.bold())
                        Text("Source").font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frostGlass(cornerRadius: 12, opacity: 0.9)
                }
                .buttonStyle(FrostPressStyle())
                .accessibilityLabel("Change playback source")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if let format = resolver.resolve(media: media, settings: store.settings, season: season, episode: episode, preferredURL: preferredPlaybackURL) {
                HybridPlayer(format: format).frame(maxHeight: .infinity)
                if AuthorizedDownloadManager.downloadableURL(for: format) != nil {
                    Button { Task { try? await store.download(media: media, format: format, episode: media.kind == .movie ? nil : episode) } } label: {
                        FrostActionLabel(title: "Download MP4", systemImage: "arrow.down.circle.fill", subtitle: "Save this file for offline playback", prominent: true)
                    }
                    .buttonStyle(FrostPressStyle())
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
