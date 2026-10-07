import SwiftUI
import StoryCharacters

/// Character showcase: carousel → stage → renderer / emotion / gesture / speech controls.
/// One `CharacterRig` drives the stage; it is recreated whenever the selected character changes.
@MainActor
struct ShowcaseView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tabIsActive) private var tabIsActive

    @State private var selectedKind: CharacterKind = .lumi
    @State private var rig = CharacterRig(kind: .lumi)
    @State private var renderer: CharacterRenderer = .automatic
    @State private var quality: CanvasQuality = .high
    @State private var intensity: Float = 1
    @State private var speechText = ""

    /// Renderers pause while the tab is hidden or the scene is inactive / in the background.
    private var isPaused: Bool { !(tabIsActive && scenePhase == .active) }

    /// What `.automatic` resolves to on this device, so the Canvas quality toggle appears only when relevant.
    private var effectiveRenderer: CharacterRenderer {
        switch renderer {
        case .automatic:
            return MetalAvailability.isSupported ? .metal : .swiftUI
        case .metal, .swiftUI:
            return renderer
        }
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                stage
                    .frame(height: stageHeight(for: proxy.size))

                ScrollView(.vertical) {
                    VStack(spacing: 14) {
                        CharacterCarousel(selection: $selectedKind, isPaused: isPaused)
                        RendererControl(renderer: $renderer,
                                        quality: $quality,
                                        showsQuality: effectiveRenderer == .swiftUI)
                        EmotionGrid(rig: rig, intensity: $intensity)
                        GestureBar(rig: rig)
                        SpeechPanel(rig: rig, text: $speechText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background {
            NightSkyBackground(kind: selectedKind, isPaused: isPaused)
                .ignoresSafeArea()
        }
        .onChange(of: selectedKind) { _, newKind in
            rig.stopSpeaking()
            rig = CharacterRig(kind: newKind)
        }
    }

    private func stageHeight(for size: CGSize) -> CGFloat {
        min(max(size.height * 0.40, 230), 440)
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                stageCharacter
                    .id(ObjectIdentifier(rig))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .gesture(stageGesture(in: proxy.size))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(stageAccessibilityLabel)
                    .accessibilityHint(L10n.stageHint)
                    .accessibilityAddTraits(.isButton)

                stageHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var stageCharacter: some View {
        if effectiveRenderer == .swiftUI {
            CharacterCanvasView(rig: rig, quality: quality, isPaused: isPaused)
        } else {
            CharacterView(rig: rig, renderer: .metal, isPaused: isPaused)
        }
    }

    private var stageAccessibilityLabel: String {
        selectedKind.displayName(languageCode: L10n.languageCode)
            + ", "
            + rig.emotion.displayName(languageCode: L10n.languageCode)
    }

    private var stageHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedKind.displayName(languageCode: L10n.languageCode))
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(rig.design.localizedTagline(languageCode: L10n.languageCode))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Image(systemName: rig.emotion.symbolName)
                    Text(rig.emotion.displayName(languageCode: L10n.languageCode))
                    if let gesture = rig.activeGesture {
                        Text(verbatim: "· " + gesture.displayName(languageCode: L10n.languageCode))
                    }
                }
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                Text(L10n.stageHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            FPSBadge(isPaused: isPaused)
        }
    }

    /// One gesture handles both interactions: a drag steers the gaze, a tap (no movement) pokes.
    private func stageGesture(in size: CGSize) -> some SwiftUI.Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if ShowcaseView.isDrag(value.translation) {
                    rig.lookAt(viewPoint: value.location, in: size)
                }
            }
            .onEnded { value in
                if !ShowcaseView.isDrag(value.translation) {
                    rig.poke()
                }
                rig.clearLookTarget()
            }
    }

    private static func isDrag(_ translation: CGSize) -> Bool {
        translation.width * translation.width + translation.height * translation.height > 64
    }
}
