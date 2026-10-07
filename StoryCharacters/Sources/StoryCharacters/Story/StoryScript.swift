import Foundation

// MARK: - StorySegment

/// One spoken unit of a story: a sentence (or a `[br]`-delimited fragment) plus the acting
/// directions that apply to it. `pauseAfter` is the silence the player keeps after the
/// sentence has been spoken, before the next segment starts.
public struct StorySegment: Sendable, Equatable, Identifiable {
    /// Position of the segment inside its script (0-based, stable for the life of the script).
    public let id: Int
    /// Plain sentence text with the tags removed and whitespace normalized.
    public var text: String
    /// Emotion the narrator switches to before speaking this segment (`nil` = keep the current one).
    public var emotion: Emotion?
    /// Gesture for this segment (`nil` = none). `StoryPlayer` plays most gestures as the sentence starts;
    /// mouth-taking ones (`.yawn`, `.wakeUp`) just before it, and `.sleep` after it has been spoken.
    public var gesture: Gesture?
    /// Seconds of silence after the segment (defaults to `StoryScript.defaultPauseAfter`).
    public var pauseAfter: TimeInterval

    public init(id: Int, text: String, emotion: Emotion? = nil, gesture: Gesture? = nil,
                pauseAfter: TimeInterval = StoryScript.defaultPauseAfter) {
        self.id = id
        self.text = text
        self.emotion = emotion
        self.gesture = gesture
        self.pauseAfter = pauseAfter
    }
}

// MARK: - StoryScript

/// A parsed, playable story: an ordered list of segments.
///
/// Tag grammar inside the tagged text:
/// * `[happy]` — any `Emotion.rawValue` (case-insensitive) → `segment.emotion`;
/// * `[gesture:wave]` — any `Gesture.rawValue` (case-insensitive) → `segment.gesture`;
/// * `[pause:0.6]` — seconds of silence after the segment (`[pause]` alone = 1 s, clamped 0…10);
/// * `[br]` — forces a segment break without sentence punctuation.
///
/// Sentences are split on `.`, `!`, `?` and `…` (runs such as `?!` or `...` and closing quotes stay
/// with the sentence; a `.` between two digits is a decimal point, not a terminator). A run does not end
/// the sentence when the text goes on with a lowercase letter, or with a dash and a lowercase letter
/// («Привет!» — сказал ёжик; "Ну... а потом"), or when the `.` closes a known abbreviation ("Mr. Fox").
/// Punctuation left detached by a removed tag is glued back ("Hello [happy], friend." → "Hello, friend."). Tags apply to the
/// segment that follows them — i.e. to the next segment that is produced after the tag — so
/// `[sad] It rained.` makes "It rained." sad and `[pause:1] Goodnight.` keeps one second of silence
/// after "Goodnight.". Unknown tags are dropped from the text. Tag-shaped brackets that are not tags
/// (contain spaces or nested brackets) are kept as literal text.
public struct StoryScript: Sendable, Equatable {
    /// Silence between sentences when no `[pause:]` tag is given.
    public static let defaultPauseAfter: TimeInterval = 0.35

    public var title: String
    public var languageCode: String
    public var segments: [StorySegment]

    public init(title: String, languageCode: String, segments: [StorySegment]) {
        self.title = title
        self.languageCode = languageCode
        self.segments = segments
    }

    /// Parses `tagged` into segments (see the type documentation for the grammar).
    public static func parse(_ tagged: String, title: String, languageCode: String) -> StoryScript {
        var scanner = StoryTagScanner(tagged)
        let segments = scanner.run()
        return StoryScript(title: title, languageCode: languageCode, segments: segments)
    }

    /// The whole story as readable text: segment texts joined by single spaces, no tags.
    public var plainText: String {
        segments.map { $0.text }.joined(separator: " ")
    }

    /// Rough spoken duration in seconds (≈ 0.075 s per character plus the pauses). For progress UIs only.
    public var estimatedDuration: TimeInterval {
        segments.reduce(0) { partial, segment in
            partial + TimeInterval(segment.text.count) * 0.075 + max(0, segment.pauseAfter)
        }
    }

    /// Every bracketed tag found in `tagged`, in order, including the unrecognized ones.
    static func tags(in tagged: String) -> [StoryTag] {
        var scanner = StoryTagScanner(tagged)
        return scanner.collectTags()
    }

    /// Tag-shaped brackets that do not resolve to an emotion, gesture, pause or break.
    static func unknownTags(in tagged: String) -> [String] {
        tags(in: tagged).compactMap { tag -> String? in
            if case .unknown(let raw) = tag { return raw }
            return nil
        }
    }
}

// MARK: - StoryTag

/// One recognized (or unrecognized) bracket tag.
enum StoryTag: Equatable {
    case emotion(Emotion)
    case gesture(Gesture)
    case pause(TimeInterval)
    case lineBreak
    case unknown(String)

    private static let emotionsByName: [String: Emotion] = {
        var table: [String: Emotion] = [:]
        for emotion in Emotion.allCases { table[emotion.rawValue.lowercased()] = emotion }
        return table
    }()

    private static let gesturesByName: [String: Gesture] = {
        var table: [String: Gesture] = [:]
        for gesture in Gesture.allCases { table[gesture.rawValue.lowercased()] = gesture }
        return table
    }()

    /// Builds a tag from the text between `[` and `]`. Returns `nil` when the content is not tag-shaped
    /// (empty name, non-letter characters in the name, whitespace inside), in which case the brackets are literal text.
    init?(content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("["), !trimmed.contains("]") else { return nil }

        var name = trimmed
        var argument: String? = nil
        if let colon = trimmed.firstIndex(of: ":") {
            name = String(trimmed[trimmed.startIndex..<colon])
            let rawArgument = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            argument = rawArgument.isEmpty ? nil : rawArgument
        }
        name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
        if let argument = argument, argument.contains(where: { $0.isWhitespace }) { return nil }

        let lowered = name.lowercased()
        switch lowered {
        case "br":
            self = .lineBreak
        case "pause":
            guard let argument = argument else { self = .pause(1); return }
            let normalized = argument.replacingOccurrences(of: ",", with: ".")
            guard let seconds = Double(normalized), seconds.isFinite else { self = .unknown(trimmed); return }
            self = .pause(min(10, max(0, seconds)))
        case "gesture":
            guard let argument = argument, let gesture = StoryTag.gesturesByName[argument.lowercased()] else {
                self = .unknown(trimmed)
                return
            }
            self = .gesture(gesture)
        case "emotion":
            guard let argument = argument, let emotion = StoryTag.emotionsByName[argument.lowercased()] else {
                self = .unknown(trimmed)
                return
            }
            self = .emotion(emotion)
        default:
            if let emotion = StoryTag.emotionsByName[lowered] {
                self = .emotion(emotion)
            } else {
                self = .unknown(trimmed)
            }
        }
    }
}

// MARK: - StoryTagScanner

/// Single-pass scanner that turns tagged text into segments. Not a hot path; it allocates freely.
struct StoryTagScanner {
    private let chars: [Character]
    private var index = 0
    private var buffer: [Character] = []
    private var segments: [StorySegment] = []
    private var pendingEmotion: Emotion? = nil
    private var pendingGesture: Gesture? = nil
    private var pendingPause: TimeInterval? = nil

    /// Longest bracket content that is still considered a tag.
    private static let maxTagLength = 48

    init(_ text: String) {
        chars = Array(text)
    }

    // MARK: Entry points

    mutating func run() -> [StorySegment] {
        index = 0
        buffer.removeAll()
        segments.removeAll()
        pendingEmotion = nil
        pendingGesture = nil
        pendingPause = nil

        while index < chars.count {
            let ch = chars[index]
            if ch == "[", let close = tagClose(from: index),
               let tag = StoryTag(content: String(chars[(index + 1)..<close])) {
                apply(tag)
                index = close + 1
                continue
            }
            buffer.append(ch)
            index += 1
            if StoryTagScanner.isTerminator(ch) && !isDecimalPoint(at: index - 1) {
                let runStart = buffer.count - 1
                consumeTrailingPunctuation()
                if !continuesSentence(from: index) && !isAbbreviation(runStart: runStart) {
                    flush()
                }
            }
        }
        flush()
        // A trailing pause tag with no sentence after it lengthens the final pause.
        if let pause = pendingPause, !segments.isEmpty {
            segments[segments.count - 1].pauseAfter = pause
        }
        return segments
    }

    mutating func collectTags() -> [StoryTag] {
        var found: [StoryTag] = []
        var i = 0
        while i < chars.count {
            if chars[i] == "[", let close = tagClose(from: i),
               let tag = StoryTag(content: String(chars[(i + 1)..<close])) {
                found.append(tag)
                i = close + 1
                continue
            }
            i += 1
        }
        return found
    }

    // MARK: Helpers

    /// Index of the `]` that closes the bracket opened at `open`, if the content looks like a tag.
    private func tagClose(from open: Int) -> Int? {
        var i = open + 1
        let limit = min(chars.count, open + 1 + StoryTagScanner.maxTagLength)
        while i < limit {
            let c = chars[i]
            if c == "]" { return i }
            if c == "[" || c.isNewline { return nil }
            i += 1
        }
        return nil
    }

    private mutating func apply(_ tag: StoryTag) {
        switch tag {
        case .emotion(let emotion):
            pendingEmotion = emotion
        case .gesture(let gesture):
            pendingGesture = gesture
        case .pause(let seconds):
            pendingPause = seconds
        case .lineBreak:
            flush()
        case .unknown:
            break
        }
    }

    private mutating func flush() {
        // Collapse whitespace; punctuation that a removed tag left detached ("Hello [happy], friend.")
        // is glued back to the previous word.
        var text = ""
        for word in String(buffer).split(whereSeparator: { $0.isWhitespace }) {
            if !text.isEmpty && !StoryTagScanner.attachesToPreviousWord(word.first) {
                text.append(" ")
            }
            text.append(contentsOf: word)
        }
        buffer.removeAll(keepingCapacity: true)
        guard !text.isEmpty else { return }
        let segment = StorySegment(id: segments.count,
                                   text: text,
                                   emotion: pendingEmotion,
                                   gesture: pendingGesture,
                                   pauseAfter: pendingPause ?? StoryScript.defaultPauseAfter)
        segments.append(segment)
        pendingEmotion = nil
        pendingGesture = nil
        pendingPause = nil
    }

    /// Pulls the rest of a punctuation run (`?!`, `...`, closing quotes) into the current sentence.
    private mutating func consumeTrailingPunctuation() {
        while index < chars.count {
            let c = chars[index]
            if StoryTagScanner.isTerminator(c) || StoryTagScanner.isClosingQuote(c) {
                buffer.append(c)
                index += 1
            } else {
                break
            }
        }
    }

    /// `3.5` — a period between two digits is not a sentence end.
    private func isDecimalPoint(at position: Int) -> Bool {
        guard position > 0, position + 1 < chars.count, chars[position] == "." else { return false }
        return chars[position - 1].isNumber && chars[position + 1].isNumber
    }

    /// True when the text after a terminator run (starting at `position`) clearly continues the same
    /// sentence: the next visible character is a lowercase letter ("Ну... а потом", "в 1999 г. летом"),
    /// or a dash followed by a lowercase letter (direct speech: «Привет!» — сказал ёжик).
    private func continuesSentence(from position: Int) -> Bool {
        var i = position
        while i < chars.count && chars[i].isWhitespace { i += 1 }
        guard i < chars.count else { return false }
        let next = chars[i]
        if next.isLowercase { return true }
        guard StoryTagScanner.isDash(next) else { return false }
        var j = i + 1
        while j < chars.count && chars[j].isWhitespace { j += 1 }
        return j < chars.count && chars[j].isLowercase
    }

    /// True when the punctuation run that starts at `runStart` in `buffer` is a single `.` closing a known
    /// abbreviation ("Mr. Fox", "ул. Лесная"), which does not end the sentence.
    private func isAbbreviation(runStart: Int) -> Bool {
        guard runStart >= 0, runStart == buffer.count - 1, buffer[runStart] == "." else { return false }
        var start = runStart
        while start > 0 && buffer[start - 1].isLetter { start -= 1 }
        guard start < runStart else { return false }
        let word = String(buffer[start..<runStart]).lowercased()
        return StoryTagScanner.abbreviations.contains(word)
    }

    /// Words that are followed by a period without ending the sentence. Single-letter Russian abbreviations
    /// ("т. е.", "г.") are not listed: they are normally followed by a lowercase word, which already keeps
    /// the sentence together, while "и т. д. Потом…" must still split.
    static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "st", "prof", "mt",
        "ул", "им", "св", "проф",
    ]

    static func isTerminator(_ c: Character) -> Bool {
        c == "." || c == "!" || c == "?" || c == "…"
    }

    static func isClosingQuote(_ c: Character) -> Bool {
        c == "»" || c == "\"" || c == "”" || c == "’" || c == "'" || c == ")"
    }

    static func isDash(_ c: Character) -> Bool {
        c == "—" || c == "–" || c == "-"
    }

    /// Punctuation that is written directly after the previous word (no space before it).
    static func attachesToPreviousWord(_ c: Character?) -> Bool {
        guard let c = c else { return false }
        return c == "," || c == "." || c == "!" || c == "?" || c == "…" || c == ":" || c == ";" || c == "»" || c == ")"
    }
}
