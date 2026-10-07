import Foundation

/// Cheap 1-D sum-of-sines noise. Smooth (C∞), bounded to −1…1, deterministic in `(t, seed)`.
public enum SmoothNoise {
    /// Noise value for time `t` (seconds) and a per-channel `seed`.
    public static func value(_ t: Float, seed: Float) -> Float {
        let p = t + seed * 17.31
        let a = sin(p * 1.00 + seed * 3.10)
        let b = sin(p * 2.17 + seed * 7.70 + 1.30)
        let c = sin(p * 3.71 + seed * 11.3 + 2.10)
        // Weights sum to 1 so the result stays inside −1…1.
        return a * 0.55 + b * 0.30 + c * 0.15
    }

    /// Two independent channels packed as a vector (handy for 2-D drift).
    public static func value2(_ t: Float, seed: Float) -> SIMD2<Float> {
        SIMD2<Float>(value(t, seed: seed), value(t, seed: seed + 41.7))
    }
}

/// Tiny deterministic PRNG (SplitMix64) for blink / saccade / micro-expression scheduling.
/// Deterministic seeds keep tests reproducible; the rig seeds it from the character kind.
struct RigRandom: Sendable, Equatable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func nextUInt64() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0 ..< 1.
    mutating func nextFloat() -> Float {
        let bits = nextUInt64() >> 40 // 24 random bits
        return Float(bits) / 16_777_216.0
    }

    /// Uniform in `range`.
    mutating func nextFloat(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * nextFloat()
    }

    /// Exponentially distributed interval with the given mean, clipped to `minimum ... 3·mean`.
    mutating func nextInterval(mean: Float, minimum: Float) -> Float {
        let u = max(1e-4, 1 - nextFloat())
        let raw = -log(u) * mean
        return min(max(raw, minimum), mean * 3)
    }

    mutating func chance(_ probability: Float) -> Bool {
        nextFloat() < probability
    }
}

/// Shared easing helpers used by gestures, blinks and micro-expressions.
enum RigCurves {
    /// Hermite smoothstep on 0…1 (zero slope at both ends).
    @inline(__always)
    static func smoothstep(_ x: Float) -> Float {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Smoothstep from `edge0` to `edge1`.
    @inline(__always)
    static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        return smoothstep((x - edge0) / (edge1 - edge0))
    }

    /// sin²(πu): a C¹ bump that is 0 with zero slope at u = 0 and u = 1, 1 at u = 0.5.
    @inline(__always)
    static func window(_ u: Float) -> Float {
        let t = min(max(u, 0), 1)
        let s = sin(Float.pi * t)
        return s * s
    }

    /// A C¹ bump centred at `center` with total `width`; zero (with zero slope) outside.
    @inline(__always)
    static func bump(_ u: Float, center: Float, width: Float) -> Float {
        guard width > 0 else { return 0 }
        let local = (u - center) / width + 0.5
        if local <= 0 || local >= 1 { return 0 }
        return window(local)
    }

    /// Rise with smoothstep over `attack`, hold at 1, fall with smoothstep over `release` (u in 0…1).
    /// Zero with zero slope at both ends, so it is safe as a gesture envelope.
    @inline(__always)
    static func plateau(_ u: Float, attack: Float, release: Float) -> Float {
        let t = min(max(u, 0), 1)
        let a = max(attack, 1e-3)
        let r = max(release, 1e-3)
        let rise = smoothstep(0, a, t)
        let fall = 1 - smoothstep(1 - r, 1, t)
        return min(rise, fall)
    }

    /// Fast attack / slow release pop used for surprise-like reactions.
    @inline(__always)
    static func pop(_ u: Float, attack: Float = 0.08) -> Float {
        plateau(u, attack: attack, release: 1 - attack - 0.05)
    }

    /// Damped oscillation inside a window: sin(2π·cycles·u) · sin²(πu).
    @inline(__always)
    static func wave(_ u: Float, cycles: Float) -> Float {
        sin(2 * Float.pi * cycles * u) * window(u)
    }

    /// Linear interpolation.
    @inline(__always)
    static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    @inline(__always)
    static func clamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
        min(max(x, lo), hi)
    }
}
