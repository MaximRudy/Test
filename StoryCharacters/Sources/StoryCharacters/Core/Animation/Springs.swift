import Foundation

/// Second-order spring that drives any `PoseVector` towards a target.
///
/// Integration is semi-implicit (symplectic) Euler, which is energy-stable for the stiffness range
/// the rig uses as long as the step stays small. Steps longer than 1/60 s are split into equal
/// sub-steps so a frame hitch (or the 1/15 s clamp after a pause) never makes the spring explode.
/// One `update` integrates at most 64 sub-steps (64/60 s); longer intervals are clamped to that, and
/// non-finite or non-positive intervals are ignored, so no sub-step ever exceeds 1/60 s.
public struct Spring<V: PoseVector>: Sendable {
    /// Restoring force per unit of displacement (rad²/s²). Higher = faster.
    public var stiffness: Float
    /// Velocity damping (1/s). `2·sqrt(stiffness)` is critical damping; lower overshoots.
    public var damping: Float
    public var value: V
    public var velocity: V

    public init(value: V, stiffness: Float = 120, damping: Float? = nil) {
        self.value = value
        self.velocity = .zero
        self.stiffness = stiffness
        self.damping = damping ?? Spring.criticalDamping(forStiffness: stiffness)
    }

    /// Damping that makes the spring critically damped at `stiffness`.
    public static func criticalDamping(forStiffness stiffness: Float) -> Float {
        2 * stiffness.squareRoot()
    }

    /// Sets stiffness and derives damping from a damping ratio (1 = critical, < 1 = bouncy).
    public mutating func setStiffness(_ stiffness: Float, dampingRatio: Float = 1) {
        self.stiffness = max(0, stiffness)
        self.damping = 2 * self.stiffness.squareRoot() * max(0, dampingRatio)
    }

    /// Advances the spring by `dt` seconds towards `target`.
    public mutating func update(target: V, dt: Float) {
        // Sub-step so that no individual step exceeds 1/60 s.
        guard let plan = SpringStepping.plan(dt) else { return }
        let steps = plan.count
        let h = plan.h
        let kh = stiffness * h
        let ch = damping * h
        var i = 0
        while i < steps {
            // v += (k·(target − x) − c·v)·h ; x += v·h
            velocity = velocity + (target - value) * kh - velocity * ch
            value = value + velocity * h
            i += 1
        }
    }

    /// Jumps straight to `target` and kills the velocity.
    public mutating func snap(to target: V) {
        value = target
        velocity = .zero
    }
}

/// Scalar version of `Spring` for single channels (gaze axes, blend weights, burst envelopes).
public struct ScalarSpring: Sendable, Equatable {
    public var stiffness: Float
    public var damping: Float
    public var value: Float
    public var velocity: Float

    public init(value: Float = 0, stiffness: Float = 120, damping: Float? = nil) {
        self.value = value
        self.velocity = 0
        self.stiffness = stiffness
        self.damping = damping ?? (2 * stiffness.squareRoot())
    }

    public mutating func setStiffness(_ stiffness: Float, dampingRatio: Float = 1) {
        self.stiffness = max(0, stiffness)
        self.damping = 2 * self.stiffness.squareRoot() * max(0, dampingRatio)
    }

    public mutating func update(target: Float, dt: Float) {
        guard let plan = SpringStepping.plan(dt) else { return }
        let steps = plan.count
        let h = plan.h
        let kh = stiffness * h
        let ch = damping * h
        var i = 0
        while i < steps {
            velocity += (target - value) * kh - velocity * ch
            value += velocity * h
            i += 1
        }
    }

    public mutating func snap(to target: Float) {
        value = target
        velocity = 0
    }
}

/// Sub-stepping shared by `Spring` and `ScalarSpring`.
private enum SpringStepping {
    /// Sub-steps per second of simulated time (each sub-step is at most 1/60 s).
    static let subStepsPerSecond: Float = 60
    /// Most sub-steps one `update` integrates; longer intervals are clamped to `maxSubSteps / subStepsPerSecond`.
    static let maxSubSteps: Float = 64

    /// Sub-step count and length for `dt`, or nil when `dt` is not a positive, finite interval
    /// (an infinite or NaN `dt` would otherwise trap in the `Int` conversion or fill the spring with NaN).
    static func plan(_ dt: Float) -> (count: Int, h: Float)? {
        guard dt > 0, dt.isFinite else { return nil }
        let clampedDt = min(dt, maxSubSteps / subStepsPerSecond)
        let count = max(1, Int(min(clampedDt * subStepsPerSecond, maxSubSteps).rounded(.up)))
        return (count: count, h: clampedDt / Float(count))
    }
}
