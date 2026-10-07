import Foundation
import CoreGraphics
import Observation
import simd

/// The animated character: emotion springs, idle life, gaze, blinks, lip-sync and gestures,
/// composed once per frame into a `CharacterPose` for the renderers.
///
/// Observable properties change rarely (emotion, speaking flag, active gesture). Every per-frame
/// field is `@ObservationIgnored` so `pose(at:)` never invalidates SwiftUI views.
@MainActor @Observable public final class CharacterRig {
    public let design: CharacterDesign
    public var configuration: RigConfiguration
    public private(set) var emotion: Emotion = .neutral
    public private(set) var emotionIntensity: Float = 1
    public private(set) var isSpeaking: Bool = false
    public private(set) var activeGesture: Gesture? = nil
    /// Normalized look target in [-1, 1]² (x right, y up) relative to the view; nil = autonomous gaze.
    public var lookTarget: SIMD2<Float>? = nil
    public var onSpeechEvent: ((SpeechEvent) -> Void)? = nil
    /// Last evaluated pose. `@ObservationIgnored` so per-frame updates do not invalidate SwiftUI views.
    @ObservationIgnored public private(set) var currentPose: CharacterPose = .neutral

    // MARK: Per-frame state (never observed)

    @ObservationIgnored private var profile: EmotionProfile = .neutral
    @ObservationIgnored private var currentEmotion: Emotion = .neutral
    @ObservationIgnored private var faceSpring = Spring<FacePose>(value: .neutral, stiffness: RigTuning.faceStiffness)
    @ObservationIgnored private var bodySpring = Spring<BodyPose>(value: .neutral, stiffness: RigTuning.bodyStiffness)
    @ObservationIgnored private var effectsSpring = Spring<EffectsPose>(value: .neutral, stiffness: RigTuning.effectsStiffness)
    @ObservationIgnored private var blink = BlinkController()
    @ObservationIgnored private var gaze = GazeController()
    @ObservationIgnored private var idle = IdleMotion()
    @ObservationIgnored private var gestures = GesturePlayer()
    @ObservationIgnored private var speech = SpeechAnimator()
    @ObservationIgnored private var lastTime: TimeInterval = 0
    @ObservationIgnored private var hasTime = false
    @ObservationIgnored private var localTime: Float = 0
    @ObservationIgnored private var externalLipSync: LipSyncSource? = nil
    @ObservationIgnored private var speechDriver: SpeechSynthesisDriver? = nil
    @ObservationIgnored private var pokeBurst: Float = 0
    /// True between `speak(_:)` and the driver's first `.started`/`.finished`/`.cancelled` event.
    @ObservationIgnored private var speechPending = false
    /// True after `stopSpeaking()` until the next `.started` event, so a late `didCancel` cannot re-open the mouth.
    @ObservationIgnored private var ignoringDriver = false
    @ObservationIgnored private var pokeCounter: Int = 0
    @ObservationIgnored private var autoSleeping = false
    /// Test hook: disables autonomous blinking so smoothness tests see only springs and idle motion.
    @ObservationIgnored var isBlinkingEnabled = true

    // MARK: Init

    public init(design: CharacterDesign, configuration: RigConfiguration = RigConfiguration()) {
        self.design = design
        self.configuration = configuration
        let seed = design.kind.rawValue.utf8.reduce(UInt64(17)) { ($0 &* 31) &+ UInt64($1) }
        blink = BlinkController(seed: seed &+ 1)
        gaze = GazeController(seed: seed &+ 2)
        idle = IdleMotion(seed: seed &+ 3)
        applyEmotion(.neutral, intensity: 1)
        faceSpring.snap(to: profile.face)
        bodySpring.snap(to: profile.body)
        effectsSpring.snap(to: profile.effects)
        currentPose = CharacterPose(face: profile.face, body: profile.body, effects: profile.effects, time: 0)
    }

    public convenience init(kind: CharacterKind, configuration: RigConfiguration = RigConfiguration()) {
        self.init(design: CharacterCatalog.design(for: kind), configuration: configuration)
    }

    // MARK: Emotions

    public func set(emotion: Emotion, intensity: Float = 1) {
        noteInteraction()
        applyEmotion(emotion, intensity: RigCurves.clamp(intensity, 0, 1))
    }

    private func applyEmotion(_ newEmotion: Emotion, intensity: Float) {
        if self.emotion != newEmotion { self.emotion = newEmotion }
        if emotionIntensity != intensity { emotionIntensity = intensity }
        currentEmotion = newEmotion
        var p = EmotionProfile.profile(for: newEmotion, intensity: intensity)
        applySignature(&p, emotion: newEmotion, intensity: intensity)
        profile = p
        let s = max(0.2, p.transitionStiffness)
        faceSpring.setStiffness(RigTuning.faceStiffness * s, dampingRatio: 0.9)
        bodySpring.setStiffness(RigTuning.bodyStiffness * s, dampingRatio: 0.8)
        effectsSpring.setStiffness(RigTuning.effectsStiffness * s, dampingRatio: 1)
        if newEmotion == .surprised { blink.suppress(for: 1.2) }
    }

    /// Per-character signature tweaks (docs/CONTRACT.md §5) and the design's ambient sparkle rate.
    private func applySignature(_ p: inout EmotionProfile, emotion: Emotion, intensity: Float) {
        p.effects.sparkleRate = RigCurves.clamp(p.effects.sparkleRate * (design.sparkleRate / 0.35), 0, 1)
        let k = intensity
        switch design.kind {
        case .lumi:
            if emotion == .excited { p.body.glow = RigCurves.lerp(1, 1.6, k) }
            if emotion == .thinking { p.body.accessory2 = RigCurves.lerp(0.3, 1.0, k) }
        case .spark:
            if emotion == .thinking { p.body.accessory = 1; p.body.glow = RigCurves.lerp(1, 1.15, k) }
        case .nox:
            p.body.accessory = RigCurves.clamp(0.3 + 0.7 * emotion.arousal, 0, 1)
            if emotion == .sleepy { p.body.glow = RigCurves.lerp(1, 0.5, k); p.face.pupil = RigCurves.lerp(1, 0.9, k) }
        case .lumie:
            if emotion == .happy || emotion == .love { p.body.accessory = 1 }
            if emotion == .scared {
                p.body.scaleX = RigCurves.lerp(1, 0.85, k)
                p.body.scaleY = RigCurves.lerp(1, 0.85, k)
            }
        case .ember, .drop, .puff, .sprout:
            break
        }
    }

    // MARK: Gestures

    public func play(_ gesture: Gesture) {
        noteInteraction()
        let clip = GestureClip(gesture: gesture, energy: profile.energy)
        gestures.play(clip, at: localTime)
        if activeGesture != gesture { activeGesture = gesture }
    }

    public func cancelGesture() {
        gestures.cancel(at: localTime)
        if activeGesture != nil { activeGesture = nil }
    }

    // MARK: Speech

    /// Replaces the built-in speech driver as the mouth source while non-nil (e.g. AudioLevelDriver for server TTS).
    public func attach(lipSync: LipSyncSource?) {
        externalLipSync = lipSync
        if lipSync == nil {
            let driving = !ignoringDriver && ((speechDriver?.isSpeaking ?? false) || speechPending)
            if isSpeaking != driving { isSpeaking = driving }
        }
    }

    /// Speaks with the built-in `SpeechSynthesisDriver` using the design's `VoiceStyle` and the current emotion's `Prosody`.
    public func speak(_ text: String, language: String? = nil) {
        noteInteraction()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let code = resolveLanguage(language, for: text)
        let driver = makeDriverIfNeeded()
        speechPending = true
        ignoringDriver = false
        driver.speak(text, languageCode: code, voice: design.voice, prosody: profile.prosody)
        if externalLipSync == nil && !isSpeaking { isSpeaking = true }
    }

    public func stopSpeaking() {
        speechPending = false
        ignoringDriver = true
        speechDriver?.stop()
        if externalLipSync == nil && isSpeaking { isSpeaking = false }
    }

    private func resolveLanguage(_ explicit: String?, for text: String) -> String {
        if let e = explicit, !e.isEmpty { return CharacterRig.expandLanguageCode(e) }
        if let c = configuration.speechLanguage, !c.isEmpty { return CharacterRig.expandLanguageCode(c) }
        return CharacterRig.expandLanguageCode(TextVisemeEstimator.detectLanguage(of: text))
    }

    /// "ru" → "ru-RU", "en" → "en-US"; full BCP-47 codes pass through.
    static func expandLanguageCode(_ code: String) -> String {
        switch code.lowercased() {
        case "ru": return "ru-RU"
        case "en": return "en-US"
        default: return code
        }
    }

    private func makeDriverIfNeeded() -> SpeechSynthesisDriver {
        if let existing = speechDriver { return existing }
        let driver = SpeechSynthesisDriver()
        driver.onEvent = { [weak self] event in
            self?.handleSpeechEvent(event)
        }
        speechDriver = driver
        return driver
    }

    private func handleSpeechEvent(_ event: SpeechEvent) {
        switch event {
        case .started:
            speechPending = false
            ignoringDriver = false
            if externalLipSync == nil && !isSpeaking { isSpeaking = true }
        case .finished, .cancelled:
            speechPending = false
            if externalLipSync == nil && isSpeaking { isSpeaking = false }
        case .word, .paused, .resumed:
            break
        }
        onSpeechEvent?(event)
    }

    // MARK: Interaction

    /// Tap reaction chosen by personality (surprisePop / giggle / shy / wink) plus a sparkle burst.
    public func poke() {
        noteInteraction()
        let personality = design.personality
        pokeCounter += 1
        let gesture: Gesture
        if personality.playfulness >= 0.6 {
            gesture = pokeCounter % 2 == 0 ? .wink : .giggle
        } else if personality.shyness >= 0.4 {
            gesture = .shy
        } else {
            gesture = .surprisePop
        }
        play(gesture)
        pokeBurst = 1
    }

    /// Converts a view point into `lookTarget` using `CanonicalSpace` (view y down → canonical y up).
    public func lookAt(viewPoint: CGPoint, in size: CGSize) {
        noteInteraction()
        guard size.width > 0, size.height > 0 else { return }
        let origin = CanonicalSpace.origin(in: size, design: design)
        let half = 0.5 * min(size.width, size.height)
        let x = Float((viewPoint.x - origin.x) / half)
        let y = Float((origin.y - viewPoint.y) / half)
        lookTarget = SIMD2<Float>(RigCurves.clamp(x, -1, 1), RigCurves.clamp(y, -1, 1))
    }

    public func clearLookTarget() {
        if lookTarget != nil { lookTarget = nil }
    }

    private func noteInteraction() {
        idle.noteInteraction(at: localTime)
        autoSleeping = false
    }

    // MARK: Simulation

    /// Advances the simulation to `time` (CACurrentMediaTime seconds) and returns the pose.
    /// Calling twice with the same time returns the same pose.
    @discardableResult
    public func pose(at time: TimeInterval) -> CharacterPose {
        if hasTime && time == lastTime { return currentPose }
        var dt: Float = 0
        if hasTime {
            let raw = time - lastTime
            if raw > 0 { dt = min(Float(raw), max(0, configuration.maxDeltaTime)) }
        }
        hasTime = true
        lastTime = time
        localTime += dt
        let now = localTime

        // Auto-sleep after a long quiet spell.
        if !autoSleeping && currentEmotion != .sleepy && !isSpeaking
            && idle.shouldAutoSleep(at: now, after: configuration.autoSleepAfter) {
            autoSleeping = true
            applyEmotion(.sleepy, intensity: 1)
            gestures.play(GestureClip(gesture: .yawn, energy: 0.1), at: now)
            if activeGesture != .yawn { activeGesture = .yawn }
        }

        let reduce = configuration.respectsReduceMotion && ReduceMotion.isEnabled
        let motionScale: Float = reduce ? ReduceMotion.idleScale : 1
        let gestureScale: Float = reduce ? ReduceMotion.gestureScale : 1

        // 1. Emotion springs.
        faceSpring.update(target: profile.face, dt: dt)
        bodySpring.update(target: profile.body, dt: dt)
        effectsSpring.update(target: profile.effects, dt: dt)
        var pose = CharacterPose(face: faceSpring.value, body: bodySpring.value, effects: effectsSpring.value, time: now)

        // 2. Idle motion (additive).
        let idleOut = idle.update(time: now, dt: dt, design: design, profile: profile, emotion: currentEmotion,
                                  variety: configuration.idleVariety, motionScale: motionScale)
        pose += idleOut.delta

        // 3. Gaze (replaces the gaze channels).
        let sample = currentSample(at: time)
        let driverSpeaking = !ignoringDriver && ((speechDriver?.isSpeaking ?? false) || speechPending)
        let speakingNow = externalLipSync != nil ? sample.isSpeaking : driverSpeaking
        let restGaze = SIMD2<Float>(profile.face.gazeX, profile.face.gazeY)
        let bias = RigCurves.clamp(profile.cameraBias * (configuration.cameraBias / 0.6), 0, 1)
        let g = gaze.update(time: now, dt: dt, restGaze: restGaze, gazeWander: profile.gazeWander, cameraBias: bias,
                            lookTarget: lookTarget, isSpeaking: speakingNow, energy: profile.energy,
                            extraOffset: idleOut.gazeOffset)
        pose.face.gazeX = g.x
        pose.face.gazeY = g.y

        // 4. Blink (multiplicative on eyeOpen).
        if isBlinkingEnabled {
            let m = blink.update(time: now, dt: dt, blinkRate: profile.blinkRate, heaviness: profile.blinkHeaviness)
            pose.face.eyeOpenL *= m
            pose.face.eyeOpenR *= m
        }

        // 5. Speech (mouth replace + additive head motion).
        speech.apply(sample: sample, headMotion: configuration.speechHeadMotion, dt: dt, to: &pose)
        if isSpeaking != speakingNow { isSpeaking = speakingNow }

        // 6. Gesture delta (additive).
        let gestureDelta = gestures.evaluate(at: now)
        pose += gestureDelta * gestureScale
        let active = gestures.activeGesture
        if activeGesture != active { activeGesture = active }

        // 7. Poke sparkle burst (0.6 s).
        if pokeBurst > 0 {
            pose.effects.sparkleBurst += pokeBurst
            pokeBurst = max(0, pokeBurst - dt / 0.6)
        }

        // 8. Clamp to sane ranges.
        CharacterRig.clamp(&pose)
        pose.time = now
        currentPose = pose
        return pose
    }

    private func currentSample(at time: TimeInterval) -> LipSyncSample {
        if let external = externalLipSync { return external.sample(at: time) }
        if !ignoringDriver, let driver = speechDriver, driver.isSpeaking { return driver.sample(at: time) }
        return .silent
    }

    /// Returns to a calm neutral state and restarts the simulation clock.
    public func reset() {
        stopSpeaking()
        if isSpeaking { isSpeaking = false }
        gestures.reset()
        blink.reset()
        gaze.reset()
        idle.reset()
        speech.reset()
        pokeBurst = 0
        autoSleeping = false
        hasTime = false
        lastTime = 0
        localTime = 0
        if lookTarget != nil { lookTarget = nil }
        if activeGesture != nil { activeGesture = nil }
        applyEmotion(.neutral, intensity: 1)
        faceSpring.snap(to: profile.face)
        bodySpring.snap(to: profile.body)
        effectsSpring.snap(to: profile.effects)
        var pose = CharacterPose(face: profile.face, body: profile.body, effects: profile.effects, time: 0)
        CharacterRig.clamp(&pose)
        currentPose = pose
    }

    // MARK: Clamping

    private static func clamp(_ p: inout CharacterPose) {
        p.face.v = pointwiseMin(pointwiseMax(p.face.v, RigTuning.faceLo), RigTuning.faceHi)
        p.face.mouth.v = pointwiseMin(pointwiseMax(p.face.mouth.v, RigTuning.mouthLo), RigTuning.mouthHi)
        p.body.v = pointwiseMin(pointwiseMax(p.body.v, RigTuning.bodyLo), RigTuning.bodyHi)
        p.effects.v = pointwiseMin(pointwiseMax(p.effects.v, RigTuning.effectsLo), RigTuning.effectsHi)
    }
}

/// Spring tuning and clamp bounds. Kept outside the `@MainActor` class so they are plain nonisolated constants.
private enum RigTuning {
    static let faceStiffness: Float = 140
    static let bodyStiffness: Float = 90
    static let effectsStiffness: Float = 50

    // face.v: eyeOpenL, eyeOpenR, gazeX, gazeY, pupil, eyeScale, lowerLidL, lowerLidR,
    //         browRaiseL, browRaiseR, browTiltL, browTiltR, blush, headTilt, headTurn, headNod
    static let faceLo = SIMD16<Float>(0, 0, -1, -1, 0.3, 0.5, 0, 0, -1, -1, -1, -1, 0, -1, -1, -1)
    static let faceHi = SIMD16<Float>(1.3, 1.3, 1, 1, 2, 1.5, 1, 1, 1.2, 1.2, 1, 1, 1, 1, 1, 1)
    // mouth.v: open, width, smile, round, upperTeeth, lowerTeeth, tongue, press
    static let mouthLo = SIMD8<Float>(0, -1, -1, 0, 0, 0, 0, 0)
    static let mouthHi = SIMD8<Float>(repeating: 1)
    // body.v: offsetX, offsetY, scaleX, scaleY, tilt, breathe, glow, wiggle, armL, armR, accessory, accessory2, legL, legR, bounce, spare
    static let bodyLo = SIMD16<Float>(-1, -1, 0.5, 0.5, -1, -1, 0, -Float.greatestFiniteMagnitude,
                                              -1, -1, 0, 0, 0, 0, 0, -Float.greatestFiniteMagnitude)
    static let bodyHi = SIMD16<Float>(1, 1, 1.6, 1.6, 1, 1, 3, Float.greatestFiniteMagnitude,
                                              1, 1, 1, 1, 1, 1, 1, Float.greatestFiniteMagnitude)
    static let effectsLo = SIMD8<Float>(repeating: 0)
    static let effectsHi = SIMD8<Float>(repeating: 1)
}
