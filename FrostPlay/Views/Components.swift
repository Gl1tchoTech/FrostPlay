import SwiftUI

// File-private copy of the shared accent so this file can stand on its own.
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
        Button { store.toggleLibrary(media) } label: {
            Label(
                store.isInLibrary(media) ? "Remove from My List" : "Add to My List",
                systemImage: store.isInLibrary(media) ? "bookmark.slash" : "bookmark"
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

/// One reorderable/removable Home section, shown while Home is in edit mode.
struct EditableHomeSectionCard: View {
    @EnvironmentObject private var store: FrostPlayStore
    let section: HomeSection
    @State private var isTargeted = false

    private var index: Int? { store.settings.homeSections.firstIndex(of: section) }
    private var canMoveUp: Bool { (index ?? 0) > 0 }
    private var canMoveDown: Bool {
        guard let position = index else { return false }
        return position < store.settings.homeSections.count - 1
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbolName)
                .font(.subheadline)
                .foregroundStyle(frostOrange)
                .frame(width: 30, height: 30)
                .background(Circle().fill(frostOrange.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.headline).foregroundStyle(.white)
                Text(section.subtitle).font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { store.nudgeHomeSection(section, by: -1) }
                } label: {
                    Image(systemName: "chevron.up").font(.caption2.bold())
                        .foregroundStyle(.white.opacity(canMoveUp ? 0.7 : 0.18))
                }
                .disabled(!canMoveUp)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { store.nudgeHomeSection(section, by: 1) }
                } label: {
                    Image(systemName: "chevron.down").font(.caption2.bold())
                        .foregroundStyle(.white.opacity(canMoveDown ? 0.7 : 0.18))
                }
                .disabled(!canMoveDown)
            }
            .buttonStyle(FrostPressStyle())
            Image(systemName: "line.3.horizontal")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.trailing, 2)
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    store.removeHomeSection(section)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.red.opacity(0.85))
            }
            .buttonStyle(FrostPressStyle())
            .accessibilityLabel("Remove \(section.title)")
        }
        .padding(13)
        .frostGlass(cornerRadius: 16, highlighted: isTargeted, opacity: 0.9)
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
        .dropDestination(for: String.self) { payloads, _ in
            guard let raw = payloads.first, let dragged = HomeSection(rawValue: raw) else { return false }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                store.moveHomeSection(dragged, before: section)
            }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .accessibilityHint("Drag to reorder this section")
    }
}

/// The interactive Home editor: reorder by dragging, remove with −, and add any
/// hidden section back. Lives on the Home screen itself.
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
                    Text("Long-press a section and drag it to reorder, or use the arrows. Tap − to remove it.")
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
