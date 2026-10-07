import Foundation
import simd

extension CharacterCatalog {

    /// Nox (reference 3): a magenta → violet → blue hooded wisp with a dark void of a face, huge glowing galaxy
    /// eyes and a crescent moon on the forehead. Mysterious and gentle.
    ///
    /// Layout notes: the face lives inside the dark inner ellipse (0, −0.08) × (0.72, 0.80). The eyes are the
    /// largest in the catalog (iris 85 % of the eye) and glow; the mouth is small and low on the face, with
    /// pink cheeks beside it.
    ///
    /// Palette: the CONTRACT §5 nox row with two documented deviations (subject of a §5 contract change request).
    /// Both renderers draw the brows, the closed-eye lash line, the lip line and the lid shade in `outline` and fill
    /// the mouth with `mouthInner`, all on top of the dark face (`accent` 0x150B33). The §5 values (outline 0x2A1550,
    /// mouthInner 0x0E0620) are about 1.1:1 against that face, so Nox had no visible mouth or brows and its eyes
    /// vanished while blinking. Here `outline` is a light lilac 0xE6B3FF (about 11:1 on the face) and `mouthInner`
    /// a raspberry 0x9E2F78 (about 2.8:1 on the face, while the tongue keeps 2.6:1 and the teeth 6.7:1 inside it),
    /// so the small pink smile of reference 3 reads even at rest, when the mouth is only a thin filled curve.
    /// Glow 1.15 keeps the silhouette edge from dissolving into the halo.
    /// Idle: slow float, stardust trail. Signature (Core): moon mark brightens with arousal; eyes dim when `.sleepy`.
    public static let nox: CharacterDesign = CharacterDesign(
        kind: .nox,
        bodyShape: .hood,
        palette: CharacterCatalog.palette(bodyTop: 0xFF6AD5, bodyBottom: 0x4C5BFF, highlight: 0xFFD0F5, shadow: 0x2B1E78,
                                          accent: 0x150B33, accent2: 0xFFF1B5, iris: 0xB86BFF, pupil: 0x1A0A33,
                                          sclera: 0x2A1550, cheek: 0xFF7FD8, glow: 0xB06CFF, mouthInner: 0x9E2F78,
                                          tongue: 0xFF6FAE, teeth: 0xFFFFFF, outline: 0xE6B3FF),
        face: FaceLayout(eyeOffsetX: 0.36, eyeY: -0.05, eyeRadiusX: 0.26, eyeRadiusY: 0.28,
                         irisRadius: 0.22, pupilRadius: 0.11,
                         browY: 0.30, browLength: 0.22, browThickness: 0.04,
                         mouthY: -0.45, mouthWidth: 0.12, mouthHeight: 0.12,
                         cheekX: 0.46, cheekY: -0.32, cheekRadius: 0.13,
                         faceScale: 1, faceOffsetY: 0),
        frame: FrameLayout(radiusScale: 0.56, centerOffsetY: -0.1),
        features: [.darkFace, .moonMark, .floats, .eyeSparkles],
        idle: IdleStyle(floatAmplitude: 0.05, floatFrequency: 0.45, wobbleAmplitude: 0.03, wobbleFrequency: 0.3,
                        flickerRate: 0, breathDepth: 0.8),
        personality: Personality(energy: 0.35, shyness: 0.5, curiosity: 0.5, playfulness: 0.3),
        voice: VoiceStyle(pitch: 1.05, rate: 0.9),
        glowStrength: 1.15,
        sparkleRate: 0.6,
        tagline: [
            "ru": "Тихий ночной дух с глазами-галактиками — шепчет сказки, когда зажигаются звёзды.",
            "en": "A gentle night wisp with galaxy eyes who whispers stories once the stars come out.",
        ]
    )
}
