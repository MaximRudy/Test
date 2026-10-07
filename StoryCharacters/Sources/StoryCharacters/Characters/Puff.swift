import Foundation
import simd

extension CharacterCatalog {

    /// Puff (reference 5, third): the air elemental — a fluffy white cloud with a spiral curl on top, little
    /// arms and feet. Dreamy and soft-spoken.
    ///
    /// Layout notes: the cloud's main lobe is a circle of radius 0.75, so the eyes are set wider (±0.42) and the
    /// mouth sits at −0.36 above the flattened base (y −0.70). Cheeks reach into the side lobes.
    /// Idle: floats 0.05 at 0.6 Hz, curl bounces (`accessory2`).
    public static let puff: CharacterDesign = CharacterDesign(
        kind: .puff,
        bodyShape: .cloud,
        palette: CharacterCatalog.palette(bodyTop: 0xFFFFFF, bodyBottom: 0xD9E2F5, highlight: 0xFFFFFF, shadow: 0xA9B6D9,
                                          accent: 0xEEF3FF, accent2: 0xC6D2F0, iris: 0x4E7BFF, pupil: 0x142152,
                                          sclera: 0xFFFFFF, cheek: 0xFFA3C2, glow: 0xE0ECFF, mouthInner: 0x3B3F7A,
                                          tongue: 0xFF86A8, teeth: 0xFFFFFF, outline: 0x7F8DB3),
        face: FaceLayout(eyeOffsetX: 0.42, eyeY: 0.02, eyeRadiusX: 0.20, eyeRadiusY: 0.23,
                         irisRadius: 0.155, pupilRadius: 0.085,
                         browY: 0.34, browLength: 0.24, browThickness: 0.045,
                         mouthY: -0.36, mouthWidth: 0.18, mouthHeight: 0.18,
                         cheekX: 0.56, cheekY: -0.24, cheekRadius: 0.14,
                         faceScale: 1, faceOffsetY: 0),
        frame: FrameLayout(radiusScale: 0.56, centerOffsetY: 0.10),
        features: [.arms, .legs, .cloudCurl, .floats],
        idle: IdleStyle(floatAmplitude: 0.05, floatFrequency: 0.6, wobbleAmplitude: 0.02, wobbleFrequency: 0.35,
                        flickerRate: 0, breathDepth: 1),
        personality: Personality(energy: 0.45, shyness: 0.25, curiosity: 0.6, playfulness: 0.5),
        voice: VoiceStyle(pitch: 1.4, rate: 0.95, preferredVoiceIdentifiers: CharacterCatalog.russianVoiceIdentifiers),
        glowStrength: 0.8,
        sparkleRate: 0.3,
        tagline: [
            "ru": "Мечтательное облачко с кудряшкой — плывёт по небу и напевает колыбельные.",
            "en": "A dreamy little cloud with a curl, drifting across the sky and humming lullabies.",
        ]
    )
}
