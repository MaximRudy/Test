import Foundation
import simd

/// Output of one idle step: an additive pose delta plus a gaze offset the gaze controller consumes.
struct IdleOutput: Sendable, Equatable {
    var delta: CharacterPose
    var gazeOffset: SIMD2<Float>
}

/// Everything the character does on its own when nobody is talking to it:
/// breathing, floating, wobbling, flame flicker phase, emotion-specific idles (bounce, giggle bob,
/// trembling, sleepy drift), micro-expressions every 6…14 s and the auto-sleep timer.
///
/// The emotion profile switches in one step, but its idle scalars (energy, float amplitude, breath depth,
/// micro-expression rate) multiply running oscillators. They are therefore low-passed with critically damped
/// springs before use, exactly like the emotion-specific idle weights, so an emotion change never makes the
/// body jump.
struct IdleMotion: Sendable, Equatable {
    private enum MicroKind: Int, Sendable {
        case browRaise = 0, quickSmile, lookAround, headTilt
    }

    /// Stiffness of the springs smoothing the profile's idle scalars (critically damped, settles in ≈ 0.6 s).
    static let parameterStiffness: Float = 30
    /// Stiffness of the emotion-specific idle weights (bounce, giggle, tremble, sleepy drift).
    static let weightStiffness: Float = 40

    private static let twoPi: Float = 2 * Float.pi
    // Phase wrap periods. Each is a whole number of cycles of every multiplier applied to that phase,
    // so wrapping never shifts an oscillator.
    /// `breathPhase` is also read at ×0.5 → wrap at 4π.
    private static let breathPeriod: Float = 4 * Float.pi
    /// `specialPhase` drives ×2.4, ×3 and ×6 oscillators → 5 turns are whole cycles of each.
    private static let specialPeriod: Float = 10 * Float.pi
    /// `wiggle` goes to the renderers (sin/cos of integer and dyadic multiples) → wrap at 1024 turns.
    private static let wigglePeriod: Float = 2048 * Float.pi

    private var rng: RigRandom
    private var breathPhase: Float = 0
    private var floatPhase: Float = 0
    private var wobblePhase: Float = 0
    private var wigglePhase: Float = 0
    private var specialPhase: Float = 0

    // Smoothed idle parameters. They start at the neutral profile, like the rig's emotion springs.
    private var energy = ScalarSpring(value: EmotionProfile.neutral.energy, stiffness: IdleMotion.parameterStiffness)
    private var floatAmplitude = ScalarSpring(value: EmotionProfile.neutral.floatAmplitude,
                                              stiffness: IdleMotion.parameterStiffness)
    private var breathDepth = ScalarSpring(value: EmotionProfile.neutral.breathDepth,
                                           stiffness: IdleMotion.parameterStiffness)
    private var microRate = ScalarSpring(value: EmotionProfile.neutral.microExpressionRate,
                                         stiffness: IdleMotion.parameterStiffness)
    private var wiggleRate = ScalarSpring(value: 1, stiffness: IdleMotion.parameterStiffness)

    // Smoothed weights of the emotion-specific idles so switching emotions never pops.
    private var bounceWeight = ScalarSpring(value: 0, stiffness: IdleMotion.weightStiffness)
    private var giggleWeight = ScalarSpring(value: 0, stiffness: IdleMotion.weightStiffness)
    private var trembleWeight = ScalarSpring(value: 0, stiffness: IdleMotion.weightStiffness)
    private var sleepyWeight = ScalarSpring(value: 0, stiffness: IdleMotion.weightStiffness)

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
        let neutral = EmotionProfile.neutral
        energy.snap(to: neutral.energy)
        floatAmplitude.snap(to: neutral.floatAmplitude)
        breathDepth.snap(to: neutral.breathDepth)
        microRate.snap(to: neutral.microExpressionRate)
        wiggleRate.snap(to: 1)
        bounceWeight.snap(to: 0)
        giggleWeight.snap(to: 0)
        trembleWeight.snap(to: 0)
        sleepyWeight.snap(to: 0)
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

    /// Advances `phase` by `step` and wraps it into `0 ..< period`.
    @inline(__always)
    private static func advance(_ phase: Float, by step: Float, period: Float) -> Float {
        let next = phase + step
        return next >= period ? next.truncatingRemainder(dividingBy: period) : next
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

        // Low-pass the profile's idle scalars (the profile itself switches in one step).
        energy.update(target: RigCurves.clamp(profile.energy, 0, 1), dt: dt)
        floatAmplitude.update(target: max(0, profile.floatAmplitude), dt: dt)
        breathDepth.update(target: max(0, profile.breathDepth), dt: dt)
        microRate.update(target: max(0.05, profile.microExpressionRate), dt: dt)
        // Spark's signature (docs/CONTRACT.md §5): its tip wiggles 2× faster when excited.
        wiggleRate.update(target: (emotion == .excited && design.kind == .spark) ? 2 : 1, dt: dt)

        let energyScale = 0.4 + 0.9 * RigCurves.clamp(energy.value, 0, 1)
        let amp = RigCurves.clamp(variety, 0, 2) * motionScale
        let idle = design.idle

        var delta = CharacterPose.zero
        var gazeOffset = SIMD2<Float>(repeating: 0)

        // Breathing. `breathe` stays a −1…1 phase value; the renderers apply the design's
        // `idle.breathDepth` on top (§3.5), so the rig must not multiply by it here.
        breathPhase = IdleMotion.advance(breathPhase, by: dt * IdleMotion.twoPi * max(0.02, profile.breathRate),
                                         period: IdleMotion.breathPeriod)
        let breathWave = sin(breathPhase) * min(1, amp + 0.25)
        let depth = max(0, breathDepth.value)
        delta.body.breathe = breathWave * min(1, depth)
        // Emotion depth beyond 1 (sleepy 1.8, laughing 1.4 …) goes straight into the squash with the renderers'
        // §3.5 factors, so deep breathing gets deeper instead of clipping at ±1.
        let extraDepth = max(0, depth - 1) * idle.breathDepth
        delta.body.scaleY += 0.025 * breathWave * extraDepth
        delta.body.scaleX -= 0.015 * breathWave * extraDepth

        // Float bob (floaters bob more; grounded designs barely move).
        floatPhase = IdleMotion.advance(floatPhase, by: dt * IdleMotion.twoPi * max(0.05, idle.floatFrequency),
                                        period: IdleMotion.twoPi)
        let floatAmp = idle.floatAmplitude * max(0, floatAmplitude.value) * energyScale * amp
        delta.body.offsetY += sin(floatPhase) * floatAmp
        delta.body.offsetX += SmoothNoise.value(time * 0.35, seed: 2.2) * floatAmp * 0.25

        // Wobble tilt (jelly designs get a little extra).
        wobblePhase = IdleMotion.advance(wobblePhase, by: dt * IdleMotion.twoPi * max(0.05, idle.wobbleFrequency),
                                         period: IdleMotion.twoPi)
        let jelly: Float = design.features.contains(.jelly) ? 1.3 : 1
        let wobbleAmp = idle.wobbleAmplitude * energyScale * amp * jelly
        delta.body.tilt += sin(wobblePhase) * wobbleAmp
        delta.body.tilt += SmoothNoise.value(time * 0.5, seed: 9.1) * wobbleAmp * 0.5
        delta.face.headTilt += SmoothNoise.value(time * 0.3, seed: 4.4) * 0.03 * energyScale * amp

        // Flame / tail / hood wiggle phase accumulation: body.wiggle += dt·2π·(0.8 + flickerRate).
        let wiggleStep = dt * IdleMotion.twoPi * (0.8 + idle.flickerRate) * max(0, wiggleRate.value)
        wigglePhase = IdleMotion.advance(wigglePhase, by: wiggleStep, period: IdleMotion.wigglePeriod)
        delta.body.wiggle = wigglePhase

        // Accessory life: leaves / book glow / brain breathe gently with the breath.
        delta.body.accessory2 += 0.08 * sin(breathPhase * 0.5 + 1.0) * amp
        delta.body.accessory += 0.05 * sin(breathPhase + 0.5) * amp

        // Emotion-specific idles with smoothed weights.
        bounceWeight.update(target: emotion == .excited ? 1 : 0, dt: dt)
        giggleWeight.update(target: emotion == .laughing ? 1 : 0, dt: dt)
        trembleWeight.update(target: emotion == .scared ? 1 : 0, dt: dt)
        sleepyWeight.update(target: emotion == .sleepy ? 1 : 0, dt: dt)
        specialPhase = IdleMotion.advance(specialPhase, by: dt * IdleMotion.twoPi, period: IdleMotion.specialPeriod)

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
            // Trembling: fast noise ×3 on offset and tilt, pupils flutter, the mouth quivers (§6 "wobbly").
            let n1 = SmoothNoise.value(time * 11, seed: 1.7)
            let n2 = SmoothNoise.value(time * 13, seed: 6.3)
            delta.body.offsetX += n1 * 0.012 * 3 * tw
            delta.body.tilt += n2 * 0.015 * 3 * tw
            delta.face.pupil += n1 * 0.04 * tw
            delta.face.headTurn += n2 * 0.04 * tw
            delta.face.mouth.smile += 0.08 * n2 * tw
            delta.face.mouth.width += 0.06 * n1 * tw
            delta.face.mouth.open += 0.03 * (0.5 + 0.5 * n1) * tw
        }
        let sw = RigCurves.clamp(sleepyWeight.value, 0, 1) * amp
        if sw > 0.001 {
            // Sleepy drift: slow head bob.
            delta.face.headNod += SmoothNoise.value(time * 0.6, seed: 8.8) * 0.06 * sw
        }

        // Micro-expressions.
        let microEvery = max(0.05, microRate.value) * (0.5 + 0.5 * RigCurves.clamp(variety, 0, 2))
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
                nextMicroAt = time + rng.nextFloat(in: 6 ... 14) / microEvery
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
