import Foundation

// MARK: - StoryPrompt

/// What the user asks a generator for.
public struct StoryPrompt: Sendable, Equatable {
    /// Name of the hero of the tale (empty = a default hero for the language).
    public var heroName: String
    /// Where the tale happens, e.g. "волшебный лес" / "a quiet forest" (empty = default).
    public var setting: String
    /// A single noun the moral is about, e.g. "дружба" / "friendship" (empty = default).
    public var theme: String
    /// "ru" or "en" (anything else falls back to English templates).
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

/// Offline generator: assembles a 10–12 sentence bedtime tale from Russian or English templates,
/// substituting the hero, the setting and the theme, with varied emotion/gesture tags and a gentle moral.
/// Deterministic: the same prompt always yields the same story, so previews and tests are stable.
public struct TemplateStoryGenerator: StoryGenerating {
    public init() {}

    public func generateStory(_ prompt: StoryPrompt) async throws -> Story {
        try Task.checkCancellation()
        return makeStory(prompt)
    }

    /// Synchronous variant for previews and tests.
    public func makeStory(_ prompt: StoryPrompt) -> Story {
        let isRussian = StoryLibrary.baseLanguage(prompt.languageCode) == "ru"
        let pack = isRussian ? StoryTemplates.russian : StoryTemplates.english
        let languageCode = isRussian ? "ru" : "en"

        let hero = StoryTemplates.sanitize(prompt.heroName, fallback: pack.defaultHero, limit: 40)
        let setting = StoryTemplates.sanitize(prompt.setting, fallback: pack.defaultSetting, limit: 60)
        let theme = StoryTemplates.sanitize(prompt.theme, fallback: pack.defaultTheme, limit: 40)
        let narratorName = isRussian ? prompt.narrator.russianName : prompt.narrator.englishName

        let seed = StoryTemplates.fnv1a("\(hero)|\(setting)|\(theme)|\(languageCode)|\(prompt.narrator.rawValue)")
        var rng = StorySeededGenerator(seed: seed)

        var lines: [String] = []
        lines.reserveCapacity(12)
        lines.append(rng.pick(pack.openings))
        lines.append(rng.pick(pack.traits))
        lines.append(contentsOf: rng.pick(pack.encounters))
        if rng.chance(0.7) { lines.append(rng.pick(pack.worries)) }
        lines.append(rng.pick(pack.ideas))
        lines.append(rng.pick(pack.resolutions))
        if rng.chance(0.7) { lines.append(rng.pick(pack.windDowns)) }
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

    /// True with probability `probability` (0…1).
    mutating func chance(_ probability: Double) -> Bool {
        let unit = Double(next() >> 11) / Double(UInt64(1) << 53)
        return unit < probability
    }
}

// MARK: - StoryTemplates

/// Template text for the offline generator. Placeholders: `{hero}`, `{Hero}` (capitalized),
/// `{setting}`, `{theme}`, `{Theme}` (title case), `{narrator}`.
/// Every template is exactly one sentence (one terminator at the end) so the parser yields one segment per line.
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
        /// Four-sentence mini arcs: incident, reaction, problem, promise to help.
        var encounters: [[String]]
        var worries: [String]
        var ideas: [String]
        var resolutions: [String]
        var windDowns: [String]
        var morals: [String]
        var goodnights: [String]
    }

    // Russian templates use the present tense so they read naturally for a hero of any gender.
    static let russian = Pack(
        defaultHero: "Звёздочка",
        defaultSetting: "Сонный лес",
        defaultTheme: "дружба",
        titleTemplate: "{Hero} и {theme}",
        summaryTemplate: "Спокойная сказка на ночь о том, как {hero} узнаёт, что такое {theme}.",
        openings: [
            "[happy][gesture:wave] Далеко-далеко, в краю под названием «{setting}», живёт {hero}.",
            "[neutral] Есть на свете тихое и удивительное место — «{setting}», и именно там живёт {hero}.",
            "[happy] Каждый вечер, когда зажигаются первые звёзды, в краю «{setting}» готовится ко сну {hero}.",
        ],
        traits: [
            "[curious] Больше всего на свете {hero} любит смотреть на звёзды и думать о том, что же такое {theme}.",
            "[thinking][gesture:think] Один вопрос никак не даёт покоя: что же на самом деле значит слово «{theme}»?",
            "[listening] {Hero} умеет слушать ветер и тихие шаги ночи, но слово «{theme}» пока остаётся загадкой.",
        ],
        encounters: [
            [
                "[surprised][gesture:surprisePop] Однажды вечером с неба тихо спускается маленький светлячок и садится прямо на ладошку.",
                "[listening] Светлячок шепчет, что заблудился и очень скучает по своей полянке.",
                "[sad] Его огонёк становится совсем слабым, а дорога домой никому не известна.",
                "[curious][gesture:nod] {Hero} кивает и обещает помочь, чего бы это ни стоило.",
            ],
            [
                "[curious][gesture:peek] Однажды в кустах что-то тихонько шуршит, и {hero} осторожно заглядывает туда.",
                "[surprised] Там сидит крошечный ёжик с мокрыми от росы иголками и дрожит.",
                "[sad] Ёжик потерял свою тропинку и боится, что никогда не найдёт дорогу к дому.",
                "[happy][gesture:nod] {Hero} садится рядом и тихо говорит, что вместе они обязательно всё придумают.",
            ],
            [
                "[surprised] Однажды утром прямо на крыльцо опускается маленькое пушистое облачко.",
                "[curious] Облачко вздыхает: оно отстало от своей облачной семьи и теперь не знает, куда плыть.",
                "[scared] Без семьи облачку страшно и одиноко, и оно начинает тихонько накрапывать дождиком.",
                "[listening][gesture:nod] {Hero} слушает очень внимательно и решает, что никого нельзя оставлять в беде.",
            ],
        ],
        worries: [
            "[thinking] Сначала {hero} совсем не знает, с чего начать.",
            "[sad] Ночь кажется очень большой, а помощь — очень маленькой.",
            "[thinking][gesture:think] Задача непростая, и {hero} долго-долго думает.",
        ],
        ideas: [
            "[excited][gesture:bounce] И вдруг {hero} вспоминает: звёзды видят всё сверху и наверняка знают дорогу!",
            "[happy][gesture:celebrate] И тут приходит идея — позвать на помощь всех друзей, ведь вместе любая дорога короче!",
            "[excited] Вдруг {hero} замечает, что тёплый свет доброго сердца освещает тропинку лучше любого фонарика!",
        ],
        resolutions: [
            "[happy][gesture:celebrate] Шаг за шагом, огонёк за огоньком, новый друг возвращается домой, а все вокруг радуются.",
            "[love] Дома нового друга давно ждут, и все вокруг говорят спасибо за доброе сердце.",
            "[laughing][gesture:giggle] Новый друг так радуется, что хихикает, и {hero} хихикает вместе с ним.",
        ],
        windDowns: [
            "[sleepy] Небо над краем «{setting}» становится мягким и тёмно-синим, как самое уютное одеяло.",
            "[sleepy][gesture:yawn] Становится поздно, глаза слипаются, и даже звёзды зевают.",
            "[neutral] Ветер стихает, травы шепчут колыбельную, и весь мир готовится ко сну.",
        ],
        morals: [
            "[pause:0.8][love] Теперь {hero} знает: {theme} — это то, что становится больше, когда делишься.",
            "[pause:0.8][happy][gesture:nod] Вот что такое {theme}: маленькое доброе дело, сделанное от всего сердца.",
            "[pause:0.8][love] Главное в этой сказке — {theme}, и это живёт в каждом добром сердце.",
        ],
        goodnights: [
            "[sleepy][gesture:sleep] Спокойной ночи, {hero}, и спокойной ночи тебе, мой маленький слушатель.",
            "[love][gesture:wave] {narrator} желает тебе самых добрых снов, а {hero} уже тихонько сопит.",
            "[sleepy] Тише, тише, сказка кончилась — пора закрывать глазки и видеть добрые сны.",
        ]
    )

    static let english = Pack(
        defaultHero: "Twinkle",
        defaultSetting: "the Sleepy Forest",
        defaultTheme: "friendship",
        titleTemplate: "{Hero} and {Theme}",
        summaryTemplate: "A calm bedtime tale in which {hero} discovers what {theme} really means.",
        openings: [
            "[happy][gesture:wave] Far, far away, in a place called {setting}, there lived {hero}.",
            "[neutral] There is a quiet and wonderful place called {setting}, and that is where {hero} lives.",
            "[happy] Every evening, when the first stars came out, {hero} got ready for bed in a place called {setting}.",
        ],
        traits: [
            "[curious] More than anything, {hero} loved to look at the stars and wonder what {theme} really means.",
            "[thinking][gesture:think] One question never left {hero} alone: what does the word {theme} truly mean?",
            "[listening] {Hero} could listen to the wind and the soft footsteps of the night, but the word {theme} was still a mystery.",
        ],
        encounters: [
            [
                "[surprised][gesture:surprisePop] One evening a tiny firefly drifted down from the sky and landed right on the hand of {hero}.",
                "[listening] The firefly whispered that it was lost and missed its little meadow very much.",
                "[sad] Its light grew dim, and nobody knew the way back home.",
                "[curious][gesture:nod] {Hero} nodded and promised to help, no matter what.",
            ],
            [
                "[curious][gesture:peek] One day something rustled softly in the bushes, and {hero} peeked inside.",
                "[surprised] There sat a tiny hedgehog, its prickles wet with dew, shivering.",
                "[sad] The hedgehog had lost its path and was afraid it would never find its way home.",
                "[happy][gesture:nod] {Hero} sat down beside it and said gently that together they would figure it out.",
            ],
            [
                "[surprised] One morning a small fluffy cloud floated down and settled on the doorstep.",
                "[curious] The cloud sighed: it had drifted away from its cloud family and did not know where to go.",
                "[scared] Without its family the little cloud felt scared and lonely, and it began to sprinkle tiny raindrops.",
                "[listening][gesture:nod] {Hero} listened very carefully and decided that no one should ever be left alone.",
            ],
        ],
        worries: [
            "[thinking] At first {hero} did not know where to begin.",
            "[sad] The night seemed very big, and the help seemed very small.",
            "[thinking][gesture:think] It was not an easy task, and {hero} thought for a long, long time.",
        ],
        ideas: [
            "[excited][gesture:bounce] Then {hero} remembered: the stars see everything from above and surely know the way!",
            "[happy][gesture:celebrate] Then an idea came along — call all the friends, because every road is shorter together!",
            "[excited] Suddenly {hero} noticed that the warm light of a kind heart lit the path better than any lantern!",
        ],
        resolutions: [
            "[happy][gesture:celebrate] Step by step, light by light, the new friend made it home, and everyone cheered.",
            "[love] At home the new friend had been missed for so long, and everyone said thank you for such a kind heart.",
            "[laughing][gesture:giggle] The new friend was so happy that it giggled, and {hero} giggled too.",
        ],
        windDowns: [
            "[sleepy] The sky above {setting} turned soft and deep blue, like the cosiest blanket.",
            "[sleepy][gesture:yawn] It was getting late, eyes were getting heavy, and even the stars were yawning.",
            "[neutral] The wind grew quiet, the grass hummed a lullaby, and the whole world got ready for sleep.",
        ],
        morals: [
            "[pause:0.8][love] Now {hero} knows: {theme} is something that grows bigger when you share it.",
            "[pause:0.8][happy][gesture:nod] That is what {theme} means: a small kind deed, done with all your heart.",
            "[pause:0.8][love] The heart of this tale is {theme}, and it lives in every kind heart.",
        ],
        goodnights: [
            "[sleepy][gesture:sleep] Good night, {hero}, and good night to you, my little listener.",
            "[love][gesture:wave] {narrator} wishes you the sweetest dreams, and {hero} is already softly snoring.",
            "[sleepy] Hush now, the tale is over — time to close your eyes and dream kind dreams.",
        ]
    )

    // MARK: Helpers

    static func fill(_ template: String, with fields: Fields) -> String {
        var text = template
        text = text.replacingOccurrences(of: "{Hero}", with: capitalizingFirst(fields.hero))
        text = text.replacingOccurrences(of: "{hero}", with: fields.hero)
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

    static func titleCased(_ text: String) -> String {
        text.split(separator: " ").map { capitalizingFirst(String($0)) }.joined(separator: " ")
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
