import Foundation

/// What a lip-sync driver reports for one frame.
public struct LipSyncSample: Sendable, Equatable {
    /// Articulated mouth (viseme blend). `smile` is normally 0 — the rig adds the emotion's smile on top.
    public var mouth: MouthShape
    /// Speech loudness/energy 0 ... 1 — drives body bob, brow emphasis and glow pulse while talking.
    public var energy: Float
    /// True while an utterance is in progress (including short pauses between words).
    public var isSpeaking: Bool
    /// Pulse that jumps to 1 at every word onset and decays to 0 within ~250 ms. Drives talking-head nods.
    public var wordOnset: Float

    public init(mouth: MouthShape = .zero, energy: Float = 0, isSpeaking: Bool = false, wordOnset: Float = 0) {
        self.mouth = mouth
        self.energy = energy
        self.isSpeaking = isSpeaking
        self.wordOnset = wordOnset
    }

    public static let silent = LipSyncSample()
}

/// Anything that can articulate the mouth over time: text-estimated visemes, TTS-aligned visemes,
/// audio-amplitude analysis, or server-provided word timings. Sampled by the rig once per frame on the main actor.
@MainActor
public protocol LipSyncSource: AnyObject {
    /// `time` is the rig's monotonic time in seconds (the same clock passed to `CharacterRig.pose(at:)`).
    func sample(at time: TimeInterval) -> LipSyncSample
}

/// Speech progress notifications (for karaoke-style text highlighting and story sequencing).
public enum SpeechEvent: Sendable, Equatable {
    case started(text: String)
    /// A word is about to be spoken. `location`/`length` index UTF-16 code units of the utterance text (NSRange semantics).
    case word(location: Int, length: Int, text: String)
    case paused
    case resumed
    case finished
    case cancelled
}
