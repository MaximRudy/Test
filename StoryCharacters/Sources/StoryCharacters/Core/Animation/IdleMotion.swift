import Foundation
import simd

/// Output of one idle step: an additive pose delta plus a gaze offset the gaze controller consumes.
struct IdleOutput: Sendable, Equatable {
    var delta: CharacterPose
    var gazeOffset: SIMD2<Float>
}

/// Everything the character does on its own when nobody is talking to it:
/// breathing, floating, wobbling, flame flicker phase, emotion-specific idles (bounce, giggle bob,
/// trembling), micro-expressions every 6…14 s and the auto-sleep timer.
struct IdleMotion: Sendable, Equatable {
    private enum MicroKind: Int, Sendable {
        case browRaise = 0, quickSmile, lookAround, headTilt
    }

    private var rng: RigRandom
    private var breathPhase: Float = 0
    private var floatPhase: Float = 0
    private var wobblePhase: Float = 0
    private var wigglePhase: Float = 0
    private var specialPhase: Float = 0

    // Smoothed weights of the emotion-specific idles so switching emotions never pops.
    private var bounceWeight = ScalarSpring(value: 0, stiffness: 40)
    private var giggleWeight = ScalarSpring(value: 0, stiffness: 40)
    private var trembleWeight = ScalarSpring(value: 0, stiffness: 40)

    // Micro-expressions.
    private var nextMicroAt: Float = 4
    private var microStart: Float = -1
    private var microDuration: Float = 1
    private var microKind: MicroKind = .browRaise
    private var microSign: Float = 1
    private var hasScheduled = false

    // Auto-sleep.
    private var lastInteractionAt: Float = 0

    init(seed: UInt64 = 5) {
        rng = RigRandom(seed: seed)
    }

    mutating func reset() {
        breathPhase = 0
        floatPhase = 0
        wobblePhase = 0
        wigglePhase = 0
        specialPhase = 0
        bounceWeight.snap(to: 0)
        giggleWeight.snap(to: 0)
        trembleWeight.snap(to: 0)
        microStart = -1
        hasScheduled = false
        lastInteractionAt = 0
    }

    /// Records user/app activity for the auto-sleep timer.
    mutating func noteInteraction(at time: Float) {
        lastInteractionAt = time
    }

    /// True when `after` seconds passed since the last interaction (0 disables).
    func shouldAutoSleep(at time: Float, after: TimeInterval) -> Bool {
        guard after > 0 else { return false }
        return time - lastInteractionAt >= Float(after)
    }

    /// Advances the idle simulation.
    /// - Parameters:
    ///   - variety: `RigConfiguration.idleVariety` (0 = still, 1 = normal, 2 = very lively).
    ///   - motionScale: 1 normally, 0.3 under Reduce Motion.
    mutating func update(time: Float, dt: Float, design: CharacterDesign, profile: EmotionProfile,
                         emotion: Emotion, variety: Float, motionScale: Float) -> IdleOutput {
        if !hasScheduled {
            hasScheduled = true
            lastInteractionAt = time
            nextMicroAt = time + rng.nextFloat(in: 3 ... 7)
        }

        let energy = RigCurves.clamp(profile.energy, 0, 1)
        let energyScale = 0.4 + 0.9 * energy
        let amp = RigCurves.clamp(variety, 0, 2) * motionScale
        let idle = design.idle

        var delta = CharacterPose.zero
        var gazeOffset = SIMD2<Float>(repeating: 0)

        // Breathing.
        breathPhase += dt * 2 * Float.pi * max(0.02, profile.breathRate)
        delta.body.breathe = sin(breathPhase) * profile.breathDepth * idle.breathDepth * min(1, amp + 0.25)

        // Float bob (floaters bob more; grounded designs barely move).
        floatPhase += dt * 2 * Float.pi * max(0.05, idle.floatFrequency)
        let floatAmp = idle.floatAmplitude * profile.floatAmplitude * energyScale * amp
        delta.body.offsetY += sin(floatPhase) * floatAmp
        delta.body.offsetX += SmoothNoise.value(time * 0.35, seed: 2.2) * floatAmp * 0.25

        // Wobble tilt (jelly designs get a little extra).
        wobblePhase += dt * 2 * Float.pi * max(0.05, idle.wobbleFrequency)
        let jelly: Float = design.features.contains(.jelly) ? 1.3 : 1
        let wobbleAmp = idle.wobbleAmplitude * energyScale * amp * jelly
        delta.body.tilt += sin(wobblePhase) * wobbleAmp
        delta.body.tilt += SmoothNoise.value(time * 0.5, seed: 9.1) * wobbleAmp * 0.5
        delta.face.headTilt += SmoothNoise.value(time * 0.3, seed: 4.4) * 0.03 * energyScale * amp

        // Flame / tail / hood wiggle phase accumulation (Spark's tip wiggles 2× faster when excited).
        let wiggleBoost: Float = emotion == .excited ? 2 : 1
        wigglePhase += dt * 2 * Float.pi * (0.8 + idle.flickerRate) * wiggleBoost
        if wigglePhase > 2 * Float.pi * 1024 { wigglePhase -= 2 * Float.pi * 1024 }
        delta.body.wiggle = wigglePhase

        // Accessory life: leaves / book glow / brain breathe gently with the breath.
        delta.body.accessory2 += 0.08 * sin(breathPhase * 0.5 + 1.0) * amp
        delta.body.accessory += 0.05 * sin(breathPhase + 0.5) * amp

        // Emotion-specific idles with smoothed weights.
        bounceWeight.update(target: emotion == .excited ? 1 : 0, dt: dt)
        giggleWeight.update(target: emotion == .laughing ? 1 : 0, dt: dt)
        trembleWeight.update(target: emotion == .scared ? 1 : 0, dt: dt)
        specialPhase += dt * 2 * Float.pi
        if specialPhase > 2 * Float.pi * 1024 { specialPhase -= 2 * Float.pi * 1024 }

        let bw = RigCurves.clamp(bounceWeight.value, 0, 1) * amp
        if bw > 0.001 {
            // Bouncy hop at ~2.4 Hz with squash & stretch.
            let s = sin(specialPhase * 2.4)
            let hop = max(0, s)
            delta.body.bounce += hop * bw
            delta.body.offsetY += hop * 0.05 * bw
            delta.body.scaleY += s * 0.03 * bw
            delta.body.scaleX -= s * 0.02 * bw
            delta.body.armL += hop * 0.3 * bw
            delta.body.armR += hop * 0.3 * bw
        }
        let gw = RigCurves.clamp(giggleWeight.value, 0, 1) * amp
        if gw > 0.001 {
            // Giggle bob at ~6 Hz: shoulders shake, head rocks, mouth opens rhythmically.
            let s = sin(specialPhase * 6.0)
            delta.body.offsetY += 0.015 * s * gw
            delta.body.scaleY += 0.015 * s * gw
            delta.body.tilt += 0.025 * sin(specialPhase * 3.0) * gw
            delta.face.headNod += 0.08 * s * gw
            delta.face.mouth.open += 0.08 * (0.5 + 0.5 * s) * gw
        }
        let tw = RigCurves.clamp(trembleWeight.value, 0, 1) * amp
        if tw > 0.001 {
            // Trembling: fast noise ×3 on offset and tilt, pupils flutter.
            let n1 = SmoothNoise.value(time * 11, seed: 1.7)
            let n2 = SmoothNoise.value(time * 13, seed: 6.3)
            delta.body.offsetX += n1 * 0.012 * 3 * tw
            delta.body.tilt += n2 * 0.015 * 3 * tw
            delta.face.pupil += n1 * 0.04 * tw
            delta.face.headTurn += n2 * 0.04 * tw
        }

        // Sleepy drift: slow head bob.
        if emotion == .sleepy {
            delta.face.headNod += SmoothNoise.value(time * 0.6, seed: 8.8) * 0.06 * amp
        }

        // Micro-expressions.
        let microRate = max(0.05, profile.microExpressionRate) * (0.5 + 0.5 * RigCurves.clamp(variety, 0, 2))
        if microStart < 0 && time >= nextMicroAt && amp > 0.001 {
            microStart = time
            microDuration = rng.nextFloat(in: 0.7 ... 1.3)
            microKind = MicroKind(rawValue: Int(rng.nextFloat() * 4) % 4) ?? .browRaise
            microSign = rng.chance(0.5) ? 1 : -1
            // Curious personalities look around and tilt more often.
            if design.personality.curiosity > 0.6 && rng.chance(0.3) {
                microKind = rng.chance(0.5) ? .lookAround : .headTilt
            }
        }
        if microStart >= 0 {
            let u = (time - microStart) / microDuration
            if u >= 1 {
                microStart = -1
                nextMicroAt = time + rng.nextFloat(in: 6 ... 14) / microRate
            } else {
                let w = RigCurves.window(u) * amp
                switch microKind {
                case .browRaise:
                    delta.face.browRaiseL += 0.25 * w
                    delta.face.browRaiseR += 0.25 * w
                    delta.face.eyeOpenL += 0.04 * w
                    delta.face.eyeOpenR += 0.04 * w
                case .quickSmile:
                    delta.face.mouth.smile += 0.18 * w
                    delta.face.lowerLidL += 0.15 * w
                    delta.face.lowerLidR += 0.15 * w
                case .lookAround:
                    gazeOffset = SIMD2<Float>(0.3 * microSign * w, 0.1 * w)
                    delta.face.headTurn += 0.12 * microSign * w
                case .headTilt:
                    delta.face.headTilt += 0.08 * microSign * w
                    delta.body.tilt += 0.03 * microSign * w
                }
            }
        }

        return IdleOutput(delta: delta, gazeOffset: gazeOffset)
    }
}
