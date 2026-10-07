import Foundation
import simd

extension CharacterCatalog {

    /// Ember (reference 5, leftmost): the fire elemental — an orange flame with waving tongues, stubby arms and
    /// legs and a big open-mouth grin. The most energetic of the eight.
    ///
    /// Layout notes: eyes at y 0, wide mouth (half width 0.24, tall when open) at −0.38 for big laughs,
    /// cheeks beside the mouth. Shares the Elementals frame (`radiusScale 0.56`, body raised 0.08 R so the legs
    /// and the flame tip balance). Idle: flicker 1.6 Hz, lively bob.
    public static let ember: CharacterDesign = CharacterDesign(
        kind: .ember,
        bodyShape: .flame,
        palette: CharacterCatalog.palette(bodyTop: 0xFFD93D, bodyBottom: 0xFF7A1A, highlight: 0xFFF3B0, shadow: 0xD8450C,
                                          accent: 0xFFF0A0, accent2: 0xFF4D1C, iris: 0x5A2E0F, pupil: 0x1A0A02,
                                          sclera: 0xFFFFFF, cheek: 0xFF8A6A, glow: 0xFF9A3A, mouthInner: 0x6E1E12,
                                          tongue: 0xFF6B6B, teeth: 0xFFFFFF, outline: 0x7A3A10),
        face: FaceLayout(eyeOffsetX: 0.36, eyeY: 0.0, eyeRadiusX: 0.20, eyeRadiusY: 0.23,
                         irisRadius: 0.155, pupilRadius: 0.085,
                         browY: 0.32, browLength: 0.24, browThickness: 0.045,
                         mouthY: -0.38, mouthWidth: 0.24, mouthHeight: 0.22,
                         cheekX: 0.52, cheekY: -0.28, cheekRadius: 0.14,
                         faceScale: 1, faceOffsetY: 0),
        frame: FrameLayout(radiusScale: 0.56, centerOffsetY: 0.08),
        features: [.arms, .legs, .flicker, .innerFlame],
        idle: IdleStyle(floatAmplitude: 0.012, floatFrequency: 1.1, wobbleAmplitude: 0.03, wobbleFrequency: 0.8,
                        flickerRate: 1.6, breathDepth: 1.1),
        personality: Personality(energy: 0.9, shyness: 0.05, curiosity: 0.6, playfulness: 0.8),
        voice: VoiceStyle(pitch: 1.2, rate: 1.1, preferredVoiceIdentifiers: CharacterCatalog.russianVoiceIdentifiers),
        glowStrength: 1.5,
        sparkleRate: 0.45,
        tagline: [
            "ru": "Неугомонный огонёк — прыгает, хохочет и греет друзей своим теплом.",
            "en": "A restless little flame who hops, giggles and keeps every friend warm.",
        ]
    )
}
