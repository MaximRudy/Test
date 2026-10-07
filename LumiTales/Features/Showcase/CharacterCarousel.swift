import SwiftUI
import StoryCharacters

/// Horizontal character picker: 8 cards, each with a live mini character. A card animates only while it is
/// inside the carousel's visible area and the carousel itself is on screen in the controls list; it pauses
/// as soon as either scrolls out of view (or when the whole showcase is paused).
///
/// Selection is reported through `onSelect` rather than a binding so the owner can swap its rig in the
/// same transaction as the selection change.
struct CharacterCarousel: View {
    let selection: CharacterKind
    var isPaused: Bool
    var onSelect: (CharacterKind) -> Void

    /// False while the carousel is scrolled out of the enclosing vertical controls list. It starts true
    /// because the carousel is the first row of that list and is on screen when the showcase appears.
    @State private var isOnScreen = true

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(CharacterKind.presentationOrder) { kind in
                        Button {
                            withAnimation(.snappy) {
                                onSelect(kind)
                            }
                        } label: {
                            CharacterCard(kind: kind,
                                          isSelected: kind == selection,
                                          isPaused: isPaused || !isOnScreen)
                        }
                        .buttonStyle(.plain)
                        .id(kind)
                        .accessibilityLabel(kind.displayName(languageCode: L10n.languageCode))
                        .accessibilityAddTraits(kind == selection ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, newValue in
                withAnimation(.snappy) {
                    scroller.scrollTo(newValue, anchor: .center)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.selectCharacter)
            // Attached outside the horizontal scroll view, so `.scrollView` is the vertical controls list.
            .onGeometryChange(for: Bool.self) { proxy in
                CarouselVisibility.fraction(of: proxy.frame(in: .scrollView),
                                          viewport: proxy.bounds(of: .scrollView)?.size,
                                          axis: .vertical) > 0
            } action: { visible in
                isOnScreen = visible
            }
        }
    }
}

/// One carousel card. The mini rig is created lazily on first appearance and kept for the card's lifetime.
/// The mini uses the `.balanced` Canvas quality (radial-gradient glow, no blur layer) so several live cards
/// stay cheap; it runs only while at least 20 % of the card is inside the carousel's visible area.
struct CharacterCard: View {
    let kind: CharacterKind
    let isSelected: Bool
    /// Paused from outside: tab hidden, scene not active or carousel scrolled out of the controls list.
    let isPaused: Bool

    @State private var rig: CharacterRig?
    /// True while at least 20 % of the card is inside the carousel's visible area. Driven only by the
    /// geometry callback below, which also reports the initial value, so a card that the lazy stack builds
    /// just past the visible edge starts paused. The `true` default only covers the moment before that
    /// first report.
    @State private var isVisible = true

    @ScaledMetric(relativeTo: .caption) private var scaledCardWidth: CGFloat = 116

    var body: some View {
        let cardWidth = min(max(scaledCardWidth, 116), 176)
        let miniSize = cardWidth - 24
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(AppTheme.glowColor(for: kind).opacity(isSelected ? 0.35 : 0.15))
                    .blur(radius: 10)
                if let rig {
                    CharacterCanvasView(rig: rig, quality: .balanced, isPaused: isPaused || !isVisible)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: miniSize, height: miniSize)

            Text(kind.displayName(languageCode: L10n.languageCode))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(width: cardWidth)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isSelected ? AppTheme.accent.opacity(0.18) : Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isSelected ? AppTheme.accent : Color.white.opacity(0.12),
                              lineWidth: isSelected ? 2 : 1)
        }
        .scaleEffect(isSelected ? 1.0 : 0.94)
        .animation(.snappy, value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear {
            if rig == nil {
                rig = CharacterRig(kind: kind)
            }
        }
        // `.scrollView` here is the carousel's horizontal scroll view (the innermost one containing the card).
        .onGeometryChange(for: Bool.self) { proxy in
            CarouselVisibility.fraction(of: proxy.frame(in: .scrollView),
                                      viewport: proxy.bounds(of: .scrollView)?.size,
                                      axis: .horizontal) >= 0.2
        } action: { visible in
            isVisible = visible
        }
    }
}

/// Pure geometry helper for the carousel's visibility checks (nonisolated, no SwiftUI state).
enum CarouselVisibility {
    /// Fraction (0…1) of `frame` along `axis` that lies inside a scroll view's visible area.
    /// `frame` is in the scroll view's coordinate space, whose origin is the top-leading corner of the
    /// visible area; `viewport` is the size of that area, or nil when there is no enclosing scroll view
    /// (then the view counts as fully visible).
    static func fraction(of frame: CGRect, viewport: CGSize?, axis: Axis) -> CGFloat {
        guard let viewport else { return 1 }
        let overlap = frame.intersection(CGRect(origin: .zero, size: viewport))
        if overlap.isNull {
            return 0
        }
        if axis == .horizontal {
            return frame.width > 0 ? overlap.width / frame.width : 0
        }
        return frame.height > 0 ? overlap.height / frame.height : 0
    }
}
