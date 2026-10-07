import Foundation

// MARK: - GestureClip

/// A one-shot animation expressed as an additive pose delta over normalized time `u` ∈ 0…1.
/// Every curve is C¹ and starts/ends at exactly zero delta, so clips can be layered and
/// cross-faded without pops.
public struct GestureClip: Sendable, Equatable {
    public let gesture: Gesture
    public let duration: TimeInterval
    /// False for designs without `.arms`: arm-led gestures (the wave) move the body and the accessories instead.
    public let hasArms: Bool

    /// - Parameters:
    ///   - energy: the current emotion's energy; lively characters perform gestures a bit faster.
    ///   - hasArms: whether the design draws arms (`DesignFeatures.arms`).
    public init(gesture: Gesture, energy: Float = 0.5, hasArms: Bool = true) {
        self.gesture = gesture
        let e = min(max(energy, 0), 1)
        self.duration = gesture.nominalDuration * Double(1.15 - 0.3 * e)
        self.hasArms = hasArms
    }

    public init(gesture: Gesture, duration: TimeInterval, hasArms: Bool = true) {
        self.gesture = gesture
        self.duration = max(0.05, duration)
        self.hasArms = hasArms
    }

    /// Additive delta at normalized time `u` (0 = start, 1 = end). Zero outside 0…1.
    public func evaluate(u: Float) -> CharacterPose {
        guard u > 0, u < 1 else { return .zero }
        var d = CharacterPose.zero
        let env = RigCurves.window(u)
        switch gesture {
        case .nod:
            // Two quick nods (down first), the body dips a touch with each.
            let n = RigCurves.wave(u, cycles: 2)
            d.face.headNod = -0.35 * n
            d.body.offsetY = -0.012 * max(0, n)
            d.face.mouth.smile = 0.1 * env

        case .shake:
            // Head shake with the gaze trailing slightly behind.
            let s = RigCurves.wave(u, cycles: 2.5)
            d.face.headTurn = 0.6 * s
            d.face.gazeX = -0.15 * s
            d.body.tilt = 0.03 * s
            d.face.browTiltL = 0.1 * env
            d.face.browTiltR = 0.1 * env
            d.face.mouth.smile = -0.1 * env

        case .bounce:
            // Anticipation squash → stretch at take-off → airborne → landing squash.
            let anticipation = RigCurves.bump(u, center: 0.12, width: 0.24)
            let takeoff = RigCurves.bump(u, center: 0.38, width: 0.30)
            let air = RigCurves.bump(u, center: 0.55, width: 0.60)
            let landing = RigCurves.bump(u, center: 0.92, width: 0.16)
            d.body.scaleY = -0.10 * anticipation + 0.12 * takeoff - 0.10 * landing
            d.body.scaleX = 0.08 * anticipation - 0.08 * takeoff + 0.08 * landing
            d.body.offsetY = 0.30 * air
            d.body.bounce = air
            d.body.legL = 0.6 * air
            d.body.legR = 0.6 * air
            d.body.armL = 0.4 * air
            d.body.armR = 0.4 * air
            d.face.eyeOpenL = 0.05 * air
            d.face.eyeOpenR = 0.05 * air
            d.face.mouth.smile = 0.25 * env
            d.face.mouth.open = 0.1 * air

        case .wave:
            // Right arm up and rocking; the whole body sways along. Designs without arms rock the body twice as far
            // and flourish their accessory instead (Lumi's wand lights up, a flame's inner core flares).
            let raise = RigCurves.plateau(u, attack: 0.2, release: 0.25)
            let rock = RigCurves.wave(u, cycles: 3.5)
            if hasArms {
                d.body.armR = 0.9 * raise + 0.15 * rock
                d.body.tilt = 0.06 * rock
            } else {
                d.body.tilt = 0.12 * rock
                d.body.accessory2 = 0.6 * raise
            }
            d.face.headTilt = 0.10 * raise + 0.04 * rock
            d.face.mouth.smile = 0.25 * raise
            d.face.mouth.open = 0.05 * raise
            d.face.browRaiseL = 0.2 * raise
            d.face.browRaiseR = 0.2 * raise
            d.face.eyeOpenL = 0.03 * raise
            d.face.eyeOpenR = 0.03 * raise
            d.body.glow = 0.1 * raise

        case .think:
            // Gaze up-right, brow asymmetry, hand to chin, question mark; the accessory pulses.
            let hold = RigCurves.plateau(u, attack: 0.18, release: 0.22)
            let pulse = 0.5 + 0.5 * sin(2 * Float.pi * 2 * u)
            d.face.gazeX = 0.45 * hold
            d.face.gazeY = 0.40 * hold
            d.face.browRaiseL = 0.40 * hold
            d.face.browRaiseR = -0.15 * hold
            d.face.headTilt = -0.15 * hold
            d.face.mouth.width = -0.25 * hold
            d.face.mouth.smile = -0.10 * hold
            d.face.mouth.round = 0.15 * hold
            d.effects.question = 0.8 * hold
            d.body.armR = 0.6 * hold
            d.body.accessory = 0.3 * hold
            d.body.accessory2 = 0.5 * hold * pulse

        case .surprisePop:
            // Fast pop, slow settle.
            let pop = RigCurves.pop(u, attack: 0.08)
            let punch = RigCurves.bump(u, center: 0.12, width: 0.24)
            d.face.eyeOpenL = 0.30 * pop
            d.face.eyeOpenR = 0.30 * pop
            d.face.eyeScale = 0.15 * pop
            d.face.pupil = -0.25 * pop
            d.face.browRaiseL = 0.9 * pop
            d.face.browRaiseR = 0.9 * pop
            d.face.mouth.open = 0.45 * pop
            d.face.mouth.round = 0.5 * pop
            d.face.mouth.width = -0.2 * pop
            d.face.mouth.smile = -0.1 * pop
            d.face.headNod = 0.12 * pop
            d.body.scaleX = 0.10 * punch - 0.02 * pop
            d.body.scaleY = 0.10 * punch + 0.04 * pop
            d.body.offsetY = 0.05 * punch
            d.body.glow = 0.2 * pop
            d.effects.exclamation = pop

        case .shy:
            // Turn away, blush, hands to face, peek back towards the end.
            let hold = RigCurves.plateau(u, attack: 0.2, release: 0.25)
            let peek = RigCurves.bump(u, center: 0.68, width: 0.3)
            d.face.headTurn = -0.45 * hold + 0.35 * peek
            d.face.headTilt = 0.15 * hold
            d.face.gazeX = -0.4 * hold + 0.6 * peek
            d.face.gazeY = -0.2 * hold + 0.2 * peek
            d.face.blush = 0.8 * hold
            d.face.eyeOpenL = -0.2 * hold + 0.1 * peek
            d.face.eyeOpenR = -0.2 * hold + 0.1 * peek
            d.face.lowerLidL = 0.3 * hold
            d.face.lowerLidR = 0.3 * hold
            d.face.mouth.smile = 0.25 * hold
            d.face.mouth.width = -0.15 * hold
            d.body.offsetX = -0.05 * hold
            d.body.tilt = -0.04 * hold
            d.body.armL = 0.4 * hold
            d.body.armR = 0.4 * hold

        case .celebrate:
            // Anticipation squash, two hops, a wiggle "spin", arms up, sparkle bursts and hearts.
            let anticipation = RigCurves.bump(u, center: 0.06, width: 0.12)
            let hop1 = RigCurves.bump(u, center: 0.28, width: 0.36)
            let hop2 = RigCurves.bump(u, center: 0.68, width: 0.36)
            let hops = hop1 + hop2
            let spin = RigCurves.wave(u, cycles: 1.5)
            d.body.offsetY = 0.28 * hops
            d.body.bounce = min(1, hops)
            let landing1 = RigCurves.bump(u, center: 0.48, width: 0.12)
            let landing2 = RigCurves.bump(u, center: 0.9, width: 0.16)
            d.body.scaleY = 0.08 * hops - 0.08 * anticipation - 0.06 * landing1 - 0.06 * landing2
            d.body.scaleX = -0.05 * hops + 0.06 * anticipation
            d.body.tilt = 0.25 * spin
            d.body.armL = 1.0 * env
            d.body.armR = 1.0 * env
            d.body.legL = 0.6 * hop1 + 0.3 * hop2
            d.body.legR = 0.3 * hop1 + 0.6 * hop2
            d.body.glow = 0.5 * env
            d.body.accessory = 0.5 * env
            d.body.accessory2 = 0.6 * env
            d.effects.sparkleBurst = RigCurves.bump(u, center: 0.16, width: 0.3) + RigCurves.bump(u, center: 0.58, width: 0.3)
            d.effects.hearts = 0.6 * env
            d.face.mouth.smile = 0.3 * env
            d.face.mouth.open = 0.3 * env
            d.face.lowerLidL = 0.4 * env
            d.face.lowerLidR = 0.4 * env
            d.face.browRaiseL = 0.3 * env
            d.face.browRaiseR = 0.3 * env

        case .wink:
            // Right eye closes with a smile and a little head tilt.
            let close = RigCurves.plateau(u, attack: 0.22, release: 0.3)
            d.face.eyeOpenR = -1.3 * close
            d.face.lowerLidR = 0.3 * close
            d.face.browRaiseR = -0.2 * close
            d.face.browRaiseL = 0.2 * close
            d.face.headTilt = 0.12 * close
            d.face.mouth.smile = 0.3 * close
            d.face.mouth.width = 0.1 * close
            d.body.tilt = 0.03 * close
            d.body.glow = 0.1 * close

        case .yawn:
            // Slow wide yawn: mouth round and open, eyes squeeze shut, head back, arms stretch.
            let yawn = RigCurves.plateau(u, attack: 0.3, release: 0.3)
            let stretch = RigCurves.bump(u, center: 0.5, width: 0.9)
            d.face.mouth.open = 0.8 * yawn
            d.face.mouth.round = 0.4 * yawn
            d.face.mouth.width = -0.3 * yawn
            d.face.mouth.smile = -0.1 * yawn
            d.face.mouth.tongue = 0.2 * yawn
            // −1.3 shuts even wide (1.3) eyes; the squint closes the last sliver of iris.
            d.face.eyeOpenL = -1.3 * yawn
            d.face.eyeOpenR = -1.3 * yawn
            d.face.lowerLidL = 0.3 * yawn
            d.face.lowerLidR = 0.3 * yawn
            d.face.browRaiseL = 0.3 * yawn
            d.face.browRaiseR = 0.3 * yawn
            d.face.browTiltL = 0.3 * yawn
            d.face.browTiltR = 0.3 * yawn
            d.face.headNod = 0.3 * yawn
            d.body.scaleY = 0.06 * stretch
            d.body.scaleX = -0.03 * stretch
            d.body.armL = 0.7 * stretch
            d.body.armR = 0.7 * stretch
            d.body.offsetY = 0.02 * stretch

        case .peek:
            // Leans in towards the viewer, eyes widen, brows up.
            let lean = RigCurves.plateau(u, attack: 0.25, release: 0.3)
            d.body.offsetY = 0.03 * lean
            d.body.scaleY = 0.05 * lean
            d.body.scaleX = 0.02 * lean
            d.face.eyeOpenL = 0.15 * lean
            d.face.eyeOpenR = 0.15 * lean
            d.face.eyeScale = 0.06 * lean
            d.face.pupil = 0.2 * lean
            d.face.browRaiseL = 0.4 * lean
            d.face.browRaiseR = 0.4 * lean
            d.face.headNod = 0.1 * lean
            d.face.headTilt = 0.06 * lean
            d.face.mouth.open = 0.1 * lean
            d.face.mouth.smile = 0.15 * lean

        case .giggle:
            // Fast little bounces, squinty eyes, big smile, hands near the mouth.
            let s = sin(2 * Float.pi * 5 * u)
            let bob = (0.5 + 0.5 * s) * env
            d.body.offsetY = 0.02 * bob
            d.body.scaleY = 0.03 * s * env
            d.body.scaleX = -0.02 * s * env
            d.body.tilt = 0.03 * RigCurves.wave(u, cycles: 2.5)
            d.body.armL = 0.3 * env
            d.body.armR = 0.3 * env
            d.face.eyeOpenL = -0.6 * env
            d.face.eyeOpenR = -0.6 * env
            d.face.lowerLidL = 0.6 * env
            d.face.lowerLidR = 0.6 * env
            d.face.mouth.smile = 0.5 * env
            d.face.mouth.open = 0.2 * env + 0.1 * bob
            d.face.mouth.width = 0.2 * env
            d.face.headTilt = 0.1 * RigCurves.wave(u, cycles: 2.5)
            d.face.headNod = 0.05 * s * env
            d.face.blush = 0.3 * env

        case .sleep:
            // Dozes off: eyes droop shut, head sinks, zzz rises, then drifts back.
            let doze = RigCurves.plateau(u, attack: 0.45, release: 0.3)
            d.face.eyeOpenL = -1.3 * doze
            d.face.eyeOpenR = -1.3 * doze
            d.face.browRaiseL = -0.15 * doze
            d.face.browRaiseR = -0.15 * doze
            d.face.browTiltL = 0.2 * doze
            d.face.browTiltR = 0.2 * doze
            d.face.headNod = -0.3 * doze
            d.face.headTilt = 0.1 * doze
            d.face.mouth.smile = 0.1 * doze
            d.face.mouth.open = 0.05 * doze
            d.body.offsetY = -0.04 * doze
            d.body.scaleY = -0.03 * doze
            d.body.tilt = 0.08 * doze
            d.body.glow = -0.3 * doze
            d.body.armL = -0.3 * doze
            d.body.armR = -0.3 * doze
            d.effects.zzz = 0.8 * doze

        case .wakeUp:
            // Eyes pop open, quick shake, then a big stretch.
            let pop = RigCurves.pop(u, attack: 0.1)
            let shake = RigCurves.wave(u, cycles: 3) * RigCurves.bump(u, center: 0.3, width: 0.5)
            let stretch = RigCurves.bump(u, center: 0.72, width: 0.5)
            d.face.eyeOpenL = 0.3 * pop
            d.face.eyeOpenR = 0.3 * pop
            d.face.eyeScale = 0.1 * pop
            d.face.browRaiseL = 0.6 * pop
            d.face.browRaiseR = 0.6 * pop
            d.face.headTurn = 0.5 * shake
            d.face.mouth.open = 0.3 * stretch
            d.face.mouth.round = 0.2 * stretch
            d.body.scaleY = 0.08 * stretch
            d.body.scaleX = -0.04 * stretch
            d.body.armL = 0.8 * stretch
            d.body.armR = 0.8 * stretch
            d.body.offsetY = 0.03 * stretch
            d.body.glow = 0.2 * pop
            d.effects.sparkleBurst = 0.5 * RigCurves.bump(u, center: 0.14, width: 0.28)
        }
        return d
    }
}

// MARK: - GesturePlayer

/// Plays one clip at a time. Interrupting or cancelling cross-fades over 120 ms so nothing pops.
///
/// * The incoming clip fades in from its own start (`fadeInStart`), independent of what is fading out.
/// * The most recently interrupted clip keeps animating while its weight falls from the value it had at the
///   moment of interruption to 0.
/// * When a clip is interrupted while another one is still fading out (rapid taps), the older clip's exact
///   weighted contribution at that instant is folded into a frozen `residue` pose that fades to zero over
///   120 ms. Any number of interruptions therefore stays continuous, with fixed storage and no allocation.
struct GesturePlayer: Sendable, Equatable {
    static let crossFade: Float = 0.12

    private(set) var current: GestureClip?
    private var currentStart: Float = 0
    /// Start of the current clip's fade-in; nil = full weight.
    private var fadeInStart: Float?

    /// Interrupted clip, still evaluated live while it fades out.
    private var previous: GestureClip?
    private var previousStart: Float = 0
    private var previousFadeStart: Float = 0
    /// Weight `previous` had when it was interrupted (its fade-out starts from here).
    private var previousWeight: Float = 0

    /// Frozen, already weighted delta of older interrupted clips; fades to zero from `residueFadeStart`.
    private var residue: CharacterPose = .zero
    private var residueFadeStart: Float = 0
    private var hasResidue = false

    init() {}

    /// The gesture currently driving the pose (nil when idle or only fading out).
    var activeGesture: Gesture? { current?.gesture }

    mutating func play(_ clip: GestureClip, at time: Float) {
        let interrupted = current != nil
        retireCurrent(at: time)
        current = clip
        currentStart = time
        fadeInStart = interrupted ? time : nil
    }

    /// Fades the current clip out over 120 ms.
    mutating func cancel(at time: Float) {
        guard current != nil else { return }
        retireCurrent(at: time)
        current = nil
        fadeInStart = nil
    }

    mutating func reset() {
        current = nil
        fadeInStart = nil
        previous = nil
        residue = .zero
        hasResidue = false
    }

    /// Additive delta for `time`; drops finished clips.
    mutating func evaluate(at time: Float) -> CharacterPose {
        var delta = CharacterPose.zero
        if hasResidue {
            let w = residueWeight(at: time)
            if w <= 0 {
                hasResidue = false
                residue = .zero
            } else {
                delta += residue * w
            }
        }
        if let prev = previous {
            let w = previousFadeWeight(at: time)
            let u = GesturePlayer.progress(at: time, start: previousStart, duration: prev.duration)
            if w <= 0 || u >= 1 {
                previous = nil
            } else {
                delta += prev.evaluate(u: u) * w
            }
        }
        if let cur = current {
            let u = GesturePlayer.progress(at: time, start: currentStart, duration: cur.duration)
            if u >= 1 {
                current = nil
                fadeInStart = nil
            } else {
                let w = currentWeight(at: time)
                if w >= 1 { fadeInStart = nil }
                delta += cur.evaluate(u: u) * w
            }
        }
        return delta
    }

    // MARK: Internals

    /// Moves the current clip into the fading-out slot at exactly the weight it has at `time`.
    /// A clip still occupying that slot is frozen into the residue at its exact contribution first.
    private mutating func retireCurrent(at time: Float) {
        if let prev = previous {
            let u = GesturePlayer.progress(at: time, start: previousStart, duration: prev.duration)
            let contribution = prev.evaluate(u: u) * previousFadeWeight(at: time)
            let carried = hasResidue ? residue * residueWeight(at: time) : CharacterPose.zero
            residue = carried + contribution
            residueFadeStart = time
            hasResidue = true
            previous = nil
        }
        guard let cur = current else { return }
        previous = cur
        previousStart = currentStart
        previousFadeStart = time
        previousWeight = currentWeight(at: time)
    }

    private func currentWeight(at time: Float) -> Float {
        guard let start = fadeInStart else { return 1 }
        return RigCurves.smoothstep((time - start) / GesturePlayer.crossFade)
    }

    private func previousFadeWeight(at time: Float) -> Float {
        previousWeight * (1 - RigCurves.smoothstep((time - previousFadeStart) / GesturePlayer.crossFade))
    }

    private func residueWeight(at time: Float) -> Float {
        1 - RigCurves.smoothstep((time - residueFadeStart) / GesturePlayer.crossFade)
    }

    private static func progress(at time: Float, start: Float, duration: TimeInterval) -> Float {
        Float(Double(time - start) / duration)
    }
}
