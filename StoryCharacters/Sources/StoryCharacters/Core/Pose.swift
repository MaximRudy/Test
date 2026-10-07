import Foundation
import simd

// MARK: - PoseVector

/// Element-wise arithmetic so springs, blends and lerps can operate on whole pose structs.
public protocol PoseVector: Sendable, Equatable {
    static var zero: Self { get }
    static func + (lhs: Self, rhs: Self) -> Self
    static func - (lhs: Self, rhs: Self) -> Self
    static func * (lhs: Self, rhs: Float) -> Self
}

public extension PoseVector {
    static func lerp(_ a: Self, _ b: Self, _ t: Float) -> Self { a + (b - a) * t }
    static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
    static func *= (lhs: inout Self, rhs: Float) { lhs = lhs * rhs }
}

// MARK: - MouthShape

/// Mouth articulation. Values are nominally 0...1 except `width` and `smile` (-1...1).
/// Visemes, emotions and gestures all produce `MouthShape`s that the rig blends.
public struct MouthShape: PoseVector {
    public var v: SIMD8<Float>

    public init(v: SIMD8<Float>) { self.v = v }

    public init(open: Float = 0, width: Float = 0, smile: Float = 0, round: Float = 0,
                upperTeeth: Float = 0, lowerTeeth: Float = 0, tongue: Float = 0, press: Float = 0) {
        v = SIMD8<Float>(open, width, smile, round, upperTeeth, lowerTeeth, tongue, press)
    }

    /// Jaw opening: 0 closed ... 1 fully open.
    public var open: Float { get { v[0] } set { v[0] = newValue } }
    /// Horizontal stretch: -1 puckered/narrow ... 0 ... 1 wide.
    public var width: Float { get { v[1] } set { v[1] = newValue } }
    /// Corner lift: -1 frown ... 1 smile.
    public var smile: Float { get { v[2] } set { v[2] = newValue } }
    /// Lip rounding 0 ... 1 ("o" / "u").
    public var round: Float { get { v[3] } set { v[3] = newValue } }
    /// Upper teeth visibility 0 ... 1.
    public var upperTeeth: Float { get { v[4] } set { v[4] = newValue } }
    /// Lower teeth visibility 0 ... 1.
    public var lowerTeeth: Float { get { v[5] } set { v[5] = newValue } }
    /// Tongue visibility/raise 0 ... 1.
    public var tongue: Float { get { v[6] } set { v[6] = newValue } }
    /// Lips pressed together (p / b / m) 0 ... 1. Squeezes `open` towards a thin line.
    public var press: Float { get { v[7] } set { v[7] = newValue } }

    public static let zero = MouthShape(v: .zero)

    public static func + (lhs: MouthShape, rhs: MouthShape) -> MouthShape { MouthShape(v: lhs.v + rhs.v) }
    public static func - (lhs: MouthShape, rhs: MouthShape) -> MouthShape { MouthShape(v: lhs.v - rhs.v) }
    public static func * (lhs: MouthShape, rhs: Float) -> MouthShape { MouthShape(v: lhs.v * rhs) }
}

// MARK: - FacePose

/// Everything above the neck except the mouth articulation (which lives in `mouth`).
/// Coordinates are in "body radius" units; see docs/CONTRACT.md → Canonical space.
public struct FacePose: PoseVector {
    public var v: SIMD16<Float>
    public var mouth: MouthShape

    public init(v: SIMD16<Float>, mouth: MouthShape) {
        self.v = v
        self.mouth = mouth
    }

    public init() {
        v = .zero
        mouth = .zero
    }

    /// Left eye opening: 0 closed, 1 open, up to 1.3 wide open.
    public var eyeOpenL: Float { get { v[0] } set { v[0] = newValue } }
    /// Right eye opening: 0 closed, 1 open, up to 1.3 wide open.
    public var eyeOpenR: Float { get { v[1] } set { v[1] = newValue } }
    /// Gaze direction -1 ... 1 (positive = viewer's right).
    public var gazeX: Float { get { v[2] } set { v[2] = newValue } }
    /// Gaze direction -1 ... 1 (positive = up).
    public var gazeY: Float { get { v[3] } set { v[3] = newValue } }
    /// Pupil dilation multiplier (1 = normal, 1.4 = love/excited, 0.7 = scared/angry).
    public var pupil: Float { get { v[4] } set { v[4] = newValue } }
    /// Whole-eye scale multiplier (1 = normal; surprise ≈ 1.15).
    public var eyeScale: Float { get { v[5] } set { v[5] = newValue } }
    /// Lower-lid squint for the left eye 0 ... 1 (happy squint, laughing).
    public var lowerLidL: Float { get { v[6] } set { v[6] = newValue } }
    /// Lower-lid squint for the right eye 0 ... 1.
    public var lowerLidR: Float { get { v[7] } set { v[7] = newValue } }
    /// Left brow raise: -1 pulled down ... 1 raised high.
    public var browRaiseL: Float { get { v[8] } set { v[8] = newValue } }
    /// Right brow raise: -1 ... 1.
    public var browRaiseR: Float { get { v[9] } set { v[9] = newValue } }
    /// Left brow tilt: +1 inner end up (sad / worried), -1 inner end down (angry / determined).
    public var browTiltL: Float { get { v[10] } set { v[10] = newValue } }
    /// Right brow tilt, same convention as `browTiltL`.
    public var browTiltR: Float { get { v[11] } set { v[11] = newValue } }
    /// Cheek blush intensity 0 ... 1 (designs may add a constant base blush).
    public var blush: Float { get { v[12] } set { v[12] = newValue } }
    /// Head roll in radians (positive = tilts towards viewer's right). Applied to the face features only.
    public var headTilt: Float { get { v[13] } set { v[13] = newValue } }
    /// Head yaw -1 ... 1 — shifts features horizontally and foreshortens the far eye.
    public var headTurn: Float { get { v[14] } set { v[14] = newValue } }
    /// Head pitch -1 (down) ... 1 (up) — shifts features vertically. Talking-head nods live here.
    public var headNod: Float { get { v[15] } set { v[15] = newValue } }

    public static let zero = FacePose(v: .zero, mouth: .zero)

    /// Resting face: eyes open, looking at the viewer, no expression.
    public static let neutral: FacePose = {
        var p = FacePose()
        p.eyeOpenL = 1
        p.eyeOpenR = 1
        p.pupil = 1
        p.eyeScale = 1
        return p
    }()

    public static func + (lhs: FacePose, rhs: FacePose) -> FacePose { FacePose(v: lhs.v + rhs.v, mouth: lhs.mouth + rhs.mouth) }
    public static func - (lhs: FacePose, rhs: FacePose) -> FacePose { FacePose(v: lhs.v - rhs.v, mouth: lhs.mouth - rhs.mouth) }
    public static func * (lhs: FacePose, rhs: Float) -> FacePose { FacePose(v: lhs.v * rhs, mouth: lhs.mouth * rhs) }
}

// MARK: - BodyPose

/// Whole-body transform, limbs and per-design accessory channels.
public struct BodyPose: PoseVector {
    public var v: SIMD16<Float>

    public init(v: SIMD16<Float>) { self.v = v }
    public init() { v = .zero }

    /// Horizontal offset of the body in body-radius units.
    public var offsetX: Float { get { v[0] } set { v[0] = newValue } }
    /// Vertical offset (positive = up) in body-radius units.
    public var offsetY: Float { get { v[1] } set { v[1] = newValue } }
    /// Squash & stretch: horizontal scale (1 = neutral).
    public var scaleX: Float { get { v[2] } set { v[2] = newValue } }
    /// Squash & stretch: vertical scale (1 = neutral).
    public var scaleY: Float { get { v[3] } set { v[3] = newValue } }
    /// Body roll in radians around its anchor (positive = leans to viewer's right).
    public var tilt: Float { get { v[4] } set { v[4] = newValue } }
    /// Breathing phase value -1 ... 1 (renderers may add their own subtle scaling from it).
    public var breathe: Float { get { v[5] } set { v[5] = newValue } }
    /// Glow multiplier (1 = design default, 0 = none, 2 = blazing).
    public var glow: Float { get { v[6] } set { v[6] = newValue } }
    /// Flame / tail / hood-tip wiggle phase in radians (renderers take sin/cos of it).
    public var wiggle: Float { get { v[7] } set { v[7] = newValue } }
    /// Left arm raise -1 (down/back) ... 0 (rest) ... 1 (up, waving).
    public var armL: Float { get { v[8] } set { v[8] = newValue } }
    /// Right arm raise -1 ... 1.
    public var armR: Float { get { v[9] } set { v[9] = newValue } }
    /// Design-specific channel A (book open / brain pulse / moon glow / dome shimmer / leaf wiggle). 0 ... 1.
    public var accessory: Float { get { v[10] } set { v[10] = newValue } }
    /// Design-specific channel B (wand glow / cloud curl / inner flame). 0 ... 1.
    public var accessory2: Float { get { v[11] } set { v[11] = newValue } }
    /// Left leg lift 0 ... 1.
    public var legL: Float { get { v[12] } set { v[12] = newValue } }
    /// Right leg lift 0 ... 1.
    public var legR: Float { get { v[13] } set { v[13] = newValue } }
    /// Bounce phase 0 ... 1 (hop height), used by excited / celebrate.
    public var bounce: Float { get { v[14] } set { v[14] = newValue } }
    /// Reserved / spare channel.
    public var spare: Float { get { v[15] } set { v[15] = newValue } }

    public static let zero = BodyPose(v: .zero)

    public static let neutral: BodyPose = {
        var p = BodyPose()
        p.scaleX = 1
        p.scaleY = 1
        p.glow = 1
        return p
    }()

    public static func + (lhs: BodyPose, rhs: BodyPose) -> BodyPose { BodyPose(v: lhs.v + rhs.v) }
    public static func - (lhs: BodyPose, rhs: BodyPose) -> BodyPose { BodyPose(v: lhs.v - rhs.v) }
    public static func * (lhs: BodyPose, rhs: Float) -> BodyPose { BodyPose(v: lhs.v * rhs) }
}

// MARK: - EffectsPose

/// Overlay effects (comic-style emotes and particle controls). All 0 ... 1.
public struct EffectsPose: PoseVector {
    public var v: SIMD8<Float>

    public init(v: SIMD8<Float>) { self.v = v }
    public init() { v = .zero }

    /// Tear drops under the eyes (sad).
    public var tears: Float { get { v[0] } set { v[0] = newValue } }
    /// Sweat drop at the temple (scared / worried).
    public var sweat: Float { get { v[1] } set { v[1] = newValue } }
    /// Floating hearts (love).
    public var hearts: Float { get { v[2] } set { v[2] = newValue } }
    /// "Z z z" (sleepy).
    public var zzz: Float { get { v[3] } set { v[3] = newValue } }
    /// Question mark (curious / thinking).
    public var question: Float { get { v[4] } set { v[4] = newValue } }
    /// Exclamation mark (surprised).
    public var exclamation: Float { get { v[5] } set { v[5] = newValue } }
    /// One-shot sparkle burst intensity (celebrate / poke). Decays quickly.
    public var sparkleBurst: Float { get { v[6] } set { v[6] = newValue } }
    /// Continuous ambient sparkle emission rate (design default ≈ 0.35).
    public var sparkleRate: Float { get { v[7] } set { v[7] = newValue } }

    public static let zero = EffectsPose(v: .zero)

    public static let neutral: EffectsPose = {
        var p = EffectsPose()
        p.sparkleRate = 0.35
        return p
    }()

    public static func + (lhs: EffectsPose, rhs: EffectsPose) -> EffectsPose { EffectsPose(v: lhs.v + rhs.v) }
    public static func - (lhs: EffectsPose, rhs: EffectsPose) -> EffectsPose { EffectsPose(v: lhs.v - rhs.v) }
    public static func * (lhs: EffectsPose, rhs: Float) -> EffectsPose { EffectsPose(v: lhs.v * rhs) }
}

// MARK: - CharacterPose

/// The complete per-frame state a renderer needs. Produced by `CharacterRig.pose(at:)`,
/// consumed by both the Metal and the SwiftUI renderers.
public struct CharacterPose: PoseVector {
    public var face: FacePose
    public var body: BodyPose
    public var effects: EffectsPose
    /// Rig time in seconds at which the pose was evaluated (drives shader-side ambient motion). Not part of the arithmetic.
    public var time: Float

    public init(face: FacePose = .neutral, body: BodyPose = .neutral, effects: EffectsPose = .neutral, time: Float = 0) {
        self.face = face
        self.body = body
        self.effects = effects
        self.time = time
    }

    public static let zero = CharacterPose(face: .zero, body: .zero, effects: .zero, time: 0)
    public static let neutral = CharacterPose()

    public static func + (lhs: CharacterPose, rhs: CharacterPose) -> CharacterPose {
        CharacterPose(face: lhs.face + rhs.face, body: lhs.body + rhs.body, effects: lhs.effects + rhs.effects, time: lhs.time)
    }
    public static func - (lhs: CharacterPose, rhs: CharacterPose) -> CharacterPose {
        CharacterPose(face: lhs.face - rhs.face, body: lhs.body - rhs.body, effects: lhs.effects - rhs.effects, time: lhs.time)
    }
    public static func * (lhs: CharacterPose, rhs: Float) -> CharacterPose {
        CharacterPose(face: lhs.face * rhs, body: lhs.body * rhs, effects: lhs.effects * rhs, time: lhs.time)
    }
}
