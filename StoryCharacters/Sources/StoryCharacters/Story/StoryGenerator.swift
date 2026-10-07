import Foundation

// MARK: - StoryPrompt

/// What the user asks a generator for.
public struct StoryPrompt: Sendable, Equatable {
    /// Name of the hero of the tale (empty = a default hero for the language).
    public var heroName: String
    /// Where the tale happens, as a noun phrase: "волшебный лес" / "an enchanted forest" (empty = default).
    public var setting: String
    /// What the moral is about, as a noun phrase: "дружба" / "friendship" / "a dream" (empty = default).
    public var theme: String
    /// "ru" or "en" (any "ru-…" code selects Russian, everything else English templates).
    public var languageCode: String
    /// The character that will narrate the result.
    public var narrator: CharacterKind

    public init(heroName: String = "", setting: String = "", theme: String = "",
                languageCode: String = "ru", narrator: CharacterKind = .lumi) {
        self.heroName = heroName
        self.setting = setting
        self.theme = theme
        self.languageCode = languageCode
        self.narrator = narrator
    }
}

// MARK: - StoryGenerating

/// Anything that can turn a prompt into a story (offline templates, a remote model, …).
public protocol StoryGenerating: Sendable {
    func generateStory(_ prompt: StoryPrompt) async throws -> Story
}

// MARK: - TemplateStoryGenerator

/// Offline generator: assembles an 8-sentence bedtime tale (within the contract's 6–8) from Russian or English templates,
/// substituting the hero, the setting and the theme, with varied emotion/gesture tags and a gentle moral.
///
/// The seed is derived from the prompt plus a `variation`. `makeStory` is deterministic (same prompt and
/// variation → same story), so previews and tests are stable. `generateStory` on a generator created with
/// the default `variation` of 0 picks a fresh random variation for every call, so pressing "Generate"
/// again with the same prompt tells a different tale; pass a non-zero `variation` to make it repeatable.
public struct TemplateStoryGenerator: StoryGenerating {
    /// Extra seed mixed into the prompt hash. 0 = a random variation per `generateStory` call.
    public var variation: UInt64

    public init(variation: UInt64 = 0) {
        self.variation = variation
    }

    public func generateStory(_ prompt: StoryPrompt) async throws -> Story {
        try Task.checkCancellation()
        let chosen = variation != 0 ? variation : UInt64.random(in: 1...UInt64.max)
        return makeStory(prompt, variation: chosen)
    }

    /// Synchronous, deterministic variant for previews and tests (uses the generator's `variation`).
    public func makeStory(_ prompt: StoryPrompt) -> Story {
        makeStory(prompt, variation: variation)
    }

    /// Synchronous, deterministic: the same prompt and variation always yield the same story
    /// (variation 0 is the prompt's canonical tale).
    public func makeStory(_ prompt: StoryPrompt, variation: UInt64) -> Story {
        let isRussian = StoryLibrary.baseLanguage(prompt.languageCode) == "ru"
        let pack = isRussian ? StoryTemplates.russian : StoryTemplates.english
        let languageCode = isRussian ? "ru" : "en"

        let hero = StoryTemplates.sanitize(prompt.heroName, fallback: pack.defaultHero, limit: 40)
        let setting = StoryTemplates.sanitize(prompt.setting, fallback: pack.defaultSetting, limit: 60)
        let theme = StoryTemplates.sanitize(prompt.theme, fallback: pack.defaultTheme, limit: 40)
        let narratorName = isRussian ? prompt.narrator.russianName : prompt.narrator.englishName

        var seed = StoryTemplates.fnv1a("\(hero)|\(setting)|\(theme)|\(languageCode)|\(prompt.narrator.rawValue)")
        if variation != 0 {
            // Mix with an odd multiplier so neighbouring variations land on unrelated seeds.
            seed ^= variation &* 0x9E37_79B9_7F4A_7C15
        }
        var rng = StorySeededGenerator(seed: seed)

        // opening + trait + 2-sentence encounter + idea + resolution + moral + goodnight
        // = 8 sentences (CONTRACT §4.6: 6–8), at least 4 gestures.
        var lines: [String] = []
        lines.reserveCapacity(8)
        lines.append(rng.pick(pack.openings))
        lines.append(rng.pick(pack.traits))
        lines.append(contentsOf: rng.pick(pack.encounters))
        lines.append(rng.pick(pack.ideas))
        lines.append(rng.pick(pack.resolutions))
        lines.append(rng.pick(pack.morals))
        lines.append(rng.pick(pack.goodnights))

        let fields = StoryTemplates.Fields(hero: hero, setting: setting, theme: theme, narrator: narratorName)
        let tagged = lines.map { StoryTemplates.fill($0, with: fields) }.joined(separator: "\n")
        let title = StoryTemplates.fill(pack.titleTemplate, with: fields)
        let summary = StoryTemplates.fill(pack.summaryTemplate, with: fields)

        return Story(id: "generated-" + String(seed, radix: 16),
                     title: title,
                     languageCode: languageCode,
                     narrator: prompt.narrator,
                     summary: summary,
                     ageRange: "3–6",
                     tagged: tagged)
    }
}

// MARK: - StorySeededGenerator

/// SplitMix64 — tiny, deterministic, platform-independent.
struct StorySeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform element pick. The array must not be empty.
    mutating func pick<T>(_ array: [T]) -> T {
        precondition(!array.isEmpty, "pick from an empty array")
        let index = Int(next() % UInt64(array.count))
        return array[index]
    }
}

// MARK: - StoryTemplates

/// Template text for the offline generator.
///
/// Placeholders: `{hero}`, `{Hero}` (first letter capitalized), `{setting}`, `{Setting}` (first letter
/// capitalized), `{theme}`, `{Theme}` (title case, small words lowercase), `{narrator}`.
///
/// Rules that keep every substitution grammatical:
/// * every template is exactly one sentence (one terminator group at the end), so the parser yields one
///   segment per line; user input is stripped of terminators and brackets by `sanitize`;
/// * Russian templates use the present tense (verbs then do not depend on the hero's gender), use the hero
///   only in the nominative case, and use the setting only as a quoted name («{Setting}»), so any
///   noun phrase in the nominative ("снежные горы", "лунная поляна") fits;
/// * English templates use the setting as a standalone noun phrase ("an enchanted forest", "the starry sky")
///   and the theme as one too ("friendship", "a dream").
/// Every encounter arc carries two gestures and every idea and goodnight one, so a story has ≥ 4 gestures.
enum StoryTemplates {
    struct Fields {
        var hero: String
        var setting: String
        var theme: String
        var narrator: String
    }

    struct Pack {
        var defaultHero: String
        var defaultSetting: String
        var defaultTheme: String
        var titleTemplate: String
        var summaryTemplate: String
        var openings: [String]
        var traits: [String]
        /// Two-sentence mini arcs: the incident with the newcomer's trouble, then the promise to help.
        var encounters: [[String]]
        var ideas: [String]
        var resolutions: [String]
        var morals: [String]
        var goodnights: [String]
    }

    static let russian = Pack(
        defaultHero: "Звёздочка",
        defaultSetting: "Сонный лес",
        defaultTheme: "дружба",
        titleTemplate: "{Hero} и тайна слова «{theme}»",
        summaryTemplate: "Спокойная сказка на ночь: {hero} помогает новому другу и узнаёт, что значит {theme}.",
        openings: [
            "[happy][gesture:wave] Далеко-далеко, в краю под названием «{Setting}», живёт {hero}.",
            "[neutral] Есть на свете тихое и удивительное место — край «{Setting}», и именно там живёт {hero}.",
            "[happy][gesture:bounce] Каждый вечер, когда зажигаются первые звёзды, в краю «{Setting}» готовится ко сну {hero}.",
            "[listening] Послушай, мой друг: в краю «{Setting}», где даже ветер говорит шёпотом, живёт {hero}.",
        ],
        traits: [
            "[curious] Больше всего на свете {hero} любит смотреть на звёзды и думать о том, что же такое {theme}.",
            "[thinking][gesture:think] Один вопрос никак не даёт покоя: что же на самом деле значит слово «{theme}»?",
            "[listening] {Hero} умеет слушать ветер и тихие шаги ночи, но слово «{theme}» пока остаётся загадкой.",
            "[shy][gesture:shy] {Hero} немного стесняется, но очень хочет узнать, что же такое {theme}.",
        ],
        encounters: [
            [
                "[surprised][gesture:surprisePop] Однажды вечером с неба спускается маленький светлячок и тихо шепчет, что заблудился, а его огонёк становится всё слабее.",
                "[curious][gesture:nod] {Hero} кивает и обещает помочь ему найти родную полянку, чего бы это ни стоило.",
            ],
            [
                "[curious][gesture:peek] Однажды в кустах что-то тихонько шуршит, а там дрожит крошечный ёжик, который потерял свою тропинку и боится, что не найдёт дорогу домой.",
                "[happy][gesture:nod] {Hero} садится рядом и тихо говорит, что вместе они обязательно всё придумают.",
            ],
            [
                "[sad][gesture:shake] Однажды утром на крыльцо опускается маленькое пушистое облачко: оно отстало от своей облачной семьи и от грусти накрапывает тихим дождиком.",
                "[listening][gesture:nod] {Hero} слушает очень внимательно и решает, что никого нельзя оставлять в беде.",
            ],
            [
                "[scared][gesture:surprisePop] Однажды ночью в траву с тихим звоном падает маленькая звёздочка, и её лучики дрожат, ведь она не может забраться обратно на небо.",
                "[happy][gesture:wave] {Hero} машет ей и ласково говорит: «Не бойся, я помогу тебе вернуться домой».",
            ],
        ],
        ideas: [
            "[excited][gesture:bounce] И вдруг {hero} вспоминает: звёзды видят всё сверху и наверняка знают дорогу!",
            "[happy][gesture:celebrate] И тут приходит идея — позвать на помощь всех друзей, ведь вместе любая дорога короче!",
            "[excited][gesture:wakeUp] Вдруг {hero} замечает, что тёплый свет доброго сердца освещает тропинку лучше любого фонарика!",
            "[curious][gesture:think] И тут {hero} придумывает: можно спеть тихую песенку, и эхо подскажет верный путь!",
        ],
        resolutions: [
            "[happy][gesture:celebrate] Шаг за шагом, огонёк за огоньком, новый друг возвращается домой, а все вокруг радуются.",
            "[love] Дома нового друга давно ждут, и все вокруг говорят спасибо за доброе сердце.",
            "[laughing][gesture:giggle] Новый друг так радуется, что хихикает, и {hero} хихикает вместе с ним.",
            "[love][gesture:wink] Наконец новый друг оказывается дома и на прощание весело подмигивает.",
        ],
        morals: [
            "[pause:0.8][love] Теперь {hero} знает: {theme} живёт в каждом сердце и просыпается, когда кому-то нужна помощь.",
            "[pause:0.8][happy][gesture:nod] Вот так и бывает: {theme} начинается с маленького доброго шага.",
            "[pause:0.8][love] Запомни, малыш: {theme} делает мир светлее, а сердце — теплее.",
            "[pause:0.8][thinking][gesture:nod] Эта сказка напоминает: {theme} — самое настоящее волшебство, и оно доступно каждому.",
        ],
        goodnights: [
            "[sleepy][gesture:sleep] Спокойной ночи, {hero}, и спокойной ночи тебе, мой маленький слушатель.",
            "[love][gesture:wave] {narrator} желает тебе самых добрых снов, а {hero} уже тихонько сопит.",
            "[sleepy][gesture:yawn] Тише, тише, сказка кончилась — пора закрывать глазки и видеть добрые сны.",
            "[love][gesture:sleep] Сладких снов, дружок, и пусть тебе приснится чудесный край «{Setting}».",
        ]
    )

    static let english = Pack(
        defaultHero: "Twinkle",
        defaultSetting: "the Sleepy Forest",
        defaultTheme: "friendship",
        titleTemplate: "{Hero} and the Secret of {Theme}",
        summaryTemplate: "A calm bedtime tale in which {hero} helps a new friend and discovers what {theme} really means.",
        openings: [
            "[happy][gesture:wave] Once upon a time, far beyond the hills and the rivers, there was {setting}, and that is where {hero} lived.",
            "[neutral] There once was a quiet and wonderful place, {setting}, and a little dreamer called {hero} lived there.",
            "[happy][gesture:bounce] Every evening, when the first stars began to twinkle, {hero} skipped home through {setting}.",
            "[listening] Listen closely, little friend, because this is the story of {hero} and a place called home: {setting}.",
        ],
        traits: [
            "[curious] More than anything, {hero} loved to look at the stars and wonder what {theme} really meant.",
            "[thinking][gesture:think] One question never left {hero} alone: what does {theme} truly mean?",
            "[listening] {Hero} could hear the wind and the soft footsteps of the night, but {theme} was still a mystery.",
            "[shy][gesture:shy] {Hero} was a little shy, but longed to find out what {theme} was all about.",
        ],
        encounters: [
            [
                "[surprised][gesture:surprisePop] One evening a tiny firefly drifted down from the sky and whispered that it was lost, and its little light was growing dim.",
                "[curious][gesture:nod] {Hero} nodded and promised to help it find its meadow, no matter what.",
            ],
            [
                "[curious][gesture:peek] One day something rustled in the bushes, and there sat a tiny hedgehog, shivering, because it had lost its path and could not find its way home.",
                "[happy][gesture:nod] {Hero} sat down beside it and said gently that together they would figure it out.",
            ],
            [
                "[sad][gesture:shake] One morning a small fluffy cloud floated down to the doorstep, sprinkling sad little raindrops, because it had drifted away from its cloud family.",
                "[listening][gesture:nod] {Hero} listened very carefully and decided that no one should ever be left alone.",
            ],
            [
                "[scared][gesture:surprisePop] One night a little star fell into the grass with a soft jingle, and its rays were trembling, because it could not climb back up into the sky.",
                "[happy][gesture:wave] {Hero} waved hello and said gently, “Do not be afraid, I will help you get home.”",
            ],
        ],
        ideas: [
            "[excited][gesture:bounce] Then {hero} remembered: the stars see everything from above and surely know the way!",
            "[happy][gesture:celebrate] Then an idea came along: call all the friends, because every road is shorter together!",
            "[excited][gesture:wakeUp] Suddenly {hero} noticed that the warm light of a kind heart lit the path better than any lantern!",
            "[curious][gesture:think] Then {hero} had a thought: a quiet little song would echo through the dark and show the way!",
        ],
        resolutions: [
            "[happy][gesture:celebrate] Step by step, light by light, the new friend made it home, and everyone cheered.",
            "[love] At home the new friend had been missed so much, and everyone said thank you for such a kind heart.",
            "[laughing][gesture:giggle] The new friend was so happy that it giggled, and {hero} giggled too.",
            "[love][gesture:wink] At last the new friend was safe at home and gave a cheerful little wink goodbye.",
        ],
        morals: [
            "[pause:0.8][love] Now {hero} knows that {theme} lives in every heart and wakes up whenever someone needs help.",
            "[pause:0.8][happy][gesture:nod] And that is how it goes: {theme} always begins with one small, kind step.",
            "[pause:0.8][love] Remember, little one: {theme} makes the world brighter and every heart a little warmer.",
            "[pause:0.8][thinking][gesture:nod] This tale reminds us that {theme} is real magic, and everyone can have it.",
        ],
        goodnights: [
            "[sleepy][gesture:sleep] Good night, {hero}, and good night to you, my little listener.",
            "[love][gesture:wave] {narrator} wishes you the sweetest dreams, and {hero} is already softly snoring.",
            "[sleepy][gesture:yawn] Hush now, the tale is over, so close your eyes and dream kind dreams.",
            "[love][gesture:sleep] Sweet dreams, little friend, and may you dream of {setting} tonight.",
        ]
    )

    // MARK: Helpers

    static func fill(_ template: String, with fields: Fields) -> String {
        var text = template
        text = text.replacingOccurrences(of: "{Hero}", with: capitalizingFirst(fields.hero))
        text = text.replacingOccurrences(of: "{hero}", with: fields.hero)
        text = text.replacingOccurrences(of: "{Setting}", with: capitalizingFirst(fields.setting))
        text = text.replacingOccurrences(of: "{setting}", with: fields.setting)
        text = text.replacingOccurrences(of: "{Theme}", with: titleCased(fields.theme))
        text = text.replacingOccurrences(of: "{theme}", with: fields.theme)
        text = text.replacingOccurrences(of: "{narrator}", with: fields.narrator)
        return text
    }

    /// Removes brackets, braces and sentence terminators (they would break the tag grammar or split sentences),
    /// collapses whitespace and limits the length. Empty input yields `fallback`.
    static func sanitize(_ raw: String, fallback: String, limit: Int) -> String {
        var cleaned = ""
        cleaned.reserveCapacity(raw.count)
        for ch in raw {
            if ch == "[" || ch == "]" || ch == "{" || ch == "}" || StoryTagScanner.isTerminator(ch) {
                cleaned.append(" ")
            } else {
                cleaned.append(ch)
            }
        }
        let collapsed = cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty else { return fallback }
        let limited = String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces)
        return limited.isEmpty ? fallback : limited
    }

    static func capitalizingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + String(text.dropFirst())
    }

    /// Words that stay lowercase inside an English title ("the Secret of a Dream").
    private static let titleSmallWords: Set<String> = ["a", "an", "the", "of", "and", "in", "on", "at", "to", "for", "with"]

    /// Title case for a fragment placed in the middle of a title: small words stay lowercase.
    static func titleCased(_ text: String) -> String {
        text.split(separator: " ").map { word -> String in
            let piece = String(word)
            let lowered = piece.lowercased()
            return StoryTemplates.titleSmallWords.contains(lowered) ? lowered : StoryTemplates.capitalizingFirst(piece)
        }.joined(separator: " ")
    }

    /// FNV-1a 64-bit over UTF-8 — stable across processes (unlike `hashValue`).
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
