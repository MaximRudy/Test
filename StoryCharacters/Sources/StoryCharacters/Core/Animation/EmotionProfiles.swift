import Foundation

// MARK: - Profile table (docs/CONTRACT.md §6)

extension EmotionProfile {
    /// Resting state with the design's defaults: eyes open, soft smile, gentle sparkles.
    public static let neutral: EmotionProfile = EmotionProfile(
        face: makeFace(open: 1.0, smile: 0.25),
        body: makeBody(accessory: 0.3, accessory2: 0.3),
        effects: makeEffects(sparkle: 0.35),
        blinkRate: 1, blinkHeaviness: 0, gazeWander: 0.5, cameraBias: 0.6,
        breathRate: 0.22, breathDepth: 1, floatAmplitude: 1, energy: 0.5, microExpressionRate: 1,
        prosody: Prosody(rate: 1, pitch: 1, volume: 1), glowHueShift: 0, transitionStiffness: 1
    )

    /// Full-intensity profile for `emotion`. Tuned for maximal cuteness and instant readability.
    public static func profile(for emotion: Emotion) -> EmotionProfile {
        switch emotion {
        case .neutral:
            return neutral

        case .happy:
            return EmotionProfile(
                face: makeFace(open: 1.0, scale: 1.0, pupil: 1.05, lowerLid: 0.35,
                               raiseL: 0.2, raiseR: 0.2, tiltL: -0.1, tiltR: -0.1,
                               smile: 0.85, mouthOpen: 0.08, width: 0.3, teeth: 0.2,
                               blush: 0.4),
                body: makeBody(scaleY: 1.02, glow: 1.15, accessory: 1.0, accessory2: 0.5),
                effects: makeEffects(sparkle: 0.5),
                blinkRate: 1, blinkHeaviness: 0, gazeWander: 0.5, cameraBias: 0.7,
                breathRate: 0.24, breathDepth: 1, floatAmplitude: 1.1, energy: 0.6, microExpressionRate: 1.2,
                prosody: Prosody(rate: 1.05, pitch: 1.08, volume: 1), glowHueShift: 0.01, transitionStiffness: 1.1
            )

        case .excited:
            return EmotionProfile(
                face: makeFace(open: 1.15, scale: 1.08, pupil: 1.3, lowerLid: 0.1,
                               raiseL: 0.6, raiseR: 0.6, tiltL: 0, tiltR: 0,
                               smile: 0.9, mouthOpen: 0.35, width: 0.4, teeth: 0.5,
                               blush: 0.35, headNod: 0.05),
                body: makeBody(scaleY: 1.05, glow: 1.5, arms: 0.5, accessory: 0.8, accessory2: 0.6),
                effects: makeEffects(sparkle: 0.8),
                blinkRate: 1.2, blinkHeaviness: 0, gazeWander: 0.6, cameraBias: 0.7,
                breathRate: 0.35, breathDepth: 1.3, floatAmplitude: 1.3, energy: 1.0, microExpressionRate: 1.5,
                prosody: Prosody(rate: 1.15, pitch: 1.15, volume: 1), glowHueShift: 0.02, transitionStiffness: 1.6
            )

        case .laughing:
            return EmotionProfile(
                face: makeFace(open: 0.15, scale: 1.0, pupil: 1.0, lowerLid: 0.9,
                               raiseL: 0.3, raiseR: 0.3, tiltL: -0.2, tiltR: -0.2,
                               smile: 1.0, mouthOpen: 0.55, width: 0.5, teeth: 0.6, tongue: 0.2,
                               blush: 0.5, headTilt: 0.06, headNod: 0.3),
                body: makeBody(scaleY: 0.97, tilt: 0.05, glow: 1.2, arms: 0.3, accessory: 0.8, accessory2: 0.4),
                effects: makeEffects(sparkle: 0.5),
                blinkRate: 0.6, blinkHeaviness: 0, gazeWander: 0.3, cameraBias: 0.6,
                breathRate: 0.5, breathDepth: 1.4, floatAmplitude: 1.1, energy: 0.9, microExpressionRate: 1,
                prosody: Prosody(rate: 1.1, pitch: 1.12, volume: 1), glowHueShift: 0.01, transitionStiffness: 1.3
            )

        case .surprised:
            return EmotionProfile(
                face: makeFace(open: 1.3, scale: 1.15, pupil: 0.75, lowerLid: 0,
                               raiseL: 0.9, raiseR: 0.9, tiltL: 0.1, tiltR: 0.1,
                               smile: 0.0, mouthOpen: 0.5, width: -0.3, round: 0.7, teeth: 0.1,
                               blush: 0.2, headNod: 0.1),
                body: makeBody(scaleX: 0.97, scaleY: 1.06, glow: 1.25, arms: 0.4, accessory: 0.6, accessory2: 0.4),
                effects: makeEffects(sparkle: 0.45, exclamation: 1),
                blinkRate: 0.4, blinkHeaviness: 0, gazeWander: 0.2, cameraBias: 0.9,
                breathRate: 0.3, breathDepth: 0.6, floatAmplitude: 0.8, energy: 0.7, microExpressionRate: 0.5,
                prosody: Prosody(rate: 1.05, pitch: 1.18, volume: 1), glowHueShift: 0, transitionStiffness: 2.5
            )

        case .curious:
            return EmotionProfile(
                face: makeFace(open: 1.05, scale: 1.0, pupil: 1.1, lowerLid: 0,
                               raiseL: 0.5, raiseR: 0.0, tiltL: 0, tiltR: 0,
                               smile: 0.3, mouthOpen: 0.1, width: 0, teeth: 0.1,
                               blush: 0.15, headTilt: 0.18),
                body: makeBody(tilt: 0.06, accessory: 0.5, accessory2: 0.35),
                effects: makeEffects(sparkle: 0.4, question: 0.8),
                blinkRate: 1, blinkHeaviness: 0, gazeWander: 0.8, cameraBias: 0.55,
                breathRate: 0.24, breathDepth: 1, floatAmplitude: 1, energy: 0.55, microExpressionRate: 1.5,
                prosody: Prosody(rate: 1.0, pitch: 1.08, volume: 1), glowHueShift: 0, transitionStiffness: 1.1
            )

        case .thinking:
            return EmotionProfile(
                face: makeFace(open: 0.85, scale: 1.0, pupil: 1.0, lowerLid: 0.1,
                               raiseL: 0.3, raiseR: -0.2, tiltL: 0.2, tiltR: 0,
                               smile: 0.1, mouthOpen: 0.0, width: -0.3, round: 0.15,
                               blush: 0.1, headTilt: -0.12,
                               gazeX: 0.45, gazeY: 0.4),
                body: makeBody(tilt: -0.03, arms: 0.35, accessory: 1.0, accessory2: 0.8),
                effects: makeEffects(sparkle: 0.3, question: 0.5),
                blinkRate: 0.9, blinkHeaviness: 0.05, gazeWander: 0.25, cameraBias: 0.15,
                breathRate: 0.2, breathDepth: 0.9, floatAmplitude: 0.8, energy: 0.3, microExpressionRate: 0.8,
                prosody: Prosody(rate: 0.9, pitch: 0.98, volume: 0.9), glowHueShift: 0, transitionStiffness: 0.9
            )

        case .sad:
            return EmotionProfile(
                face: makeFace(open: 0.7, scale: 1.0, pupil: 1.1, lowerLid: 0.0,
                               raiseL: -0.1, raiseR: -0.1, tiltL: 0.8, tiltR: 0.8,
                               smile: -0.6, mouthOpen: 0.05, width: -0.2,
                               blush: 0.1, headNod: -0.3,
                               gazeY: -0.3),
                body: makeBody(scaleY: 0.96, offsetY: -0.05, tilt: 0, glow: 0.7, arms: -0.3, accessory: 0.1, accessory2: 0.1),
                effects: makeEffects(sparkle: 0.15, tears: 0.6),
                blinkRate: 0.8, blinkHeaviness: 0.2, gazeWander: 0.3, cameraBias: 0.3,
                breathRate: 0.16, breathDepth: 1.2, floatAmplitude: 0.5, energy: 0.15, microExpressionRate: 0.5,
                prosody: Prosody(rate: 0.82, pitch: 0.9, volume: 0.8), glowHueShift: -0.02, transitionStiffness: 0.5
            )

        case .scared:
            return EmotionProfile(
                face: makeFace(open: 1.25, scale: 1.1, pupil: 0.7, lowerLid: 0,
                               raiseL: 0.7, raiseR: 0.7, tiltL: 0.6, tiltR: 0.6,
                               smile: -0.3, mouthOpen: 0.3, width: 0.4, teeth: 0.4,
                               blush: 0, headNod: -0.05),
                body: makeBody(scaleX: 0.95, scaleY: 0.95, offsetY: -0.03, glow: 0.8, arms: 0.2, accessory: 0.2, accessory2: 0.2),
                effects: makeEffects(sparkle: 0.2, sweat: 0.8),
                blinkRate: 1.4, blinkHeaviness: 0, gazeWander: 0.7, cameraBias: 0.5,
                breathRate: 0.6, breathDepth: 0.8, floatAmplitude: 0.7, energy: 0.6, microExpressionRate: 1.2,
                prosody: Prosody(rate: 1.15, pitch: 1.12, volume: 0.9), glowHueShift: -0.03, transitionStiffness: 2.0
            )

        case .sleepy:
            return EmotionProfile(
                face: makeFace(open: 0.35, scale: 1.0, pupil: 1.0, lowerLid: 0.2,
                               raiseL: -0.15, raiseR: -0.15, tiltL: 0.3, tiltR: 0.3,
                               smile: 0.1, mouthOpen: 0.0, width: -0.1,
                               blush: 0.2, headTilt: 0.1, headNod: -0.25,
                               gazeY: -0.2),
                body: makeBody(offsetY: -0.04, tilt: 0.1, glow: 0.6, arms: -0.2, accessory: 0.05, accessory2: 0.1),
                effects: makeEffects(sparkle: 0.15, zzz: 0.8),
                blinkRate: 0.5, blinkHeaviness: 0.55, gazeWander: 0.15, cameraBias: 0.3,
                breathRate: 0.12, breathDepth: 1.8, floatAmplitude: 0.6, energy: 0.1, microExpressionRate: 0.3,
                prosody: Prosody(rate: 0.78, pitch: 0.92, volume: 0.75), glowHueShift: 0, transitionStiffness: 0.6
            )

        case .grumpy:
            return EmotionProfile(
                face: makeFace(open: 0.75, scale: 1.0, pupil: 0.85, lowerLid: 0.3,
                               raiseL: -0.7, raiseR: -0.7, tiltL: -0.8, tiltR: -0.8,
                               smile: -0.5, mouthOpen: 0.0, width: -0.3, press: 0.2,
                               blush: 0.15, headNod: -0.1),
                body: makeBody(scaleX: 1.04, scaleY: 0.97, glow: 0.9, arms: -0.4, accessory: 0.2, accessory2: 0.2),
                effects: makeEffects(sparkle: 0.2),
                blinkRate: 0.8, blinkHeaviness: 0.1, gazeWander: 0.3, cameraBias: 0.4,
                breathRate: 0.26, breathDepth: 1.1, floatAmplitude: 0.7, energy: 0.35, microExpressionRate: 0.6,
                prosody: Prosody(rate: 0.92, pitch: 0.88, volume: 0.95), glowHueShift: -0.03, transitionStiffness: 1.0
            )

        case .shy:
            return EmotionProfile(
                face: makeFace(open: 0.85, scale: 1.0, pupil: 1.15, lowerLid: 0.25,
                               raiseL: 0.3, raiseR: 0.3, tiltL: 0.4, tiltR: 0.4,
                               smile: 0.45, mouthOpen: 0.0, width: -0.2,
                               blush: 1.0, headTilt: 0.15, headTurn: -0.4,
                               gazeX: -0.25, gazeY: -0.15),
                body: makeBody(offsetX: -0.04, arms: 0.3, accessory: 0.4, accessory2: 0.25),
                effects: makeEffects(sparkle: 0.3),
                blinkRate: 1.3, blinkHeaviness: 0.1, gazeWander: 0.6, cameraBias: 0.2,
                breathRate: 0.26, breathDepth: 0.9, floatAmplitude: 0.8, energy: 0.3, microExpressionRate: 1.2,
                prosody: Prosody(rate: 0.9, pitch: 1.05, volume: 0.75), glowHueShift: 0.01, transitionStiffness: 0.9
            )

        case .love:
            return EmotionProfile(
                face: makeFace(open: 0.9, scale: 1.05, pupil: 1.45, lowerLid: 0.3,
                               raiseL: 0.4, raiseR: 0.4, tiltL: 0.3, tiltR: 0.3,
                               smile: 0.8, mouthOpen: 0.1, width: 0.1, teeth: 0.1,
                               blush: 0.8, headTilt: 0.08),
                body: makeBody(scaleY: 1.03, glow: 1.4, arms: 0.3, accessory: 1.0, accessory2: 0.6),
                effects: makeEffects(sparkle: 0.6, hearts: 1),
                blinkRate: 0.8, blinkHeaviness: 0.1, gazeWander: 0.2, cameraBias: 0.9,
                breathRate: 0.2, breathDepth: 1.2, floatAmplitude: 1.5, energy: 0.5, microExpressionRate: 1,
                prosody: Prosody(rate: 0.95, pitch: 1.1, volume: 0.95), glowHueShift: 0.04, transitionStiffness: 0.9
            )

        case .listening:
            return EmotionProfile(
                face: makeFace(open: 1.05, scale: 1.0, pupil: 1.05, lowerLid: 0,
                               raiseL: 0.35, raiseR: 0.35, tiltL: 0, tiltR: 0,
                               smile: 0.4, mouthOpen: 0.05, width: 0.1,
                               blush: 0.2, headTilt: 0.12),
                body: makeBody(offsetY: 0.02, accessory: 0.5, accessory2: 0.3),
                effects: makeEffects(sparkle: 0.35),
                blinkRate: 0.8, blinkHeaviness: 0, gazeWander: 0.2, cameraBias: 0.95,
                breathRate: 0.22, breathDepth: 0.9, floatAmplitude: 0.8, energy: 0.35, microExpressionRate: 0.8,
                prosody: Prosody(rate: 1, pitch: 1, volume: 1), glowHueShift: 0, transitionStiffness: 1.0
            )
        }
    }

    /// Profile for `emotion` at `intensity` (0 = neutral … 1 = full profile). Every field is interpolated.
    public static func profile(for emotion: Emotion, intensity: Float) -> EmotionProfile {
        let k = min(max(intensity, 0), 1)
        let full = profile(for: emotion)
        if k >= 1 { return full }
        return interpolate(from: neutral, to: full, k)
    }

    /// Linear interpolation of every field (prosody included).
    public static func interpolate(from a: EmotionProfile, to b: EmotionProfile, _ t: Float) -> EmotionProfile {
        EmotionProfile(
            face: FacePose.lerp(a.face, b.face, t),
            body: BodyPose.lerp(a.body, b.body, t),
            effects: EffectsPose.lerp(a.effects, b.effects, t),
            blinkRate: RigCurves.lerp(a.blinkRate, b.blinkRate, t),
            blinkHeaviness: RigCurves.lerp(a.blinkHeaviness, b.blinkHeaviness, t),
            gazeWander: RigCurves.lerp(a.gazeWander, b.gazeWander, t),
            cameraBias: RigCurves.lerp(a.cameraBias, b.cameraBias, t),
            breathRate: RigCurves.lerp(a.breathRate, b.breathRate, t),
            breathDepth: RigCurves.lerp(a.breathDepth, b.breathDepth, t),
            floatAmplitude: RigCurves.lerp(a.floatAmplitude, b.floatAmplitude, t),
            energy: RigCurves.lerp(a.energy, b.energy, t),
            microExpressionRate: RigCurves.lerp(a.microExpressionRate, b.microExpressionRate, t),
            prosody: Prosody(rate: RigCurves.lerp(a.prosody.rate, b.prosody.rate, t),
                             pitch: RigCurves.lerp(a.prosody.pitch, b.prosody.pitch, t),
                             volume: RigCurves.lerp(a.prosody.volume, b.prosody.volume, t)),
            glowHueShift: RigCurves.lerp(a.glowHueShift, b.glowHueShift, t),
            transitionStiffness: RigCurves.lerp(a.transitionStiffness, b.transitionStiffness, t)
        )
    }
}

// MARK: - Builders

extension EmotionProfile {
    /// Builds a resting face. Eye/brow values apply to both sides unless a side is given explicitly.
    static func makeFace(open: Float, scale: Float = 1, pupil: Float = 1, lowerLid: Float = 0,
                         raiseL: Float = 0, raiseR: Float = 0, tiltL: Float = 0, tiltR: Float = 0,
                         smile: Float, mouthOpen: Float = 0, width: Float = 0, round: Float = 0,
                         teeth: Float = 0, tongue: Float = 0, press: Float = 0,
                         blush: Float = 0, headTilt: Float = 0, headTurn: Float = 0, headNod: Float = 0,
                         gazeX: Float = 0, gazeY: Float = 0) -> FacePose {
        var f = FacePose.neutral
        f.eyeOpenL = open
        f.eyeOpenR = open
        f.eyeScale = scale
        f.pupil = pupil
        f.lowerLidL = lowerLid
        f.lowerLidR = lowerLid
        f.browRaiseL = raiseL
        f.browRaiseR = raiseR
        f.browTiltL = tiltL
        f.browTiltR = tiltR
        f.blush = blush
        f.headTilt = headTilt
        f.headTurn = headTurn
        f.headNod = headNod
        f.gazeX = gazeX
        f.gazeY = gazeY
        f.mouth = MouthShape(open: mouthOpen, width: width, smile: smile, round: round,
                             upperTeeth: teeth, lowerTeeth: teeth * 0.5, tongue: tongue, press: press)
        return f
    }

    static func makeBody(scaleX: Float = 1, scaleY: Float = 1, offsetX: Float = 0, offsetY: Float = 0,
                         tilt: Float = 0, glow: Float = 1, arms: Float = 0,
                         accessory: Float = 0.3, accessory2: Float = 0.3) -> BodyPose {
        var b = BodyPose.neutral
        b.scaleX = scaleX
        b.scaleY = scaleY
        b.offsetX = offsetX
        b.offsetY = offsetY
        b.tilt = tilt
        b.glow = glow
        b.armL = arms
        b.armR = arms
        b.accessory = accessory
        b.accessory2 = accessory2
        return b
    }

    static func makeEffects(sparkle: Float, tears: Float = 0, sweat: Float = 0, hearts: Float = 0,
                            zzz: Float = 0, question: Float = 0, exclamation: Float = 0) -> EffectsPose {
        var e = EffectsPose.neutral
        e.sparkleRate = sparkle
        e.tears = tears
        e.sweat = sweat
        e.hearts = hearts
        e.zzz = zzz
        e.question = question
        e.exclamation = exclamation
        return e
    }
}
