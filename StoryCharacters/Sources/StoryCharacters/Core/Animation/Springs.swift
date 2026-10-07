import Foundation

/// Second-order spring that drives any `PoseVector` towards a target.
///
/// Integration is semi-implicit (symplectic) Euler, which is energy-stable for the stiffness range
/// the rig uses as long as the step stays small. Steps longer than 1/60 s are split into equal
/// sub-steps so a frame hitch (or the 1/15 s clamp after a pause) never makes the spring explode.
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
        guard dt > 0 else { return }
        // Sub-step so that no individual step exceeds 1/60 s.
        let stepCount = Int((dt * 60).rounded(.up))
        let steps = max(1, min(stepCount, 64))
        let h = dt / Float(steps)
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
        guard dt > 0 else { return }
        let stepCount = Int((dt * 60).rounded(.up))
        let steps = max(1, min(stepCount, 64))
        let h = dt / Float(steps)
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
