import Foundation
import AVFoundation
import QuartzCore
import os

/// On-device TTS with word-aligned lip-sync.
///
/// Owns an `AVSpeechSynthesizer`, a `LipSyncMixer` and a nonisolated delegate proxy that hops every callback to
/// the main actor. On `willSpeakRangeOfSpeechString` the word's visemes are estimated and scheduled from the
/// callback time by `SpeechWordTimer` (adaptive seconds-per-character, EMA of the measured inter-word intervals
/// excluding punctuation pauses); the mixer clips the previous word to the measured gap when the next word arrives.
/// The `AVAudioSession` is shared by all drivers through `SpeechAudioSession`: each driver holds it from `speak`
/// until its utterance ends (or the driver is deallocated), and the session is deactivated shortly after the last
/// holder lets go.
@MainActor
public final class SpeechSynthesisDriver: NSObject, LipSyncSource {

    /// Speech progress for karaoke highlighting and story sequencing. Called on the main actor.
    /// `.word` ranges index the exact string passed to `speak` (UTF-16, NSRange semantics).
    public var onEvent: ((SpeechEvent) -> Void)?
    /// True from `speak` until `finished`/`cancelled`.
    public private(set) var isSpeaking: Bool = false
    /// True while paused with `pause()`.
    public private(set) var isPaused: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private let mixer = LipSyncMixer()
    private var proxy: SpeechDelegateProxy?

    private var text: String = ""
    private var languageCode: String = "en"
    private var currentUtteranceID: ObjectIdentifier?
    /// Strong reference to the utterance named by `currentUtteranceID`. Callbacks cross to the main actor as a bare
    /// `ObjectIdentifier`; keeping the utterance alive guarantees no other utterance can share its address meanwhile.
    private var currentUtterance: AVSpeechUtterance?
    /// Stopped utterances whose terminal delegate callback (`didCancel`/`didFinish`) has not been handled yet. They are
    /// kept alive so a new utterance cannot be allocated at their address and match their in-flight callbacks.
    private var retiredUtterances: [AVSpeechUtterance] = []
    private var timer = SpeechWordTimer()
    /// `pause()` was called but the synthesizer has not confirmed it yet (it pauses at the next word boundary).
    private var pauseRequested = false
    /// `resume()` arrived while a pause was still pending: continue as soon as the pause is confirmed.
    private var resumeAfterPause = false
    /// The pending pause was undone internally; swallow the matching `didContinue`.
    private var suppressResumeEvent = false
    /// Whether this driver holds one reference on the shared `SpeechAudioSession`. A Sendable `let`, so `deinit`
    /// can return the hold of a driver that is deallocated mid-utterance.
    private let audioSessionHold = OSAllocatedUnfairLock(initialState: false)
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    /// Bound on `retiredUtterances` in case the synthesizer never reports the end of a stopped utterance.
    private static let maxRetiredUtterances = 8

    public override init() {
        super.init()
        let proxy = SpeechDelegateProxy(owner: self)
        self.proxy = proxy
        synthesizer.delegate = proxy
    }

    deinit {
        // The synthesizer goes away with the driver, so its speech ends here. Return the session hold so the shared
        // coordinator can schedule the deactivation this driver can no longer perform.
        let heldSession = audioSessionHold.withLock { (flag: inout Bool) -> Bool in
            let previous = flag
            flag = false
            return previous
        }
        if heldSession {
            Task { @MainActor in
                SpeechAudioSession.release()
            }
        }
    }

    // MARK: Control

    /// Speaks `text`; an utterance already in progress is cancelled first.
    public func speak(_ text: String, languageCode: String, voice: VoiceStyle, prosody: Prosody) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep the session hold across the hand-over from the cancelled utterance to the new one, so it is not
        // released and re-acquired for every sentence.
        cancelCurrentUtterance(releasingAudioSession: trimmed.isEmpty)
        guard !trimmed.isEmpty else { return }

        acquireAudioSession()

        // Speak the caller's string unchanged so `.word` ranges index it directly.
        let utterance = AVSpeechUtterance(string: text)
        let resolvedLanguage = languageCode.isEmpty ? TextVisemeEstimator.detectLanguage(of: trimmed) : languageCode
        utterance.voice = selectVoice(languageCode: resolvedLanguage, voice: voice)

        let rateMultiplier = max(0.1, voice.rate * prosody.rate)
        let rawRate = AVSpeechUtteranceDefaultSpeechRate * rateMultiplier
        let rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, rawRate))
        utterance.rate = rate
        utterance.pitchMultiplier = min(2.0, max(0.5, voice.pitch * prosody.pitch))
        utterance.volume = min(1, max(0, prosody.volume))
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0

        self.text = text
        self.languageCode = resolvedLanguage
        timer.begin(languageCode: resolvedLanguage,
                    effectiveRate: TimeInterval(rate / AVSpeechUtteranceDefaultSpeechRate))
        currentUtteranceID = ObjectIdentifier(utterance)
        currentUtterance = utterance
        isSpeaking = true
        isPaused = false
        pauseRequested = false
        resumeAfterPause = false
        suppressResumeEvent = false
        mixer.clear()
        synthesizer.speak(utterance)
    }

    /// Stops immediately; emits `.cancelled` if an utterance was in progress.
    public func stop() {
        cancelCurrentUtterance(releasingAudioSession: true)
    }

    /// Stops the current utterance (emitting `.cancelled` if there was one). `speak` passes
    /// `releasingAudioSession: false` because it takes over the hold for the next utterance.
    private func cancelCurrentUtterance(releasingAudioSession: Bool) {
        let wasSpeaking = currentUtteranceID != nil
        // Unconditional: the synthesizer queues work asynchronously and may not report `isSpeaking` yet.
        _ = synthesizer.stopSpeaking(at: .immediate)
        if let utterance = currentUtterance {
            retire(utterance)
        }
        if wasSpeaking {
            finish(with: .cancelled, releasingAudioSession: releasingAudioSession)
        } else {
            mixer.clear()
            isSpeaking = false
            isPaused = false
            pauseRequested = false
            resumeAfterPause = false
            suppressResumeEvent = false
            if releasingAudioSession {
                releaseAudioSession()
            }
        }
    }

    /// Pauses at the end of the current word.
    public func pause() {
        guard currentUtteranceID != nil, !isPaused else { return }
        if pauseRequested {
            // A pause is already on its way; cancel a queued resume instead of pausing twice.
            resumeAfterPause = false
            return
        }
        pauseRequested = synthesizer.pauseSpeaking(at: .word)
        resumeAfterPause = false
    }

    public func resume() {
        guard currentUtteranceID != nil else { return }
        if isPaused {
            _ = synthesizer.continueSpeaking()
        } else if pauseRequested {
            // The word-boundary pause has not happened yet: undo it as soon as it does.
            resumeAfterPause = true
        }
    }

    public func sample(at time: TimeInterval) -> LipSyncSample {
        var sample = mixer.sample(at: time)
        if isSpeaking && !isPaused {
            sample.isSpeaking = true
        }
        return sample
    }

    // MARK: Delegate handling (main actor)

    func handleDidStart(_ id: ObjectIdentifier) {
        guard id == currentUtteranceID else { return }
        isSpeaking = true
        isPaused = false
        onEvent?(.started(text: text))
    }

    func handleWillSpeak(location: Int, length: Int, utteranceID: ObjectIdentifier, at now: TimeInterval) {
        guard utteranceID == currentUtteranceID else { return }
        guard let word = timer.handleWord(in: text as NSString, location: location, length: length,
                                          languageCode: languageCode, at: now, mixer: mixer) else { return }
        onEvent?(.word(location: location, length: length, text: word))
    }

    func handleDidPause(_ id: ObjectIdentifier) {
        guard id == currentUtteranceID else { return }
        pauseRequested = false
        if resumeAfterPause {
            resumeAfterPause = false
            suppressResumeEvent = true
            timer.resetAnchor()
            _ = synthesizer.continueSpeaking()
            return
        }
        isPaused = true
        mixer.clear()
        onEvent?(.paused)
    }

    func handleDidContinue(_ id: ObjectIdentifier) {
        guard id == currentUtteranceID else { return }
        // `pauseRequested`/`resumeAfterPause` are left alone: they can only belong to a newer `pause()` call.
        isPaused = false
        timer.resetAnchor()
        if suppressResumeEvent {
            suppressResumeEvent = false
            return
        }
        onEvent?(.resumed)
    }

    func handleDidFinish(_ id: ObjectIdentifier) {
        guard id == currentUtteranceID else {
            releaseRetired(id)
            return
        }
        finish(with: .finished)
    }

    func handleDidCancel(_ id: ObjectIdentifier) {
        guard id == currentUtteranceID else {
            releaseRetired(id)
            return
        }
        finish(with: .cancelled)
    }

    private func finish(with event: SpeechEvent, releasingAudioSession: Bool = true) {
        currentUtteranceID = nil
        currentUtterance = nil
        timer.resetAnchor()
        mixer.clear()
        isSpeaking = false
        isPaused = false
        pauseRequested = false
        resumeAfterPause = false
        suppressResumeEvent = false
        if releasingAudioSession {
            releaseAudioSession()
        }
        onEvent?(event)
    }

    /// Keeps a stopped utterance alive until its terminal callback arrives (see `retiredUtterances`).
    private func retire(_ utterance: AVSpeechUtterance) {
        if retiredUtterances.count >= SpeechSynthesisDriver.maxRetiredUtterances {
            retiredUtterances.removeFirst()
        }
        retiredUtterances.append(utterance)
    }

    /// Drops a retired utterance once its terminal callback has been handled. Sound because every retired
    /// utterance is still alive, so no other object can carry the same `ObjectIdentifier`.
    private func releaseRetired(_ id: ObjectIdentifier) {
        if let index = retiredUtterances.firstIndex(where: { ObjectIdentifier($0) == id }) {
            retiredUtterances.remove(at: index)
        }
    }

    // MARK: Voice selection

    /// First preferred identifier whose language matches, else the best installed voice for the language
    /// (premium/enhanced first; novelty and Personal Voice entries are skipped). When only default-quality voices
    /// exist, the system's default voice for the language (the one chosen in Settings) is used.
    private func selectVoice(languageCode: String, voice: VoiceStyle) -> AVSpeechSynthesisVoice? {
        let bcp47 = SpeechSynthesisDriver.bcp47(for: languageCode)
        let language = SpeechSynthesisDriver.baseLanguage(of: bcp47)
        for identifier in voice.preferredVoiceIdentifiers {
            if let found = AVSpeechSynthesisVoice(identifier: identifier),
               SpeechSynthesisDriver.baseLanguage(of: found.language) == language {
                return found
            }
        }
        if let cached = voiceCache[bcp47] {
            return cached
        }
        let region = bcp47.lowercased()
        var best: AVSpeechSynthesisVoice?
        var bestScore = Int.min
        for candidate in AVSpeechSynthesisVoice.speechVoices() {
            guard SpeechSynthesisDriver.baseLanguage(of: candidate.language) == language else { continue }
            let traits = candidate.voiceTraits
            if traits.contains(.isNoveltyVoice) || traits.contains(.isPersonalVoice) { continue }
            var score = candidate.quality.rawValue * 10
            if candidate.language.lowercased() == region { score += 1 }
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        let chosen: AVSpeechSynthesisVoice?
        if let best = best, best.quality != .default {
            chosen = best
        } else {
            chosen = AVSpeechSynthesisVoice(language: bcp47) ?? best
        }
        if let chosen = chosen {
            voiceCache[bcp47] = chosen
        }
        return chosen
    }

    /// "en-US" → "en", "ru_RU" → "ru", "RU" → "ru".
    static func baseLanguage(of code: String) -> String {
        let normalized = code.lowercased().replacingOccurrences(of: "_", with: "-")
        if let dash = normalized.firstIndex(of: "-") {
            return String(normalized[..<dash])
        }
        return normalized
    }

    /// Maps a bare language code to the region-qualified identifier `AVSpeechSynthesisVoice(language:)` expects.
    static func bcp47(for languageCode: String) -> String {
        if languageCode.contains("-") || languageCode.contains("_") {
            return languageCode.replacingOccurrences(of: "_", with: "-")
        }
        switch languageCode.lowercased() {
        case "ru": return "ru-RU"
        case "en": return "en-US"
        case "uk": return "uk-UA"
        case "de": return "de-DE"
        case "fr": return "fr-FR"
        case "es": return "es-ES"
        case "it": return "it-IT"
        case "pt": return "pt-BR"
        case "pl": return "pl-PL"
        case "tr": return "tr-TR"
        case "ja": return "ja-JP"
        case "zh": return "zh-CN"
        case "ko": return "ko-KR"
        default: return languageCode
        }
    }

    // MARK: Audio session

    /// Takes this driver's hold on the shared session (at most one per driver).
    private func acquireAudioSession() {
        let alreadyHeld = audioSessionHold.withLock { (flag: inout Bool) -> Bool in
            let previous = flag
            flag = true
            return previous
        }
        if !alreadyHeld {
            SpeechAudioSession.acquire()
        }
    }

    /// Returns this driver's hold; the coordinator deactivates the session a little later once nobody holds it.
    private func releaseAudioSession() {
        let wasHeld = audioSessionHold.withLock { (flag: inout Bool) -> Bool in
            let previous = flag
            flag = false
            return previous
        }
        if wasHeld {
            SpeechAudioSession.release()
        }
    }
}

// MARK: - Delegate proxy

/// Receives `AVSpeechSynthesizerDelegate` callbacks on whatever thread the synthesizer uses and forwards
/// them to the main-actor driver. Only Sendable values (ids, ints, timestamps) cross the hop.
private final class SpeechDelegateProxy: NSObject, AVSpeechSynthesizerDelegate {
    weak var owner: SpeechSynthesisDriver?

    init(owner: SpeechSynthesisDriver) {
        self.owner = owner
        super.init()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let owner = self.owner
        Task { @MainActor in
            owner?.handleDidStart(id)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let now = CACurrentMediaTime()
        let id = ObjectIdentifier(utterance)
        let location = characterRange.location
        let length = characterRange.length
        let owner = self.owner
        Task { @MainActor in
            owner?.handleWillSpeak(location: location, length: length, utteranceID: id, at: now)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let owner = self.owner
        Task { @MainActor in
            owner?.handleDidPause(id)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let owner = self.owner
        Task { @MainActor in
            owner?.handleDidContinue(id)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let owner = self.owner
        Task { @MainActor in
            owner?.handleDidFinish(id)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let owner = self.owner
        Task { @MainActor in
            owner?.handleDidCancel(id)
        }
    }
}
