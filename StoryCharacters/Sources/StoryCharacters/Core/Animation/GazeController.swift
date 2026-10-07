import Foundation
import simd

/// Autonomous eye movement.
///
/// * Saccades every 1.5…4 s to targets inside radius `0.35·gazeWander` around the emotion's rest gaze,
///   60 ms long, with a smoothstep profile; micro-drift noise of ±0.02 on top.
/// * Returns to the viewer (rest gaze) with probability `cameraBias` (+0.3 while speaking).
/// * An explicit `lookTarget` overrides everything through a fast spring.
struct GazeController: Sendable, Equatable {
    private var rng: RigRandom
    private var springX = ScalarSpring(value: 0, stiffness: 600)
    private var springY = ScalarSpring(value: 0, stiffness: 600)
    private var saccadeFrom = SIMD2<Float>(repeating: 0)
    private var saccadeTo = SIMD2<Float>(repeating: 0)
    private var saccadeStart: Float = -1
    private var nextSaccadeAt: Float = 0
    private var lastRest = SIMD2<Float>(repeating: 0)
    private var hasScheduled = false

    static let saccadeDuration: Float = 0.06

    init(seed: UInt64 = 11) {
        rng = RigRandom(seed: seed)
    }

    mutating func reset() {
        springX.snap(to: 0)
        springY.snap(to: 0)
        saccadeFrom = .zero
        saccadeTo = .zero
        saccadeStart = -1
        hasScheduled = false
        lastRest = .zero
    }

    /// Forces a new saccade soon (used by look-around micro-expressions and emotion changes).
    mutating func requestSaccade(at time: Float, delay: Float = 0) {
        nextSaccadeAt = min(nextSaccadeAt, time + delay)
    }

    /// Advances the controller and returns the gaze in −1…1 (x right, y up).
    /// - Parameters:
    ///   - restGaze: where "looking at the viewer" is for the current emotion (e.g. up-right while thinking).
    ///   - extraOffset: additive wander from idle micro-expressions.
    mutating func update(time: Float, dt: Float,
                         restGaze: SIMD2<Float>, gazeWander: Float, cameraBias: Float,
                         lookTarget: SIMD2<Float>?, isSpeaking: Bool, energy: Float,
                         extraOffset: SIMD2<Float>) -> SIMD2<Float> {
        if !hasScheduled {
            hasScheduled = true
            lastRest = restGaze
            saccadeFrom = restGaze
            saccadeTo = restGaze
            springX.snap(to: restGaze.x)
            springY.snap(to: restGaze.y)
            nextSaccadeAt = time + rng.nextFloat(in: 1.0 ... 2.5)
        }

        // The emotion moved the resting gaze noticeably: glance there soon.
        let restDelta = restGaze - lastRest
        if simd_length_squared(restDelta) > 0.01 {
            lastRest = restGaze
            nextSaccadeAt = min(nextSaccadeAt, time + 0.15)
        }

        var desired: SIMD2<Float>
        let stiffness: Float
        if let target = lookTarget {
            // Explicit target: fast, slightly under-damped spring so it feels alive.
            desired = SIMD2<Float>(RigCurves.clamp(target.x, -1, 1), RigCurves.clamp(target.y, -1, 1))
            stiffness = 320
            // Keep the autonomous state parked at the target so releasing is seamless.
            saccadeFrom = desired
            saccadeTo = desired
            saccadeStart = -1
        } else {
            if time >= nextSaccadeAt {
                beginSaccade(at: time, restGaze: restGaze, gazeWander: gazeWander,
                             cameraBias: cameraBias, isSpeaking: isSpeaking, energy: energy)
            }
            if saccadeStart >= 0 {
                let u = RigCurves.smoothstep((time - saccadeStart) / GazeController.saccadeDuration)
                desired = saccadeFrom + (saccadeTo - saccadeFrom) * u
                if u >= 1 { saccadeStart = -1; saccadeFrom = saccadeTo }
            } else {
                desired = saccadeTo
            }
            // Micro drift.
            desired += SmoothNoise.value2(time * 0.9, seed: 3.3) * 0.02
            desired += extraOffset
            stiffness = 600
        }

        springX.setStiffness(stiffness, dampingRatio: lookTarget == nil ? 1.0 : 0.9)
        springY.setStiffness(stiffness, dampingRatio: lookTarget == nil ? 1.0 : 0.9)
        springX.update(target: desired.x, dt: dt)
        springY.update(target: desired.y, dt: dt)

        return SIMD2<Float>(RigCurves.clamp(springX.value, -1, 1), RigCurves.clamp(springY.value, -1, 1))
    }

    private mutating func beginSaccade(at time: Float, restGaze: SIMD2<Float>, gazeWander: Float,
                                       cameraBias: Float, isSpeaking: Bool, energy: Float) {
        let bias = RigCurves.clamp(cameraBias + (isSpeaking ? 0.3 : 0), 0, 1)
        saccadeFrom = saccadeStart >= 0 ? currentValue() : saccadeTo
        if rng.chance(bias) {
            saccadeTo = restGaze
        } else {
            let radius = 0.35 * RigCurves.clamp(gazeWander, 0, 1.5)
            let angle = rng.nextFloat(in: 0 ... (2 * Float.pi))
            let r = radius * (0.4 + 0.6 * rng.nextFloat())
            saccadeTo = restGaze + SIMD2<Float>(cos(angle) * r, sin(angle) * r * 0.7)
            saccadeTo = SIMD2<Float>(RigCurves.clamp(saccadeTo.x, -1, 1), RigCurves.clamp(saccadeTo.y, -1, 1))
        }
        saccadeStart = time
        // Livelier emotions glance around more often.
        let speed = 0.75 + 0.5 * RigCurves.clamp(energy, 0, 1)
        nextSaccadeAt = time + rng.nextFloat(in: 1.5 ... 4.0) / speed
    }

    private func currentValue() -> SIMD2<Float> {
        SIMD2<Float>(springX.value, springY.value)
    }
}
