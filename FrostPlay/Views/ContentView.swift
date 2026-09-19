import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "sparkles") }
            SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
            LibraryView().tabItem { Label("Library", systemImage: "bookmark") }
            HistoryView().tabItem { Label("Recent", systemImage: "clock") }
            SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(.orange)
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: FrostPlayStore
    private let featured = [MediaItem.preview]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("FROSTPLAY").font(.caption.weight(.bold)).tracking(4).foregroundStyle(.orange)
                    Text("Your world of stories.").font(.system(size: 36, weight: .bold, design: .rounded))
                    ProviderFilterView()
                    ForEach(featured) { media in
                        MediaCard(media: media, featured: true)
                    }
                    ContentRail(title: "Continue watching", items: store.history.map(\.media))
                    ContentRail(title: "Your library", items: store.library)
                    ContentRail(title: "Popular right now", items: featured)
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Home")
        }
        .preferredColorScheme(.dark)
    }
}

struct ProviderFilterView: View {
    @EnvironmentObject private var store: FrostPlayStore
    let providers = ["All providers", "Netflix", "Disney+", "Hulu", "Max", "Prime Video"]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(providers, id: \.self) { provider in
                    Button(provider) { store.settings.selectedProvider = provider == "All providers" ? nil : provider }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background((store.settings.selectedProvider == provider || (provider == "All providers" && store.settings.selectedProvider == nil)) ? .orange : Color.white.opacity(0.1))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
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
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search movies, shows, anime", text: $query)
                        .onSubmit { Task { await store.search(query: query, kind: kind) } }
                }
                .padding().background(Color.white.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 14))
                Picker("Type", selection: $kind) {
                    Text("All").tag(MediaKind?.none)
                    ForEach(MediaKind.allCases) { Text($0.title).tag(Optional($0)) }
                }.pickerStyle(.segmented).padding(.vertical)
                if store.isSearching { ProgressView() }
                else if let error = store.searchError { Text(error).foregroundStyle(.secondary) }
                else if store.searchResults.isEmpty { ContentUnavailableView("Start exploring", systemImage: "sparkles", description: Text("Search the TMDB and AniList catalogs.")) }
                else { List(store.searchResults) { media in MediaRow(media: media) }.scrollContentBackground(.hidden) }
            }.padding().background(Color.black.ignoresSafeArea()).navigationTitle("Search")
        }.preferredColorScheme(.dark)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        NavigationStack {
            List {
                ForEach(MediaKind.allCases) { kind in
                    let items = store.library.filter { $0.kind == kind }
                    if !items.isEmpty { Section(kind.title) { ForEach(items) { MediaRow(media: $0) } } }
                }
            }.navigationTitle("Library").overlay { if store.library.isEmpty { ContentUnavailableView("Your library is empty", systemImage: "bookmark", description: Text("Save something you want to watch.")) } }
        }.preferredColorScheme(.dark)
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        NavigationStack { List(store.history) { entry in MediaRow(media: entry.media, progress: entry.progress) }.navigationTitle("Recently Watched").overlay { if store.history.isEmpty { ContentUnavailableView("Nothing watched yet", systemImage: "clock", description: Text("Your local watch history will appear here.")) } } }.preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") { Picker("Theme", selection: $store.settings.theme) { ForEach(AppTheme.allCases) { Text($0.rawValue.capitalized).tag($0) } } }
                Section("Anime") { Picker("Preferred streams", selection: $store.settings.preferredAnimeLanguage) { Text("Sub").tag("sub"); Text("Dub").tag("dub") } }
                Section("Playback sources") {
                    ForEach(PlaybackSource.allCases) { source in Toggle(source.rawValue, isOn: Binding(get: { store.settings.enabledSources.contains(source) }, set: { _ in store.toggleSource(source) })) }
                    ForEach(store.settings.enabledSources) { source in Text(source.rawValue).foregroundStyle(.secondary) }
                }
                Section { Text("FrostPlay stores library, settings, and watch history only on this device.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Settings")
        }
    }
}

struct MediaRow: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    var progress: Double = 0
    var body: some View {
        NavigationLink(destination: DetailView(media: media)) {
            HStack(spacing: 12) { Poster(url: media.posterURL, width: 54, height: 76); VStack(alignment: .leading) { Text(media.title).font(.headline); Text(media.kind.title + (media.year.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary); if progress > 0 { ProgressView(value: progress).tint(.orange) } } }
        }.swipeActions { Button { store.toggleLibrary(media) } label: { Label("Save", systemImage: "bookmark") } }
    }
}

struct ContentRail: View { let title: String; let items: [MediaItem]; var body: some View { if !items.isEmpty { VStack(alignment: .leading) { Text(title).font(.title3.bold()); ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(items) { NavigationLink(destination: DetailView(media: $0)) { Poster(url: $0.posterURL, width: 110, height: 160).overlay(alignment: .bottomLeading) { Text($0.title).font(.caption.bold()).lineLimit(2).padding(6).frame(maxWidth: .infinity, alignment: .leading).background(.black.opacity(0.65)) } } } } } } } }

struct MediaCard: View { @EnvironmentObject private var store: FrostPlayStore; let media: MediaItem; var featured = false; var body: some View { NavigationLink(destination: DetailView(media: media)) { ZStack(alignment: .bottomLeading) { Poster(url: media.backdropURL ?? media.posterURL, width: nil, height: featured ? 300 : 180).frame(maxWidth: .infinity).clipped(); LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom); VStack(alignment: .leading) { Text(media.title).font(.title.bold()); Text(media.overview).font(.caption).lineLimit(2) }.padding() } }.buttonStyle(.plain).clipShape(RoundedRectangle(cornerRadius: 20)) } }

struct Poster: View { let url: URL?; let width: CGFloat?; let height: CGFloat; var body: some View { AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(Color.white.opacity(0.1)).overlay { Image(systemName: "film").foregroundStyle(.secondary) } }.frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 12)) } }

struct DetailView: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) { Poster(url: media.backdropURL ?? media.posterURL, width: nil, height: 260).frame(maxWidth: .infinity); Text(media.title).font(.largeTitle.bold()); Text(media.kind.title + (media.year.map { " · \($0)" } ?? "")).foregroundStyle(.secondary); HStack { Button(store.isInLibrary(media) ? "Saved" : "Add to Library") { store.toggleLibrary(media) }.buttonStyle(.borderedProminent); NavigationLink("Watch", destination: PlayerView(media: media)).buttonStyle(.bordered) }; Text(media.overview).foregroundStyle(.secondary); if !media.providerNames.isEmpty { Text("Sources: \(media.providerNames.joined(separator: ", "))").font(.caption).foregroundStyle(.orange) } }.padding() }.navigationTitle(media.title).navigationBarTitleDisplayMode(.inline).background(Color.black.ignoresSafeArea()).preferredColorScheme(.dark)
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
                ContentUnavailableView("No source available", systemImage: "exclamationmark.triangle", description: Text("Enable another compatible source in Settings."))
            }
        }
        .onAppear { store.recordWatch(media) }
        .navigationTitle(media.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
