import Foundation
import Observation

/// Sequences a `Story` through a `CharacterRig`: for every segment it sets the emotion, plays the
/// gesture, speaks the sentence with the rig's built-in TTS, tracks the spoken word for karaoke
/// highlighting, waits `pauseAfter` and moves on.
///
/// Gestures are staged around the sentence so they never fight the lip-sync (the rig adds gesture
/// deltas on top of the speech mouth): most gestures play as the sentence starts; gestures that take
/// over the mouth and eyes (`.yawn`, `.wakeUp`) play first and the narrator starts talking near their
/// end; `.sleep` plays after the sentence has been spoken and the next segment waits for it.
///
/// State machine: `idle → playing ⇄ paused → finished`. `stop()` returns to `idle` and calms the rig.
/// Pause/resume is implemented as "stop speaking + re-speak the current segment" because
/// `AVSpeechSynthesizer` pausing is unreliable across voices. Pausing during the silence after a
/// sentence resumes with the next sentence.
///
/// The player listens through `rig.onSpeechEvent`; the handler that was installed before is saved and
/// still called first, so other observers keep working. Call `detach()` to restore it.
///
/// If somebody else interrupts the narrator (`rig.stopSpeaking()`, `rig.reset()`, another `speak`
/// call) the player switches to `paused` so playback can be resumed. When the speech engine pauses
/// on its own (an audio-session interruption) the player mirrors it as `paused` and returns to
/// `playing` if the engine resumes. A generous watchdog advances the story if the speech engine never
/// reports the end of a sentence.
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
    /// True once the current segment has been spoken completely (it then counts towards `progress`).
    public private(set) var isCurrentSegmentSpoken: Bool = false

    /// The character that narrates.
    public let rig: CharacterRig

    /// Test seam: when set, it is called instead of `rig.speak(_:language:)` so tests never touch audio.
    @ObservationIgnored var speakOverride: ((String, String?) -> Void)? = nil
    /// Test seam: multiplies the gesture lead-in / hold times so tests do not wait for real gesture lengths.
    @ObservationIgnored var gestureTimeScale: Double = 1

    @ObservationIgnored private var pendingTask: Task<Void, Never>? = nil
    @ObservationIgnored private var taskGeneration: Int = 0
    /// True while an utterance started by this player is in progress (also while the engine has paused it).
    @ObservationIgnored private var speakingSegment = false
    /// True while `state == .paused` only because the speech engine reported `.paused` by itself.
    @ObservationIgnored private var pausedBySpeechEngine = false
    /// Segment whose gesture has already been played (so resuming does not repeat it).
    @ObservationIgnored private var gesturePlayedIndex: Int? = nil
    @ObservationIgnored private var hooked = false
    @ObservationIgnored private var previousHandler: ((SpeechEvent) -> Void)? = nil

    /// Longest pause the player will honour between segments.
    private static let maxPause: TimeInterval = 60
    /// Watchdog: seconds allowed for a sentence = base + perCharacter × characters.
    private static let watchdogBase: TimeInterval = 10
    private static let watchdogPerCharacter: TimeInterval = 0.3
    /// Fraction of a lead-in gesture that plays before the narrator starts talking (the mouth/eye deltas
    /// have almost faded by then, so the visemes are not drowned out).
    private static let leadInFraction: Double = 0.9

    private enum PendingAction: Sendable {
        case speak
        case advance
        case watchdog
    }

    /// When a segment's gesture plays relative to its sentence.
    enum GestureStaging: Sendable, Equatable {
        /// Together with the first words (head, arm, body and brow gestures that leave the mouth free).
        case withSpeech
        /// Before the sentence: the gesture takes over the mouth and eyes, so speech starts near its end.
        case leadIn
        /// After the sentence has been spoken; the next segment waits until it has played out.
        case trailing
    }

    static func staging(of gesture: Gesture) -> GestureStaging {
        switch gesture {
        case .yawn, .wakeUp:
            return .leadIn
        case .sleep:
            return .trailing
        default:
            return .withSpeech
        }
    }

    /// Expected length of `gesture` when the rig plays it while showing `emotion`: the rig stretches
    /// gestures for calm emotions (nominal × (1.15 − 0.3 · energy)).
    static func gestureDuration(_ gesture: Gesture, emotion: Emotion) -> TimeInterval {
        let energy = Double(min(max(EmotionProfile.profile(for: emotion).energy, 0), 1))
        return gesture.nominalDuration * (1.15 - 0.3 * energy)
    }

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
        let spoken = min(max(segmentIndex, 0), count) + (isCurrentSegmentSpoken ? 1 : 0)
        return min(1, Double(spoken) / Double(count))
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
        moveTo(0)
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
            moveTo(0)
        case .idle:
            break
        }
        if segmentIndex < 0 || segmentIndex >= script.segments.count { moveTo(0) }
        installHookIfNeeded()
        state = .playing
        speakCurrentSegment()
    }

    public func pause() {
        guard state == .playing else { return }
        haltSpeech()
        state = .paused
    }

    /// Re-speaks the current segment from its start (its gesture is not repeated), or moves on to the next
    /// segment when the pause happened in the silence after a fully spoken sentence.
    public func resume() {
        guard state == .paused, let script = script, !script.segments.isEmpty else { return }
        installHookIfNeeded()
        state = .playing
        if isCurrentSegmentSpoken {
            advance()
        } else {
            speakCurrentSegment()
        }
    }

    /// Stops speaking, clears the playback position (first segment, no highlighted word) and calms the rig
    /// (neutral emotion). The story stays loaded so `play()` starts it again.
    public func stop() {
        haltSpeech()
        moveTo(0)
        state = .idle
        rig.set(emotion: .neutral)
    }

    /// Jumps to the next segment (finishes when already on the last one while playing or paused).
    public func skipForward() {
        guard let script = script, !script.segments.isEmpty else { return }
        haltSpeech()
        if segmentIndex + 1 < script.segments.count {
            moveTo(segmentIndex + 1)
            if state == .playing { speakCurrentSegment() }
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
            moveTo(script.segments.count - 1)
            state = .idle
            return
        }
        moveTo(max(0, segmentIndex - 1))
        if state == .playing { speakCurrentSegment() }
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

    // MARK: Emotion bookkeeping

    /// The emotion in effect at `index`: the segment's own tag, else the closest tag before it, else neutral.
    /// Used so skipping or resuming lands on the right mood even for untagged sentences.
    func effectiveEmotion(at index: Int) -> Emotion {
        let all = segments
        guard !all.isEmpty else { return .neutral }
        var i = min(index, all.count - 1)
        while i >= 0 {
            if let emotion = all[i].emotion { return emotion }
            i -= 1
        }
        return .neutral
    }

    // MARK: Sequencing

    private func moveTo(_ index: Int) {
        segmentIndex = index
        isCurrentSegmentSpoken = false
        gesturePlayedIndex = nil
        spokenRange = nil
    }

    private func speakCurrentSegment() {
        cancelPendingTask()
        speakingSegment = false
        pausedBySpeechEngine = false
        spokenRange = nil
        isCurrentSegmentSpoken = false
        guard let segment = currentSegment else {
            finish()
            return
        }

        let emotion = effectiveEmotion(at: segmentIndex)
        if segment.emotion != nil || rig.emotion != emotion {
            rig.set(emotion: emotion)
        }

        // Seconds to wait before speaking (a lead-in gesture that has just been started).
        var leadIn: TimeInterval = 0
        if let gesture = segment.gesture, gesturePlayedIndex != segmentIndex {
            switch StoryPlayer.staging(of: gesture) {
            case .withSpeech:
                rig.play(gesture)
                gesturePlayedIndex = segmentIndex
            case .leadIn:
                rig.play(gesture)
                gesturePlayedIndex = segmentIndex
                let duration = StoryPlayer.gestureDuration(gesture, emotion: emotion) * max(0, gestureTimeScale)
                leadIn = StoryPlayer.leadInFraction * duration
            case .trailing:
                // Played by `segmentDidFinish` once the sentence has been said.
                break
            }
        }

        if segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segmentDidFinish()
            return
        }

        if leadIn > 0 {
            // The watchdog is armed only when speech actually starts; pause/skip/stop cancel this task,
            // and a resume re-enters here with the gesture already marked as played.
            schedule(.speak, after: leadIn)
        } else {
            startSpeaking()
        }
    }

    /// Hands the current sentence to the speech engine and arms the watchdog.
    private func startSpeaking() {
        guard state == .playing, let segment = currentSegment else { return }
        // `rig.speak` cancels any utterance in progress first and reports that `.cancelled` synchronously.
        // `speakingSegment` is still false at that moment, so the event is ignored; it becomes true only
        // for the events of the utterance started here (the driver drops stale callbacks of older ones).
        speakingSegment = false
        let language = script?.languageCode
        if let override = speakOverride {
            override(segment.text, language)
        } else {
            rig.speak(segment.text, language: language)
        }
        speakingSegment = true
        armWatchdog(for: segment)
    }

    private func armWatchdog(for segment: StorySegment) {
        let timeout = StoryPlayer.watchdogBase + StoryPlayer.watchdogPerCharacter * TimeInterval(segment.text.count)
        schedule(.watchdog, after: timeout)
    }

    private func handleSpeechEvent(_ event: SpeechEvent) {
        guard speakingSegment else { return }
        switch event {
        case .started:
            guard state == .playing else { return }
            spokenRange = nil
        case .word(let location, let length, _):
            guard state == .playing else { return }
            let limit = currentSegment?.text.utf16.count ?? 0
            if location >= 0, length > 0, location + length <= limit {
                spokenRange = NSRange(location: location, length: length)
            }
        case .finished:
            guard state == .playing else { return }
            segmentDidFinish()
        case .cancelled:
            // Our own stops clear `speakingSegment` before calling the rig, so this cancel came from
            // somebody else. Keep the position and let the user resume.
            speakingSegment = false
            pausedBySpeechEngine = false
            cancelPendingTask()
            spokenRange = nil
            if state == .playing { state = .paused }
        case .paused:
            // The engine paused by itself (e.g. an audio-session interruption). Mirror it so the UI shows
            // Paused and the watchdog cannot skip the interrupted sentence.
            guard state == .playing else { return }
            cancelPendingTask()
            pausedBySpeechEngine = true
            state = .paused
        case .resumed:
            guard state == .paused, pausedBySpeechEngine else { return }
            pausedBySpeechEngine = false
            state = .playing
            if let segment = currentSegment { armWatchdog(for: segment) }
        }
    }

    /// The current sentence has been spoken: count it, play a trailing gesture, then wait `pauseAfter`
    /// (or until the trailing gesture has played out, whichever is longer) before the next one.
    private func segmentDidFinish() {
        speakingSegment = false
        pausedBySpeechEngine = false
        spokenRange = nil
        isCurrentSegmentSpoken = true
        let pause = currentSegment?.pauseAfter ?? StoryScript.defaultPauseAfter
        var wait = min(StoryPlayer.maxPause, max(0, pause))
        if let gesture = currentSegment?.gesture, gesturePlayedIndex != segmentIndex,
           StoryPlayer.staging(of: gesture) == .trailing {
            rig.play(gesture)
            gesturePlayedIndex = segmentIndex
            let hold = StoryPlayer.gestureDuration(gesture, emotion: rig.emotion) * max(0, gestureTimeScale)
            wait = max(wait, hold)
        }
        schedule(.advance, after: wait)
    }

    /// The speech engine never reported the end of the sentence: stop it and carry on.
    private func speechTimedOut() {
        guard state == .playing, speakingSegment else { return }
        speakingSegment = false
        rig.stopSpeaking()
        segmentDidFinish()
    }

    private func advance() {
        guard state == .playing, let script = script else { return }
        if segmentIndex + 1 < script.segments.count {
            moveTo(segmentIndex + 1)
            speakCurrentSegment()
        } else {
            finish()
        }
    }

    private func finish() {
        cancelPendingTask()
        speakingSegment = false
        pausedBySpeechEngine = false
        spokenRange = nil
        isCurrentSegmentSpoken = true
        state = .finished
    }

    /// Cancels the pending task and stops the utterance this player started (other speech is left alone).
    private func haltSpeech() {
        cancelPendingTask()
        spokenRange = nil
        pausedBySpeechEngine = false
        if speakingSegment {
            speakingSegment = false
            rig.stopSpeaking()
        }
    }

    private func schedule(_ action: PendingAction, after seconds: TimeInterval) {
        cancelPendingTask()
        let generation = taskGeneration
        let delay = max(0, seconds)
        pendingTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self = self, !Task.isCancelled, self.taskGeneration == generation else { return }
            self.pendingTask = nil
            switch action {
            case .speak:
                self.startSpeaking()
            case .advance:
                self.advance()
            case .watchdog:
                self.speechTimedOut()
            }
        }
    }

    private func cancelPendingTask() {
        taskGeneration &+= 1
        pendingTask?.cancel()
        pendingTask = nil
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
