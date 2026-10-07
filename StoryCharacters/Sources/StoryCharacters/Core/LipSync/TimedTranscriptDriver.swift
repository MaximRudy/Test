import Foundation

/// A word with its start/end time in seconds relative to the transcript start (e.g. from a server TTS alignment).
public struct TimedWord: Sendable, Equatable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Lip-sync from server-provided word timings. Each word's visemes are estimated from its text and retimed
/// to fit its `start ... end` window; `start(at:)` maps transcript time 0 onto the rig clock.
@MainActor
public final class TimedTranscriptDriver: LipSyncSource {
    private struct PreparedWord {
        var track: LipSyncTrack
        var start: TimeInterval
        var energyGain: Float
    }

    private let words: [TimedWord]
    private let languageCode: String
    private let prepared: [PreparedWord]
    private let mixer = LipSyncMixer()
    private var startTime: TimeInterval?

    public init(words: [TimedWord], languageCode: String) {
        self.words = words
        self.languageCode = languageCode
        var prepared: [PreparedWord] = []
        prepared.reserveCapacity(words.count)
        let sorted = words.sorted { $0.start < $1.start }
        for (index, word) in sorted.enumerated() {
            let keyframes = TextVisemeEstimator.visemes(forWord: word.text, languageCode: languageCode)
            guard !keyframes.isEmpty else { continue }
            var track = LipSyncTrack(keyframes: keyframes)
            let length = max(0.04, word.end - word.start)
            track = track.retimed(toDuration: length)
            let punctuation = TimedTranscriptDriver.trailingPunctuation(of: word.text)
            if punctuation.endsSentence {
                // Close the mouth after sentence-final punctuation, but never into the next word.
                var closing: TimeInterval = 0.12
                if index + 1 < sorted.count {
                    closing = min(closing, max(0, sorted[index + 1].start - word.end))
                }
                track = track.appendingSilence(closing)
            }
            prepared.append(PreparedWord(track: track, start: word.start, energyGain: punctuation.isQuestion ? 1.35 : 1))
        }
        self.prepared = prepared
    }

    /// Starts playback: `time` is the absolute rig-clock time that corresponds to transcript time 0.
    public func start(at time: TimeInterval) {
        mixer.clear()
        startTime = time
        for word in prepared {
            mixer.schedule(word.track, startingAt: time + word.start, energyGain: word.energyGain)
        }
    }

    public func stop() {
        startTime = nil
        mixer.clear()
    }

    /// True between `start(at:)` and `stop()`.
    public var isRunning: Bool { startTime != nil }

    public func sample(at time: TimeInterval) -> LipSyncSample {
        guard startTime != nil else { return .silent }
        return mixer.sample(at: time)
    }

    /// Scans the end of a word for punctuation; words from alignment services often keep it attached.
    static func trailingPunctuation(of text: String) -> (endsSentence: Bool, isQuestion: Bool) {
        var endsSentence = false
        var isQuestion = false
        for c in text.reversed() {
            if c.isLetter || c.isNumber { break }
            switch c {
            case "?": isQuestion = true; endsSentence = true
            case ".", "!", "\u{2026}": endsSentence = true
            default: break
            }
        }
        return (endsSentence, isQuestion)
    }
}
