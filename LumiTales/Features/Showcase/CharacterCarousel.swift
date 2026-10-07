import SwiftUI
import StoryCharacters

/// Horizontal character picker: 8 cards, each with a live mini character. A card animates while it is on
/// screen and pauses as soon as it scrolls out of view (or when the whole showcase is paused).
///
/// Selection is reported through `onSelect` rather than a binding so the owner can swap its rig in the
/// same transaction as the selection change.
struct CharacterCarousel: View {
    let selection: CharacterKind
    var isPaused: Bool
    var onSelect: (CharacterKind) -> Void

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
                                          isPaused: isPaused)
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
        }
    }
}

/// One carousel card. The mini rig is created lazily on first appearance and kept for the card's lifetime.
/// The mini uses the `.balanced` Canvas quality (radial-gradient glow, no blur layer) so several live cards
/// stay cheap; it runs only while at least 20 % of the card is visible.
struct CharacterCard: View {
    let kind: CharacterKind
    let isSelected: Bool
    /// Paused from outside: tab hidden or scene not active.
    let isPaused: Bool

    @State private var rig: CharacterRig?
    /// True while the card is inside the carousel's visible area.
    @State private var isVisible = false

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
            isVisible = true
            if rig == nil {
                rig = CharacterRig(kind: kind)
            }
        }
        .onDisappear {
            isVisible = false
        }
        .onScrollVisibilityChange(threshold: 0.2) { visible in
            isVisible = visible
        }
    }
}
