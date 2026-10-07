import XCTest
import Foundation
@testable import StoryCharacters

/// Metal module tests. No GPU, window or audio hardware: only the uniform layout and the shader text.
final class MetalShaderTests: XCTestCase {

    /// The 35 `float4` members of `CharacterUniforms`, in Swift declaration order (CONTRACT §RenderContract).
    private static let expectedFieldNames: [String] = [
        "viewport", "transform", "bodyParams", "armsAccessory", "legsBounce",
        "eyesA", "eyesB", "brows", "head", "mouthA", "mouthB", "fxA", "fxB",
        "layoutA", "layoutB", "layoutC", "layoutD", "layoutE", "style", "idle",
        "colBodyTop", "colBodyBottom", "colHighlight", "colShadow", "colAccent", "colAccent2",
        "colIris", "colPupil", "colSclera", "colCheek", "colGlow", "colMouthInner", "colTongue",
        "colTeeth", "colOutline",
    ]

    /// `…/StoryCharacters/Sources/StoryCharacters/Metal/Shaders/CharacterShaders.metal`, located relative to this file
    /// (`Tests/StoryCharactersTests/MetalShaderTests.swift` → `../../Sources/…`).
    private static var shaderFileURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Tests/StoryCharactersTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // package root
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("StoryCharacters", isDirectory: true)
            .appendingPathComponent("Metal", isDirectory: true)
            .appendingPathComponent("Shaders", isDirectory: true)
            .appendingPathComponent("CharacterShaders.metal", isDirectory: false)
    }

    // MARK: - Uniform layout

    func testUniformsStrideIs560Bytes() {
        XCTAssertEqual(MemoryLayout<CharacterUniforms>.stride, 560)
        XCTAssertEqual(MemoryLayout<CharacterUniforms>.size, 560)
        XCTAssertEqual(MemoryLayout<CharacterUniforms>.stride, CharacterUniforms.slotCount * 16)
        XCTAssertEqual(CharacterUniforms.slotCount, 35)
        XCTAssertEqual(MemoryLayout<CharacterUniforms>.alignment, MemoryLayout<SIMD4<Float>>.alignment)
    }

    func testUniformsPackPoseAndDesign() {
        let design = CharacterDesign(kind: .lumi, bodyShape: .star, palette: MetalShaderTests.testPalette,
                                     frame: FrameLayout(radiusScale: 0.5, centerOffsetY: -0.05),
                                     features: [.hood, .bookAndWand, .starPattern, .floats])
        var pose = CharacterPose.neutral
        pose.face.eyeOpenL = 0.4
        pose.face.mouth.open = 0.7
        pose.body.tilt = 0.2
        pose.effects.hearts = 1
        let u = CharacterUniforms(pose: pose, design: design, viewportSize: SIMD2<Float>(300, 200), time: 2.5)
        XCTAssertEqual(u.viewport.x, 300)
        XCTAssertEqual(u.viewport.y, 200)
        XCTAssertEqual(u.viewport.z, 1.5, accuracy: 1e-6)
        XCTAssertEqual(u.viewport.w, 2.5)
        XCTAssertEqual(u.eyesA.x, 0.4)
        XCTAssertEqual(u.mouthA.x, 0.7)
        XCTAssertEqual(u.bodyParams.x, 0.2)
        XCTAssertEqual(u.fxA.z, 1)
        XCTAssertEqual(Int(u.style.x), BodyShape.star.rawValue)
        XCTAssertEqual(UInt32(u.style.y), design.features.rawValue)
        XCTAssertEqual(u.layoutE.y, 0.5)
        XCTAssertEqual(u.layoutE.z, -0.05)
        XCTAssertEqual(u.colBodyTop, design.palette.bodyTop)
        XCTAssertEqual(u.colOutline, design.palette.outline)
    }

    // MARK: - Shader source parity

    func testEmbeddedSourceMatchesMetalFile() throws {
        let url = MetalShaderTests.shaderFileURL
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "CharacterShaders.metal not found next to the test sources at \(url.path)")
        let fileText = try String(contentsOf: url, encoding: .utf8)
        let embedded = CharacterShaderSource.msl
        // CONTRACT §4.4: byte-identical, including the final newline.
        XCTAssertEqual(embedded.utf8.count, fileText.utf8.count, "embedded MSL length differs from the .metal file")
        XCTAssertTrue(embedded.utf8.elementsEqual(fileText.utf8), "embedded MSL differs from CharacterShaders.metal")
        XCTAssertTrue(embedded.hasSuffix("}\n"), "embedded MSL lost the file's final newline")
    }

    func testEmbeddedSourceHasNoSwiftInterpolationSequence() {
        // A raw string would keep it literally, but tools/check.py forbids it; keep the two files trivially identical.
        XCTAssertFalse(CharacterShaderSource.msl.contains("\\("))
        XCTAssertFalse(CharacterShaderSource.msl.contains("\\"))
    }

    func testShaderDeclaresEntryPoints() {
        let msl = CharacterShaderSource.msl
        XCTAssertTrue(msl.contains("#include <metal_stdlib>"))
        XCTAssertTrue(msl.contains("using namespace metal;"))
        XCTAssertTrue(msl.contains("vertex CharacterVaryings characterVertex("))
        XCTAssertTrue(msl.contains("fragment float4 characterFragment("))
        XCTAssertTrue(msl.contains("vertex SparkleVaryings sparkleVertex("))
        XCTAssertTrue(msl.contains("fragment float4 sparkleFragment("))
    }

    func testShaderUniformFieldsMatchSwiftOrder() throws {
        let names = try MetalShaderTests.uniformFieldNames(in: CharacterShaderSource.msl)
        XCTAssertEqual(names.count, 35)
        XCTAssertEqual(names, MetalShaderTests.expectedFieldNames)
    }

    func testSparkleFormulaConstantsPresent() {
        // §3.8 is implemented verbatim in sparkleVertex.
        let msl = CharacterShaderSource.msl
        // The hash uses precise::sin so GPU seeds match Swift's Float sin (fast-math sin is inexact at ~770 rad).
        XCTAssertTrue(msl.contains("fract(precise::sin(i * 12.9898) * 43758.5453)"))
        XCTAssertTrue(msl.contains("fract(seed * 7.1 + 0.37)"))
        XCTAssertTrue(msl.contains("2.2 + 1.8 * seed2"))
        XCTAssertTrue(msl.contains("1.10 + 0.60 * fract(seed * 3.3)"))
        XCTAssertTrue(msl.contains("0.05 * (0.6 + fract(seed * 5.5))"))
        XCTAssertTrue(msl.contains("iid >= 40u"))
        // Burst particles share the ambient position formula (§3.8 changes only rate, rad and lifetime).
        XCTAssertTrue(msl.contains("float2 pos = float2(cos(ang) * rad, sin(ang) * rad * 0.6 + (t - 0.5) * 0.6);"))
    }

    func testRobeStarHashMatchesTheCanvasMirror() {
        // `cellHash` must stay bit-identical to `CharacterPaths.cellHash` (Canvas robe star field).
        let msl = CharacterShaderSource.msl
        XCTAssertTrue(msl.contains("uint h = uint(cell.x) * 73856093u;"))
        XCTAssertTrue(msl.contains("h ^= uint(cell.y) * 19349663u;"))
        XCTAssertTrue(msl.contains("h ^= salt * 83492791u;"))
        XCTAssertTrue(msl.contains("h *= 2146121005u;"))
        XCTAssertTrue(msl.contains("h *= 2221713035u;"))
        XCTAssertTrue(msl.contains("return float(h & 16777215u) / 16777216.0;"))
    }

    func testSilhouettesAndLayeringFollowTheCanvasRenderer() {
        let msl = CharacterShaderSource.msl
        // Flame = the drop outline plus the §3.5 modulation, swayed like `CharacterPaths.flamePoint`.
        XCTAssertTrue(msl.contains("float2 u = float2(q.x - 0.22 * sin(wig) * smoothstep(0.1, 1.05, q.y), q.y);"))
        // Hood curl runs along the same quadratic Bezier as `CharacterPaths.hoodBody` ((0.25, 1.25) is its control point).
        XCTAssertTrue(msl.contains("2.0 * u * t * float2(0.25, 1.25)"))
        // Brows are clamped to the FacePose range like the Canvas brows.
        XCTAssertTrue(msl.contains("float raise = clamp((side < 0.0) ? u.brows.x : u.brows.y, -1.0, 1.0);"))
        // Dome fireflies are composited under the glass (Canvas order: sparkles, then glass).
        XCTAssertTrue(msl.contains("m *= fillAA(sdDomeGlass(in.world), aa) * (1.0 - glass.a);"))
    }

    func testAccessoryShadingFollowsTheCanvasRenderer() {
        let msl = CharacterShaderSource.msl
        // Lumi's dark robe is back-lit by an accent2 rim so the hood silhouette stays visible on the night sky.
        XCTAssertTrue(msl.contains("col = mix(col, u.colAccent2.rgb, 0.60 * rim * rim * rim);"))
        // Puff's cloud is an exact union of circles like `CharacterPaths.cloudBody` (no smooth-min filling the creases).
        XCTAssertTrue(msl.contains("d = min(d, sdCircle(q, float2(-0.55, -0.10), 0.55));"))
        // Dome highlights: the Canvas streak, reflection ellipse and accessory shimmer.
        XCTAssertTrue(msl.contains("float dS = sdCapsule(p, float2(-1.12, 0.50), float2(-0.70, 1.20), 0.045);"))
        XCTAssertTrue(msl.contains("float dR = sdEllipseGrad(p, float2(0.0, -1.20), float2(1.15, 0.06));"))
        XCTAssertTrue(msl.contains("float dSh = sdCapsule(p, float2(1.05, 0.20), float2(0.85, 0.95), 0.03);"))
        // Sparkle sprite = the Canvas 4-point star (tips at `size`, inner vertices at 0.36 size); same visibility cut-off.
        XCTAssertTrue(msl.contains("float2(0.254558441, 0.254558441)"))
        XCTAssertTrue(msl.contains("float m = fillAA(sdSparkleStar(sp), aaS) * in.alpha;"))
        XCTAssertTrue(msl.contains("if (alpha <= 0.04 || size <= 0.002) {"))
    }

    func testClosedEyesAndBrainFollowTheCanvasRenderer() {
        let msl = CharacterShaderSource.msl
        // Closed eyes: a relaxed closure sags, a cheek-squeezed one (laughing, giggle) arches into the happy ^ ^ like
        // the Canvas lash line y = y0 + amp·(1 − xn²).
        XCTAssertTrue(msl.contains("float happy = smoothstep(0.45, 0.85, clamp(lowerLid, 0.0, 1.0));"))
        XCTAssertTrue(msl.contains("float amp = -0.04 + 0.09 * happy;"))
        XCTAssertTrue(msl.contains("float curveY = y0 + amp * (1.0 - xn * xn);"))
        // Spark's brain: the Canvas centre (0, 0.58) and radius 0.27 (= 0.9 × 0.30), sheared with the swaying drop tip.
        XCTAssertTrue(msl.contains("float k = (1.0 + 0.08 * a) * 0.9;"))
        XCTAssertTrue(msl.contains("float2 c = float2(0.0, 0.58);"))
        XCTAssertTrue(msl.contains("float2 qs = float2(q.x - tipX * smoothstep(0.05, 1.15, q.y), q.y);"))
        XCTAssertTrue(msl.contains("acc = drawBrain(acc, q, (shape == 2) ? (0.18 * sin(wig)) : 0.0, aaB, u);"))
    }

    func testBreathingUsesTheDesignBreathDepth() {
        // §3.5: renderers scale `breathe` by `idle.breathDepth`; the renderer stores it in the spare `layoutE.w`.
        XCTAssertTrue(CharacterShaderSource.msl.contains("float breathe = u.bodyParams.y * u.layoutE.w;"))
    }

    // MARK: - Helpers

    /// Scans `struct CharacterUniforms { … };` and returns the `float4` member names in order (no regex).
    private static func uniformFieldNames(in source: String) throws -> [String] {
        guard let structRange = source.range(of: "struct CharacterUniforms") else {
            throw TestError.missingStruct
        }
        guard let openBrace = source.range(of: "{", range: structRange.upperBound..<source.endIndex) else {
            throw TestError.missingStruct
        }
        guard let closeBrace = source.range(of: "};", range: openBrace.upperBound..<source.endIndex) else {
            throw TestError.missingStruct
        }
        let body = source[openBrace.upperBound..<closeBrace.lowerBound]
        var names: [String] = []
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = Substring(rawLine)
            if let comment = line.range(of: "//") {
                line = line[line.startIndex..<comment.lowerBound]
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("float4 ") else { continue }
            var rest = trimmed.dropFirst("float4 ".count)
            if let semicolon = rest.firstIndex(of: ";") {
                rest = rest[rest.startIndex..<semicolon]
            }
            let name = rest.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                names.append(name)
            }
        }
        return names
    }

    private enum TestError: Error {
        case missingStruct
    }

    private static let testPalette = Palette(
        bodyTop: SIMD4<Float>(hex: 0xFFE066), bodyBottom: SIMD4<Float>(hex: 0xFFB224),
        highlight: SIMD4<Float>(hex: 0xFFF6C2), shadow: SIMD4<Float>(hex: 0xE08A12),
        accent: SIMD4<Float>(hex: 0x1E1748), accent2: SIMD4<Float>(hex: 0x7B5CFF),
        iris: SIMD4<Float>(hex: 0x2B1B12), pupil: SIMD4<Float>(hex: 0x120A06),
        sclera: SIMD4<Float>(hex: 0xFFFFFF), cheek: SIMD4<Float>(hex: 0xFFB088),
        glow: SIMD4<Float>(hex: 0xFFD36A), mouthInner: SIMD4<Float>(hex: 0x5A2415),
        tongue: SIMD4<Float>(hex: 0xFF7E8A), teeth: SIMD4<Float>(hex: 0xFFFFFF),
        outline: SIMD4<Float>(hex: 0x4A2A10))
}
