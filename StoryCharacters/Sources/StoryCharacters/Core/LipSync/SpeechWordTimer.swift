import Foundation

/// Word-timing model behind `SpeechSynthesisDriver` (a plain value type, testable without a synthesizer).
///
/// `AVSpeechSynthesizer` only reports when each word *starts*. The model estimates the word's spoken length from an
/// adaptive seconds-per-character value (EMA of the measured inter-word intervals) and schedules the word's
/// visemes on a `LipSyncMixer`; the next word's schedule clips the previous track to the real gap.
///
/// Intervals that end in a punctuation pause (comma, dash, sentence end...) are not used for adaptation and
/// unusually long intervals are capped, so pauses do not inflate the estimate. Words followed by a pause are
/// slightly under-estimated and a sentence end appends a short closing silence, so the mouth closes before the
/// pause instead of articulating into it.
struct SpeechWordTimer {

    /// Punctuation found between a word and the next word.
    struct Boundary: Sendable, Equatable {
        var endsSentence = false
        var isQuestion = false
        /// Any pause-producing punctuation (comma, semicolon, colon, dash or a sentence end).
        var hasPause = false
    }

    /// EMA weight of a newly measured seconds-per-character value.
    static let adaptationRate: TimeInterval = 0.35
    /// Scheduling lead: words start slightly after the callback to match audio output latency.
    static let schedulingLatency: TimeInterval = 0.01
    /// Words followed directly by another word are over-estimated a little; the next callback clips them.
    static let continuationFactor: TimeInterval = 1.1
    /// Words followed by a pause are under-estimated a little so the mouth settles before the silence.
    static let pauseFactor: TimeInterval = 0.95
    /// Silence appended after sentence-final words (closes the mouth).
    static let closingSilence: TimeInterval = 0.12
    /// Measured intervals above this multiple of the current estimate are capped (pauses the scan missed).
    static let maxObservationRatio: TimeInterval = 1.5
    /// Energy multiplier for the last word of a question (brow emphasis).
    static let questionEnergyGain: Float = 1.35
    static let minimumWordDuration: TimeInterval = 0.06

    /// Current seconds-per-character estimate.
    private(set) var secondsPerCharacter: TimeInterval = 0.07
    private var lastWordStart: TimeInterval?
    private var lastWordLetters = 0
    private var lastWordBoundary = Boundary()

    init() {}

    /// Starts a new utterance: initial estimate `0.075 / rate` s per character for Russian, `0.065 / rate` otherwise.
    mutating func begin(languageCode: String, effectiveRate: TimeInterval) {
        let base: TimeInterval = TextVisemeEstimator.isRussian(languageCode) ? 0.075 : 0.065
        secondsPerCharacter = base / max(0.2, effectiveRate)
        resetAnchor()
    }

    /// Forgets the previous word (after a pause/resume the next interval is not a speech measurement).
    mutating func resetAnchor() {
        lastWordStart = nil
        lastWordLetters = 0
        lastWordBoundary = Boundary()
    }

    /// Handles a word callback at `now`: adapts the rate, schedules the word's visemes on `mixer` and returns the
    /// word text. Returns nil (and schedules nothing) when the range does not fit `text`.
    @MainActor
    mutating func handleWord(in text: NSString, location: Int, length: Int, languageCode: String,
                             at now: TimeInterval, mixer: LipSyncMixer) -> String? {
        guard length > 0, location >= 0, location + length <= text.length else { return nil }
        let word = text.substring(with: NSRange(location: location, length: length))
        let letters = max(1, TextVisemeEstimator.articulatedLength(of: word))
        let boundary = SpeechWordTimer.boundary(
            after: SpeechWordTimer.articulationEnd(in: text, location: location, length: length), in: text)

        adapt(to: now)
        lastWordStart = now
        lastWordLetters = letters
        lastWordBoundary = boundary

        let keyframes = TextVisemeEstimator.visemes(forWord: word, languageCode: languageCode)
        if !keyframes.isEmpty {
            var track = LipSyncTrack(keyframes: keyframes)
            track = track.retimed(toDuration: estimatedDuration(letters: letters, boundary: boundary))
            if boundary.endsSentence {
                track = track.appendingSilence(SpeechWordTimer.closingSilence)
            }
            mixer.schedule(track,
                           startingAt: now + SpeechWordTimer.schedulingLatency,
                           energyGain: boundary.isQuestion ? SpeechWordTimer.questionEnergyGain : 1)
        }
        return word
    }

    /// Spoken-length estimate for a word of `letters` articulated characters.
    func estimatedDuration(letters: Int, boundary: Boundary) -> TimeInterval {
        let factor = boundary.hasPause ? SpeechWordTimer.pauseFactor : SpeechWordTimer.continuationFactor
        return max(SpeechWordTimer.minimumWordDuration, TimeInterval(max(1, letters)) * secondsPerCharacter * factor)
    }

    /// Updates the EMA from the interval since the previous word, unless that interval contains a pause.
    private mutating func adapt(to now: TimeInterval) {
        guard let previousStart = lastWordStart, lastWordLetters > 0, !lastWordBoundary.hasPause else { return }
        let gap = now - previousStart
        guard gap > 0.02 && gap < 3 else { return }
        // +1: the space between the words.
        let observed = gap / TimeInterval(lastWordLetters + 1)
        let capped = min(observed, secondsPerCharacter * SpeechWordTimer.maxObservationRatio)
        let bounded = min(0.25, max(0.025, capped))
        secondsPerCharacter = secondsPerCharacter * (1 - SpeechWordTimer.adaptationRate)
            + bounded * SpeechWordTimer.adaptationRate
    }

    /// UTF-16 offset just after the last letter or digit inside the word range, so punctuation that a voice
    /// includes in the reported range ("разбил.") is still seen by `boundary(after:in:)`.
    static func articulationEnd(in text: NSString, location: Int, length: Int) -> Int {
        let lower = max(0, location)
        var index = min(text.length, location + length)
        while index > lower {
            let code = text.character(at: index - 1)
            if let scalar = Unicode.Scalar(code),
               CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                break
            }
            index -= 1
        }
        return index
    }

    /// Scans the punctuation between the end of a word (UTF-16 offset `index`) and the next letter or digit.
    static func boundary(after index: Int, in text: NSString) -> Boundary {
        var result = Boundary()
        var scan = max(0, index)
        var sawSpace = false
        let count = text.length
        while scan < count {
            let code = text.character(at: scan)
            // Surrogate halves (emoji) end the scan.
            guard let scalar = Unicode.Scalar(code) else { break }
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                break
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                sawSpace = true
                scan += 1
                continue
            }
            switch code {
            case 0x3F, 0xFF1F:                                   // ? ？
                result.isQuestion = true
                result.endsSentence = true
            case 0x2E, 0x21, 0x2026, 0xFF01, 0x3002:             // . ! … ！ 。
                result.endsSentence = true
            case 0x2C, 0x3B, 0x3A, 0x2013, 0x2014, 0xFF0C, 0x3001: // , ; : – — ， 、
                result.hasPause = true
            case 0x2D:                                           // "-" used as a spaced dash
                if sawSpace { result.hasPause = true }
            default:
                break
            }
            scan += 1
        }
        if result.endsSentence { result.hasPause = true }
        return result
    }
}
