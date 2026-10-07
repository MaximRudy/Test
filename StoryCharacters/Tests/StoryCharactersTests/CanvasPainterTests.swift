import XCTest
import SwiftUI
import simd
#if canImport(UIKit)
import UIKit
#endif
@testable import StoryCharacters

/// Canvas renderer tests (CONTRACT §4.5, §3, §9): pure geometry and colour checks — no GPU, window or audio.
@MainActor
final class CanvasPainterTests: XCTestCase {

    // MARK: - Helpers

    private func makeDesign(kind: CharacterKind, shape: BodyShape, features: DesignFeatures = []) -> CharacterDesign {
        let palette = Palette(bodyTop: SIMD4<Float>(hex: 0xFFE066), bodyBottom: SIMD4<Float>(hex: 0xFFB224),
                              highlight: SIMD4<Float>(hex: 0xFFF6C2), shadow: SIMD4<Float>(hex: 0xE08A12),
                              accent: SIMD4<Float>(hex: 0x1E1748), accent2: SIMD4<Float>(hex: 0x7B5CFF),
                              iris: SIMD4<Float>(hex: 0x2B1B12), pupil: SIMD4<Float>(hex: 0x120A06),
                              sclera: SIMD4<Float>(hex: 0xFFFFFF), cheek: SIMD4<Float>(hex: 0xFFB088),
                              glow: SIMD4<Float>(hex: 0xFFD36A), mouthInner: SIMD4<Float>(hex: 0x5A2415),
                              tongue: SIMD4<Float>(hex: 0xFF7E8A), teeth: SIMD4<Float>(hex: 0xFFFFFF),
                              outline: SIMD4<Float>(hex: 0x4A2A10))
        return CharacterDesign(kind: kind, bodyShape: shape, palette: palette, features: features)
    }

    private func assertInside(_ box: CGRect, _ limit: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(box.isEmpty, "empty bounding box", file: file, line: line)
        XCTAssertGreaterThanOrEqual(box.minX, -limit, file: file, line: line)
        XCTAssertLessThanOrEqual(box.maxX, limit, file: file, line: line)
        XCTAssertGreaterThanOrEqual(box.minY, -limit, file: file, line: line)
        XCTAssertLessThanOrEqual(box.maxY, limit, file: file, line: line)
    }

    // MARK: - Body silhouettes (§3.5)

    func testStarBodyFitsUnitBox() {
        let box = CharacterPaths.starBody().boundingRect
        assertInside(box, 1.1)
        // One point straight up, reaching (almost) the outer radius 1.05.
        XCTAssertEqual(box.maxY, 1.05, accuracy: 0.08)
        XCTAssertLessThan(abs(box.midX), 0.05)
    }

    func testRoundBodyIsUnitCircle() {
        let box = CharacterPaths.roundBody().boundingRect
        XCTAssertEqual(box.minX, -1, accuracy: 1e-6)
        XCTAssertEqual(box.maxX, 1, accuracy: 1e-6)
        XCTAssertEqual(box.minY, -1, accuracy: 1e-6)
        XCTAssertEqual(box.maxY, 1, accuracy: 1e-6)
    }

    func testDropTipNearTop() {
        let box = CharacterPaths.dropBody(wiggle: 0).boundingRect
        XCTAssertEqual(box.maxY, 1.05, accuracy: 0.02)
        XCTAssertEqual(box.minY, -1.0, accuracy: 0.02)
        XCTAssertEqual(box.maxX, 0.85, accuracy: 0.05)
        XCTAssertEqual(box.minX, -0.85, accuracy: 0.05)
    }

    func testDropWiggleBendsTheTip() {
        // The tip x is 0.18·sin(wiggle); sample the path's current point right after the move (start of the
        // arc) stays put, so compare the bounding boxes' upper regions via a clipped intersection instead.
        let band = Path(CGRect(x: -1, y: 0.95, width: 2, height: 0.3))
        let straight = CharacterPaths.dropBody(wiggle: 0).intersection(band).boundingRect
        let bent = CharacterPaths.dropBody(wiggle: CGFloat.pi / 2).intersection(band).boundingRect
        XCTAssertGreaterThan(bent.midX, straight.midX + 0.08)
    }

    func testCloudBottomIsFlattened() {
        let box = CharacterPaths.cloudBody().boundingRect
        XCTAssertFalse(box.isEmpty)
        XCTAssertGreaterThanOrEqual(box.minY, -0.75)
        XCTAssertLessThanOrEqual(box.minY, -0.65)
        XCTAssertGreaterThan(box.maxY, 0.80)
        XCTAssertGreaterThan(box.maxX, 1.0)
        XCTAssertLessThan(box.minX, -1.0)
    }

    func testFlameAndHoodAreBounded() {
        let flame = CharacterPaths.flameBody(wiggle: 1.3).boundingRect
        assertInside(flame, 1.4)
        XCTAssertGreaterThan(flame.maxY, 0.95)
        let hood = CharacterPaths.hoodBody().boundingRect
        assertInside(hood, 1.5)
        XCTAssertGreaterThan(hood.maxY, 1.2, "the curl must rise above the body")
        XCTAssertGreaterThan(hood.maxX, 0.55, "the curl tip reaches x ≈ 0.6")
    }

    func testEveryShapeBuilds() {
        for shape in BodyShape.allCases {
            let path = CharacterPaths.body(shape: shape, wiggle: 0.4)
            XCTAssertFalse(path.isEmpty, "\(shape) is empty")
            XCTAssertFalse(path.boundingRect.isEmpty, "\(shape) has an empty bounding box")
        }
    }

    // MARK: - Primitive builders

    func testCapsuleBounds() {
        let box = CharacterPaths.capsule(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 1, y: 0), radius: 0.25).boundingRect
        XCTAssertEqual(box.minX, -0.25, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 1.25, accuracy: 0.01)
        XCTAssertEqual(box.minY, -0.25, accuracy: 0.01)
        XCTAssertEqual(box.maxY, 0.25, accuracy: 0.01)
        let degenerate = CharacterPaths.capsule(from: .zero, to: .zero, radius: 0.1).boundingRect
        XCTAssertEqual(degenerate.width, 0.2, accuracy: 1e-6)
    }

    func testRoundedBoxStarHeartCrescentSpiral() {
        let box = CharacterPaths.roundedBox(center: CGPoint(x: 1, y: 2), width: 0.5, height: 0.3, corner: 0.1).boundingRect
        XCTAssertEqual(box.midX, 1, accuracy: 1e-6)
        XCTAssertEqual(box.midY, 2, accuracy: 1e-6)
        XCTAssertEqual(box.width, 0.5, accuracy: 1e-6)
        XCTAssertEqual(box.height, 0.3, accuracy: 1e-6)

        let star = CharacterPaths.star4(center: .zero, radius: 0.2).boundingRect
        XCTAssertEqual(star.width, 0.4, accuracy: 1e-6)
        XCTAssertEqual(star.height, 0.4, accuracy: 1e-6)

        let heart = CharacterPaths.heart(center: .zero, size: 0.5).boundingRect
        XCTAssertFalse(heart.isEmpty)
        XCTAssertLessThan(heart.minY, -0.4)
        XCTAssertGreaterThan(heart.maxY, 0.3)
        XCTAssertEqual(heart.midX, 0, accuracy: 0.02)

        let crescent = CharacterPaths.moonCrescent().boundingRect
        XCTAssertFalse(crescent.isEmpty)
        XCTAssertLessThan(crescent.width, 0.35)
        XCTAssertGreaterThan(crescent.height, 0.25)

        let spiral = CharacterPaths.spiral(center: .zero, startRadius: 0.3, endRadius: 0.05, turns: 1.25).boundingRect
        XCTAssertFalse(spiral.isEmpty)
        XCTAssertLessThanOrEqual(spiral.maxX, 0.31)
        XCTAssertGreaterThanOrEqual(spiral.minX, -0.31)
    }

    func testStaticAccessoryPaths() {
        XCTAssertFalse(CharacterPaths.domeGlass().isEmpty)
        XCTAssertEqual(CharacterPaths.domeGlass().boundingRect.maxY, 1.65, accuracy: 0.01)
        XCTAssertEqual(CharacterPaths.domeGlass().boundingRect.minY, -1.30, accuracy: 0.01)
        XCTAssertFalse(CharacterPaths.robeStarField().isEmpty)
        XCTAssertFalse(CharacterPaths.capMask().isEmpty)
        XCTAssertFalse(CharacterPaths.robe(peakX: 0.05).isEmpty)
        XCTAssertEqual(CharacterPaths.robe(peakX: 0).boundingRect.maxY, 1.38, accuracy: 0.02)
        XCTAssertFalse(CharacterPaths.brain(center: CGPoint(x: 0, y: 0.62), radius: 0.3).isEmpty)
    }

    /// The inset brain (rim bands) shrinks every lobe by the inset; the grooves need the brain clip because the
    /// central fissure starts below the brain's lower edge.
    func testBrainInsetAndGrooveClip() {
        let c = CGPoint(x: 0, y: 0.62)
        let full = CharacterPaths.brain(center: c, radius: 0.3).boundingRect
        let inset = CharacterPaths.brain(center: c, radius: 0.3, inset: 0.04).boundingRect
        XCTAssertEqual(inset.minX, full.minX + 0.04, accuracy: 1e-3)
        XCTAssertEqual(inset.maxX, full.maxX - 0.04, accuracy: 1e-3)
        XCTAssertEqual(inset.minY, full.minY + 0.04, accuracy: 1e-3)
        XCTAssertEqual(inset.maxY, full.maxY - 0.04, accuracy: 1e-3)
        XCTAssertTrue(CharacterPaths.brain(center: c, radius: 0.3, inset: 0.5).isEmpty)

        let brain = CharacterPaths.brain(center: c, radius: 0.3)
        let fissureStart = CGPoint(x: 0, y: c.y - 0.16)
        XCTAssertFalse(brain.contains(fissureStart), "fissure starts outside the brain, so it must be clipped")
        XCTAssertTrue(brain.contains(CGPoint(x: 0, y: c.y)))
    }

    // MARK: - Mouth (§3.3)

    func testMouthSamplerIsClosed() {
        let pts = CharacterPaths.mouthSamples(halfWidth: 0.2, halfHeight: 0.1, smile: 0.5, restWidth: 0.2)
        XCTAssertEqual(pts.count, 33)
        guard let first = pts.first, let last = pts.last else { return XCTFail("no samples") }
        XCTAssertEqual(first.x, last.x, accuracy: 1e-9)
        XCTAssertEqual(first.y, last.y, accuracy: 1e-9)
        XCTAssertFalse(CharacterPaths.mouth(halfWidth: 0.2, halfHeight: 0.1, smile: 0.5, restWidth: 0.2).isEmpty)
    }

    func testSmileWarpRaisesCornersAndDipsCentre() {
        let w: CGFloat = 0.2
        let h: CGFloat = 0.05
        let bigW: CGFloat = 0.2
        let neutralCorner = CharacterPaths.mouthPoint(theta: 0, halfWidth: w, halfHeight: h, smile: 0, restWidth: bigW)
        let smileCorner = CharacterPaths.mouthPoint(theta: 0, halfWidth: w, halfHeight: h, smile: 1, restWidth: bigW)
        let frownCorner = CharacterPaths.mouthPoint(theta: 0, halfWidth: w, halfHeight: h, smile: -1, restWidth: bigW)
        XCTAssertGreaterThan(smileCorner.y, neutralCorner.y + 0.05)
        XCTAssertLessThan(frownCorner.y, neutralCorner.y - 0.05)

        let bottom = 3 * CGFloat.pi / 2
        let neutralBottom = CharacterPaths.mouthPoint(theta: bottom, halfWidth: w, halfHeight: h, smile: 0, restWidth: bigW)
        let smileBottom = CharacterPaths.mouthPoint(theta: bottom, halfWidth: w, halfHeight: h, smile: 1, restWidth: bigW)
        XCTAssertLessThan(smileBottom.y, neutralBottom.y)

        // Upper lip is flatter than the lower lip.
        let top = CharacterPaths.mouthPoint(theta: CGFloat.pi / 2, halfWidth: w, halfHeight: h, smile: 0, restWidth: bigW)
        XCTAssertEqual(top.y, 0.70 * h, accuracy: 1e-9)
        XCTAssertEqual(neutralBottom.y, -h, accuracy: 1e-9)
    }

    func testTeethBandsCoverTheRightSide() {
        let upper = CharacterPaths.teethBand(upper: true, halfWidth: 0.2, halfHeight: 0.1, smile: 0, restWidth: 0.2, amount: 1).boundingRect
        XCTAssertGreaterThan(upper.maxY, 0.1)
        XCTAssertEqual(upper.minY, 0.70 * 0.1 - 0.45 * 0.1, accuracy: 1e-6)
        let lower = CharacterPaths.teethBand(upper: false, halfWidth: 0.2, halfHeight: 0.1, smile: 0, restWidth: 0.2, amount: 1).boundingRect
        XCTAssertLessThan(lower.minY, -0.1)
        XCTAssertEqual(lower.maxY, -0.1 + 0.35 * 0.1, accuracy: 1e-6)
    }

    // MARK: - Colours (§2)

    func testColorConversionRoundTrips() {
        let samples: [SIMD4<Float>] = [
            SIMD4<Float>(hex: 0xFFE066), SIMD4<Float>(hex: 0x1E1748), SIMD4<Float>(hex: 0x000000),
            SIMD4<Float>(hex: 0xFFFFFF), SIMD4<Float>(0.6, 0.8, 1.0, 0.5),
        ]
        for c in samples {
            let k = CharacterColors.rgba(c)
            XCTAssertEqual(Float(k.red), c.x, accuracy: 1e-6)
            XCTAssertEqual(Float(k.green), c.y, accuracy: 1e-6)
            XCTAssertEqual(Float(k.blue), c.z, accuracy: 1e-6)
            XCTAssertEqual(Float(k.opacity), c.w, accuracy: 1e-6)
            let color = CharacterColors.color(c)
            XCTAssertEqual(color, CharacterColors.color(c), "Color conversion must be deterministic")
            #if canImport(UIKit)
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            XCTAssertTrue(UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a))
            XCTAssertEqual(Float(r), c.x, accuracy: 1.5 / 255)
            XCTAssertEqual(Float(g), c.y, accuracy: 1.5 / 255)
            XCTAssertEqual(Float(b), c.z, accuracy: 1.5 / 255)
            XCTAssertEqual(Float(a), c.w, accuracy: 1.5 / 255)
            #endif
        }
        let clamped = CharacterColors.rgba(SIMD4<Float>(1.5, -0.2, 0.5, 2))
        XCTAssertEqual(clamped.red, 1, accuracy: 1e-9)
        XCTAssertEqual(clamped.green, 0, accuracy: 1e-9)
        XCTAssertEqual(clamped.opacity, 1, accuracy: 1e-9)
    }

    func testDarkenAndMix() {
        let d = CharacterColors.darkened(SIMD4<Float>(1, 0.5, 0.2, 1), by: 0.5)
        XCTAssertEqual(d.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(d.y, 0.25, accuracy: 1e-6)
        XCTAssertEqual(d.w, 1, accuracy: 1e-6)
        let m = CharacterColors.mix(SIMD4<Float>(0, 0, 0, 1), SIMD4<Float>(1, 1, 1, 1), 0.5)
        XCTAssertEqual(m.x, 0.5, accuracy: 1e-6)
    }

    // MARK: - Resource cache (§8)

    func testGradientCacheReturnsSameInstancePerKind() {
        CharacterColors.clearCache()
        let lumi = makeDesign(kind: .lumi, shape: .star, features: [.hood, .bookAndWand, .starPattern, .floats])
        let a = CharacterColors.resources(for: lumi)
        let b = CharacterColors.resources(for: lumi)
        XCTAssertTrue(a === b, "the cache must return the same instance for the same kind")
        XCTAssertEqual(a.kind, .lumi)
        XCTAssertNotNil(a.staticBody, "star silhouette is static and cached")

        let drop = makeDesign(kind: .drop, shape: .drop, features: [.arms, .legs, .jelly])
        let c = CharacterColors.resources(for: drop)
        XCTAssertFalse(a === c)
        XCTAssertNil(c.staticBody, "drop silhouette depends on wiggle and must not be cached")
        XCTAssertEqual(a.bodyGradient.stops.count, 2)
        XCTAssertEqual(a.irisGradient.stops.count, 3)
        CharacterColors.clearCache()
    }

    // MARK: - Transforms (§2)

    func testCanvasTransformMapsUnitSpaceToView() {
        let size = CGSize(width: 300, height: 400)
        let design = makeDesign(kind: .sprout, shape: .round, features: [.arms, .legs, .leaves])
        let r = CanonicalSpace.bodyRadius(in: size, design: design)
        let origin = CanonicalSpace.origin(in: size, design: design)
        let base = CanvasTransform(matrix: CGAffineTransform(a: r, b: 0, c: 0, d: -r, tx: origin.x, ty: origin.y), unitScale: r)
        let o = base.point(0, 0)
        XCTAssertEqual(o.x, origin.x, accuracy: 1e-9)
        XCTAssertEqual(o.y, origin.y, accuracy: 1e-9)
        let top = base.point(0, 1)
        XCTAssertEqual(top.y, origin.y - r, accuracy: 1e-9, "y is flipped: unit +1 is above the origin")
        let right = base.point(1, 0)
        XCTAssertEqual(right.x, origin.x + r, accuracy: 1e-9)
        XCTAssertEqual(base.length(0.5), r * 0.5, accuracy: 1e-9)

        let scaled = base.prepending(CGAffineTransform(scaleX: 2, y: 0.5))
        XCTAssertEqual(scaled.unitScale, r, accuracy: 1e-9, "geometric mean of (2, 0.5) is 1")
        let p = scaled.point(1, 1)
        XCTAssertEqual(p.x, origin.x + 2 * r, accuracy: 1e-9)
        XCTAssertEqual(p.y, origin.y - 0.5 * r, accuracy: 1e-9)
    }

    func testSceneBodyTransformUsesAnchorAndTilt() {
        let size = CGSize(width: 400, height: 400)
        let grounded = makeDesign(kind: .sprout, shape: .round, features: [.arms, .legs, .leaves])
        var pose = CharacterPose.neutral
        pose.body.scaleY = 1.2
        let scene = CanvasScene(pose: pose, design: grounded, size: size, quality: .balanced,
                                resources: CanvasResources(design: grounded))
        // Grounded designs scale about the feet (0, −1): the feet stay put, the top moves up.
        let feet = scene.body.point(0, -1)
        let feetStatic = scene.base.point(0, -1)
        XCTAssertEqual(feet.y, feetStatic.y, accuracy: 1e-6)
        let top = scene.body.point(0, 1)
        let topStatic = scene.base.point(0, 1)
        XCTAssertLessThan(top.y, topStatic.y - 1)

        var tilted = CharacterPose.neutral
        tilted.body.tilt = 0.3
        let floater = makeDesign(kind: .lumi, shape: .star, features: [.floats])
        let floatScene = CanvasScene(pose: tilted, design: floater, size: size, quality: .high,
                                     resources: CanvasResources(design: floater))
        // Positive tilt leans the top towards the viewer's right (view x grows).
        let centre = floatScene.body.point(0, 0)
        let centreStatic = floatScene.base.point(0, 0)
        XCTAssertEqual(centre.x, centreStatic.x, accuracy: 1e-6, "floaters rotate about their centre")
        XCTAssertGreaterThan(floatScene.body.point(0, 1).x, centreStatic.x + 1)
        XCTAssertFalse(floatScene.bodyPath.isEmpty)
    }

    // MARK: - Parity details (§3.5, §3.6, §3.8)

    func testFlameHasPointedTipAndPlainLowerHalf() {
        XCTAssertEqual(CharacterPaths.dropOutlineCount, 48)
        XCTAssertEqual(CharacterPaths.dropOutlinePoint(0), CGPoint(x: 0, y: 1.05), "index 0 is the drop tip")
        for w in [CGFloat(0), 1, 2.5, 4] {
            var maxOtherY = -CGFloat.greatestFiniteMagnitude
            for i in 0..<CharacterPaths.dropOutlineCount {
                let p = CharacterPaths.flamePoint(i, wiggle: w, flickerPhase: 1.7, flicker: 0.012)
                if i > 0 { maxOtherY = max(maxOtherY, p.y) }
                // Below y = −0.15 the modulation weight is exactly 0: the flame is the plain drop there,
                // so nothing switches on at the equator.
                let d = CharacterPaths.dropOutlinePoint(i)
                if d.y < -0.15 {
                    XCTAssertEqual(p.x, d.x, accuracy: 1e-9)
                    XCTAssertEqual(p.y, d.y, accuracy: 1e-9)
                }
            }
            let tip = CharacterPaths.flamePoint(0, wiggle: w, flickerPhase: 1.7, flicker: 0.012)
            XCTAssertGreaterThan(tip.y, maxOtherY + 0.02, "the tip is a point above every other sample")
            XCTAssertEqual(tip.y, 1.05, accuracy: 0.11)
            XCTAssertEqual(tip.x, 0.22 * sin(w), accuracy: 0.02, "the tip sways 0.22·sin(wiggle)")
        }
    }

    func testCapEdgeIsShallow() {
        // Same edge as the MSL: 0.35 − 0.09·(0.5 + 0.5·cos 10x) — never below 0.26, well above Sprout's eyes.
        XCTAssertEqual(CharacterPaths.capEdgeY(0), 0.26, accuracy: 1e-9)
        XCTAssertEqual(CharacterPaths.capEdgeY(CGFloat.pi / 10), 0.35, accuracy: 1e-9)
        let box = CharacterPaths.capMask().boundingRect
        XCTAssertGreaterThanOrEqual(box.minY, 0.25)
        XCTAssertLessThanOrEqual(box.minY, 0.27)
    }

    func testCellHashMatchesTheShaderReferenceValues() {
        // Reference values of the integer hash shared with the MSL `cellHash` (computed with 32-bit wrapping arithmetic).
        XCTAssertEqual(CharacterPaths.cellHash(x: 0, y: 0, salt: 1), CGFloat(8984527) / 16777216)
        XCTAssertEqual(CharacterPaths.cellHash(x: -3, y: 2, salt: 2), CGFloat(16702215) / 16777216)
        XCTAssertEqual(CharacterPaths.cellHash(x: 4, y: -6, salt: 3), CGFloat(8344647) / 16777216)
        XCTAssertEqual(CharacterPaths.cellHash(x: -5, y: -6, salt: 1), CGFloat(5307642) / 16777216)
    }

    func testRobeStarFieldStaysOnTheRobe() {
        let box = CharacterPaths.robeStarField().boundingRect
        XCTAssertFalse(box.isEmpty)
        XCTAssertGreaterThanOrEqual(box.minX, -1.45)
        XCTAssertLessThanOrEqual(box.maxX, 1.45)
        XCTAssertGreaterThanOrEqual(box.minY, -1.70)
        XCTAssertLessThanOrEqual(box.maxY, 1.50)
        // The collar follows y = −0.55 + 0.05·x² like the MSL robe front.
        XCTAssertTrue(CharacterPaths.robeFrontMask().contains(CGPoint(x: 0, y: -0.60)))
        XCTAssertFalse(CharacterPaths.robeFrontMask().contains(CGPoint(x: 0, y: -0.50)))
        XCTAssertTrue(CharacterPaths.robeFrontMask().contains(CGPoint(x: 1.0, y: -0.55)))
        XCTAssertFalse(CharacterPaths.robeFrontMask().contains(CGPoint(x: 1.0, y: -0.45)))
    }

    func testInnerFlameColourFollowsDesign() {
        let lumie = CharacterCatalog.design(for: .lumie)
        let lumieRes = CanvasResources(design: lumie)
        XCTAssertEqual(lumieRes.innerFlame, CharacterColors.color(lumie.palette.highlight, alpha: 0.85),
                       "dome designs light the inner flame with the highlight colour, not the wooden accent")
        let ember = CharacterCatalog.design(for: .ember)
        let emberRes = CanvasResources(design: ember)
        XCTAssertEqual(emberRes.innerFlame, CharacterColors.color(ember.palette.accent, alpha: 0.85))
    }

    func testCacheRebuildsForCustomDesignWithSameKind() {
        CharacterColors.clearCache()
        let lumi = makeDesign(kind: .lumi, shape: .star, features: [.hood, .floats])
        let a = CharacterColors.resources(for: lumi)
        var themed = lumi
        themed.palette.bodyTop = SIMD4<Float>(hex: 0x66CCFF)
        let b = CharacterColors.resources(for: themed)
        XCTAssertFalse(a === b, "a different palette must not reuse the cached colours")
        XCTAssertTrue(b.matches(themed))
        XCTAssertTrue(CharacterColors.resources(for: themed) === b)
        var reshaped = themed
        reshaped.bodyShape = .round
        let c = CharacterColors.resources(for: reshaped)
        XCTAssertFalse(c === b, "a different silhouette must not reuse the cached static body")
        XCTAssertEqual(c.bodyShape, .round)
        CharacterColors.clearCache()
    }

    func testSparkleBinsDrawAtMidpoints() {
        XCTAssertEqual(SparkleBins.index(alpha: 0.05), 0)
        XCTAssertEqual(SparkleBins.index(alpha: 0.3), 2)
        XCTAssertEqual(SparkleBins.index(alpha: 1.0), 7)
        XCTAssertEqual(SparkleBins.index(alpha: .nan), 0)
        XCTAssertEqual(SparkleBins.opacity(0), 0.0625, accuracy: 1e-12)
        for a in stride(from: Float(0.05), through: 1.0, by: 0.01) {
            let k = SparkleBins.index(alpha: a)
            XCTAssertLessThanOrEqual(abs(SparkleBins.opacity(k) - Double(a)), 1.0 / 16 + 1e-6)
        }
    }

    func testPainterSurvivesNonFinitePose() {
        var broken = CharacterPose.neutral
        broken.body.accessory = .nan
        broken.body.armL = .nan
        broken.face.eyeOpenL = .infinity
        XCTAssertFalse(CharacterPainter.isFinite(broken))
        XCTAssertTrue(CharacterPainter.isFinite(.neutral))
        let brokenPose = broken
        for kind in [CharacterKind.lumie, .sprout, .lumi] {
            let design = CharacterCatalog.design(for: kind)
            let view = Canvas { context, size in
                CharacterPainter.draw(pose: brokenPose, design: design, in: &context, size: size, quality: .high)
            }
            .frame(width: 120, height: 120)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: 120, height: 120)
            renderer.scale = 1
            _ = renderer.cgImage
        }
    }

    // MARK: - Rendering smoke test

    func testPainterRendersEveryKindWithoutCrashing() {
        var busy = CharacterPose.neutral
        busy.face.mouth = MouthShape(open: 0.7, width: 0.3, smile: 0.6, round: 0.1, upperTeeth: 0.8, lowerTeeth: 0.5, tongue: 0.6, press: 0)
        busy.face.eyeOpenL = 1.2
        busy.face.eyeOpenR = 0.6
        busy.face.lowerLidR = 0.5
        busy.face.gazeX = 0.5
        busy.face.gazeY = -0.3
        busy.face.headTurn = 0.4
        busy.face.headTilt = 0.1
        busy.face.blush = 0.8
        busy.face.browRaiseL = -1
        busy.face.browTiltR = 0.7
        busy.body.armL = 0.8
        busy.body.legR = 1
        busy.body.accessory = 1
        busy.body.accessory2 = 1
        busy.body.tilt = 0.1
        busy.body.wiggle = 2
        busy.effects = EffectsPose(v: SIMD8<Float>(repeating: 1))
        busy.time = 3.7

        for kind in CharacterKind.allCases {
            let design = CharacterCatalog.design(for: kind)
            for quality in CanvasQuality.allCases {
                for pose in [CharacterPose.neutral, busy] {
                    let view = Canvas { context, size in
                        CharacterPainter.draw(pose: pose, design: design, in: &context, size: size, quality: quality)
                    }
                    .frame(width: 160, height: 200)
                    let renderer = ImageRenderer(content: view)
                    renderer.proposedSize = ProposedViewSize(width: 160, height: 200)
                    renderer.scale = 1
                    #if canImport(UIKit)
                    if let image = renderer.uiImage {
                        XCTAssertGreaterThan(image.size.width, 0)
                        XCTAssertGreaterThan(image.size.height, 0)
                    }
                    #else
                    _ = renderer.cgImage
                    #endif
                }
            }
        }
    }
}
