import Foundation
import simd

/// Catalogue of the eight built-in character designs (CONTRACT §4.3 and §5).
///
/// Everything a renderer or the rig needs to know about a character — silhouette, palette, face layout,
/// framing, idle motion, personality and voice — lives in the static designs declared in the per-character
/// files (`Lumi.swift`, `Spark.swift`, …). Nothing character-specific is hard-coded anywhere else.
///
/// Voices: designs set only pitch and rate and leave `preferredVoiceIdentifiers` empty, so
/// `SpeechSynthesisDriver` picks the best installed voice for each utterance's language (premium/enhanced
/// first). Russian and English text are therefore both spoken by a native voice.
public enum CharacterCatalog {

    /// The design for a kind. O(1): returns a stored static value, no allocation.
    public static func design(for kind: CharacterKind) -> CharacterDesign {
        switch kind {
        case .lumi: return lumi
        case .spark: return spark
        case .nox: return nox
        case .lumie: return lumie
        case .ember: return ember
        case .drop: return drop
        case .puff: return puff
        case .sprout: return sprout
        }
    }

    /// All designs in `CharacterKind.presentationOrder`.
    public static var all: [CharacterDesign] {
        CharacterKind.presentationOrder.map { CharacterCatalog.design(for: $0) }
    }

    /// Suggested app background gradient (top, bottom) per character: deep night-sky tones that let the glow read.
    public static func backgroundColors(for kind: CharacterKind) -> (top: SIMD4<Float>, bottom: SIMD4<Float>) {
        switch kind {
        case .lumi:
            return (top: SIMD4<Float>(hex: 0x1B1240), bottom: SIMD4<Float>(hex: 0x3A1F6E))
        case .spark:
            return (top: SIMD4<Float>(hex: 0x2E1A5E), bottom: SIMD4<Float>(hex: 0x4A2A8A))
        case .nox:
            return (top: SIMD4<Float>(hex: 0x0B0624), bottom: SIMD4<Float>(hex: 0x2B1458))
        case .lumie:
            return (top: SIMD4<Float>(hex: 0x0E1B2E), bottom: SIMD4<Float>(hex: 0x223B5A))
        case .ember:
            return (top: SIMD4<Float>(hex: 0x2A0F1E), bottom: SIMD4<Float>(hex: 0x5A1F28))
        case .drop:
            return (top: SIMD4<Float>(hex: 0x0E2A4A), bottom: SIMD4<Float>(hex: 0x1E4E8A))
        case .puff:
            return (top: SIMD4<Float>(hex: 0x2A2E55), bottom: SIMD4<Float>(hex: 0x4F5A9A))
        case .sprout:
            return (top: SIMD4<Float>(hex: 0x13261A), bottom: SIMD4<Float>(hex: 0x2E5A32))
        }
    }
}

// MARK: - Shared building blocks (internal)

extension CharacterCatalog {

    /// Builds a palette from `0xRRGGBB` values, in the column order of the CONTRACT §5 table.
    static func palette(bodyTop: UInt32, bodyBottom: UInt32, highlight: UInt32, shadow: UInt32,
                        accent: UInt32, accent2: UInt32, iris: UInt32, pupil: UInt32, sclera: UInt32,
                        cheek: UInt32, glow: UInt32, mouthInner: UInt32, tongue: UInt32, teeth: UInt32,
                        outline: UInt32) -> Palette {
        Palette(bodyTop: SIMD4<Float>(hex: bodyTop),
                bodyBottom: SIMD4<Float>(hex: bodyBottom),
                highlight: SIMD4<Float>(hex: highlight),
                shadow: SIMD4<Float>(hex: shadow),
                accent: SIMD4<Float>(hex: accent),
                accent2: SIMD4<Float>(hex: accent2),
                iris: SIMD4<Float>(hex: iris),
                pupil: SIMD4<Float>(hex: pupil),
                sclera: SIMD4<Float>(hex: sclera),
                cheek: SIMD4<Float>(hex: cheek),
                glow: SIMD4<Float>(hex: glow),
                mouthInner: SIMD4<Float>(hex: mouthInner),
                tongue: SIMD4<Float>(hex: tongue),
                teeth: SIMD4<Float>(hex: teeth),
                outline: SIMD4<Float>(hex: outline))
    }
}
