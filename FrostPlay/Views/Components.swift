import SwiftUI

// File-private copies of the shared palette so this file can stand on its own.
private let frostBackground = Color(red: 0.025, green: 0.025, blue: 0.03)
private let frostPanel = Color.white.opacity(0.075)
private let frostOrange = Color.orange

// MARK: - Press feedback

/// Tactile press feedback every custom control in FrostPlay uses instead of the
/// flat default button highlight.
struct FrostPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Glass surface

/// A soft, layered translucent surface: continuous rounded corners, a hairline
/// top-lit highlight, and a gentle drop shadow. Deliberately neither a hard
/// square nor a capsule pill.
private struct FrostGlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var highlighted: Bool
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: highlighted
                                    ? [frostOrange.opacity(0.34), frostOrange.opacity(0.16), Color.white.opacity(0.05)]
                                    : [Color.white.opacity(0.13 * opacity), Color.white.opacity(0.035 * opacity)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(highlighted ? 0.45 : 0.2),
                                Color.white.opacity(highlighted ? 0.14 : 0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(highlighted ? 0.3 : 0.34), radius: 14, y: 7)
    }
}

extension View {
    /// Applies the FrostPlay glass surface. `highlighted` tints the surface with
    /// the accent color, `opacity` scales the inner sheen.
    func frostGlass(cornerRadius: CGFloat = 16, highlighted: Bool = false, opacity: Double = 1) -> some View {
        modifier(FrostGlassSurface(cornerRadius: cornerRadius, highlighted: highlighted, opacity: opacity))
    }
}

// MARK: - Segmented control

/// A glass segmented control with a spring-animated sliding selector. Used in
/// place of the stock pill-shaped picker.
struct FrostSegmentedControl<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item
    @Namespace private var indicator

    private var compact: Bool { items.count > 3 }

    init(items: [Item], title: @escaping (Item) -> String, selection: Binding<Item>) {
        self.items = items
        self.title = title
        self._selection = selection
    }

    private var selectorShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    guard !isSelected else { return }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { selection = item }
                } label: {
                    Text(title(item))
                        .font((compact ? Font.footnote : Font.subheadline).weight(isSelected ? .bold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 8 : 9)
                        .background {
                            if isSelected {
                                selectorShape
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 1.0, green: 0.74, blue: 0.34), frostOrange],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay(selectorShape.strokeBorder(Color.white.opacity(0.34), lineWidth: 1))
                                    .shadow(color: frostOrange.opacity(0.42), radius: 10, y: 4)
                                    .matchedGeometryEffect(id: "frostSegment", in: indicator)
                            }
                        }
                        .contentShape(selectorShape)
                }
                .buttonStyle(FrostPressStyle(scale: 0.98))
            }
        }
        .padding(4)
        .frostGlass(cornerRadius: 15)
    }
}

extension FrostSegmentedControl where Item == String {
    init(items: [String], selection: Binding<String>) {
        self.init(items: items, title: { $0 }, selection: selection)
    }
}

// MARK: - Action label

/// The shared visual for every in-app action ("Play", "My List", "Source", …).
/// Renders as a glass row with an accent icon chip, optional subtitle, and an
/// optional trailing chevron.
struct FrostActionLabel: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil
    var prominent = false
    var trailingChevron = false
    var compact = false

    private var iconChip: CGFloat { compact ? 24 : 30 }

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 11 : 13, weight: .bold))
                .foregroundStyle(prominent ? Color.black.opacity(0.82) : frostOrange)
                .frame(width: iconChip, height: iconChip)
                .background(Circle().fill(prominent ? Color.black.opacity(0.14) : frostOrange.opacity(0.17)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(prominent ? Color.black : Color.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(prominent ? Color.black.opacity(0.58) : Color.white.opacity(0.52))
                }
            }
            Spacer(minLength: 0)
            if trailingChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(prominent ? Color.black.opacity(0.35) : Color.white.opacity(0.35))
            }
        }
        .padding(.horizontal, compact ? 11 : 13)
        .padding(.vertical, compact ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostGlass(cornerRadius: 14, highlighted: prominent, opacity: prominent ? 1 : 0.85)
    }
}

// MARK: - Media navigation

/// Coordinates the detail push and player presentation for a tab so that a
/// long-press menu can offer the same actions a tap performs.
@MainActor
final class MediaNavigator: ObservableObject {
    @Published var detail: MediaItem?
    @Published var player: MediaItem?
}

/// The long-press menu available on every title surface in the app.
struct MediaContextMenu: View {
    @EnvironmentObject private var store: FrostPlayStore
    let media: MediaItem
    var onOpen: () -> Void
    var onPlay: () -> Void

    var body: some View {
        Button { onOpen() } label: { Label("View details", systemImage: "info.circle") }
        Button { onPlay() } label: {
            Label(media.kind == .anime ? "Play first episode" : "Play", systemImage: "play.fill")
        }
        Menu {
            ForEach(store.collections) { collection in
                Button {
                    store.toggle(media, in: collection.id)
                } label: {
                    Label(
                        collection.name,
                        systemImage: store.isSaved(media, in: collection.id) ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
        } label: {
            Label(
                store.isInLibrary(media) ? "Saved in your lists" : "Add to list",
                systemImage: store.isInLibrary(media) ? "bookmark.fill" : "bookmark"
            )
        }
        if store.isInHistory(media) {
            Button { store.removeFromHistory(media) } label: {
                Label("Remove from watch history", systemImage: "clock.arrow.circlepath")
            }
        } else {
            Button { store.recordWatch(media) } label: {
                Label("Mark as watched", systemImage: "checkmark.circle")
            }
        }
    }
}

/// A tappable, long-pressable title card. Tapping opens the detail screen;
/// long-pressing reveals View details, Play, My List, and history actions.
struct MediaLink<Label: View>: View {
    @EnvironmentObject private var navigator: MediaNavigator
    let media: MediaItem
    private let label: Label

    init(media: MediaItem, @ViewBuilder label: () -> Label) {
        self.media = media
        self.label = label()
    }

    var body: some View {
        Button {
            navigator.detail = media
        } label: {
            label
        }
        .buttonStyle(FrostPressStyle(scale: 0.985))
        .contextMenu {
            MediaContextMenu(
                media: media,
                onOpen: { navigator.detail = media },
                onPlay: { navigator.player = media }
            )
        }
    }
}

// MARK: - On-Home section editor

/// The interactive Home editor's add tray. Reordering and removal happen
/// directly on the live Home rails (see `HomeView.sectionContainer`).
struct HomeSectionsEditor: View {
    @EnvironmentObject private var store: FrostPlayStore

    private var hiddenSections: [HomeSection] {
        HomeSection.allCases.filter { !store.settings.homeSections.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.draw.fill").foregroundStyle(frostOrange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Editing Home").font(.subheadline.bold()).foregroundStyle(.white)
                    Text("Long-press a rail's drag bar, then drop it on another rail to reorder. − removes it.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if hiddenSections.isEmpty {
                Text(store.settings.homeSections.isEmpty
                     ? "Every section is hidden. Add one back to rebuild Home."
                     : "Every available section is already on Home.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            if !hiddenSections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ADD A SECTION")
                        .font(.caption2.bold())
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.45))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(hiddenSections) { section in
                                Button {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                        store.addHomeSection(section)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus").font(.caption2.bold())
                                        Text(section.title).font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .frostGlass(cornerRadius: 13, opacity: 0.9)
                                }
                                .buttonStyle(FrostPressStyle())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostGlass(cornerRadius: 18)
    }
}

// MARK: - Loading placeholders

/// A shimmering placeholder block. It deliberately mirrors the shape of the
/// content it replaces, so the layout never jumps when the real data arrives.
struct FrostShimmer: View {
    @EnvironmentObject private var store: FrostPlayStore

    var cornerRadius: CGFloat = 14
    @State private var sweep: CGFloat = -1

    private var isAnimated: Bool {
        !store.settings.reduceMotion && store.settings.showLoadingPlaceholders
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [Color.clear, Color.white.opacity(0.16), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(proxy.size.width * 0.55, 1))
                    .offset(x: sweep * proxy.size.width * 1.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            }
            .onAppear {
                guard isAnimated, sweep < 0 else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    sweep = 1
                }
            }
    }
}

/// Placeholder for a horizontal rail: a heading bar plus a row of poster cards.
struct SkeletonRail: View {
    var cardCount = 4
    var cardWidth: CGFloat = 106
    var cardHeight: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FrostShimmer(cornerRadius: 6).frame(width: 132, height: 18)
            HStack(spacing: 12) {
                ForEach(0..<cardCount, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 7) {
                        FrostShimmer().frame(width: cardWidth, height: cardHeight)
                        FrostShimmer(cornerRadius: 5).frame(width: cardWidth * 0.78, height: 11)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Placeholder for a poster grid.
struct SkeletonGrid: View {
    var count = 6

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 18) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 7) {
                    FrostShimmer().frame(height: 220)
                    FrostShimmer(cornerRadius: 5).frame(height: 12)
                    FrostShimmer(cornerRadius: 5).frame(width: 96, height: 10)
                }
            }
        }
    }
}

/// Placeholder for the Home hero card.
struct SkeletonHero: View {
    var body: some View {
        FrostShimmer(cornerRadius: 22)
            .frame(maxWidth: .infinity)
            .frame(height: 255)
    }
}

/// Placeholder rows for a detail screen's episode list.
struct SkeletonEpisodeRows: View {
    var count = 5

    var body: some View {
        VStack(spacing: 9) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 11) {
                    FrostShimmer(cornerRadius: 12).frame(width: 48, height: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        FrostShimmer(cornerRadius: 5).frame(height: 11)
                        FrostShimmer(cornerRadius: 5).frame(width: 140, height: 9)
                    }
                    Spacer(minLength: 0)
                }
                .padding(11)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
    }
}

extension View {
    /// Cross-fades a placeholder into real content without bouncing the layout.
    func frostSwapTransition(reduceMotion: Bool) -> some View {
        transition(reduceMotion ? .identity : .opacity)
    }
}

// MARK: - Adding titles to a list

/// Adds titles to a list from everything FrostPlay already knows about: watch
/// history and the other lists. Titles found while browsing are added from any
/// title's long-press menu instead.
struct CollectionAddTitlesSheet: View {
    @EnvironmentObject private var store: FrostPlayStore
    let collectionID: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var collection: MediaCollection? { store.collection(id: collectionID) }

    /// De-duplicated candidates, minus the titles this list already holds.
    private var candidates: [MediaItem] {
        var seen = Set<String>()
        let known = store.history.map(\.media) + store.collections.flatMap(\.items)
        let unique = known.filter { seen.insert($0.id).inserted }
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return unique.filter { media in
            guard let collection, !collection.contains(media) else { return false }
            guard !clean.isEmpty else { return true }
            return media.title.lowercased().contains(clean)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.55))
                        TextField("Filter titles", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.45))
                            }
                        }
                    }
                    .padding(14)
                    .background(frostPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if candidates.isEmpty {
                        ContentUnavailableView(
                            "Nothing to add",
                            systemImage: "text.badge.plus",
                            description: Text("Titles you watch or save to other lists show up here. Any title can also be added from its long-press menu.")
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(candidates) { media in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                        store.add(media, to: collectionID)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Poster(url: media.posterURL, width: 50, height: 72)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(media.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                                            Text(media.kind.title + (media.year.map { " · \($0)" } ?? "")).font(.caption2).foregroundStyle(.white.opacity(0.55))
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(frostOrange)
                                    }
                                    .padding(11)
                                    .frostGlass(cornerRadius: 16, opacity: 0.85)
                                }
                                .buttonStyle(FrostPressStyle(scale: 0.985))
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .background(frostBackground.ignoresSafeArea())
            .navigationTitle("Add titles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationBackground(frostBackground)
        .preferredColorScheme(.dark)
    }
}
