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
            for identifier in design.voice.preferredVoiceIdentifiers {
                XCTAssertFalse(identifier.isEmpty, "\(kind) has an empty voice identifier")
            }
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
        XCTAssertTrue(CharacterCatalog.lumi.voice.preferredVoiceIdentifiers.contains("com.apple.voice.compact.ru-RU.Milena"))
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
        XCTAssertEqual(CharacterCatalog.backgroundColors(for: .lumi).top, SIMD4<Float>(hex: 0x1B1240))
        XCTAssertEqual(CharacterCatalog.backgroundColors(for: .sprout).bottom, SIMD4<Float>(hex: 0x2E5A32))
    }
}
