import SwiftUI
import StoryCharacters

/// Character showcase: stage → carousel → renderer / emotion / gesture / speech controls.
///
/// One `CharacterRig` drives the stage. It is created lazily on first appearance (re-initialising this view,
/// which SwiftUI does on every parent update, never allocates a throwaway rig) and replaced in the same
/// transaction as the selection, so the header, background and stage always show the same character.
/// The replacement keeps the chosen emotion and intensity.
///
/// Layout: stage above the controls; in compact height (iPhone landscape) stage and controls sit side by
/// side. On wide screens the controls column is capped at 640 pt.
@MainActor
struct ShowcaseView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tabIsActive) private var tabIsActive
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var selectedKind: CharacterKind = .lumi
    @State private var rig: CharacterRig?
    @State private var renderer: CharacterRenderer = .automatic
    @State private var quality: CanvasQuality = .high
    @State private var intensity: Float = 1
    @State private var speechText = ""

    /// Renderers pause while the tab is hidden or the scene is inactive / in the background.
    private var isPaused: Bool { !(tabIsActive && scenePhase == .active) }

    /// What `.automatic` resolves to on this device, so the Canvas quality control appears only when relevant.
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
            if let rig {
                content(rig: rig, size: proxy.size)
            }
        }
        .background {
            NightSkyBackground(kind: selectedKind, isPaused: isPaused)
                .ignoresSafeArea()
        }
        .onAppear {
            if rig == nil {
                rig = CharacterRig(kind: selectedKind)
            }
        }
        .onChange(of: tabIsActive) { _, active in
            // Leaving the tab silences the showcase so it never talks over the story narrator.
            if !active {
                rig?.stopSpeaking()
                rig?.clearLookTarget()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                rig?.stopSpeaking()
            }
        }
    }

    /// `AnyLayout` keeps the stage's identity when the size class flips, so the renderer is not rebuilt on rotation.
    @ViewBuilder
    private func content(rig: CharacterRig, size: CGSize) -> some View {
        let isCompactHeight = verticalSizeClass == .compact
        let layout = isCompactHeight
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
        layout {
            stage(rig: rig)
                .frame(width: isCompactHeight ? size.width * 0.45 : nil,
                       height: isCompactHeight ? nil : stageHeight(for: size))
            controls(rig: rig)
        }
    }

    private func controls(rig: CharacterRig) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 14) {
                CharacterCarousel(selection: selectedKind,
                                  isPaused: isPaused,
                                  onSelect: { kind in
                                      select(kind)
                                  })
                RendererControl(renderer: $renderer,
                                quality: $quality,
                                showsQuality: effectiveRenderer == .swiftUI)
                EmotionGrid(rig: rig, intensity: $intensity)
                GestureBar(rig: rig)
                SpeechPanel(rig: rig, text: $speechText)
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func stageHeight(for size: CGSize) -> CGFloat {
        min(max(size.height * 0.40, 230), 440)
    }

    /// Switches character: silences the old rig and builds the new one with the same emotion and intensity,
    /// then publishes the selection. Rig and selection change together, so no view ever pairs the new name
    /// with the old character.
    private func select(_ kind: CharacterKind) {
        guard kind != selectedKind || rig == nil else { return }
        let carriedEmotion = rig?.emotion ?? .neutral
        rig?.stopSpeaking()
        rig?.clearLookTarget()
        let newRig = CharacterRig(kind: kind)
        newRig.set(emotion: carriedEmotion, intensity: intensity)
        rig = newRig
        selectedKind = kind
    }

    // MARK: Stage

    private func stage(rig: CharacterRig) -> some View {
        ZStack(alignment: .top) {
            StageCharacter(rig: rig,
                           renderer: effectiveRenderer == .swiftUI ? .swiftUI : renderer,
                           quality: quality,
                           isPaused: isPaused)
                .id(ObjectIdentifier(rig))

            StageHeader(rig: rig,
                        rendererName: L10n.rendererName(effectiveRenderer),
                        isPaused: isPaused)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .allowsHitTesting(false)
        }
    }
}

/// The big interactive character. Tap → `poke()`, drag → `lookAt(viewPoint:in:)`, release → `clearLookTarget()`.
/// `.automatic` / `.metal` go through the `CharacterView` facade; the SwiftUI renderer is used directly
/// so the Canvas quality setting can be applied.
struct StageCharacter: View {
    let rig: CharacterRig
    let renderer: CharacterRenderer
    let quality: CanvasQuality
    let isPaused: Bool

    var body: some View {
        GeometryReader { proxy in
            character
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(interaction(in: proxy.size))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityHint(L10n.stageHint)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    rig.poke()
                }
        }
    }

    @ViewBuilder
    private var character: some View {
        if renderer == .swiftUI {
            CharacterCanvasView(rig: rig, quality: quality, isPaused: isPaused)
        } else {
            CharacterView(rig: rig, renderer: renderer, isPaused: isPaused)
        }
    }

    private var accessibilityText: String {
        rig.design.kind.displayName(languageCode: L10n.languageCode)
            + ", "
            + rig.emotion.displayName(languageCode: L10n.languageCode)
    }

    /// One gesture handles both interactions: a drag steers the gaze, a tap (no movement) pokes.
    private func interaction(in size: CGSize) -> some SwiftUI.Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if StageCharacter.isDrag(value.translation) {
                    rig.lookAt(viewPoint: value.location, in: size)
                }
            }
            .onEnded { value in
                if !StageCharacter.isDrag(value.translation) {
                    rig.poke()
                }
                rig.clearLookTarget()
            }
    }

    private static func isDrag(_ translation: CGSize) -> Bool {
        translation.width * translation.width + translation.height * translation.height > 64
    }
}

/// Name, tagline, current emotion / gesture and the FPS badge over the stage. A separate view so that
/// emotion and gesture changes re-evaluate only this header, not the whole showcase. Everything shown is
/// taken from the rig, so the header can never describe a different character than the stage draws.
struct StageHeader: View {
    let rig: CharacterRig
    let rendererName: String
    let isPaused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rig.design.kind.displayName(languageCode: L10n.languageCode))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(rig.design.localizedTagline(languageCode: L10n.languageCode))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Image(systemName: rig.emotion.symbolName)
                        .accessibilityHidden(true)
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
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            FPSBadge(isPaused: isPaused, rendererName: rendererName)
        }
    }
}
