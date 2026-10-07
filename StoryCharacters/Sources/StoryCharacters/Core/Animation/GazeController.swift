import Foundation
import simd

/// Autonomous eye movement.
///
/// * Saccades every 1.5…4 s to targets inside radius `0.35·gazeWander` around the emotion's rest gaze,
///   60 ms long with a smoothstep profile, so the eyes dart; micro-drift noise of ±0.02 on top. The autonomous
///   path is already C¹, so it is used directly (a follower spring would stretch every saccade to ≈ 180 ms).
/// * Returns to the viewer (rest gaze) with probability `cameraBias` (+0.3 while speaking).
/// * An explicit `lookTarget` overrides everything through a fast spring that starts from the current gaze.
///   When the target is released, the remaining offset to the autonomous path decays through a critically damped
///   spring, so neither hand-over jumps.
struct GazeController: Sendable, Equatable {
    static let saccadeDuration: Float = 0.06
    /// Look-target follower: fast and slightly under-damped so it feels alive.
    static let targetStiffness: Float = 320
    static let targetDampingRatio: Float = 0.9
    /// Hand-over from a released look target back to the autonomous path (critically damped).
    static let handOffStiffness: Float = 600

    private var rng: RigRandom
    private var followX = ScalarSpring(value: 0, stiffness: GazeController.targetStiffness)
    private var followY = ScalarSpring(value: 0, stiffness: GazeController.targetStiffness)
    private var handOffX = ScalarSpring(value: 0, stiffness: GazeController.handOffStiffness)
    private var handOffY = ScalarSpring(value: 0, stiffness: GazeController.handOffStiffness)
    private var isFollowingTarget = false
    /// Gaze returned by the previous update (clamped to −1…1).
    private var output = SIMD2<Float>(repeating: 0)
    private var saccadeFrom = SIMD2<Float>(repeating: 0)
    private var saccadeTo = SIMD2<Float>(repeating: 0)
    private var saccadeStart: Float = -1
    private var nextSaccadeAt: Float = 0
    private var lastRest = SIMD2<Float>(repeating: 0)
    private var hasScheduled = false

    init(seed: UInt64 = 11) {
        rng = RigRandom(seed: seed)
        followX.setStiffness(GazeController.targetStiffness, dampingRatio: GazeController.targetDampingRatio)
        followY.setStiffness(GazeController.targetStiffness, dampingRatio: GazeController.targetDampingRatio)
    }

    mutating func reset() {
        followX.snap(to: 0)
        followY.snap(to: 0)
        handOffX.snap(to: 0)
        handOffY.snap(to: 0)
        isFollowingTarget = false
        output = .zero
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
            saccadeStart = -1
            output = SIMD2<Float>(RigCurves.clamp(restGaze.x, -1, 1), RigCurves.clamp(restGaze.y, -1, 1))
            nextSaccadeAt = time + rng.nextFloat(in: 1.0 ... 2.5)
        }

        // The emotion moved the resting gaze noticeably: glance there soon.
        let restDelta = restGaze - lastRest
        if simd_length_squared(restDelta) > 0.01 {
            lastRest = restGaze
            nextSaccadeAt = min(nextSaccadeAt, time + 0.15)
        }

        var gaze: SIMD2<Float>
        if let target = lookTarget {
            let desired = SIMD2<Float>(RigCurves.clamp(target.x, -1, 1), RigCurves.clamp(target.y, -1, 1))
            if !isFollowingTarget {
                // Start following from where the eyes are right now.
                isFollowingTarget = true
                followX.snap(to: output.x)
                followY.snap(to: output.y)
            }
            // Keep the autonomous path parked at the target so releasing it is seamless.
            saccadeFrom = desired
            saccadeTo = desired
            saccadeStart = -1
            followX.update(target: desired.x, dt: dt)
            followY.update(target: desired.y, dt: dt)
            gaze = SIMD2<Float>(followX.value, followY.value)
        } else {
            if time >= nextSaccadeAt {
                beginSaccade(at: time, restGaze: restGaze, gazeWander: gazeWander,
                             cameraBias: cameraBias, isSpeaking: isSpeaking, energy: energy)
            }
            var path: SIMD2<Float>
            if saccadeStart >= 0 {
                let u = RigCurves.smoothstep((time - saccadeStart) / GazeController.saccadeDuration)
                path = saccadeFrom + (saccadeTo - saccadeFrom) * u
                if u >= 1 { saccadeStart = -1; saccadeFrom = saccadeTo }
            } else {
                path = saccadeTo
            }
            // Micro drift.
            path += SmoothNoise.value2(time * 0.9, seed: 3.3) * 0.02
            path += extraOffset
            if isFollowingTarget {
                // Target released: start from the current gaze (keeping its velocity) and let the gap decay.
                isFollowingTarget = false
                handOffX.snap(to: output.x - path.x)
                handOffY.snap(to: output.y - path.y)
                handOffX.velocity = followX.velocity
                handOffY.velocity = followY.velocity
            }
            handOffX.update(target: 0, dt: dt)
            handOffY.update(target: 0, dt: dt)
            gaze = path + SIMD2<Float>(handOffX.value, handOffY.value)
        }

        output = SIMD2<Float>(RigCurves.clamp(gaze.x, -1, 1), RigCurves.clamp(gaze.y, -1, 1))
        return output
    }

    private mutating func beginSaccade(at time: Float, restGaze: SIMD2<Float>, gazeWander: Float,
                                       cameraBias: Float, isSpeaking: Bool, energy: Float) {
        let bias = RigCurves.clamp(cameraBias + (isSpeaking ? 0.3 : 0), 0, 1)
        // A saccade still in flight is redirected from the point it has reached.
        if saccadeStart >= 0 {
            let u = RigCurves.smoothstep((time - saccadeStart) / GazeController.saccadeDuration)
            saccadeFrom = saccadeFrom + (saccadeTo - saccadeFrom) * u
        } else {
            saccadeFrom = saccadeTo
        }
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
}
