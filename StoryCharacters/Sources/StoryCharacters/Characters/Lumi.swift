import Foundation
import simd

extension CharacterCatalog {

    /// Lumi (reference 1): a golden five-point star wrapped in an indigo, star-speckled hood, holding a glowing
    /// book in one hand and a pencil-wand in the other. The warm storyteller of the group.
    ///
    /// Layout notes: the star's inner radius is only 0.52, so the face is compact and centred — eyes close
    /// together and low, a small mouth just below them, cheeks tucked into the lower star notches.
    /// The brows sit directly under the upper notches (inner vertices at (±0.306, 0.421)), so they are short,
    /// thin and low (browY 0.29): curious, excited and scared raises keep them inside the silhouette, and even the
    /// surprised raise (+0.108) leaves only about 6 % of the upward-bent middle at the notch edge.
    /// Idle: hood sway (`wiggle`), book glow breathing (`accessory`), wand sparkles (`accessory2`), gentle float.
    /// Signature (Core): `.thinking` taps the wand to the chin (accessory2 pulses); `.excited` flares the star tips (glow 1.6).
    public static let lumi: CharacterDesign = CharacterDesign(
        kind: .lumi,
        bodyShape: .star,
        palette: CharacterCatalog.palette(bodyTop: 0xFFE066, bodyBottom: 0xFFB224, highlight: 0xFFF6C2, shadow: 0xE08A12,
                                          accent: 0x1E1748, accent2: 0x7B5CFF, iris: 0x2B1B12, pupil: 0x120A06,
                                          sclera: 0xFFFFFF, cheek: 0xFFB088, glow: 0xFFD36A, mouthInner: 0x5A2415,
                                          tongue: 0xFF7E8A, teeth: 0xFFFFFF, outline: 0x4A2A10),
        face: FaceLayout(eyeOffsetX: 0.30, eyeY: 0.05, eyeRadiusX: 0.17, eyeRadiusY: 0.20,
                         irisRadius: 0.135, pupilRadius: 0.075,
                         browY: 0.29, browLength: 0.16, browThickness: 0.035,
                         mouthY: -0.28, mouthWidth: 0.18, mouthHeight: 0.16,
                         cheekX: 0.40, cheekY: -0.14, cheekRadius: 0.10,
                         faceScale: 1, faceOffsetY: 0),
        frame: FrameLayout(radiusScale: 0.50, centerOffsetY: -0.05),
        features: [.hood, .bookAndWand, .starPattern, .floats],
        idle: IdleStyle(floatAmplitude: 0.03, floatFrequency: 0.5, wobbleAmplitude: 0.02, wobbleFrequency: 0.35,
                        flickerRate: 0, breathDepth: 1),
        personality: Personality(energy: 0.5, shyness: 0.15, curiosity: 0.7, playfulness: 0.5),
        voice: VoiceStyle(pitch: 1.15, rate: 0.95),
        glowStrength: 1.1,
        sparkleRate: 0.45,
        tagline: [
            "ru": "Звёздный сказочник в капюшоне из ночного неба — читает сказки при свете волшебной книги.",
            "en": "A little star storyteller in a night-sky hood, reading tales by the light of a magic book.",
        ]
    )
}
