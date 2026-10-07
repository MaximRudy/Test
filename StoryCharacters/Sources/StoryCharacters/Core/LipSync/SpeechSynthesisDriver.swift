import Foundation
import AVFoundation
import QuartzCore

/// On-device TTS with word-aligned lip-sync.
///
/// Owns an `AVSpeechSynthesizer`, a `LipSyncMixer` and a nonisolated delegate proxy that hops every callback to
/// the main actor. On `willSpeakRangeOfSpeechString` the word's visemes are estimated and scheduled from the
/// callback time with an adaptive seconds-per-character estimate (EMA of the measured inter-word intervals);
/// the mixer clips the previous word to the measured gap when the next word arrives.
@MainActor
public final class SpeechSynthesisDriver: NSObject, LipSyncSource {

    /// Speech progress for karaoke highlighting and story sequencing. Called on the main actor.
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
    private var secondsPerCharacter: TimeInterval = 0.07
    private var lastWordStart: TimeInterval?
    private var lastWordLength: Int = 0
    private var sessionActive = false
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    /// EMA weight of a newly measured seconds-per-character value.
    private static let adaptationRate: TimeInterval = 0.35
    /// Scheduling lead: words are scheduled slightly after the callback to match audio output latency.
    private static let schedulingLatency: TimeInterval = 0.01

    public override init() {
        super.init()
        let proxy = SpeechDelegateProxy(owner: self)
        self.proxy = proxy
        synthesizer.delegate = proxy
    }

    // MARK: Control

    /// Speaks `text`; an utterance already in progress is cancelled first.
    public func speak(_ text: String, languageCode: String, voice: VoiceStyle, prosody: Prosody) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stop()
        guard !trimmed.isEmpty else { return }

        activateSessionIfNeeded()

        let utterance = AVSpeechUtterance(string: trimmed)
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

        self.text = trimmed
        self.languageCode = resolvedLanguage
        let effectiveRate = TimeInterval(rate / AVSpeechUtteranceDefaultSpeechRate)
        let base: TimeInterval = TextVisemeEstimator.isRussian(resolvedLanguage) ? 0.075 : 0.065
        secondsPerCharacter = base / max(0.2, effectiveRate)
        lastWordStart = nil
        lastWordLength = 0
        currentUtteranceID = ObjectIdentifier(utterance)
        isSpeaking = true
        isPaused = false
        mixer.clear()
        synthesizer.speak(utterance)
    }

    /// Stops immediately; emits `.cancelled` if an utterance was in progress.
    public func stop() {
        let wasSpeaking = currentUtteranceID != nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            _ = synthesizer.stopSpeaking(at: .immediate)
        }
        if wasSpeaking {
            finish(with: .cancelled)
        } else {
            mixer.clear()
            isSpeaking = false
            isPaused = false
        }
    }

    public func pause() {
        guard currentUtteranceID != nil, !isPaused else { return }
        _ = synthesizer.pauseSpeaking(at: .word)
    }

    public func resume() {
        guard currentUtteranceID != nil, isPaused else { return }
        _ = synthesizer.continueSpeaking()
    }

    public func sample(at time: TimeInterval) -> LipSyncSample {
        var sample = mixer.sample(at: time)
        if isSpeaking && !isPaused {
            sample.isSpeaking = true
        }
        return sample
    }

    // MARK: Delegate handling (main actor)

    fileprivate func handleDidStart(_ id: ObjectIdentifier) {
        guard id == currentUtteranceID else { return }
        isSpeaking = true
        isPaused = false
        onEvent?(.started(text: text))
    }

    fileprivate func handleWillSpeak(location: Int, length: Int, utteranceID: ObjectIdentifier, at now: TimeInterval) {
        guard utteranceID == currentUtteranceID, length > 0 else { return }
        let nsText = text as NSString
        guard location >= 0, location + length <= nsText.length else { return }
        let range = NSRange(location: location, length: length)
        let word = nsText.substring(with: range)

        // Adaptive seconds-per-character from the measured gap since the previous word.
        if let previousStart = lastWordStart, lastWordLength > 0 {
            let gap = now - previousStart
            if gap > 0.02 && gap < 3 {
                let observed = gap / TimeInterval(lastWordLength + 1)
                let bounded = min(0.25, max(0.025, observed))
                secondsPerCharacter = secondsPerCharacter * (1 - SpeechSynthesisDriver.adaptationRate)
                    + bounded * SpeechSynthesisDriver.adaptationRate
            }
        }
        lastWordStart = now
        lastWordLength = length

        // Punctuation right after the word: sentence end closes the mouth, a question emphasises the brows.
        var endsSentence = false
        var isQuestion = false
        var scan = location + length
        while scan < nsText.length {
            let code = nsText.character(at: scan)
            guard let scalar = Unicode.Scalar(code) else { break }
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                break
            }
            switch code {
            case 0x3F: isQuestion = true; endsSentence = true      // ?
            case 0x2E, 0x21, 0x2026: endsSentence = true           // . ! …
            default: break
            }
            scan += 1
        }

        let keyframes = TextVisemeEstimator.visemes(forWord: word, languageCode: languageCode)
        if !keyframes.isEmpty {
            var track = LipSyncTrack(keyframes: keyframes)
            // Slight over-estimate: the next word's callback clips it to the real gap.
            let estimated = max(0.06, TimeInterval(length) * secondsPerCharacter * 1.1)
            track = track.retimed(toDuration: estimated)
            if endsSentence {
                track = track.appendingSilence(0.12)
            }
            mixer.schedule(track, startingAt: now + SpeechSynthesisDriver.schedulingLatency, energyGain: isQuestion ? 1.35 : 1)
        }
        onEvent?(.word(location: location, length: length, text: word))
    }

    fileprivate func handleDidPause(_ id: ObjectIdentifier) {
        guard id == currentUtteranceID else { return }
        isPaused = true
        mixer.clear()
        onEvent?(.paused)
    }

    fileprivate func handleDidContinue(_ id: ObjectIdentifier) {
        guard id == currentUtteranceID else { return }
        isPaused = false
        lastWordStart = nil
        onEvent?(.resumed)
    }

    fileprivate func handleDidFinish(_ id: ObjectIdentifier) {
        guard id == currentUtteranceID else { return }
        finish(with: .finished)
    }

    fileprivate func handleDidCancel(_ id: ObjectIdentifier) {
        guard id == currentUtteranceID else { return }
        finish(with: .cancelled)
    }

    private func finish(with event: SpeechEvent) {
        currentUtteranceID = nil
        lastWordStart = nil
        lastWordLength = 0
        mixer.clear()
        isSpeaking = false
        isPaused = false
        deactivateSession()
        onEvent?(event)
    }

    // MARK: Voice selection

    private func selectVoice(languageCode: String, voice: VoiceStyle) -> AVSpeechSynthesisVoice? {
        for identifier in voice.preferredVoiceIdentifiers {
            if let found = AVSpeechSynthesisVoice(identifier: identifier) {
                return found
            }
        }
        let bcp47 = SpeechSynthesisDriver.bcp47(for: languageCode)
        if let cached = voiceCache[bcp47] {
            return cached
        }
        let prefix = String(languageCode.lowercased().prefix(2))
        var best: AVSpeechSynthesisVoice?
        var bestScore = Int.min
        for candidate in AVSpeechSynthesisVoice.speechVoices() {
            let candidateLanguage = candidate.language.lowercased()
            guard candidateLanguage.hasPrefix(prefix) else { continue }
            var score = candidate.quality.rawValue * 10
            if candidateLanguage == bcp47.lowercased() { score += 1 }
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        let chosen = best ?? AVSpeechSynthesisVoice(language: bcp47)
        if let chosen = chosen {
            voiceCache[bcp47] = chosen
        }
        return chosen
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

    private func activateSessionIfNeeded() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            sessionActive = true
        } catch {
            sessionActive = false
        }
        #endif
    }

    private func deactivateSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        guard sessionActive else { return }
        sessionActive = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Another player may own the session; nothing to do.
        }
        #endif
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
