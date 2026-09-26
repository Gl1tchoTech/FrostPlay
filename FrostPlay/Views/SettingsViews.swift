import SwiftUI
import Darwin

// File-private copies of the shared palette so this file can stand on its own.
private let frostBackground = Color(red: 0.025, green: 0.025, blue: 0.03)
private let frostPanel = Color.white.opacity(0.075)
private let frostOrange = Color.orange

struct AppearanceSettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        Form {
            Section("Display") {
                Picker("Theme", selection: $store.settings.theme) {
                    Text("Dark").tag(AppTheme.dark)
                    Text("Light").tag(AppTheme.light)
                    Text("System").tag(AppTheme.system)
                }
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
                Toggle("Allow direct-file downloads", isOn: $store.settings.downloadsEnabled)
            }
            Section("Anime") {
                Picker("Preferred language", selection: $store.settings.preferredAnimeLanguage) { Text("Sub").tag("sub"); Text("Dub").tag("dub") }
                Picker("Default anime source", selection: $store.settings.defaultAnimeSource) {
                    ForEach(PlaybackSource.implemented.filter { $0.supports.contains(.anime) }) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                Text("Anime titles play through their AniList/MAL ID.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Movies & TV") {
                Picker("Default source", selection: $store.settings.defaultMovieTVSource) {
                    ForEach(PlaybackSource.implemented.filter { $0.supports.contains(.movie) }) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                Text("TMDB titles are addressed with their TMDB ID and never use MegaPlay.").font(.footnote).foregroundStyle(.secondary)
            }
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
                ForEach(store.settings.homeSections) { section in
                    Label(section.title, systemImage: "line.3.horizontal")
                }
                .onMove(perform: store.moveHomeSection)
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
            Section("Defaults") {
                Picker("Default anime source", selection: $store.settings.defaultAnimeSource) {
                    ForEach(PlaybackSource.implemented.filter { $0.supports.contains(.anime) }) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                Picker("Default movies & TV source", selection: $store.settings.defaultMovieTVSource) {
                    ForEach(PlaybackSource.implemented.filter { $0.supports.contains(.movie) }) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                Text("The default source is tried first for each title type; the remaining enabled sources are used as fallback.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Enabled sources") {
                ForEach(PlaybackSource.implemented) { source in
                    Toggle(source.rawValue, isOn: Binding(
                        get: { store.settings.enabledSources.contains(source) },
                        set: { store.setSource(source, enabled: $0) }
                    ))
                }
                Text("Anime plays through MegaPlay. Movies and TV play through VidLink or MoviesAPI, and a TMDB title never uses MegaPlay.").font(.footnote).foregroundStyle(.secondary)
                Text("Tap Edit, then drag sources to change their fallback priority.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Fallback priority") {
                ForEach(store.settings.enabledSources) { source in
                    Label(source.rawValue, systemImage: source == .megaPlay ? "sparkles" : "play.rectangle.fill")
                }
                .onMove(perform: store.moveSource)
            }
        }
        .navigationTitle("Sources")
        .toolbar { EditButton() }
        .scrollContentBackground(.hidden)
        .background(frostBackground)
    }
}

struct CacheSettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    @State private var showingClearConfirmation = false
    @State private var showingClearedConfirmation = false
    @State private var isClearing = false

    private var totalBytes: Int { store.cacheBreakdown.values.reduce(0, +) }

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Total cached", systemImage: "internaldrive")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ForEach(CacheCategory.allCases) { category in
                    HStack {
                        Text(category.rawValue)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(store.cacheBreakdown[category] ?? 0), countStyle: .file))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Sizes are approximate. Your saved list, watch history, downloads, and settings are kept when cache is cleared.")
            }

            Section {
                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        if isClearing { ProgressView() }
                        else { Label("Clear all cache", systemImage: "trash") }
                        Spacer()
                    }
                }
                .disabled(isClearing)
            } footer: {
                Text("Clears URL/image cache, WebKit data, temporary files, and the anime catalog cache.")
            }
        }
        .navigationTitle("Cache")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshCacheBreakdown() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh cache sizes")
            }
        }
        .scrollContentBackground(.hidden)
        .background(frostBackground)
        .task { await store.refreshCacheBreakdown() }
        .confirmationDialog("Clear all cached data?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Clear cache", role: .destructive) {
                Task {
                    isClearing = true
                    await store.clearAllCache()
                    isClearing = false
                    showingClearedConfirmation = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes temporary cached data. Your library, history, downloads, and settings will remain.")
        }
        .alert("Cache cleared", isPresented: $showingClearedConfirmation) {
            Button("Close app", role: .destructive) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { exit(EXIT_SUCCESS) }
            }
            Button("Keep using FrostPlay", role: .cancel) {}
        } message: {
            Text("FrostPlay will close. Reopen it to start with a fresh cache.")
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String
    var body: some View { VStack(alignment: .leading, spacing: 6) { HStack { Text(title); Spacer(); Text(suffix).foregroundStyle(.secondary) }; Slider(value: $value, in: range).tint(frostOrange) } }
}
