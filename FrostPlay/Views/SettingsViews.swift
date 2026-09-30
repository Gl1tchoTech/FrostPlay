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
            Section("Loading") {
                Toggle("Loading placeholders", isOn: $store.settings.showLoadingPlaceholders)
                SliderRow(
                    title: "Minimum time",
                    value: $store.settings.minimumPlaceholderSeconds,
                    range: 0...3,
                    suffix: String(format: "%.1f s", store.settings.minimumPlaceholderSeconds)
                )
                .disabled(!store.settings.showLoadingPlaceholders)
                Text("Placeholders stay up for at least this long on a first load, so content never flashes in and out. Later refreshes resolve as fast as the network allows.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(frostPanel)
            Section("Library") {
                NavigationLink { LibrarySettingsView() } label: {
                    Label("Lists & covers", systemImage: "rectangle.stack")
                }
                Text("Cover style for new lists, per-list title names, and deletion behaviour.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(frostPanel)
        }
        .navigationTitle("Appearance")
        .scrollContentBackground(.hidden)
        .background(frostBackground)
    }
}

/// Settings for the multi-list Library: default covers, counts, per-list names,
/// and deletion behaviour.
struct LibrarySettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Section("New lists") {
                Picker("Default cover", selection: $store.settings.listCoverStyle) {
                    ForEach(CollectionArtwork.Style.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Text("Applied to every list you create from now on. Any list's cover can still be changed from the Library tab.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Covers") {
                Toggle("Show title counts", isOn: $store.settings.showListCounts)
                Toggle("Use per-list names", isOn: $store.settings.showListAliases)
                Text("A per-list name only changes a title inside that one list. Everywhere else keeps the real title.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset all covers", systemImage: "arrow.counterclockwise")
                }
            }
            Section("Lists") {
                Toggle("Confirm before deleting", isOn: $store.settings.confirmListDeletion)
                ForEach(store.collections) { collection in
                    Label(collection.name, systemImage: collection.isBuiltIn ? "bookmark.fill" : "rectangle.stack")
                }
            }
        }
        .listRowBackground(frostPanel)
        .navigationTitle("Lists & covers")
        .scrollContentBackground(.hidden)
        .background(frostBackground)
        .confirmationDialog("Reset every list cover?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Reset covers", role: .destructive) { store.resetAllCovers() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Custom photos and chosen titles are removed. Your lists and their titles stay.")
        }
    }
}

struct PlaybackSettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        Form {
            Section("Playback") {
                Picker("Preferred quality", selection: $store.settings.preferredQuality) { Text("Auto").tag("Auto"); Text("1080p").tag("1080p"); Text("720p").tag("720p") }
                Toggle("Auto skip intro", isOn: $store.settings.autoSkipIntro)
                Toggle("Auto subtitles", isOn: $store.settings.autoSubtitles)
                Toggle("Allow direct-file downloads", isOn: $store.settings.downloadsEnabled)
            }
            Section("Episodes") {
                Toggle("Autoplay next episode", isOn: $store.settings.autoplayNextEpisode)
                Toggle("Mark watched when finished", isOn: $store.settings.autoMarkWatchedOnFinish)
                Toggle("Long-press marks watched", isOn: $store.settings.longPressMarksWatched)
                NavigationLink { EpisodeMetadataSettingsView() } label: {
                    Label("Episode metadata", systemImage: "list.bullet.rectangle")
                }
                Text("Autoplay offers the next episode with a countdown you can accept or cancel, continues into the next season, and stops after the final episode. Your position inside every episode is remembered separately.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

/// The presets the AI connection starts from. OpenRouter and OpenAI speak the
/// same OpenAI-compatible request shape, so only the base URL and model change.
private enum AIMetadataPreset: String, CaseIterable, Identifiable {
    case openRouter = "OpenRouter"
    case openAI = "OpenAI"
    case custom = "Custom"

    var id: String { rawValue }

    var baseURL: String {
        switch self {
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .openRouter: return "openai/gpt-4o-mini"
        case .openAI: return "gpt-4o-mini"
        case .custom: return ""
        }
    }

    static func matching(_ baseURL: String) -> AIMetadataPreset {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == Self.openRouter.baseURL.lowercased() { return .openRouter }
        if trimmed == Self.openAI.baseURL.lowercased() { return .openAI }
        return .custom
    }
}

/// Links an OpenAI-compatible key (OpenAI, OpenRouter, or a custom host) and
/// edits the prompt the model receives when the user taps "Add Season Metadata".
struct AIMetadataSettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Preset", selection: presetSelection) {
                    ForEach(AIMetadataPreset.allCases) { preset in Text(preset.rawValue).tag(preset) }
                }
                Toggle("Enable AI metadata", isOn: $store.settings.aiMetadataEnabled)
                Text("FrostPlay calls the endpoint you configure directly from this device. The key is stored locally in settings, exactly like your TMDB key.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(frostPanel)
            Section("Connection") {
                SecureField("API key", text: $store.settings.aiAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                TextField("Base URL", text: $store.settings.aiBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Model", text: $store.settings.aiModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Label(
                    store.isAIConfigured ? "Ready" : "Add a key and model to enable AI metadata",
                    systemImage: store.isAIConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(store.isAIConfigured ? .green : .orange)
                Text("Any host that speaks the OpenAI chat-completions API works. FrostPlay appends `/chat/completions` to the base URL unless it is already there.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(frostPanel)
            Section("Prompt") {
                Text("Placeholders: {title} {year} {format} {season} {episode_count} {episode_numbers} {genres} {overview}")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("System").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextEditor(text: $store.settings.aiSystemPrompt)
                    .frame(minHeight: 80)
                    .font(.footnote.monospaced())
                Text("User").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextEditor(text: $store.settings.aiEpisodePrompt)
                    .frame(minHeight: 190)
                    .font(.footnote.monospaced())
                Button("Reset prompts") {
                    store.settings.aiSystemPrompt = AIMetadataPrompts.system
                    store.settings.aiEpisodePrompt = AIMetadataPrompts.episode
                }
            }
            .listRowBackground(frostPanel)
        }
        .navigationTitle("AI metadata")
        .scrollContentBackground(.hidden)
        .background(frostBackground)
    }

    /// Picking a preset fills in the base URL and model; Custom leaves whatever
    /// the user already typed so they can point at their own host.
    private var presetSelection: Binding<AIMetadataPreset> {
        Binding(
            get: { AIMetadataPreset.matching(store.settings.aiBaseURL) },
            set: { preset in
                guard preset != .custom else { return }
                store.settings.aiBaseURL = preset.baseURL
                store.settings.aiModel = preset.defaultModel
            }
        )
    }
}

struct SubtitleSettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    var body: some View {
        Form {
            Section { Text("The quick brown fox").font(.title3.weight(store.settings.boldText ? .bold : .regular)).foregroundStyle(subtitleColor).frame(maxWidth: .infinity).padding(28).background(Color.black).clipShape(RoundedRectangle(cornerRadius: 16)) }
            Section("Subtitles") { Toggle("Use native player", isOn: $store.settings.subtitleUseNativePlayer) }
            Section("Color") { FrostSegmentedControl(items: ["White", "Yellow", "Cyan", "Green"], selection: subtitleColorSelection) }
            Section("Text size") { Slider(value: $store.settings.textScale, in: 0.85...1.5).tint(frostOrange) }
        }
        .navigationTitle("Subtitles")
        .scrollContentBackground(.hidden)
        .background(frostBackground)
    }
    private var subtitleColor: Color { store.settings.subtitleColor == "yellow" ? .yellow : store.settings.subtitleColor == "cyan" ? .cyan : store.settings.subtitleColor == "green" ? .green : .white }

    /// Bridges the stored lowercase token to the display-cased segmented control.
    private var subtitleColorSelection: Binding<String> {
        Binding(
            get: { store.settings.subtitleColor.capitalized },
            set: { store.settings.subtitleColor = $0.lowercased() }
        )
    }
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
            Section("Home") {
                Toggle("Rotate Home picks", isOn: $store.settings.rotateHomeCatalog)
                Text("Home shows a different trending or popular feed on every visit, instead of the same row of titles. The current feed is named above its rail.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Anime episode details") {
                Toggle("Kitsu episode details", isOn: $store.settings.kitsuEpisodeDetails)
                Text("Adds Kitsu's per-episode titles, synopses, air dates, and artwork to the episode list. AniList still owns the numbering and the MegaPlay playback URLs, so turning this off never removes episodes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Catalog & API")
        .scrollContentBackground(.hidden)
        .background(frostBackground)
    }
}

/// The per-episode experience: how episode rows behave, how watched state is
/// tracked, and one place to undo every manual episode edit.
struct EpisodeMetadataSettingsView: View {
    @EnvironmentObject private var store: FrostPlayStore
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Section("Episode screen") {
                Toggle("Open episode details first", isOn: $store.settings.episodeDetailViewEnabled)
                Toggle("Allow editing episode details", isOn: $store.settings.episodeMetadataEditingEnabled)
                Text("Tapping an episode opens its own screen with the full synopsis and its watched state. Long-pressing a row still offers Play, watched, and edit actions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Watched state") {
                Toggle("Long-press marks watched", isOn: $store.settings.longPressMarksWatched)
                Toggle("Mark watched when finished", isOn: $store.settings.autoMarkWatchedOnFinish)
                SliderRow(
                    title: "Finished at",
                    value: $store.settings.watchCompletionThreshold,
                    range: 0.5...0.99,
                    suffix: "\(Int(store.settings.watchCompletionThreshold * 100))%"
                )
                .disabled(!store.settings.autoMarkWatchedOnFinish)
                Text("An episode counts as finished once playback passes this point. Resume positions are kept per episode whether or not you mark them watched.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Autoplay") {
                Toggle("Autoplay next episode", isOn: $store.settings.autoplayNextEpisode)
                Toggle("Stop after the last episode", isOn: $store.settings.stopAfterLastEpisode)
                Text("The next episode is offered with a countdown bar. Ending a season continues with the next season's first episode.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Episodes with your edits", value: "\(store.episodeOverrideCount)")
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset all episode edits", systemImage: "arrow.counterclockwise")
                }
                .disabled(store.episodeOverrideCount == 0)
            } footer: {
                Text("Titles, synopses, and artwork you replaced go back to what the providers published. Watched state and resume positions are kept.\n\nWhen a provider publishes no title, synopsis, or artwork for an episode, FrostPlay says so on the row instead of repeating \"Episode N\".")
            }
        }
        .listRowBackground(frostPanel)
        .navigationTitle("Episode metadata")
        .scrollContentBackground(.hidden)
        .background(frostBackground)
        .confirmationDialog("Reset every episode edit?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Reset edits", role: .destructive) { store.clearAllEpisodeOverrides() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Episode titles, synopses, and artwork you replaced return to the provider's own data.")
        }
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
                Text("You can also edit Home in place: tap the sliders icon on the Home screen and drag sections into place.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Order") {
                ForEach(store.settings.homeSections) { section in
                    Label(section.title, systemImage: section.symbolName)
                }
                .onMove { indices, newOffset in store.moveHomeSection(from: indices, to: newOffset) }
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
