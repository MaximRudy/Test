import Foundation
import simd

extension CharacterCatalog {

    /// Drop (reference 5, second): the water elemental — a glossy blue jelly teardrop with stubby arms and legs.
    /// Cheerful and wobbly.
    ///
    /// Layout notes: the drop's round part is centred at (0, −0.15), so the eyes sit at y 0 and the mouth at
    /// −0.40; the mouth is fairly wide (0.22) for open laughs. Shares the Elementals frame.
    /// Idle: strong jelly wobble (`wobbleAmplitude 0.05`).
    public static let drop: CharacterDesign = CharacterDesign(
        kind: .drop,
        bodyShape: .drop,
        palette: CharacterCatalog.palette(bodyTop: 0x7FD8FF, bodyBottom: 0x2A8CFF, highlight: 0xE6F9FF, shadow: 0x1E5BD6,
                                          accent: 0xBDEBFF, accent2: 0x1266D1, iris: 0xC04B6E, pupil: 0x2A0C1A,
                                          sclera: 0xFFFFFF, cheek: 0xFF9FC0, glow: 0x6FC3FF, mouthInner: 0x1E3F8A,
                                          tongue: 0xFF7FA3, teeth: 0xFFFFFF, outline: 0x1B4FA8),
        face: FaceLayout(eyeOffsetX: 0.36, eyeY: 0.0, eyeRadiusX: 0.21, eyeRadiusY: 0.24,
                         irisRadius: 0.165, pupilRadius: 0.09,
                         browY: 0.33, browLength: 0.24, browThickness: 0.045,
                         mouthY: -0.40, mouthWidth: 0.22, mouthHeight: 0.20,
                         cheekX: 0.52, cheekY: -0.28, cheekRadius: 0.14,
                         faceScale: 1, faceOffsetY: 0),
        frame: FrameLayout(radiusScale: 0.56, centerOffsetY: 0.08),
        features: [.arms, .legs, .jelly],
        idle: IdleStyle(floatAmplitude: 0.012, floatFrequency: 1.0, wobbleAmplitude: 0.05, wobbleFrequency: 0.9,
                        flickerRate: 0, breathDepth: 1),
        personality: Personality(energy: 0.6, shyness: 0.15, curiosity: 0.55, playfulness: 0.7),
        voice: VoiceStyle(pitch: 1.3, rate: 1.0, preferredVoiceIdentifiers: CharacterCatalog.russianVoiceIdentifiers),
        glowStrength: 0.9,
        sparkleRate: 0.35,
        tagline: [
            "ru": "Весёлая капелька-желе — дрожит от смеха и больше всего на свете любит дождик.",
            "en": "A cheerful jelly droplet who wobbles with laughter and loves nothing more than rain.",
        ]
    )
}
