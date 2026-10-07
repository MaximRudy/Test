import Foundation

/// Grapheme → viseme rules for Russian (Cyrillic) and English (Latin). Other scripts degrade to the
/// English rules (unknown letters alternate between an open vowel and a dental consonant).
///
/// Russian: "мама" → pp aa pp aa, "привет" → pp rr ih ff e dd, "жили-были" → ch ih dd ih sil pp ih dd ih.
/// Iotated vowels (я ю ё е) get a short `ih` glide at a word start, after a vowel or after ь/ъ; the soft
/// sign lengthens the preceding consonant (palatalisation), the hard sign separates. Doubled letters merge.
/// English: digraphs (th sh ch ng qu ph ck wh and the common vowel pairs), soft `c`, silent final `e`.
public enum TextVisemeEstimator {

    // MARK: Public API

    /// Viseme keyframes for one word. Times are relative to the word start and use `Viseme.nominalDuration`.
    public static func visemes(forWord word: String, languageCode: String) -> [VisemeKeyframe] {
        let normalized = word.lowercased().precomposedStringWithCanonicalMapping
        let chars = Array(normalized)
        guard !chars.isEmpty else { return [] }
        var builder = KeyframeBuilder()
        let cyrillic = containsCyrillic(normalized)
        let latin = containsLatin(normalized)
        if cyrillic || (!latin && isRussian(languageCode)) {
            emitRussian(chars, into: &builder)
        } else {
            emitEnglish(chars, into: &builder)
        }
        return builder.keyframes
    }

    /// Full track for a text: words, 0.04 s spaces, punctuation pauses (comma 0.18 s, sentence end 0.35 s,
    /// ellipsis 0.5 s). `languageCode == nil` auto-detects; `totalDuration` retimes the whole track.
    public static func track(for text: String, languageCode: String?, totalDuration: TimeInterval?) -> LipSyncTrack {
        let language = languageCode ?? detectLanguage(of: text)
        let chars = Array(text.precomposedStringWithCanonicalMapping)
        var builder = KeyframeBuilder()
        var word: [Character] = []
        var i = 0
        let n = chars.count
        while i < n {
            let c = chars[i]
            if c.isLetter || c.isNumber || c == "'" || c == "\u{2019}" {
                word.append(c)
                i += 1
                continue
            }
            if (c == "-" || c == "\u{2010}") && !word.isEmpty && i + 1 < n && chars[i + 1].isLetter {
                // In-word hyphen ("жили-были"): a tiny pause inside the word.
                word.append("-")
                i += 1
                continue
            }
            flush(&word, language: language, into: &builder)
            if c.isWhitespace {
                builder.addSilence(spacePause)
                i += 1
                continue
            }
            var pause: TimeInterval = 0
            switch c {
            case "\u{2026}":
                pause = ellipsisPause
            case ".":
                if i + 2 < n && chars[i + 1] == "." && chars[i + 2] == "." {
                    pause = ellipsisPause
                    i += 2
                } else {
                    pause = sentencePause
                }
            case "!", "?":
                pause = sentencePause
            case ",", ";", ":", "\u{2014}", "\u{2013}", "-":
                pause = clausePause
            default:
                pause = 0
            }
            if pause > 0 { builder.addSilence(pause) }
            i += 1
        }
        flush(&word, language: language, into: &builder)
        let track = LipSyncTrack(keyframes: builder.keyframes)
        if let total = totalDuration, total > 0 {
            return track.retimed(toDuration: total)
        }
        return track
    }

    /// "ru" if the text contains Cyrillic letters, else "en".
    public static func detectLanguage(of text: String) -> String {
        containsCyrillic(text) ? "ru" : "en"
    }

    // MARK: Pause lengths

    static let spacePause: TimeInterval = 0.04
    static let clausePause: TimeInterval = 0.18
    static let sentencePause: TimeInterval = 0.35
    static let ellipsisPause: TimeInterval = 0.5
    static let hyphenPause: TimeInterval = 0.04

    // MARK: Script detection

    static func isRussian(_ languageCode: String) -> Bool {
        let lower = languageCode.lowercased()
        return lower.hasPrefix("ru") || lower.hasPrefix("uk") || lower.hasPrefix("be") || lower.hasPrefix("bg")
    }

    static func containsCyrillic(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (v >= 0x0400 && v <= 0x052F) || (v >= 0x2DE0 && v <= 0x2DFF) || (v >= 0xA640 && v <= 0xA69F) {
                return true
            }
        }
        return false
    }

    static func containsLatin(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || (v >= 0x00C0 && v <= 0x024F) {
                return true
            }
        }
        return false
    }

    private static func flush(_ word: inout [Character], language: String, into builder: inout KeyframeBuilder) {
        guard !word.isEmpty else { return }
        let keyframes = visemes(forWord: String(word), languageCode: language)
        builder.append(keyframes)
        word.removeAll(keepingCapacity: true)
    }

    // MARK: Russian rules

    private static func emitRussian(_ chars: [Character], into b: inout KeyframeBuilder) {
        let n = chars.count
        var i = 0
        // True at a word start, after a vowel, after a hyphen pause and after ь/ъ: iotated vowels get a glide.
        var glideContext = true
        while i < n {
            let c = chars[i]
            var run = 1
            while i + run < n && chars[i + run] == c { run += 1 }
            let scale: Double = run > 1 ? 1.4 : 1
            switch c {
            case "а":
                b.add(.aa, scale: scale); glideContext = true
            case "я":
                if glideContext { b.add(.ih, scale: 0.45, weight: 0.6) }
                b.add(.aa, scale: scale); glideContext = true
            case "о":
                b.add(.oh, scale: scale); glideContext = true
            case "ё":
                if glideContext { b.add(.ih, scale: 0.45, weight: 0.6) }
                b.add(.oh, scale: scale); glideContext = true
            case "у":
                b.add(.ou, scale: scale); glideContext = true
            case "ю":
                if glideContext { b.add(.ih, scale: 0.45, weight: 0.6) }
                b.add(.ou, scale: scale); glideContext = true
            case "э":
                b.add(.e, scale: scale); glideContext = true
            case "е":
                if glideContext { b.add(.ih, scale: 0.45, weight: 0.6) }
                b.add(.e, scale: scale); glideContext = true
            case "и":
                b.add(.ih, scale: scale); glideContext = true
            case "ы":
                b.add(.ih, scale: scale, weight: 0.85); glideContext = true
            case "й":
                b.add(.ih, scale: 0.5, weight: 0.7); glideContext = true
            case "п", "б", "м":
                b.add(.pp, scale: scale); glideContext = false
            case "ф", "в":
                b.add(.ff, scale: scale); glideContext = false
            case "т", "д", "л":
                b.add(.dd, scale: scale); glideContext = false
            case "н":
                b.add(.nn, scale: scale); glideContext = false
            case "к", "г", "х":
                b.add(.kk, scale: scale); glideContext = false
            case "с", "з", "ц":
                b.add(.ss, scale: scale); glideContext = false
            case "ш", "ж", "ч":
                b.add(.ch, scale: scale); glideContext = false
            case "щ":
                b.add(.ch, scale: scale * 1.2); glideContext = false
            case "р":
                b.add(.rr, scale: scale); glideContext = false
            case "ь":
                // Soft sign: palatalises (lengthens) the previous consonant.
                b.scaleLastConsonant(by: 1.3)
                glideContext = true
            case "ъ":
                // Hard sign: brief separation before the iotated vowel.
                b.scaleLastConsonant(by: 1.15)
                glideContext = true
            case "-", "\u{2010}", "\u{2013}", "\u{2014}":
                b.addSilence(hyphenPause)
                glideContext = true
            default:
                if c.isNumber {
                    emitDigit(into: &b)
                    glideContext = true
                } else if c.isLetter {
                    if isLatinLetter(c) {
                        emitEnglishSingle(c, next: i + run < n ? chars[i + run] : nil, into: &b)
                    } else {
                        emitUnknownLetter(into: &b)
                    }
                    glideContext = b.lastIsVowel
                }
                // Apostrophes and other symbols are silent.
            }
            i += run
        }
    }

    // MARK: English rules

    private static func emitEnglish(_ chars: [Character], into b: inout KeyframeBuilder) {
        let n = chars.count
        var i = 0
        while i < n {
            let c = chars[i]
            let next: Character? = i + 1 < n ? chars[i + 1] : nil
            let next2: Character? = i + 2 < n ? chars[i + 2] : nil

            // Trigraph.
            if c == "t", next == "c", next2 == "h" {
                b.add(.ch, scale: 1.1)
                i += 3
                continue
            }
            // Consonant digraphs.
            if let next = next, let consumed = emitEnglishDigraph(c, next, into: &b) {
                i += consumed
                continue
            }
            // Doubled letters merge into one longer viseme.
            if let next = next, next == c, c.isLetter {
                var run = 2
                while i + run < n && chars[i + run] == c { run += 1 }
                emitEnglishSingle(c, next: i + run < n ? chars[i + run] : nil, into: &b, scale: 1.4)
                i += run
                continue
            }
            // Silent final "e": like, make, home (needs an earlier vowel and a preceding consonant).
            if c == "e", i == n - 1, n >= 3, isEnglishConsonant(chars[i - 1]), hasEnglishVowel(chars, before: i - 1) {
                i += 1
                continue
            }
            switch c {
            case "-", "\u{2010}", "\u{2013}", "\u{2014}":
                b.addSilence(hyphenPause)
            case "'", "\u{2019}":
                break
            default:
                if c.isNumber {
                    emitDigit(into: &b)
                } else {
                    emitEnglishSingle(c, next: next, into: &b)
                }
            }
            i += 1
        }
    }

    /// Emits a two-letter digraph and returns the number of characters consumed, or nil if `c, next` is not one.
    private static func emitEnglishDigraph(_ c: Character, _ next: Character, into b: inout KeyframeBuilder) -> Int? {
        switch (c, next) {
        case ("t", "h"): b.add(.th); return 2
        case ("s", "h"): b.add(.ch); return 2
        case ("c", "h"): b.add(.ch); return 2
        case ("p", "h"): b.add(.ff); return 2
        case ("c", "k"): b.add(.kk); return 2
        case ("n", "g"): b.add(.nn, scale: 1.2); return 2
        case ("q", "u"):
            b.add(.kk)
            b.add(.ou, scale: 0.6, weight: 0.8)
            return 2
        case ("w", "h"): b.add(.ou, scale: 0.7, weight: 0.8); return 2
        case ("e", "e"): b.add(.ih, scale: 1.3); return 2
        case ("o", "o"): b.add(.ou, scale: 1.3); return 2
        case ("e", "a"): b.add(.ih, scale: 1.2); return 2
        case ("o", "u"):
            b.add(.aa, scale: 0.8)
            b.add(.ou, scale: 0.6)
            return 2
        case ("o", "w"): b.add(.oh, scale: 1.2); return 2
        case ("o", "a"): b.add(.oh, scale: 1.3); return 2
        case ("a", "i"), ("a", "y"):
            b.add(.e, scale: 0.9)
            b.add(.ih, scale: 0.5, weight: 0.8)
            return 2
        case ("e", "y"), ("e", "i"): b.add(.e, scale: 1.2); return 2
        case ("i", "e"): b.add(.ih, scale: 1.3); return 2
        case ("o", "i"), ("o", "y"):
            b.add(.oh, scale: 0.8)
            b.add(.ih, scale: 0.5, weight: 0.8)
            return 2
        case ("a", "u"), ("a", "w"): b.add(.oh, scale: 1.2); return 2
        case ("u", "e"), ("e", "w"): b.add(.ou, scale: 1.3); return 2
        default: return nil
        }
    }

    private static func emitEnglishSingle(_ c: Character, next: Character?, into b: inout KeyframeBuilder, scale: Double = 1) {
        switch c {
        case "a": b.add(.aa, scale: scale)
        case "e": b.add(.e, scale: scale)
        case "i": b.add(.ih, scale: scale)
        case "o": b.add(.oh, scale: scale)
        case "u": b.add(.ou, scale: scale, weight: 0.75)
        case "y":
            if let next = next, isEnglishVowelLetter(next) {
                b.add(.ih, scale: scale * 0.6, weight: 0.7)   // consonantal y ("yes")
            } else {
                b.add(.ih, scale: scale)                       // vocalic y ("happy")
            }
        case "w": b.add(.ou, scale: scale * 0.7, weight: 0.8)
        case "b", "m", "p": b.add(.pp, scale: scale)
        case "f", "v": b.add(.ff, scale: scale)
        case "d", "t", "l": b.add(.dd, scale: scale)
        case "n": b.add(.nn, scale: scale)
        case "k", "q", "g": b.add(.kk, scale: scale)
        case "c":
            if let next = next, next == "e" || next == "i" || next == "y" {
                b.add(.ss, scale: scale)
            } else {
                b.add(.kk, scale: scale)
            }
        case "x":
            b.add(.kk, scale: scale * 0.7)
            b.add(.ss, scale: scale * 0.7)
        case "h": b.add(.kk, scale: scale * 0.8, weight: 0.6)
        case "j": b.add(.ch, scale: scale)
        case "s", "z": b.add(.ss, scale: scale)
        case "r": b.add(.rr, scale: scale)
        default:
            if c.isLetter {
                if let folded = foldDiacritic(c) {
                    emitEnglishSingle(folded, next: next, into: &b, scale: scale)
                } else {
                    emitUnknownLetter(into: &b)
                }
            }
        }
    }

    /// Maps common accented Latin letters to their base vowel/consonant.
    private static func foldDiacritic(_ c: Character) -> Character? {
        switch c {
        case "à", "á", "â", "ã", "ä", "å", "ā": return "a"
        case "è", "é", "ê", "ë", "ē": return "e"
        case "ì", "í", "î", "ï", "ī": return "i"
        case "ò", "ó", "ô", "õ", "ö", "ø", "ō": return "o"
        case "ù", "ú", "û", "ü", "ū": return "u"
        case "ç": return "s"
        case "ñ": return "n"
        case "ß": return "s"
        case "ý", "ÿ": return "y"
        default: return nil
        }
    }

    private static func isEnglishVowelLetter(_ c: Character) -> Bool {
        switch c {
        case "a", "e", "i", "o", "u": return true
        default: return false
        }
    }

    private static func isEnglishConsonant(_ c: Character) -> Bool {
        c.isLetter && isLatinLetter(c) && !isEnglishVowelLetter(c) && c != "y"
    }

    private static func hasEnglishVowel(_ chars: [Character], before index: Int) -> Bool {
        var i = 0
        while i < index {
            if isEnglishVowelLetter(chars[i]) || chars[i] == "y" { return true }
            i += 1
        }
        return false
    }

    private static func isLatinLetter(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        let v = scalar.value
        return (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || (v >= 0x00C0 && v <= 0x024F)
    }

    // MARK: Fallbacks

    /// Digits are read as short number words: approximate with an open vowel and a dental.
    private static func emitDigit(into b: inout KeyframeBuilder) {
        b.add(.dd, scale: 0.9)
        b.add(.aa, scale: 0.9, weight: 0.9)
        b.add(.ss, scale: 0.8, weight: 0.8)
    }

    /// Unknown scripts: alternate an open vowel and a dental consonant so speech still looks articulated.
    private static func emitUnknownLetter(into b: inout KeyframeBuilder) {
        if b.lastIsVowel {
            b.add(.dd, weight: 0.8)
        } else {
            b.add(.aa, weight: 0.8)
        }
    }
}

// MARK: - KeyframeBuilder

/// Appends keyframes back to back, merging adjacent silences.
struct KeyframeBuilder {
    private(set) var keyframes: [VisemeKeyframe] = []
    private(set) var cursor: TimeInterval = 0

    var lastIsVowel: Bool {
        guard let last = keyframes.last else { return false }
        return last.viseme.isVowel
    }

    mutating func add(_ viseme: Viseme, scale: Double = 1, weight: Float = 1) {
        let duration = viseme.nominalDuration * scale
        guard duration > 0 else { return }
        keyframes.append(VisemeKeyframe(time: cursor, viseme: viseme, duration: duration, weight: weight))
        cursor += duration
    }

    /// Adds a silence of `length`; merges with a preceding silence by taking the longer of the two.
    mutating func addSilence(_ length: TimeInterval) {
        guard length > 0 else { return }
        if let last = keyframes.last, last.viseme == .sil {
            let merged = max(last.duration, length)
            keyframes[keyframes.count - 1].duration = merged
            cursor = last.time + merged
        } else {
            keyframes.append(VisemeKeyframe(time: cursor, viseme: .sil, duration: length, weight: 1))
            cursor += length
        }
    }

    /// Lengthens the last keyframe if it is a consonant (soft/hard sign handling).
    mutating func scaleLastConsonant(by factor: Double) {
        guard let last = keyframes.last, last.viseme != .sil, !last.viseme.isVowel else { return }
        let duration = last.duration * factor
        keyframes[keyframes.count - 1].duration = duration
        cursor = last.time + duration
    }

    /// Appends already-timed keyframes (times relative to their own start) at the cursor.
    mutating func append(_ frames: [VisemeKeyframe]) {
        guard !frames.isEmpty else { return }
        var end = cursor
        for kf in frames {
            let shifted = VisemeKeyframe(time: kf.time + cursor, viseme: kf.viseme, duration: kf.duration, weight: kf.weight)
            if shifted.viseme == .sil, let last = keyframes.last, last.viseme == .sil, abs(last.end - shifted.time) < 1e-9 {
                keyframes[keyframes.count - 1].duration = last.duration + shifted.duration
            } else {
                keyframes.append(shifted)
            }
            end = max(end, shifted.end)
        }
        cursor = end
    }
}
