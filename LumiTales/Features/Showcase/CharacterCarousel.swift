import SwiftUI
import StoryCharacters

/// Horizontal character picker. Every card owns a small live `CharacterView`; only the selected
/// card animates, the others stay paused on their first frame.
struct CharacterCarousel: View {
    @Binding var selection: CharacterKind
    var isPaused: Bool

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(CharacterKind.presentationOrder) { kind in
                        CharacterCard(kind: kind,
                                      isSelected: kind == selection,
                                      isPaused: isPaused || kind != selection)
                            .id(kind)
                            .onTapGesture {
                                withAnimation(.snappy) {
                                    selection = kind
                                }
                            }
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
            .accessibilityLabel(L10n.selectCharacter)
        }
    }
}

/// One carousel card. The mini rig is created lazily on first appearance and kept for the card's lifetime.
struct CharacterCard: View {
    let kind: CharacterKind
    let isSelected: Bool
    let isPaused: Bool

    @State private var rig: CharacterRig?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(AppTheme.glowColor(for: kind).opacity(isSelected ? 0.35 : 0.15))
                    .blur(radius: 10)
                if let rig {
                    CharacterView(rig: rig, renderer: .swiftUI, isPaused: isPaused)
                }
            }
            .frame(width: 92, height: 92)

            Text(kind.displayName(languageCode: L10n.languageCode))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(width: 116)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.displayName(languageCode: L10n.languageCode))
        .accessibilityAddTraits(cardTraits)
    }

    private var cardTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = .isButton
        if isSelected {
            traits.insert(.isSelected)
        }
        return traits
    }
}
