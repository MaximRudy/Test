import SwiftUI
import StoryCharacters

// MARK: - Renderer

/// Segmented renderer selector (Auto / Metal / SwiftUI) plus the Canvas quality toggle when the
/// SwiftUI renderer is the one actually drawing.
struct RendererControl: View {
    @Binding var renderer: CharacterRenderer
    @Binding var quality: CanvasQuality
    var showsQuality: Bool

    var body: some View {
        VStack(spacing: 10) {
            Picker(L10n.renderer, selection: $renderer) {
                Text(L10n.rendererAuto).tag(CharacterRenderer.automatic)
                if MetalAvailability.isSupported {
                    Text(verbatim: "Metal").tag(CharacterRenderer.metal)
                }
                Text(verbatim: "SwiftUI").tag(CharacterRenderer.swiftUI)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(L10n.renderer)

            if showsQuality {
                HStack(spacing: 10) {
                    Text(L10n.quality)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker(L10n.quality, selection: $quality) {
                        ForEach(CanvasQuality.allCases, id: \.self) { item in
                            Text(L10n.qualityName(item)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(L10n.quality)
                }
            }
        }
        .padding(12)
        .contentPanel()
        .animation(.snappy, value: showsQuality)
    }
}

// MARK: - Emotions

/// 14 emotion buttons plus an intensity slider. Selection mirrors `rig.emotion`.
/// The column count drops as Dynamic Type grows so long names (e.g. "Задумчивость") stay readable
/// within the captions' 0.7 minimum scale instead of truncating.
struct EmotionGrid: View {
    let rig: CharacterRig
    @Binding var intensity: Float

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columnCount: Int {
        if dynamicTypeSize >= .accessibility1 {
            return 2
        }
        if dynamicTypeSize >= .xxLarge {
            return 3
        }
        return 4
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.emotions, systemImage: "theatermasks")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Text(rig.emotion.displayName(languageCode: L10n.languageCode))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Emotion.allCases) { emotion in
                    EmotionButton(emotion: emotion, isSelected: rig.emotion == emotion) {
                        rig.set(emotion: emotion, intensity: intensity)
                    }
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "dial.low")
                    .foregroundStyle(.secondary)
                Slider(value: $intensity, in: 0.2...1)
                    .tint(AppTheme.accent)
                    .accessibilityLabel(L10n.intensity)
                Image(systemName: "dial.high")
                    .foregroundStyle(.secondary)
            }
            .onChange(of: intensity) { _, value in
                rig.set(emotion: rig.emotion, intensity: value)
            }
        }
        .padding(12)
        .contentPanel()
    }
}

struct EmotionButton: View {
    let emotion: Emotion
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: emotion.symbolName)
                    .font(.title3)
                    .frame(minHeight: 24)
                Text(emotion.displayName(languageCode: L10n.languageCode))
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                    .fill(isSelected ? AppTheme.accent.opacity(0.28) : Color.white.opacity(0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.accent : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AppTheme.accent : Color.white)
        .accessibilityLabel(emotion.displayName(languageCode: L10n.languageCode))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Gestures

/// Horizontal bar with the 14 one-shot gestures; the running one is highlighted and can be cancelled.
struct GestureBar: View {
    let rig: CharacterRig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.gestures, systemImage: "figure.wave")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                if rig.activeGesture != nil {
                    Button {
                        rig.cancelGesture()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.cancelGesture)
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(StoryCharacters.Gesture.allCases) { gesture in
                        GestureChip(gesture: gesture, isActive: rig.activeGesture == gesture) {
                            rig.play(gesture)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .contentPanel()
    }

    /// SF Symbol for each gesture (the package does not define one).
    static func symbolName(for gesture: StoryCharacters.Gesture) -> String {
        switch gesture {
        case .nod: return "hand.thumbsup"
        case .shake: return "hand.raised"
        case .bounce: return "arrow.up.circle"
        case .wave: return "hand.wave"
        case .think: return "lightbulb"
        case .surprisePop: return "exclamationmark.circle"
        case .shy: return "face.dashed"
        case .celebrate: return "party.popper"
        case .wink: return "eye"
        case .yawn: return "mouth"
        case .peek: return "eyes"
        case .giggle: return "face.smiling"
        case .sleep: return "zzz"
        case .wakeUp: return "sunrise"
        }
    }
}

struct GestureChip: View {
    let gesture: StoryCharacters.Gesture
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(gesture.displayName(languageCode: L10n.languageCode),
                  systemImage: GestureBar.symbolName(for: gesture))
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(isActive ? AppTheme.accent.opacity(0.3) : Color.white.opacity(0.08))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(isActive ? AppTheme.accent : Color.clear, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? AppTheme.accent : Color.white)
        .accessibilityLabel(gesture.displayName(languageCode: L10n.languageCode))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
