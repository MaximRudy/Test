import XCTest
import CoreGraphics
@testable import StoryCharacters

/// Core animation tests: pure maths and rig behaviour. No GPU, window or audio hardware required.
@MainActor
final class CoreAnimationTests: XCTestCase {

    // MARK: - PoseVector arithmetic

    func testMouthShapeArithmetic() {
        let a = MouthShape(open: 0.5, width: 0.2, smile: -0.4, round: 0.1, upperTeeth: 0.3, lowerTeeth: 0.2, tongue: 0.1, press: 0.0)
        let b = MouthShape(open: 0.25, width: -0.2, smile: 0.4, round: 0.3, upperTeeth: 0.1, lowerTeeth: 0.0, tongue: 0.5, press: 1.0)
        let sum = a + b
        XCTAssertEqual(sum.open, 0.75, accuracy: 1e-6)
        XCTAssertEqual(sum.width, 0.0, accuracy: 1e-6)
        XCTAssertEqual(sum.press, 1.0, accuracy: 1e-6)
        let diff = a - b
        XCTAssertEqual(diff.smile, -0.8, accuracy: 1e-6)
        XCTAssertEqual(diff.tongue, -0.4, accuracy: 1e-6)
        let scaled = a * 2
        XCTAssertEqual(scaled.open, 1.0, accuracy: 1e-6)
        XCTAssertEqual(scaled.upperTeeth, 0.6, accuracy: 1e-6)
        let mid = MouthShape.lerp(a, b, 0.5)
        XCTAssertEqual(mid.open, 0.375, accuracy: 1e-6)
        XCTAssertEqual(mid.press, 0.5, accuracy: 1e-6)
        XCTAssertEqual(MouthShape.zero + a, a)
    }

    func testCharacterPoseArithmeticKeepsTime() {
        var a = CharacterPose.neutral
        a.time = 12.5
        var b = CharacterPose.zero
        b.body.offsetY = 0.1
        b.face.eyeOpenL = -0.5
        b.effects.hearts = 0.3
        let sum = a + b
        XCTAssertEqual(sum.time, 12.5)
        XCTAssertEqual(sum.body.offsetY, 0.1, accuracy: 1e-6)
        XCTAssertEqual(sum.face.eyeOpenL, 0.5, accuracy: 1e-6)
        XCTAssertEqual(sum.effects.hearts, 0.3, accuracy: 1e-6)
        let half = b * 0.5
        XCTAssertEqual(half.body.offsetY, 0.05, accuracy: 1e-6)
        var c = a
        c += b
        XCTAssertEqual(c, sum)
        c -= b
        XCTAssertEqual(c.face.eyeOpenL, 1.0, accuracy: 1e-6)
        XCTAssertEqual(FacePose.neutral.pupil, 1)
        XCTAssertEqual(BodyPose.neutral.scaleX, 1)
        XCTAssertEqual(EffectsPose.neutral.sparkleRate, 0.35)
    }

    // MARK: - Uniforms layout

    func testCharacterUniformsStride() {
        XCTAssertEqual(MemoryLayout<CharacterUniforms>.stride, 560)
        XCTAssertEqual(MemoryLayout<CharacterUniforms>.size, CharacterUniforms.slotCount * 16)
    }

    // MARK: - Springs

    func testSpringConvergesAtSixtyHertz() {
        var spring = Spring<FacePose>(value: .zero, stiffness: 140)
        let target = FacePose.neutral
        for _ in 0..<240 { spring.update(target: target, dt: 1.0 / 60.0) }
        XCTAssertEqual(spring.value.eyeOpenL, 1, accuracy: 1e-3)
        XCTAssertEqual(spring.value.pupil, 1, accuracy: 1e-3)
        XCTAssertEqual(spring.value.mouth.open, 0, accuracy: 1e-3)
        XCTAssertLessThan(abs(spring.velocity.eyeOpenL), 1e-2)
    }

    func testSpringStableAtFifteenHertzAndLargeStiffness() {
        var spring = ScalarSpring(value: 0, stiffness: 140 * 2.5)
        var maxValue: Float = 0
        for _ in 0..<60 {
            spring.update(target: 1, dt: 1.0 / 15.0)
            XCTAssertFalse(spring.value.isNaN)
            maxValue = max(maxValue, spring.value)
        }
        XCTAssertEqual(spring.value, 1, accuracy: 1e-3)
        XCTAssertLessThan(maxValue, 1.05, "critically damped spring must not overshoot noticeably")
    }

    func testSpringIgnoresZeroStep() {
        var spring = ScalarSpring(value: 0.25, stiffness: 100)
        spring.update(target: 1, dt: 0)
        XCTAssertEqual(spring.value, 0.25)
        XCTAssertEqual(spring.velocity, 0)
    }

    // MARK: - Noise and curves

    func testSmoothNoiseBounded() {
        var t: Float = 0
        while t < 50 {
            let v = SmoothNoise.value(t, seed: 3.7)
            XCTAssertGreaterThanOrEqual(v, -1)
            XCTAssertLessThanOrEqual(v, 1)
            t += 0.013
        }
    }

    func testCurvesAreZeroAtEnds() {
        XCTAssertEqual(RigCurves.window(0), 0, accuracy: 1e-6)
        XCTAssertEqual(RigCurves.window(1), 0, accuracy: 1e-6)
        XCTAssertEqual(RigCurves.window(0.5), 1, accuracy: 1e-6)
        XCTAssertEqual(RigCurves.plateau(0, attack: 0.2, release: 0.3), 0, accuracy: 1e-6)
        XCTAssertEqual(RigCurves.plateau(1, attack: 0.2, release: 0.3), 0, accuracy: 1e-6)
        XCTAssertEqual(RigCurves.plateau(0.5, attack: 0.2, release: 0.3), 1, accuracy: 1e-6)
        XCTAssertEqual(RigCurves.bump(0, center: 0.5, width: 0.5), 0, accuracy: 1e-6)
        XCTAssertEqual(RigCurves.bump(0.5, center: 0.5, width: 0.5), 1, accuracy: 1e-6)
    }

    // MARK: - Emotion profiles

    func testAllEmotionProfilesExistAndNeutralMatches() {
        XCTAssertEqual(EmotionProfile.profile(for: .neutral), EmotionProfile.neutral)
        for emotion in Emotion.allCases {
            let p = EmotionProfile.profile(for: emotion)
            XCTAssertGreaterThan(p.transitionStiffness, 0)
            XCTAssertGreaterThan(p.breathRate, 0)
            XCTAssertGreaterThanOrEqual(p.face.eyeOpenL, 0)
            XCTAssertLessThanOrEqual(p.face.eyeOpenL, 1.3)
            XCTAssertGreaterThanOrEqual(p.face.mouth.open, 0)
            XCTAssertLessThanOrEqual(p.face.mouth.open, 1)
        }
        XCTAssertEqual(EmotionProfile.profile(for: .surprised).effects.exclamation, 1)
        XCTAssertEqual(EmotionProfile.profile(for: .sad).effects.tears, 0.6, accuracy: 1e-6)
        XCTAssertEqual(EmotionProfile.profile(for: .sleepy).blinkHeaviness, 0.55, accuracy: 1e-6)
        let half = EmotionProfile.profile(for: .happy, intensity: 0.5)
        XCTAssertEqual(half.face.mouth.smile, (0.25 + 0.85) / 2, accuracy: 1e-5)
        XCTAssertEqual(EmotionProfile.profile(for: .happy, intensity: 0), EmotionProfile.neutral)
    }

    // MARK: - Gestures

    func testGestureClipsStartAndEndAtZeroDelta() {
        for gesture in Gesture.allCases {
            let clip = GestureClip(gesture: gesture)
            XCTAssertEqual(maxAbs(clip.evaluate(u: 0)), 0, accuracy: 1e-6, "\(gesture) at u = 0")
            XCTAssertEqual(maxAbs(clip.evaluate(u: 1)), 0, accuracy: 1e-6, "\(gesture) at u = 1")
            // C¹ start/end: the delta must still be tiny a few milliseconds in.
            XCTAssertLessThan(maxAbs(clip.evaluate(u: 0.005)), 0.05, "\(gesture) near u = 0")
            XCTAssertLessThan(maxAbs(clip.evaluate(u: 0.995)), 0.05, "\(gesture) near u = 1")
            XCTAssertGreaterThan(clip.duration, 0)
            // The clip actually does something.
            var peak: Float = 0
            var u: Float = 0.02
            while u < 1 {
                peak = max(peak, maxAbs(clip.evaluate(u: u)))
                u += 0.02
            }
            XCTAssertGreaterThan(peak, 0.05, "\(gesture) should move the character")
        }
    }

    func testGesturePlayerCrossFadesAndFinishes() {
        var player = GesturePlayer()
        player.play(GestureClip(gesture: .nod, duration: 1.0), at: 0)
        XCTAssertEqual(player.activeGesture, .nod)
        _ = player.evaluate(at: 0.3)
        player.play(GestureClip(gesture: .wave, duration: 1.0), at: 0.3)
        XCTAssertEqual(player.activeGesture, .wave)
        var previous = player.evaluate(at: 0.3)
        var t: Float = 0.3
        while t < 1.5 {
            t += 1.0 / 60.0
            let d = player.evaluate(at: t)
            XCTAssertLessThan(maxAbs(d - previous), 0.2, "cross-fade must stay smooth at t = \(t)")
            previous = d
        }
        XCTAssertNil(player.activeGesture)
        XCTAssertEqual(maxAbs(player.evaluate(at: 2)), 0, accuracy: 1e-6)
    }

    // MARK: - Rig

    func testRigSmoothnessWhenSwitchingEmotions() {
        let rig = CharacterRig(design: testDesign())
        rig.isBlinkingEnabled = false
        var time: TimeInterval = 100
        var previous = rig.pose(at: time)
        var maxEye: Float = 0
        var maxMouth: Float = 0
        var maxScale: Float = 0
        var frame = 0
        let emotions: [Emotion] = Emotion.allCases + [.laughing, .surprised, .sleepy, .excited, .sad, .surprised, .laughing]
        while frame < emotions.count * 30 {
            if frame % 30 == 0 {
                rig.set(emotion: emotions[frame / 30])
            }
            time += 1.0 / 60.0
            let pose = rig.pose(at: time)
            maxEye = max(maxEye, abs(pose.face.eyeOpenL - previous.face.eyeOpenL))
            maxMouth = max(maxMouth, abs(pose.face.mouth.open - previous.face.mouth.open))
            maxScale = max(maxScale, abs(pose.body.scaleY - previous.body.scaleY))
            previous = pose
            frame += 1
        }
        XCTAssertLessThan(maxEye, 0.25)
        XCTAssertLessThan(maxMouth, 0.25)
        XCTAssertLessThan(maxScale, 0.25)
    }

    func testRigPoseIsDeterministicForRepeatedTime() {
        let rig = CharacterRig(design: testDesign())
        rig.set(emotion: .happy)
        var time: TimeInterval = 1_000
        for _ in 0..<30 {
            time += 1.0 / 60.0
            rig.pose(at: time)
        }
        let a = rig.pose(at: time)
        let b = rig.pose(at: time)
        XCTAssertEqual(a, b)
        XCTAssertEqual(rig.currentPose, a)
        // Time going backwards never breaks the rig.
        let c = rig.pose(at: time - 5)
        XCTAssertFalse(c.face.eyeOpenL.isNaN)
    }

    func testRigFirstCallUsesZeroDeltaAndClampsLongGaps() {
        let rig = CharacterRig(design: testDesign())
        let first = rig.pose(at: 50)
        XCTAssertEqual(first.time, 0, accuracy: 1e-6)
        rig.set(emotion: .excited)
        // A 10 s gap must be clamped to maxDeltaTime: no explosion, no NaN, still inside sane ranges.
        let later = rig.pose(at: 60)
        XCTAssertFalse(later.face.eyeOpenL.isNaN)
        XCTAssertLessThanOrEqual(later.face.eyeOpenL, 1.3)
        XCTAssertGreaterThanOrEqual(later.body.scaleY, 0.5)
        XCTAssertLessThanOrEqual(later.body.scaleY, 1.6)
        XCTAssertEqual(later.time, rig.configuration.maxDeltaTime, accuracy: 1e-5)
    }

    func testRigEmotionConvergesToProfile() {
        let rig = CharacterRig(design: testDesign(), configuration: RigConfiguration(idleVariety: 0))
        rig.isBlinkingEnabled = false
        rig.set(emotion: .sad)
        var time: TimeInterval = 10
        for _ in 0..<300 {
            time += 1.0 / 60.0
            rig.pose(at: time)
        }
        let pose = rig.currentPose
        let profile = EmotionProfile.profile(for: .sad)
        XCTAssertEqual(pose.face.mouth.smile, profile.face.mouth.smile, accuracy: 0.02)
        XCTAssertEqual(pose.face.eyeOpenL, profile.face.eyeOpenL, accuracy: 0.03)
        XCTAssertEqual(pose.effects.tears, profile.effects.tears, accuracy: 0.02)
        XCTAssertEqual(rig.emotion, .sad)
        XCTAssertEqual(rig.emotionIntensity, 1)
    }

    func testRigGesturesStartAndFinish() {
        let rig = CharacterRig(design: testDesign())
        var time: TimeInterval = 0
        rig.pose(at: time)
        rig.play(.wave)
        XCTAssertEqual(rig.activeGesture, .wave)
        for _ in 0..<60 {
            time += 1.0 / 60.0
            rig.pose(at: time)
        }
        XCTAssertEqual(rig.activeGesture, .wave, "a 1.6 s wave is still running after 1 s")
        for _ in 0..<120 {
            time += 1.0 / 60.0
            rig.pose(at: time)
        }
        XCTAssertNil(rig.activeGesture)
        rig.play(.nod)
        rig.cancelGesture()
        XCTAssertNil(rig.activeGesture)
    }

    func testRigPokeAndLookTarget() {
        let rig = CharacterRig(design: testDesign())
        rig.pose(at: 0)
        rig.poke()
        XCTAssertNotNil(rig.activeGesture)
        let pose = rig.pose(at: 1.0 / 60.0)
        XCTAssertGreaterThan(pose.effects.sparkleBurst, 0.5)

        let size = CGSize(width: 300, height: 300)
        rig.lookAt(viewPoint: CGPoint(x: 300, y: 0), in: size)
        let target = rig.lookTarget ?? SIMD2<Float>(repeating: 0)
        XCTAssertEqual(target.x, 1, accuracy: 1e-5)
        XCTAssertGreaterThan(target.y, 0.5)
        var t: TimeInterval = 1.0 / 60.0
        for _ in 0..<60 {
            t += 1.0 / 60.0
            rig.pose(at: t)
        }
        XCTAssertGreaterThan(rig.currentPose.face.gazeX, 0.6)
        XCTAssertGreaterThan(rig.currentPose.face.gazeY, 0.3)
        rig.clearLookTarget()
        XCTAssertNil(rig.lookTarget)
    }

    func testRigAttachedLipSyncDrivesMouthAndSpeakingFlag() {
        let rig = CharacterRig(design: testDesign())
        rig.set(emotion: .happy)
        let source = FixedLipSyncSource()
        source.current = LipSyncSample(mouth: Viseme.aa.shape, energy: 0.8, isSpeaking: true, wordOnset: 1)
        rig.attach(lipSync: source)
        var time: TimeInterval = 0
        for _ in 0..<30 {
            time += 1.0 / 60.0
            rig.pose(at: time)
        }
        XCTAssertTrue(rig.isSpeaking)
        XCTAssertGreaterThan(rig.currentPose.face.mouth.open, 0.7)
        // The emotion's smile persists while talking.
        XCTAssertGreaterThan(rig.currentPose.face.mouth.smile, 0.2)
        source.current = .silent
        for _ in 0..<30 {
            time += 1.0 / 60.0
            rig.pose(at: time)
        }
        XCTAssertFalse(rig.isSpeaking)
        XCTAssertLessThan(rig.currentPose.face.mouth.open, 0.2)
        rig.attach(lipSync: nil)
        XCTAssertFalse(rig.isSpeaking)
    }

    func testRigResetReturnsToNeutral() {
        let rig = CharacterRig(design: testDesign())
        rig.set(emotion: .excited)
        rig.play(.celebrate)
        rig.pose(at: 3)
        rig.reset()
        XCTAssertEqual(rig.emotion, .neutral)
        XCTAssertNil(rig.activeGesture)
        XCTAssertNil(rig.lookTarget)
        XCTAssertEqual(rig.currentPose.time, 0)
        XCTAssertEqual(rig.currentPose.face.mouth.smile, 0.25, accuracy: 1e-5)
    }

    func testLanguageCodeExpansion() {
        XCTAssertEqual(CharacterRig.expandLanguageCode("ru"), "ru-RU")
        XCTAssertEqual(CharacterRig.expandLanguageCode("EN"), "en-US")
        XCTAssertEqual(CharacterRig.expandLanguageCode("de-DE"), "de-DE")
    }

    func testBlinkControllerMultiplierInRange() {
        var blink = BlinkController(seed: 3)
        var t: Float = 0
        var sawClosed = false
        while t < 60 {
            let m = blink.update(time: t, dt: 1.0 / 60.0, blinkRate: 1, heaviness: 0)
            XCTAssertGreaterThanOrEqual(m, 0)
            XCTAssertLessThanOrEqual(m, 1)
            if m < 0.05 { sawClosed = true }
            t += 1.0 / 60.0
        }
        XCTAssertTrue(sawClosed, "a minute of idle time must contain at least one blink")
    }

    // MARK: - Helpers

    /// A self-contained design so the tests do not depend on the Characters module's catalog values.
    private func testDesign() -> CharacterDesign {
        let palette = Palette(bodyTop: SIMD4<Float>(hex: 0xFFE066), bodyBottom: SIMD4<Float>(hex: 0xFFB224),
                              highlight: SIMD4<Float>(hex: 0xFFF6C2), shadow: SIMD4<Float>(hex: 0xE08A12),
                              accent: SIMD4<Float>(hex: 0x1E1748), accent2: SIMD4<Float>(hex: 0x7B5CFF),
                              iris: SIMD4<Float>(hex: 0x2B1B12), pupil: SIMD4<Float>(hex: 0x120A06),
                              sclera: SIMD4<Float>(hex: 0xFFFFFF), cheek: SIMD4<Float>(hex: 0xFFB088),
                              glow: SIMD4<Float>(hex: 0xFFD36A), mouthInner: SIMD4<Float>(hex: 0x5A2415),
                              tongue: SIMD4<Float>(hex: 0xFF7E8A), teeth: SIMD4<Float>(hex: 0xFFFFFF),
                              outline: SIMD4<Float>(hex: 0x4A2A10))
        return CharacterDesign(kind: .lumi, bodyShape: .star, palette: palette,
                               features: [.hood, .bookAndWand, .starPattern, .floats],
                               idle: IdleStyle(floatAmplitude: 0.03, floatFrequency: 0.8),
                               personality: Personality(energy: 0.5, shyness: 0.2, curiosity: 0.7, playfulness: 0.5))
    }

    private func maxAbs(_ pose: CharacterPose) -> Float {
        var m: Float = 0
        for i in 0..<16 {
            m = max(m, abs(pose.face.v[i]))
            m = max(m, abs(pose.body.v[i]))
        }
        for i in 0..<8 {
            m = max(m, abs(pose.face.mouth.v[i]))
            m = max(m, abs(pose.effects.v[i]))
        }
        return m
    }
}

/// Minimal lip-sync source returning a fixed sample.
@MainActor
private final class FixedLipSyncSource: LipSyncSource {
    var current: LipSyncSample = .silent
    func sample(at time: TimeInterval) -> LipSyncSample { current }
}
