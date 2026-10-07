import SwiftUI
import StoryCharacters

// MARK: - Localization

/// Tiny two-language helper: Russian when the device language is Russian, English otherwise.
/// Russian is the primary market, so every string carries both variants side by side.
enum L10n {
    static var isRussian: Bool {
        Locale.current.language.languageCode?.identifier == "ru"
    }

    /// "ru" or "en" — the language code handed to the StoryCharacters display-name helpers.
    static var languageCode: String { isRussian ? "ru" : "en" }

    static func t(_ ru: String, _ en: String) -> String { isRussian ? ru : en }

    // Tabs
    static var charactersTab: String { t("Персонажи", "Characters") }
    static var storiesTab: String { t("Сказки", "Stories") }

    // Showcase
    static var renderer: String { t("Рендерер", "Renderer") }
    static var rendererAuto: String { t("Авто", "Auto") }
    static var quality: String { t("Качество", "Quality") }
    static var emotions: String { t("Эмоции", "Emotions") }
    static var intensity: String { t("Сила эмоции", "Emotion intensity") }
    static var gestures: String { t("Жесты", "Gestures") }
    static var cancelGesture: String { t("Отменить жест", "Cancel gesture") }
    static var speech: String { t("Речь", "Speech") }
    static var speechPlaceholder: String { t("Что сказать?", "What should I say?") }
    static var say: String { t("Сказать", "Say") }
    static var stop: String { t("Стоп", "Stop") }
    static var speaking: String { t("Говорит", "Speaking") }
    static var silent: String { t("Молчит", "Quiet") }
    static var samplePhrases: String { t("Примеры фраз", "Sample phrases") }
    static var fps: String { t("Кадров в секунду", "Frames per second") }
    static var stageHint: String { t("Коснись — удивится, потяни — посмотрит", "Tap to poke, drag to look around") }
    static var selectCharacter: String { t("Выбор персонажа", "Character picker") }

    static func qualityName(_ quality: CanvasQuality) -> String {
        switch quality {
        case .balanced: return t("Баланс", "Balanced")
        case .high: return t("Высокое", "High")
        }
    }

    // Stories
    static var generate: String { t("Сочинить", "Generate") }
    static var generateTitle: String { t("Сочинить сказку", "Generate a tale") }
    static var yourStories: String { t("Ваши сказки", "Your stories") }
    static var library: String { t("Библиотека", "Library") }
    static var noStories: String { t("Сказок пока нет", "No stories yet") }
    static var noStoriesHint: String {
        t("Сочините первую сказку кнопкой с волшебной палочкой.", "Tap the magic wand to generate your first tale.")
    }
    static var hero: String { t("Герой", "Hero") }
    static var heroNamePlaceholder: String { t("Имя героя", "Hero name") }
    static var storySettings: String { t("Сказка", "Tale") }
    static var setting: String { t("Место действия", "Setting") }
    static var theme: String { t("Тема", "Theme") }
    static var narrator: String { t("Рассказчик", "Narrator") }
    static var language: String { t("Язык", "Language") }
    static var cancel: String { t("Отмена", "Cancel") }
    static var generating: String { t("Сочиняю…", "Writing…") }
    static var generationFailed: String {
        t("Не удалось сочинить сказку. Попробуйте ещё раз.", "Could not generate the story. Please try again.")
    }

    // Player
    static var play: String { t("Играть", "Play") }
    static var pause: String { t("Пауза", "Pause") }
    static var resume: String { t("Продолжить", "Resume") }
    static var replay: String { t("Ещё раз", "Play again") }
    static var nextSegment: String { t("Следующая часть", "Next part") }
    static var previousSegment: String { t("Предыдущая часть", "Previous part") }
    static var storyProgress: String { t("Прогресс сказки", "Story progress") }
    static var narratedBy: String { t("Рассказывает", "Narrated by") }

    static func segmentCounter(current: Int, total: Int) -> String {
        t("Часть \(current) из \(total)", "Part \(current) of \(total)")
    }

    static func playerState(_ state: StoryPlayer.State) -> String {
        switch state {
        case .idle: return t("Готово", "Ready")
        case .playing: return t("Играет", "Playing")
        case .paused: return t("Пауза", "Paused")
        case .finished: return t("Конец", "The end")
        }
    }
}

// MARK: - Theme

/// Colours, radii and gradients shared by every screen.
enum AppTheme {
    /// Warm golden accent (matches Assets.xcassets/AccentColor).
    static let accent = Color(.sRGB, red: 1.0, green: 0.824, blue: 0.416, opacity: 1.0)
    static let panelRadius: CGFloat = 24
    static let controlRadius: CGFloat = 14

    /// sRGB colour from a straight-alpha `SIMD4<Float>` (the palette / background format of StoryCharacters).
    static func color(_ c: SIMD4<Float>) -> Color {
        Color(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: Double(c.w))
    }

    /// Night-sky gradient suggested by the catalog for a character.
    static func backgroundGradient(for kind: CharacterKind) -> LinearGradient {
        let colors = CharacterCatalog.backgroundColors(for: kind)
        return LinearGradient(colors: [color(colors.top), color(colors.bottom)], startPoint: .top, endPoint: .bottom)
    }

    static func glowColor(for kind: CharacterKind) -> Color {
        color(CharacterCatalog.design(for: kind).palette.glow)
    }

    static func bodyGradient(for kind: CharacterKind) -> LinearGradient {
        let palette = CharacterCatalog.design(for: kind).palette
        return LinearGradient(colors: [color(palette.bodyTop), color(palette.bodyBottom)], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Liquid Glass helpers

/// Rounded Liquid Glass panel used for every grouped control block.
struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = AppTheme.panelRadius) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Tab visibility

private struct TabIsActiveKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    /// True while the enclosing tab is the visible one. Renderers combine it with `scenePhase` to pause.
    var tabIsActive: Bool {
        get { self[TabIsActiveKey.self] }
        set { self[TabIsActiveKey.self] = newValue }
    }
}

// MARK: - Background

/// Per-character night-sky gradient with a soft glow halo and twinkling stars.
struct NightSkyBackground: View {
    let kind: CharacterKind
    var isPaused: Bool = false

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(for: kind)
            RadialGradient(colors: [AppTheme.glowColor(for: kind).opacity(0.28), Color.clear],
                           center: UnitPoint(x: 0.5, y: 0.3),
                           startRadius: 0,
                           endRadius: 360)
            StarFieldView(isPaused: isPaused)
        }
        .animation(.easeInOut(duration: 0.6), value: kind)
        .accessibilityHidden(true)
    }
}

/// Lightweight twinkling star field: hashed positions, sine twinkle, 20 fps, nothing retained between frames.
struct StarFieldView: View {
    var isPaused: Bool = false
    var starCount: Int = 70

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: isPaused || reduceMotion)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                StarFieldView.draw(in: &context,
                                   size: size,
                                   time: timeline.date.timeIntervalSinceReferenceDate,
                                   count: starCount)
            }
        }
        .allowsHitTesting(false)
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval, count: Int) {
        guard size.width > 0, size.height > 0 else { return }
        var index = 0
        while index < count {
            let seedBase = Double(index)
            let s1 = hash(seedBase * 12.9898 + 0.1)
            let s2 = hash(seedBase * 78.233 + 1.7)
            let s3 = hash(seedBase * 37.719 + 4.2)
            let s4 = hash(seedBase * 93.989 + 8.1)

            let x = s1 * size.width
            let y = s2 * size.height
            let period = 1.6 + 2.8 * s3
            let phase = s4 * 2.0 * Double.pi
            let twinkle = 0.5 + 0.5 * sin(time * (2.0 * Double.pi / period) + phase)
            let radius = 0.6 + 1.2 * s4 + 0.7 * twinkle
            let alpha = 0.2 + 0.7 * twinkle * (0.4 + 0.6 * s3)

            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2.0, height: radius * 2.0)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))
            index += 1
        }
    }

    /// Deterministic pseudo-random value in 0..<1.
    private static func hash(_ v: Double) -> Double {
        let s = sin(v) * 43758.5453
        return s - floor(s)
    }
}
