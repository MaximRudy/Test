import Foundation
import Observation

/// Sequences a `Story` through a `CharacterRig`: for every segment it sets the emotion, plays the
/// gesture, speaks the sentence with the rig's built-in TTS, tracks the spoken word for karaoke
/// highlighting, waits `pauseAfter` and moves on.
///
/// State machine: `idle → playing ⇄ paused → finished`. `stop()` returns to `idle` and calms the rig.
/// Pause/resume is implemented as "stop speaking + re-speak the current segment" because
/// `AVSpeechSynthesizer` pausing is unreliable across voices.
///
/// The player listens through `rig.onSpeechEvent`; the handler that was installed before is saved and
/// still called first, so other observers keep working. Call `detach()` to restore it.
@MainActor @Observable public final class StoryPlayer {
    public enum State: Sendable, Equatable {
        case idle
        case playing
        case paused
        case finished
    }

    public private(set) var state: State = .idle
    public private(set) var story: Story? = nil
    /// Parsed form of `story`, cached at `load`.
    public private(set) var script: StoryScript? = nil
    /// Index of the current segment (clamped to the script; stays on the last segment when finished).
    public private(set) var segmentIndex: Int = 0
    /// UTF-16 range of the word being spoken inside `currentSegment.text` (NSRange semantics); nil between words/segments.
    public private(set) var spokenRange: NSRange? = nil

    /// The character that narrates.
    public let rig: CharacterRig

    @ObservationIgnored private var pauseTask: Task<Void, Never>? = nil
    @ObservationIgnored private var advanceGeneration: Int = 0
    /// True while an utterance started by this player is in progress.
    @ObservationIgnored private var speakingSegment = false
    @ObservationIgnored private var hooked = false
    @ObservationIgnored private var previousHandler: ((SpeechEvent) -> Void)? = nil

    /// Longest pause the player will honour between segments.
    private static let maxPause: TimeInterval = 60

    public init(rig: CharacterRig) {
        self.rig = rig
    }

    // MARK: Derived state

    public var segments: [StorySegment] {
        script?.segments ?? []
    }

    public var currentSegment: StorySegment? {
        let all = segments
        guard segmentIndex >= 0, segmentIndex < all.count else { return nil }
        return all[segmentIndex]
    }

    /// Segments spoken / total (1 when finished, 0 when nothing is loaded).
    public var progress: Double {
        let count = segments.count
        guard count > 0 else { return 0 }
        if state == .finished { return 1 }
        return Double(min(max(segmentIndex, 0), count)) / Double(count)
    }

    public var isActive: Bool {
        state == .playing || state == .paused
    }

    // MARK: Loading

    /// Loads a story and rewinds. Any playback in progress is stopped.
    public func load(_ story: Story) {
        haltSpeech()
        self.story = story
        script = story.script
        segmentIndex = 0
        spokenRange = nil
        state = .idle
    }

    // MARK: Transport

    /// Starts from the current segment (from the beginning when finished); resumes when paused.
    public func play() {
        guard let script = script, !script.segments.isEmpty else { return }
        switch state {
        case .playing:
            return
        case .paused:
            resume()
            return
        case .finished:
            segmentIndex = 0
        case .idle:
            break
        }
        if segmentIndex < 0 || segmentIndex >= script.segments.count { segmentIndex = 0 }
        installHookIfNeeded()
        state = .playing
        speakCurrentSegment(playGesture: true)
    }

    public func pause() {
        guard state == .playing else { return }
        haltSpeech()
        state = .paused
    }

    /// Re-speaks the current segment from its start (the gesture is not repeated).
    public func resume() {
        guard state == .paused, currentSegment != nil else { return }
        installHookIfNeeded()
        state = .playing
        speakCurrentSegment(playGesture: false)
    }

    /// Stops speaking, rewinds to the first segment and calms the rig (neutral emotion). The story stays loaded.
    public func stop() {
        haltSpeech()
        segmentIndex = 0
        state = .idle
        rig.set(emotion: .neutral)
    }

    /// Jumps to the next segment (finishes when already on the last one while playing or paused).
    public func skipForward() {
        guard let script = script, !script.segments.isEmpty else { return }
        haltSpeech()
        if segmentIndex + 1 < script.segments.count {
            segmentIndex += 1
            if state == .playing { speakCurrentSegment(playGesture: true) }
        } else if state == .playing || state == .paused {
            finish()
        }
    }

    /// Jumps to the previous segment (restarts the first one when already there).
    public func skipBackward() {
        guard let script = script, !script.segments.isEmpty else { return }
        haltSpeech()
        if state == .finished {
            // Rewinding a finished story leaves it on the last segment, ready to be played again.
            state = .idle
        } else if segmentIndex > 0 {
            segmentIndex -= 1
        }
        if state == .playing { speakCurrentSegment(playGesture: true) }
    }

    /// Stops playback and gives `rig.onSpeechEvent` back to whoever owned it before the player hooked in.
    public func detach() {
        haltSpeech()
        if hooked {
            rig.onSpeechEvent = previousHandler
            previousHandler = nil
            hooked = false
        }
        if state != .idle { state = .idle }
    }

    // MARK: Sequencing

    private func speakCurrentSegment(playGesture: Bool) {
        cancelPendingAdvance()
        spokenRange = nil
        guard let segment = currentSegment else {
            finish()
            return
        }
        if let emotion = segment.emotion {
            rig.set(emotion: emotion)
        }
        if playGesture, let gesture = segment.gesture {
            rig.play(gesture)
        }
        if segment.text.isEmpty {
            speakingSegment = false
            scheduleAdvance(after: segment.pauseAfter)
            return
        }
        // `rig.speak` cancels any utterance in progress first; the resulting `.cancelled` is ignored below
        // because `speakingSegment` is only consulted for events of the utterance we are waiting for.
        speakingSegment = true
        rig.speak(segment.text, language: script?.languageCode)
    }

    private func handleSpeechEvent(_ event: SpeechEvent) {
        guard speakingSegment, state == .playing else { return }
        switch event {
        case .started:
            spokenRange = nil
        case .word(let location, let length, _):
            spokenRange = NSRange(location: location, length: length)
        case .finished:
            speakingSegment = false
            spokenRange = nil
            scheduleAdvance(after: currentSegment?.pauseAfter ?? StoryScript.defaultPauseAfter)
        case .cancelled, .paused, .resumed:
            break
        }
    }

    private func scheduleAdvance(after seconds: TimeInterval) {
        cancelPendingAdvance()
        advanceGeneration &+= 1
        let generation = advanceGeneration
        let delay = min(StoryPlayer.maxPause, max(0, seconds))
        pauseTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self = self, !Task.isCancelled, self.advanceGeneration == generation else { return }
            self.pauseTask = nil
            self.advance()
        }
    }

    private func advance() {
        guard state == .playing, let script = script else { return }
        if segmentIndex + 1 < script.segments.count {
            segmentIndex += 1
            speakCurrentSegment(playGesture: true)
        } else {
            finish()
        }
    }

    private func finish() {
        cancelPendingAdvance()
        speakingSegment = false
        spokenRange = nil
        state = .finished
    }

    /// Cancels the pending advance and stops the utterance this player started (other speech is left alone).
    private func haltSpeech() {
        cancelPendingAdvance()
        spokenRange = nil
        if speakingSegment {
            speakingSegment = false
            rig.stopSpeaking()
        }
    }

    private func cancelPendingAdvance() {
        advanceGeneration &+= 1
        pauseTask?.cancel()
        pauseTask = nil
    }

    private func installHookIfNeeded() {
        guard !hooked else { return }
        hooked = true
        let previous = rig.onSpeechEvent
        previousHandler = previous
        rig.onSpeechEvent = { [weak self] event in
            previous?(event)
            self?.handleSpeechEvent(event)
        }
    }
}
