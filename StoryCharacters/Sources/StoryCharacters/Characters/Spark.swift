import Foundation
import simd

extension CharacterCatalog {

    /// Spark (reference 2): a translucent golden flame-drop with a lavender brain on its forehead, tiny arms
    /// and feet. Bright and endlessly curious.
    ///
    /// Layout notes: the drop's round part is centred at (0, −0.15), so the face sits slightly low; the brain
    /// occupies the forehead around (0, 0.58) with its lowest lobes at y ≈ 0.42, and the brows rest just beneath it
    /// (browY 0.27, clear of the eye tops at 0.23 and of the brain while raised). Big dark irises fill the eyes.
    /// Idle: jelly wobble, flame-tip wiggle. Signature (Core): `.thinking` → brain pulses and glows (accessory 1);
    /// `.excited` → tip wiggles twice as fast.
    public static let spark: CharacterDesign = CharacterDesign(
        kind: .spark,
        bodyShape: .drop,
        palette: CharacterCatalog.palette(bodyTop: 0xFFE873, bodyBottom: 0xFFC531, highlight: 0xFFF8D0, shadow: 0xE79A1A,
                                          accent: 0xB9A0EC, accent2: 0x8E6FD6, iris: 0x4A2A6E, pupil: 0x1D0F33,
                                          sclera: 0xFFFFFF, cheek: 0xFF9FB0, glow: 0xFFD866, mouthInner: 0x6B2E4A,
                                          tongue: 0xFF8DA1, teeth: 0xFFFFFF, outline: 0x6A3E12),
        face: FaceLayout(eyeOffsetX: 0.36, eyeY: -0.02, eyeRadiusX: 0.21, eyeRadiusY: 0.25,
                         irisRadius: 0.165, pupilRadius: 0.09,
                         browY: 0.27, browLength: 0.24, browThickness: 0.045,
                         mouthY: -0.42, mouthWidth: 0.16, mouthHeight: 0.16,
                         cheekX: 0.50, cheekY: -0.30, cheekRadius: 0.13,
                         faceScale: 1, faceOffsetY: 0),
        frame: FrameLayout(radiusScale: 0.56, centerOffsetY: 0.08),
        features: [.brain, .arms, .legs, .jelly],
        idle: IdleStyle(floatAmplitude: 0.012, floatFrequency: 1.0, wobbleAmplitude: 0.035, wobbleFrequency: 0.7,
                        flickerRate: 0, breathDepth: 1),
        personality: Personality(energy: 0.7, shyness: 0.1, curiosity: 0.9, playfulness: 0.7),
        voice: VoiceStyle(pitch: 1.35, rate: 1.0),
        glowStrength: 1.0,
        sparkleRate: 0.4,
        tagline: [
            "ru": "Любопытная искорка с сияющим мозгом — обожает спрашивать «а почему?».",
            "en": "A bright, curious spark with a glowing brain who adores asking “but why?”.",
        ]
    )
}
