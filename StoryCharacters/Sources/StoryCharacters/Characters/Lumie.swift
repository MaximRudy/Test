import Foundation
import simd

extension CharacterCatalog {

    /// Lumie (reference 4): a small warm flame sprite living inside a glass bell jar on a wooden base,
    /// surrounded by fireflies. Cosy and a little sleepy.
    ///
    /// Layout notes: the flame is small so the dome (r 1.55) and base fit the view — `radiusScale 0.40`, body
    /// raised by 0.25 R. A lighter inner flame sits behind the face. Eyes centred at y 0, mouth at −0.38.
    /// Idle: flicker 1.2 Hz, fireflies (sparkle field confined to the dome), float 0.04.
    /// Signature (Core): `.happy`/`.love` → dome fills with fireflies (accessory 1); `.scared` → flame shrinks (scale 0.85).
    public static let lumie: CharacterDesign = CharacterDesign(
        kind: .lumie,
        bodyShape: .flame,
        palette: CharacterCatalog.palette(bodyTop: 0xFFE07A, bodyBottom: 0xFFB13D, highlight: 0xFFF9DC, shadow: 0xE68A1E,
                                          accent: 0x7A4E2A, accent2: 0xDFF5FF, iris: 0x3B2412, pupil: 0x140B05,
                                          sclera: 0xFFFFFF, cheek: 0xFFA573, glow: 0xFFC95A, mouthInner: 0x6A2E1A,
                                          tongue: 0xFF8E8E, teeth: 0xFFFFFF, outline: 0x5C3A14),
        face: FaceLayout(eyeOffsetX: 0.34, eyeY: 0.0, eyeRadiusX: 0.19, eyeRadiusY: 0.22,
                         irisRadius: 0.15, pupilRadius: 0.082,
                         browY: 0.32, browLength: 0.22, browThickness: 0.04,
                         mouthY: -0.38, mouthWidth: 0.16, mouthHeight: 0.15,
                         cheekX: 0.50, cheekY: -0.26, cheekRadius: 0.13,
                         faceScale: 1, faceOffsetY: 0),
        frame: FrameLayout(radiusScale: 0.40, centerOffsetY: 0.25),
        features: [.dome, .flicker, .innerFlame, .floats],
        idle: IdleStyle(floatAmplitude: 0.04, floatFrequency: 0.7, wobbleAmplitude: 0.02, wobbleFrequency: 0.4,
                        flickerRate: 1.2, breathDepth: 1),
        personality: Personality(energy: 0.4, shyness: 0.3, curiosity: 0.45, playfulness: 0.4),
        voice: VoiceStyle(pitch: 1.25, rate: 0.9),
        glowStrength: 1.4,
        sparkleRate: 0.7,
        tagline: [
            "ru": "Уютный огонёк под стеклянным куполом — мягко светит и собирает вокруг себя светлячков.",
            "en": "A cosy little flame under a glass dome, glowing softly and gathering fireflies around it.",
        ]
    )
}
