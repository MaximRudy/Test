import XCTest
import simd
@testable import StoryCharacters

/// Character catalog tests (CONTRACT §4.3, §5, §9): pure data checks — no GPU, window or audio hardware.
final class CharacterCatalogTests: XCTestCase {

    // MARK: - Helpers

    private func colors(of palette: Palette) -> [SIMD4<Float>] {
        [palette.bodyTop, palette.bodyBottom, palette.highlight, palette.shadow, palette.accent, palette.accent2,
         palette.iris, palette.pupil, palette.sclera, palette.cheek, palette.glow, palette.mouthInner,
         palette.tongue, palette.teeth, palette.outline]
    }

    private func luminanceSum(_ c: SIMD4<Float>) -> Float {
        c.x + c.y + c.z
    }

    /// WCAG relative luminance of an sRGB colour.
    private func relativeLuminance(_ c: SIMD4<Float>) -> Float {
        func linear(_ v: Float) -> Float {
            v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.x) + 0.7152 * linear(c.y) + 0.0722 * linear(c.z)
    }

    /// WCAG contrast ratio (1 … 21) between two opaque colours.
    private func contrastRatio(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// One number from the CONTRACT §5 per-character notes.
    private func expectNote(_ kind: CharacterKind, _ keyPath: KeyPath<CharacterDesign, Float>, _ expected: Float,
                            _ label: String, line: UInt = #line) {
        let actual = CharacterCatalog.design(for: kind)[keyPath: keyPath]
        XCTAssertEqual(actual, expected, accuracy: 1e-6, "\(kind) \(label)", line: line)
    }

    // MARK: - CONTRACT §5 tables

    /// The §5 palette table, one row per kind, columns in table order (bodyTop, bodyBottom, highlight, shadow,
    /// accent, accent2, iris, pupil, sclera, cheek, glow, mouthInner, tongue, teeth, outline).
    /// Documented deviation (see `Nox.swift`, pending a §5 contract change request): Nox's mouthInner is 0x9E2F78
    /// instead of 0x0E0620 and its outline 0xE6B3FF instead of 0x2A1550, so mouth, brows and closed eyes read on
    /// the dark face.
    private static let paletteTable: [CharacterKind: [UInt32]] = [
        .lumi: [0xFFE066, 0xFFB224, 0xFFF6C2, 0xE08A12, 0x1E1748, 0x7B5CFF, 0x2B1B12, 0x120A06,
                0xFFFFFF, 0xFFB088, 0xFFD36A, 0x5A2415, 0xFF7E8A, 0xFFFFFF, 0x4A2A10],
        .spark: [0xFFE873, 0xFFC531, 0xFFF8D0, 0xE79A1A, 0xB9A0EC, 0x8E6FD6, 0x4A2A6E, 0x1D0F33,
                 0xFFFFFF, 0xFF9FB0, 0xFFD866, 0x6B2E4A, 0xFF8DA1, 0xFFFFFF, 0x6A3E12],
        .nox: [0xFF6AD5, 0x4C5BFF, 0xFFD0F5, 0x2B1E78, 0x150B33, 0xFFF1B5, 0xB86BFF, 0x1A0A33,
               0x2A1550, 0xFF7FD8, 0xB06CFF, 0x9E2F78, 0xFF6FAE, 0xFFFFFF, 0xE6B3FF],
        .lumie: [0xFFE07A, 0xFFB13D, 0xFFF9DC, 0xE68A1E, 0x7A4E2A, 0xDFF5FF, 0x3B2412, 0x140B05,
                 0xFFFFFF, 0xFFA573, 0xFFC95A, 0x6A2E1A, 0xFF8E8E, 0xFFFFFF, 0x5C3A14],
        .ember: [0xFFD93D, 0xFF7A1A, 0xFFF3B0, 0xD8450C, 0xFFF0A0, 0xFF4D1C, 0x5A2E0F, 0x1A0A02,
                 0xFFFFFF, 0xFF8A6A, 0xFF9A3A, 0x6E1E12, 0xFF6B6B, 0xFFFFFF, 0x7A3A10],
        .drop: [0x7FD8FF, 0x2A8CFF, 0xE6F9FF, 0x1E5BD6, 0xBDEBFF, 0x1266D1, 0xC04B6E, 0x2A0C1A,
                0xFFFFFF, 0xFF9FC0, 0x6FC3FF, 0x1E3F8A, 0xFF7FA3, 0xFFFFFF, 0x1B4FA8],
        .puff: [0xFFFFFF, 0xD9E2F5, 0xFFFFFF, 0xA9B6D9, 0xEEF3FF, 0xC6D2F0, 0x4E7BFF, 0x142152,
                0xFFFFFF, 0xFFA3C2, 0xE0ECFF, 0x3B3F7A, 0xFF86A8, 0xFFFFFF, 0x7F8DB3],
        .sprout: [0xD9893C, 0x9C5A22, 0xF3C58C, 0x6E3B12, 0x6DBE45, 0x3F9A2E, 0x7A4414, 0x1C0C03,
                  0xFFFFFF, 0xFF9E7E, 0xB7E07A, 0x5A2A10, 0xFF8080, 0xFFFFFF, 0x4F2A0E],
    ]

    /// §5 background gradients (top → bottom).
    private static let backgroundTable: [CharacterKind: (top: UInt32, bottom: UInt32)] = [
        .lumi: (top: 0x1B1240, bottom: 0x3A1F6E),
        .spark: (top: 0x2E1A5E, bottom: 0x4A2A8A),
        .nox: (top: 0x0B0624, bottom: 0x2B1458),
        .lumie: (top: 0x0E1B2E, bottom: 0x223B5A),
        .ember: (top: 0x2A0F1E, bottom: 0x5A1F28),
        .drop: (top: 0x0E2A4A, bottom: 0x1E4E8A),
        .puff: (top: 0x2A2E55, bottom: 0x4F5A9A),
        .sprout: (top: 0x13261A, bottom: 0x2E5A32),
    ]

    // MARK: - Presence and keys

    func testAllKindsPresentAndKeyed() {
        for kind in CharacterKind.allCases {
            let design = CharacterCatalog.design(for: kind)
            XCTAssertEqual(design.kind, kind, "design(for: \(kind)) must return a design of that kind")
            XCTAssertEqual(design.id, kind)
        }
        let all = CharacterCatalog.all
        XCTAssertEqual(all.count, 8)
        XCTAssertEqual(all.map { $0.kind }, CharacterKind.presentationOrder)
        XCTAssertEqual(Set(all.map { $0.kind }).count, CharacterKind.allCases.count)
    }

    func testStaticAccessorsMatchLookup() {
        XCTAssertEqual(CharacterCatalog.lumi, CharacterCatalog.design(for: .lumi))
        XCTAssertEqual(CharacterCatalog.spark, CharacterCatalog.design(for: .spark))
        XCTAssertEqual(CharacterCatalog.nox, CharacterCatalog.design(for: .nox))
        XCTAssertEqual(CharacterCatalog.lumie, CharacterCatalog.design(for: .lumie))
        XCTAssertEqual(CharacterCatalog.ember, CharacterCatalog.design(for: .ember))
        XCTAssertEqual(CharacterCatalog.drop, CharacterCatalog.design(for: .drop))
        XCTAssertEqual(CharacterCatalog.puff, CharacterCatalog.design(for: .puff))
        XCTAssertEqual(CharacterCatalog.sprout, CharacterCatalog.design(for: .sprout))
    }

    // MARK: - Palette

    func testPaletteAlphasAreOpaque() {
        for design in CharacterCatalog.all {
            for (index, color) in colors(of: design.palette).enumerated() {
                XCTAssertEqual(color.w, 1, "\(design.kind) palette colour #\(index) must be opaque")
                XCTAssertGreaterThanOrEqual(color.x, 0)
                XCTAssertLessThanOrEqual(color.x, 1)
                XCTAssertGreaterThanOrEqual(color.y, 0)
                XCTAssertLessThanOrEqual(color.y, 1)
                XCTAssertGreaterThanOrEqual(color.z, 0)
                XCTAssertLessThanOrEqual(color.z, 1)
            }
        }
    }

    func testHexInitializerAndSpotColours() {
        let c = SIMD4<Float>(hex: 0xFF8000)
        XCTAssertEqual(c.x, 1, accuracy: 1e-6)
        XCTAssertEqual(c.y, 128.0 / 255.0, accuracy: 1e-6)
        XCTAssertEqual(c.z, 0, accuracy: 1e-6)
        XCTAssertEqual(c.w, 1, accuracy: 1e-6)
        let translucent = SIMD4<Float>(hex: 0x000000, alpha: 0.5)
        XCTAssertEqual(translucent.w, 0.5, accuracy: 1e-6)

        // Spot checks against the §5 table.
        XCTAssertEqual(CharacterCatalog.lumi.palette.bodyTop, SIMD4<Float>(hex: 0xFFE066))
        XCTAssertEqual(CharacterCatalog.lumi.palette.accent, SIMD4<Float>(hex: 0x1E1748))
        XCTAssertEqual(CharacterCatalog.spark.palette.accent, SIMD4<Float>(hex: 0xB9A0EC))
        XCTAssertEqual(CharacterCatalog.nox.palette.sclera, SIMD4<Float>(hex: 0x2A1550))
        XCTAssertEqual(CharacterCatalog.nox.palette.accent2, SIMD4<Float>(hex: 0xFFF1B5))
        XCTAssertEqual(CharacterCatalog.lumie.palette.accent2, SIMD4<Float>(hex: 0xDFF5FF))
        XCTAssertEqual(CharacterCatalog.ember.palette.bodyBottom, SIMD4<Float>(hex: 0xFF7A1A))
        XCTAssertEqual(CharacterCatalog.drop.palette.iris, SIMD4<Float>(hex: 0xC04B6E))
        XCTAssertEqual(CharacterCatalog.puff.palette.outline, SIMD4<Float>(hex: 0x7F8DB3))
        XCTAssertEqual(CharacterCatalog.sprout.palette.accent, SIMD4<Float>(hex: 0x6DBE45))
        // Every design uses white teeth.
        for design in CharacterCatalog.all {
            XCTAssertEqual(design.palette.teeth, SIMD4<Float>(hex: 0xFFFFFF), "\(design.kind) teeth")
        }
    }

    func testPalettesMatchDesignBibleTable() {
        XCTAssertEqual(Set(CharacterCatalogTests.paletteTable.keys), Set(CharacterKind.allCases))
        for design in CharacterCatalog.all {
            guard let row = CharacterCatalogTests.paletteTable[design.kind] else {
                XCTFail("\(design.kind) is missing from the palette table")
                continue
            }
            let actual = colors(of: design.palette)
            XCTAssertEqual(row.count, 15, "\(design.kind) palette row must have 15 columns")
            XCTAssertEqual(actual.count, row.count)
            for (column, hex) in row.enumerated() where column < actual.count {
                XCTAssertEqual(actual[column], SIMD4<Float>(hex: hex), "\(design.kind) palette column \(column)")
            }
        }
    }

    func testDarkFaceEyesAndMouthInteriorRead() {
        var checked = 0
        for design in CharacterCatalog.all where design.features.contains(.darkFace) {
            let palette = design.palette
            // The glowing irises sit directly on the dark face (accent); tongue and teeth sit on the mouth fill.
            XCTAssertGreaterThanOrEqual(contrastRatio(palette.iris, palette.accent), 3,
                                        "\(design.kind) irises vanish on the dark face")
            // Brows, closed-eye lash lines and the lip line are drawn in `outline` on the dark face.
            XCTAssertGreaterThanOrEqual(contrastRatio(palette.outline, palette.accent), 4.5,
                                        "\(design.kind) brows and closed eyes vanish on the dark face")
            // At rest the mouth is only a thin `mouthInner` curve (the lip line fades in with the jaw), so the fill
            // itself must read on the dark face.
            XCTAssertGreaterThanOrEqual(contrastRatio(palette.mouthInner, palette.accent), 2.5,
                                        "\(design.kind) mouth vanishes on the dark face")
            XCTAssertGreaterThanOrEqual(contrastRatio(palette.tongue, palette.mouthInner), 2.5,
                                        "\(design.kind) tongue vanishes inside the mouth")
            XCTAssertGreaterThanOrEqual(contrastRatio(palette.teeth, palette.mouthInner), 2.5,
                                        "\(design.kind) teeth vanish inside the mouth")
            checked += 1
        }
        XCTAssertEqual(checked, 1, "exactly one dark-faced design (Nox)")
    }

    // MARK: - Body shapes and features (§5 table)

    func testBodyShapes() {
        XCTAssertEqual(CharacterCatalog.lumi.bodyShape, .star)
        XCTAssertEqual(CharacterCatalog.spark.bodyShape, .drop)
        XCTAssertEqual(CharacterCatalog.nox.bodyShape, .hood)
        XCTAssertEqual(CharacterCatalog.lumie.bodyShape, .flame)
        XCTAssertEqual(CharacterCatalog.ember.bodyShape, .flame)
        XCTAssertEqual(CharacterCatalog.drop.bodyShape, .drop)
        XCTAssertEqual(CharacterCatalog.puff.bodyShape, .cloud)
        XCTAssertEqual(CharacterCatalog.sprout.bodyShape, .round)
    }

    func testFeatureSetsMatchDesignBible() {
        let lumi: DesignFeatures = [.hood, .bookAndWand, .starPattern, .floats]
        let spark: DesignFeatures = [.brain, .arms, .legs, .jelly]
        let nox: DesignFeatures = [.darkFace, .moonMark, .floats, .eyeSparkles]
        let lumie: DesignFeatures = [.dome, .flicker, .innerFlame, .floats]
        let ember: DesignFeatures = [.arms, .legs, .flicker, .innerFlame]
        let drop: DesignFeatures = [.arms, .legs, .jelly]
        let puff: DesignFeatures = [.arms, .legs, .cloudCurl, .floats]
        let sprout: DesignFeatures = [.arms, .legs, .leaves]

        XCTAssertEqual(CharacterCatalog.lumi.features, lumi)
        XCTAssertEqual(CharacterCatalog.spark.features, spark)
        XCTAssertEqual(CharacterCatalog.nox.features, nox)
        XCTAssertEqual(CharacterCatalog.lumie.features, lumie)
        XCTAssertEqual(CharacterCatalog.ember.features, ember)
        XCTAssertEqual(CharacterCatalog.drop.features, drop)
        XCTAssertEqual(CharacterCatalog.puff.features, puff)
        XCTAssertEqual(CharacterCatalog.sprout.features, sprout)

        // Highlights called out by the contract.
        XCTAssertTrue(CharacterCatalog.lumi.features.contains(.hood))
        XCTAssertTrue(CharacterCatalog.lumi.features.contains(.bookAndWand))
        XCTAssertTrue(CharacterCatalog.nox.features.contains(.darkFace))
        XCTAssertTrue(CharacterCatalog.nox.features.contains(.moonMark))
        XCTAssertTrue(CharacterCatalog.lumie.features.contains(.dome))
        XCTAssertTrue(CharacterCatalog.spark.features.contains(.brain))
        XCTAssertTrue(CharacterCatalog.puff.features.contains(.cloudCurl))
        XCTAssertTrue(CharacterCatalog.sprout.features.contains(.leaves))
        for kind in CharacterKind.allCases where kind.isElemental {
            let features = CharacterCatalog.design(for: kind).features
            XCTAssertTrue(features.contains(.arms), "\(kind) must have arms")
            XCTAssertTrue(features.contains(.legs), "\(kind) must have legs")
        }
        // Flicker only on flames; the dark face only on Nox.
        for design in CharacterCatalog.all {
            if design.features.contains(.flicker) {
                XCTAssertEqual(design.bodyShape, .flame, "\(design.kind) flickers but is not a flame")
                XCTAssertGreaterThan(design.idle.flickerRate, 0, "\(design.kind) flickers at 0 Hz")
            } else {
                XCTAssertEqual(design.idle.flickerRate, 0, "\(design.kind) has a flicker rate without .flicker")
            }
            XCTAssertEqual(design.features.contains(.darkFace), design.kind == .nox)
        }
    }

    // MARK: - Framing and face layout

    func testFrameRadiusScaleRange() {
        for design in CharacterCatalog.all {
            XCTAssertGreaterThanOrEqual(design.frame.radiusScale, 0.3, "\(design.kind) radiusScale too small")
            XCTAssertLessThanOrEqual(design.frame.radiusScale, 0.8, "\(design.kind) radiusScale too large")
            XCTAssertLessThanOrEqual(abs(design.frame.centerOffsetY), 0.5, "\(design.kind) centerOffsetY out of range")
        }
        // Contract-specified framing.
        XCTAssertEqual(CharacterCatalog.lumi.frame.radiusScale, 0.50, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.lumi.frame.centerOffsetY, -0.05, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.spark.frame.radiusScale, 0.56, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.nox.frame.radiusScale, 0.56, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.nox.frame.centerOffsetY, -0.1, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.lumie.frame.radiusScale, 0.40, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.lumie.frame.centerOffsetY, 0.25, accuracy: 1e-6)
    }

    func testCutenessRules() {
        for design in CharacterCatalog.all {
            let face = design.face
            let kind = design.kind
            // Irises ≥ 70 % of the eye, yet the iris still fits inside the eye and the pupil inside the iris.
            XCTAssertGreaterThanOrEqual(face.irisRadius, 0.7 * face.eyeRadiusX, "\(kind) iris too small")
            XCTAssertLessThan(face.irisRadius, face.eyeRadiusX, "\(kind) iris wider than the eye")
            XCTAssertLessThan(face.irisRadius, face.eyeRadiusY, "\(kind) iris taller than the eye")
            XCTAssertLessThan(face.pupilRadius, face.irisRadius, "\(kind) pupil larger than the iris")
            XCTAssertGreaterThan(face.pupilRadius, 0, "\(kind) pupil missing")
            // Big eyes, low on the face; mouth small and below the eyes; brows above the eyes.
            XCTAssertGreaterThanOrEqual(face.eyeRadiusX, 0.15, "\(kind) eyes too small")
            XCTAssertLessThanOrEqual(face.eyeY, 0.10, "\(kind) eyes too high")
            XCTAssertLessThan(face.mouthY, face.eyeY - face.eyeRadiusY, "\(kind) mouth overlaps the eyes")
            XCTAssertLessThanOrEqual(face.mouthWidth, 0.25, "\(kind) mouth too wide")
            XCTAssertGreaterThan(face.browY, face.eyeY + face.eyeRadiusY, "\(kind) brows overlap the eyes")
            // Eyes stay inside the unit body.
            XCTAssertLessThanOrEqual(face.eyeOffsetX + face.eyeRadiusX, 0.95, "\(kind) eyes stick out of the body")
            XCTAssertEqual(face.faceScale, 1, accuracy: 1e-6)
            XCTAssertGreaterThan(face.cheekRadius, 0)
            XCTAssertGreaterThan(face.mouthHeight, 0)
        }
        // Contract-specified layouts.
        XCTAssertEqual(CharacterCatalog.lumi.face.eyeOffsetX, 0.30, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.lumi.face.mouthY, -0.28, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.lumi.face.cheekX, 0.40, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.spark.face.irisRadius, 0.165, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.spark.face.mouthY, -0.42, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.nox.face.eyeRadiusX, 0.26, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.nox.face.eyeRadiusY, 0.28, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.nox.face.irisRadius, 0.22, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.nox.face.pupilRadius, 0.11, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.nox.face.mouthWidth, 0.12, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.ember.face.mouthWidth, 0.24, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.drop.idle.wobbleAmplitude, 0.05, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.puff.face.eyeOffsetX, 0.42, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.sprout.face.mouthY, -0.36, accuracy: 1e-6)
    }

    /// Every number named in the §5 per-character notes.
    func testPerCharacterNotesMatchDesignBible() {
        // Lumi
        expectNote(.lumi, \.face.eyeOffsetX, 0.30, "eyeOffsetX")
        expectNote(.lumi, \.face.eyeY, 0.05, "eyeY")
        expectNote(.lumi, \.face.eyeRadiusX, 0.17, "eyeRadiusX")
        expectNote(.lumi, \.face.eyeRadiusY, 0.20, "eyeRadiusY")
        expectNote(.lumi, \.face.mouthY, -0.28, "mouthY")
        expectNote(.lumi, \.face.mouthWidth, 0.18, "mouthWidth")
        expectNote(.lumi, \.face.cheekX, 0.40, "cheekX")
        expectNote(.lumi, \.frame.radiusScale, 0.50, "radiusScale")
        expectNote(.lumi, \.frame.centerOffsetY, -0.05, "centerOffsetY")
        expectNote(.lumi, \.idle.floatAmplitude, 0.03, "floatAmplitude")
        expectNote(.lumi, \.personality.energy, 0.5, "energy")
        expectNote(.lumi, \.personality.curiosity, 0.7, "curiosity")
        expectNote(.lumi, \.voice.pitch, 1.15, "pitch")
        expectNote(.lumi, \.voice.rate, 0.95, "rate")
        // Spark
        expectNote(.spark, \.face.eyeOffsetX, 0.36, "eyeOffsetX")
        expectNote(.spark, \.face.eyeY, -0.02, "eyeY")
        expectNote(.spark, \.face.eyeRadiusX, 0.21, "eyeRadiusX")
        expectNote(.spark, \.face.eyeRadiusY, 0.25, "eyeRadiusY")
        expectNote(.spark, \.face.irisRadius, 0.165, "irisRadius")
        expectNote(.spark, \.face.mouthY, -0.42, "mouthY")
        expectNote(.spark, \.face.mouthWidth, 0.16, "mouthWidth")
        expectNote(.spark, \.frame.radiusScale, 0.56, "radiusScale")
        expectNote(.spark, \.personality.energy, 0.7, "energy")
        expectNote(.spark, \.personality.curiosity, 0.9, "curiosity")
        expectNote(.spark, \.personality.playfulness, 0.7, "playfulness")
        expectNote(.spark, \.voice.pitch, 1.35, "pitch")
        expectNote(.spark, \.voice.rate, 1.0, "rate")
        // Nox
        expectNote(.nox, \.face.eyeRadiusX, 0.26, "eyeRadiusX")
        expectNote(.nox, \.face.eyeRadiusY, 0.28, "eyeRadiusY")
        expectNote(.nox, \.face.irisRadius, 0.22, "irisRadius")
        expectNote(.nox, \.face.pupilRadius, 0.11, "pupilRadius")
        expectNote(.nox, \.face.eyeOffsetX, 0.36, "eyeOffsetX")
        expectNote(.nox, \.face.eyeY, -0.05, "eyeY")
        expectNote(.nox, \.face.mouthY, -0.45, "mouthY")
        expectNote(.nox, \.face.mouthWidth, 0.12, "mouthWidth")
        expectNote(.nox, \.frame.radiusScale, 0.56, "radiusScale")
        expectNote(.nox, \.frame.centerOffsetY, -0.1, "centerOffsetY")
        expectNote(.nox, \.idle.floatAmplitude, 0.05, "floatAmplitude")
        expectNote(.nox, \.sparkleRate, 0.6, "sparkleRate")
        expectNote(.nox, \.personality.energy, 0.35, "energy")
        expectNote(.nox, \.personality.shyness, 0.5, "shyness")
        expectNote(.nox, \.voice.pitch, 1.05, "pitch")
        expectNote(.nox, \.voice.rate, 0.9, "rate")
        // Lumie
        expectNote(.lumie, \.frame.radiusScale, 0.40, "radiusScale")
        expectNote(.lumie, \.frame.centerOffsetY, 0.25, "centerOffsetY")
        expectNote(.lumie, \.face.eyeRadiusX, 0.19, "eyeRadiusX")
        expectNote(.lumie, \.face.eyeRadiusY, 0.22, "eyeRadiusY")
        expectNote(.lumie, \.face.eyeY, 0.0, "eyeY")
        expectNote(.lumie, \.face.mouthY, -0.38, "mouthY")
        expectNote(.lumie, \.idle.flickerRate, 1.2, "flickerRate")
        expectNote(.lumie, \.sparkleRate, 0.7, "sparkleRate")
        expectNote(.lumie, \.idle.floatAmplitude, 0.04, "floatAmplitude")
        expectNote(.lumie, \.personality.energy, 0.4, "energy")
        expectNote(.lumie, \.personality.shyness, 0.3, "shyness")
        expectNote(.lumie, \.voice.pitch, 1.25, "pitch")
        expectNote(.lumie, \.voice.rate, 0.9, "rate")
        // Ember
        expectNote(.ember, \.face.eyeRadiusX, 0.20, "eyeRadiusX")
        expectNote(.ember, \.face.eyeRadiusY, 0.23, "eyeRadiusY")
        expectNote(.ember, \.face.eyeY, 0.0, "eyeY")
        expectNote(.ember, \.face.mouthY, -0.38, "mouthY")
        expectNote(.ember, \.face.mouthWidth, 0.24, "mouthWidth")
        expectNote(.ember, \.idle.flickerRate, 1.6, "flickerRate")
        expectNote(.ember, \.personality.energy, 0.9, "energy")
        expectNote(.ember, \.personality.playfulness, 0.8, "playfulness")
        expectNote(.ember, \.voice.pitch, 1.2, "pitch")
        expectNote(.ember, \.voice.rate, 1.1, "rate")
        // Drop
        expectNote(.drop, \.face.eyeRadiusX, 0.21, "eyeRadiusX")
        expectNote(.drop, \.face.eyeRadiusY, 0.24, "eyeRadiusY")
        expectNote(.drop, \.face.mouthWidth, 0.22, "mouthWidth")
        expectNote(.drop, \.idle.wobbleAmplitude, 0.05, "wobbleAmplitude")
        expectNote(.drop, \.personality.energy, 0.6, "energy")
        expectNote(.drop, \.personality.playfulness, 0.7, "playfulness")
        expectNote(.drop, \.voice.pitch, 1.3, "pitch")
        expectNote(.drop, \.voice.rate, 1.0, "rate")
        // Puff
        expectNote(.puff, \.face.eyeOffsetX, 0.42, "eyeOffsetX")
        expectNote(.puff, \.face.eyeY, 0.02, "eyeY")
        expectNote(.puff, \.face.eyeRadiusX, 0.20, "eyeRadiusX")
        expectNote(.puff, \.face.eyeRadiusY, 0.23, "eyeRadiusY")
        expectNote(.puff, \.idle.floatAmplitude, 0.05, "floatAmplitude")
        expectNote(.puff, \.idle.floatFrequency, 0.6, "floatFrequency")
        expectNote(.puff, \.personality.energy, 0.45, "energy")
        expectNote(.puff, \.personality.curiosity, 0.6, "curiosity")
        expectNote(.puff, \.voice.pitch, 1.4, "pitch")
        expectNote(.puff, \.voice.rate, 0.95, "rate")
        // Sprout
        expectNote(.sprout, \.face.eyeY, 0.02, "eyeY")
        expectNote(.sprout, \.face.eyeRadiusX, 0.21, "eyeRadiusX")
        expectNote(.sprout, \.face.eyeRadiusY, 0.24, "eyeRadiusY")
        expectNote(.sprout, \.face.mouthY, -0.36, "mouthY")
        expectNote(.sprout, \.personality.energy, 0.4, "energy")
        expectNote(.sprout, \.personality.shyness, 0.4, "shyness")
        expectNote(.sprout, \.voice.pitch, 1.1, "pitch")
        expectNote(.sprout, \.voice.rate, 0.9, "rate")
    }

    /// Lumi's brows are centred right under the star's upper notches (inner vertices at radius 0.52, 54°:
    /// (±0.306, 0.4207)). Even at the surprised raise (§6: 0.9 → +0.108, §3.2) the brow's straight capsule (the 0.03
    /// upward bend aside) must stay below the notch vertex, and at rest the brows must clear the eyes.
    func testLumiBrowsStayInsideTheStar() {
        let face = CharacterCatalog.lumi.face
        let notchY: Float = 0.4207
        let surprisedRaise: Float = 0.9
        let raisedBrowTop = face.browY + 0.12 * surprisedRaise + face.browThickness / 2
        XCTAssertLessThanOrEqual(raisedBrowTop, notchY, "Lumi's raised brows poke out through the star's upper notches")
        XCTAssertGreaterThan(face.browY - face.browThickness / 2, face.eyeY + face.eyeRadiusY,
                             "Lumi's brows touch the eyes at rest")
    }

    /// Sprout's cap covers the body above y 0.35 (§3.6). At rest the brows, including their 0.03 upward bend (§3.2),
    /// must stay under that line and clear of the eye tops.
    func testSproutBrowsStayUnderTheCap() {
        let face = CharacterCatalog.sprout.face
        let capLine: Float = 0.35
        let browSagitta: Float = 0.03
        let restingBrowTop = face.browY + browSagitta + face.browThickness / 2
        XCTAssertLessThan(restingBrowTop, capLine, "Sprout's resting brows run onto the cap")
        XCTAssertGreaterThan(face.browY - face.browThickness / 2, face.eyeY + face.eyeRadiusY,
                             "Sprout's brows touch the eyes at rest")
    }

    // MARK: - Idle, personality, voice, text

    func testIdleStylesAreSane() {
        for design in CharacterCatalog.all {
            let idle = design.idle
            let kind = design.kind
            XCTAssertGreaterThan(idle.floatAmplitude, 0, "\(kind) never bobs")
            XCTAssertLessThanOrEqual(idle.floatAmplitude, 0.08, "\(kind) bobs too much")
            XCTAssertGreaterThan(idle.floatFrequency, 0)
            XCTAssertLessThanOrEqual(idle.floatFrequency, 2)
            XCTAssertGreaterThanOrEqual(idle.wobbleAmplitude, 0)
            XCTAssertLessThanOrEqual(idle.wobbleAmplitude, 0.1)
            XCTAssertGreaterThan(idle.wobbleFrequency, 0)
            XCTAssertGreaterThan(idle.breathDepth, 0)
            if design.features.contains(.floats) {
                XCTAssertGreaterThanOrEqual(idle.floatAmplitude, 0.03, "\(kind) floats but barely bobs")
            } else {
                XCTAssertLessThanOrEqual(idle.floatAmplitude, 0.02, "\(kind) is grounded but bobs like a floater")
            }
        }
        XCTAssertEqual(CharacterCatalog.lumie.idle.flickerRate, 1.2, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.ember.idle.flickerRate, 1.6, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.puff.idle.floatFrequency, 0.6, accuracy: 1e-6)
    }

    func testPersonalityVoiceAndGlowRanges() {
        for design in CharacterCatalog.all {
            let p = design.personality
            let kind = design.kind
            for value in [p.energy, p.shyness, p.curiosity, p.playfulness] {
                XCTAssertGreaterThanOrEqual(value, 0, "\(kind) personality below 0")
                XCTAssertLessThanOrEqual(value, 1, "\(kind) personality above 1")
            }
            XCTAssertGreaterThanOrEqual(design.voice.pitch, 0.5, "\(kind) pitch out of AVSpeechUtterance range")
            XCTAssertLessThanOrEqual(design.voice.pitch, 2.0, "\(kind) pitch out of AVSpeechUtterance range")
            XCTAssertGreaterThanOrEqual(design.voice.rate, 0.5, "\(kind) rate too slow")
            XCTAssertLessThanOrEqual(design.voice.rate, 1.5, "\(kind) rate too fast")
            XCTAssertGreaterThanOrEqual(design.glowStrength, 0, "\(kind) glow")
            XCTAssertLessThanOrEqual(design.glowStrength, 2, "\(kind) glow")
            XCTAssertGreaterThanOrEqual(design.sparkleRate, 0, "\(kind) sparkleRate")
            XCTAssertLessThanOrEqual(design.sparkleRate, 1, "\(kind) sparkleRate")
            // No pinned voices: a fixed (single-language) list would override the per-utterance language choice
            // and the premium/enhanced preference of SpeechSynthesisDriver.
            XCTAssertTrue(design.voice.preferredVoiceIdentifiers.isEmpty,
                          "\(kind) must not pin voices; the driver picks the best voice for each utterance's language")
        }
        // Contract-specified voices and personalities.
        XCTAssertEqual(CharacterCatalog.lumi.voice.pitch, 1.15, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.spark.voice.pitch, 1.35, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.spark.personality.curiosity, 0.9, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.nox.personality.shyness, 0.5, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.ember.personality.energy, 0.9, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.ember.voice.rate, 1.1, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.puff.voice.pitch, 1.4, accuracy: 1e-6)
        XCTAssertEqual(CharacterCatalog.sprout.voice.rate, 0.9, accuracy: 1e-6)
    }

    func testTaglinesAreBilingual() {
        for design in CharacterCatalog.all {
            let kind = design.kind
            let ru = design.tagline["ru"] ?? ""
            let en = design.tagline["en"] ?? ""
            XCTAssertFalse(ru.isEmpty, "\(kind) has no Russian tagline")
            XCTAssertFalse(en.isEmpty, "\(kind) has no English tagline")
            XCTAssertNotEqual(ru, en, "\(kind) taglines must differ by language")
            XCTAssertEqual(design.localizedTagline(languageCode: "ru"), ru)
            XCTAssertEqual(design.localizedTagline(languageCode: "en"), en)
            XCTAssertEqual(design.localizedTagline(languageCode: "fr"), en, "unknown languages fall back to English")
            let hasCyrillic = ru.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) })
            XCTAssertTrue(hasCyrillic, "\(kind) Russian tagline must contain Cyrillic")
        }
    }

    // MARK: - Background gradients

    func testBackgroundGradientsAreDistinctAndOpaque() {
        let kinds = CharacterKind.allCases
        let gradients = kinds.map { CharacterCatalog.backgroundColors(for: $0) }
        for (index, gradient) in gradients.enumerated() {
            let kind = kinds[index]
            XCTAssertEqual(gradient.top.w, 1, "\(kind) background top must be opaque")
            XCTAssertEqual(gradient.bottom.w, 1, "\(kind) background bottom must be opaque")
            XCTAssertNotEqual(gradient.top, gradient.bottom, "\(kind) background has no gradient")
            // Night-sky gradients get lighter towards the bottom.
            XCTAssertLessThan(luminanceSum(gradient.top), luminanceSum(gradient.bottom), "\(kind) background top should be darker")
        }
        for i in gradients.indices {
            for j in gradients.indices where j > i {
                let same = gradients[i].top == gradients[j].top && gradients[i].bottom == gradients[j].bottom
                XCTAssertFalse(same, "\(kinds[i]) and \(kinds[j]) share a background gradient")
            }
        }
        XCTAssertEqual(Set(CharacterCatalogTests.backgroundTable.keys), Set(CharacterKind.allCases))
        for kind in CharacterKind.allCases {
            guard let expected = CharacterCatalogTests.backgroundTable[kind] else {
                XCTFail("\(kind) is missing from the background table")
                continue
            }
            let gradient = CharacterCatalog.backgroundColors(for: kind)
            XCTAssertEqual(gradient.top, SIMD4<Float>(hex: expected.top), "\(kind) background top")
            XCTAssertEqual(gradient.bottom, SIMD4<Float>(hex: expected.bottom), "\(kind) background bottom")
        }
    }
}
