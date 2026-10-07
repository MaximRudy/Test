import Foundation
import simd

extension CharacterCatalog {

    /// Sprout (reference 5, rightmost): the earth elemental — a round brown body with a green scalloped cap and
    /// two leaves, stubby arms and legs. Calm and kind.
    ///
    /// Layout notes: the cap covers the body above y 0.35 with a scalloped edge that dips to about 0.34 above the
    /// eyes, so the brows are short, thin and low (browY 0.28): at rest they sit fully under the cap edge and
    /// still clear the eye tops (0.26). Eyes at y 0.02, mouth at −0.36 (both fixed by the contract), so strongly
    /// raised brows still reach the cap. Shares the Elementals frame, barely raised (leaves and legs balance).
    /// Idle: slow, grounded; leaves wiggle with `accessory`.
    public static let sprout: CharacterDesign = CharacterDesign(
        kind: .sprout,
        bodyShape: .round,
        palette: CharacterCatalog.palette(bodyTop: 0xD9893C, bodyBottom: 0x9C5A22, highlight: 0xF3C58C, shadow: 0x6E3B12,
                                          accent: 0x6DBE45, accent2: 0x3F9A2E, iris: 0x7A4414, pupil: 0x1C0C03,
                                          sclera: 0xFFFFFF, cheek: 0xFF9E7E, glow: 0xB7E07A, mouthInner: 0x5A2A10,
                                          tongue: 0xFF8080, teeth: 0xFFFFFF, outline: 0x4F2A0E),
        face: FaceLayout(eyeOffsetX: 0.38, eyeY: 0.02, eyeRadiusX: 0.21, eyeRadiusY: 0.24,
                         irisRadius: 0.165, pupilRadius: 0.09,
                         browY: 0.28, browLength: 0.18, browThickness: 0.035,
                         mouthY: -0.36, mouthWidth: 0.20, mouthHeight: 0.20,
                         cheekX: 0.54, cheekY: -0.22, cheekRadius: 0.15,
                         faceScale: 1, faceOffsetY: 0),
        frame: FrameLayout(radiusScale: 0.56, centerOffsetY: 0.04),
        features: [.arms, .legs, .leaves],
        idle: IdleStyle(floatAmplitude: 0.01, floatFrequency: 0.8, wobbleAmplitude: 0.02, wobbleFrequency: 0.4,
                        flickerRate: 0, breathDepth: 1),
        personality: Personality(energy: 0.4, shyness: 0.4, curiosity: 0.5, playfulness: 0.4),
        voice: VoiceStyle(pitch: 1.1, rate: 0.9),
        glowStrength: 0.7,
        sparkleRate: 0.3,
        tagline: [
            "ru": "Добрый росток в шляпке из листьев — растёт потихоньку и всегда готов обнять.",
            "en": "A kind little sprout in a leafy cap who grows slowly and is always ready for a hug.",
        ]
    )
}
