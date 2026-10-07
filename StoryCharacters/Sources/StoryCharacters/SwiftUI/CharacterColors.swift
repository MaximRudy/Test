import SwiftUI
import simd

/// Colour helpers for the Canvas renderer (CONTRACT §2 "Colours"): palette values are sRGB floats with
/// straight alpha and are converted with `Color(.sRGB, red:green:blue:opacity:)` so they match the Metal
/// renderer's `.bgra8Unorm` pass-through exactly.
enum CharacterColors {

    /// sRGB components as Doubles, clamped to 0...1.
    static func rgba(_ c: SIMD4<Float>) -> (red: Double, green: Double, blue: Double, opacity: Double) {
        (red: Double(min(max(c.x, 0), 1)),
         green: Double(min(max(c.y, 0), 1)),
         blue: Double(min(max(c.z, 0), 1)),
         opacity: Double(min(max(c.w, 0), 1)))
    }

    /// `SIMD4<Float>` → SwiftUI `Color` (sRGB, straight alpha).
    static func color(_ c: SIMD4<Float>) -> Color {
        let k = rgba(c)
        return Color(.sRGB, red: k.red, green: k.green, blue: k.blue, opacity: k.opacity)
    }

    /// Same as `color(_:)` with the alpha replaced.
    static func color(_ c: SIMD4<Float>, alpha: Float) -> Color {
        color(SIMD4<Float>(c.x, c.y, c.z, alpha))
    }

    /// Multiplies RGB by `(1 − fraction)`, keeps alpha.
    static func darkened(_ c: SIMD4<Float>, by fraction: Float) -> SIMD4<Float> {
        let k = 1 - min(max(fraction, 0), 1)
        return SIMD4<Float>(c.x * k, c.y * k, c.z * k, c.w)
    }

    /// Linear blend of two colours (all four channels).
    static func mix(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
        a + (b - a) * t
    }

    static func withAlpha(_ c: SIMD4<Float>, _ alpha: Float) -> SIMD4<Float> {
        SIMD4<Float>(c.x, c.y, c.z, alpha)
    }

    /// Multiplies RGB by `k` (which may exceed 1) and clamps it to 0...1, keeps alpha — the MSL `min(c·k, 1)`.
    static func scaled(_ c: SIMD4<Float>, by k: Float) -> SIMD4<Float> {
        SIMD4<Float>(min(max(c.x * k, 0), 1), min(max(c.y * k, 0), 1), min(max(c.z * k, 0), 1), c.w)
    }

    static let white = SIMD4<Float>(1, 1, 1, 1)
    static let tear = SIMD4<Float>(0.6, 0.8, 1.0, 1.0)

    // MARK: - Cache

    @MainActor private static var cache: [CharacterKind: CanvasResources] = [:]

    /// Cached colours, gradients and static unit paths for a design. One instance per `CharacterKind`
    /// (§8); the entry is rebuilt when a custom design reuses a kind with another palette, shape or features.
    @MainActor
    static func resources(for design: CharacterDesign) -> CanvasResources {
        if let cached = cache[design.kind], cached.matches(design) {
            return cached
        }
        let created = CanvasResources(design: design)
        cache[design.kind] = created
        return created
    }

    /// Drops every cached resource (tests / memory pressure).
    @MainActor
    static func clearCache() {
        cache.removeAll()
    }
}

/// Per-design immutable resources: pre-converted `Color`s, `Gradient`s and static unit-space paths.
/// Built once per `CharacterKind` by `CharacterColors.resources(for:)` so the per-frame painter never
/// constructs a `Color` or `Gradient`.
@MainActor
final class CanvasResources {
    let kind: CharacterKind
    /// The design values these resources were built from (cache validation).
    let palette: Palette
    let bodyShape: BodyShape
    let features: DesignFeatures

    // Palette as Colors.
    let bodyTop: Color
    let bodyBottom: Color
    let highlight: Color
    let shadow: Color
    let accent: Color
    let accent2: Color
    let iris: Color
    let pupil: Color
    let sclera: Color
    let cheek: Color
    let glow: Color
    let mouthInner: Color
    let tongue: Color
    let teeth: Color
    let outline: Color

    // Derived colours (alpha baked in where the contract fixes it).
    let white: Color
    let eyeHighlight: Color       // white α 0.95
    let rimBand1: Color           // shadow α 0.020 — rim ramp, outermost band (0.08 deep)
    let rimBand2: Color           // shadow α 0.055 — 0.055 deep
    let rimBand3: Color           // shadow α 0.125 — 0.03 deep
    let rimBand4: Color           // shadow α 0.135 — 0.012 deep (≈ 0.30 combined at the edge)
    let rimShadowSoft: Color      // shadow α 0.12
    let limbalRing: Color         // pupil α 0.35
    let browColor: Color          // outline α 0.9
    let lipLine: Color            // outline α 0.35
    let lidShadow: Color          // outline α 0.18
    let legColor: Color           // bodyBottom darkened 15 %
    let robeStar: Color           // accent2 α 0.7
    let accentDark: Color         // accent darkened 30 %
    let robeRimSoft: Color        // accent2 α 0.22 — robe rim light, outer band (0.10 deep)
    let robeRimHard: Color        // accent2 α 0.45 — 0.035 deep (≈ 0.57 combined at the edge)
    let glassFill: Color          // accent2 α 0.10
    let glassRim: Color           // accent2 α 0.35
    let specular: Color           // white α 0.35
    let specularDim: Color        // white α 0.25 (second dome streak)
    let reflection: Color         // white α 0.15
    let wandStripe: Color         // highlight α 0.35 (stripe along the wand)
    let bookRimOuter: Color       // outline α 0.052 — book cover rim ramp, outer band (0.04 deep)
    let bookRimInner: Color       // outline α 0.229 — 0.015 deep (≈ 0.27 combined at the edge)
    let innerFlame: Color         // accent α 0.85 (highlight for `.dome` designs, whose accent is the wooden base)
    let tearColor: Color          // (0.6, 0.8, 1.0)
    let sparkle: Color            // mix(glow, white, 0.5)
    let wandColor: Color          // shadow
    let glyph: Color              // white
    let glyphShadow: Color        // outline α 0.6
    let glowBand: Color           // glow α 0.35 (outer band of the blurred `.high` glow)
    let capShadowNear: Color      // shadow α 0.15 (first 0.035 under Sprout's cap edge)
    let capShadowFar: Color       // shadow α 0.06 (first 0.07 under the cap edge)
    let brainRimOuter: Color      // accent2 × 0.8 α 0.065 — Spark's brain rim ramp, outer band (0.04 deep)
    let brainRimInner: Color      // accent2 × 0.8 α 0.29 — 0.015 deep (≈ 0.34 combined at the edge)

    // Gradients.
    let bodyGradient: Gradient         // bodyTop (y = +1) → bodyBottom (y = −1)
    let highlightGradient: Gradient    // highlight α 0.35 → 0 over a unit disc: (1 − smoothstep(0.35, 1, ρ))·0.35
    let robeGradient: Gradient         // min(accent × 1.45, 1) at y ≥ 1 → accent × 0.72 at y ≤ −1.5 (MSL robeColor)
    let robeInteriorGradient: Gradient // robeGradient × 0.45 (hood interior seen through the face opening)
    let darkFaceGradient: Gradient     // accent × 1.8 at the centre → accent at the rim (unit disc)
    let irisGradient: Gradient         // iris → 35 % darker at the rim, linear in the radius (MSL iris·(1 − 0.35·t))
    let irisHaloGradient: Gradient     // iris α 0.6 → 0
    let glowHaloGradient: Gradient     // glow, exp(−d/0.35) outside the unit circle, for a circle of radius 1.9
    let softGlowGradient: Gradient     // glow α 1 → 0 (accessory glows, burst)
    let accent2GlowGradient: Gradient  // accent2 α 1 → 0 (moon / wand)
    let cheekGradient: Gradient        // cheek α 1 with Gaussian falloff → 0
    let lidShadowGradient: Gradient    // outline α 0.18 → 0
    let baseGradient: Gradient         // accent → accent darkened 35 % (dome base)
    let shoulderShadowGradient: Gradient // shadow α 0.28 → 0 (arm contact shadow)
    let brainGradient: Gradient        // accent → mix(accent, accent2, 0.4) (Spark's brain, vertical shade)
    let bookGradient: Gradient         // accent2 × 0.7 → accent2 (book cover, along the book's y)

    // Static unit-space paths.
    let staticBody: Path?
    let moonCrescent: Path
    let domeGlass: Path
    let robeStarField: Path
    let robeOpening: Path
    let robeFrontMask: Path
    let capMask: Path
    let capShadowNearPath: Path        // capMask shifted down 0.035
    let capShadowFarPath: Path         // capMask shifted down 0.07
    let haloCircle: Path               // circle r 1.9 at the origin
    let unitDisc: Path                 // circle r 1 at the origin

    init(design: CharacterDesign) {
        let p = design.palette
        kind = design.kind
        palette = p
        bodyShape = design.bodyShape
        features = design.features

        bodyTop = CharacterColors.color(p.bodyTop)
        bodyBottom = CharacterColors.color(p.bodyBottom)
        highlight = CharacterColors.color(p.highlight)
        shadow = CharacterColors.color(p.shadow)
        accent = CharacterColors.color(p.accent)
        accent2 = CharacterColors.color(p.accent2)
        iris = CharacterColors.color(p.iris)
        pupil = CharacterColors.color(p.pupil)
        sclera = CharacterColors.color(p.sclera)
        cheek = CharacterColors.color(p.cheek)
        glow = CharacterColors.color(p.glow)
        mouthInner = CharacterColors.color(p.mouthInner)
        tongue = CharacterColors.color(p.tongue)
        teeth = CharacterColors.color(p.teeth)
        outline = CharacterColors.color(p.outline)

        white = CharacterColors.color(CharacterColors.white)
        eyeHighlight = CharacterColors.color(CharacterColors.white, alpha: 0.95)
        rimBand1 = CharacterColors.color(p.shadow, alpha: 0.020)
        rimBand2 = CharacterColors.color(p.shadow, alpha: 0.055)
        rimBand3 = CharacterColors.color(p.shadow, alpha: 0.125)
        rimBand4 = CharacterColors.color(p.shadow, alpha: 0.135)
        rimShadowSoft = CharacterColors.color(p.shadow, alpha: 0.12)
        limbalRing = CharacterColors.color(p.pupil, alpha: 0.35)
        browColor = CharacterColors.color(p.outline, alpha: 0.9)
        lipLine = CharacterColors.color(p.outline, alpha: 0.35)
        lidShadow = CharacterColors.color(p.outline, alpha: 0.18)
        legColor = CharacterColors.color(CharacterColors.darkened(p.bodyBottom, by: 0.15))
        robeStar = CharacterColors.color(p.accent2, alpha: 0.7)
        accentDark = CharacterColors.color(CharacterColors.darkened(p.accent, by: 0.30))
        // MSL robeColor rim light: mix(col, accent2, 0.60·rim³), rim = (d + 0.10)/0.10. Two strokes clipped to the
        // robe approximate it: 0.22 over the outer 0.10, and 0.22 + 0.45·(1 − 0.22) ≈ 0.57 over the outermost 0.035.
        robeRimSoft = CharacterColors.color(p.accent2, alpha: 0.22)
        robeRimHard = CharacterColors.color(p.accent2, alpha: 0.45)
        glassFill = CharacterColors.color(p.accent2, alpha: 0.10)
        glassRim = CharacterColors.color(p.accent2, alpha: 0.35)
        specular = CharacterColors.color(CharacterColors.white, alpha: 0.35)
        specularDim = CharacterColors.color(CharacterColors.white, alpha: 0.25)
        reflection = CharacterColors.color(CharacterColors.white, alpha: 0.15)
        wandStripe = CharacterColors.color(p.highlight, alpha: 0.35)
        // MSL book rim: mix(col, outline, 0.4·rim²), rim = (d + 0.04)/0.04. Two bands average the ramp: 0.052 over
        // 0.015…0.04 deep, and 0.052 + 0.229·(1 − 0.052) ≈ 0.27 over the outermost 0.015.
        bookRimOuter = CharacterColors.color(p.outline, alpha: 0.052)
        bookRimInner = CharacterColors.color(p.outline, alpha: 0.229)
        // Lumie's accent is the wooden dome base, so dome designs light the inner flame with the highlight
        // colour (same rule as the Metal shader).
        innerFlame = CharacterColors.color(design.features.contains(.dome) ? p.highlight : p.accent, alpha: 0.85)
        tearColor = CharacterColors.color(CharacterColors.tear)
        sparkle = CharacterColors.color(CharacterColors.mix(p.glow, CharacterColors.white, 0.5))
        wandColor = CharacterColors.color(p.shadow)
        glyph = CharacterColors.color(CharacterColors.white)
        glyphShadow = CharacterColors.color(p.outline, alpha: 0.6)
        glowBand = CharacterColors.color(p.glow, alpha: 0.35)
        capShadowNear = CharacterColors.color(p.shadow, alpha: 0.15)
        capShadowFar = CharacterColors.color(p.shadow, alpha: 0.06)
        // MSL drawBrain rim: mix(col, accent2·0.8, 0.5·rim²), rim = (d + 0.04)/0.04. Two bands average the ramp:
        // 0.065 over 0.015…0.04 deep, and 0.065 + 0.29·(1 − 0.065) ≈ 0.336 over the outermost 0.015.
        let brainRim = CharacterColors.darkened(p.accent2, by: 0.2)
        brainRimOuter = CharacterColors.color(brainRim, alpha: 0.065)
        brainRimInner = CharacterColors.color(brainRim, alpha: 0.29)

        bodyGradient = Gradient(colors: [bodyTop, bodyBottom])
        // (1 − smoothstep(0.35, 1, ρ)) · 0.35 sampled at ρ = 0, 0.35, 0.5, 0.675, 0.85, 1.
        highlightGradient = Gradient(stops: [
            Gradient.Stop(color: CharacterColors.color(p.highlight, alpha: 0.35), location: 0),
            Gradient.Stop(color: CharacterColors.color(p.highlight, alpha: 0.35), location: 0.35),
            Gradient.Stop(color: CharacterColors.color(p.highlight, alpha: 0.303), location: 0.5),
            Gradient.Stop(color: CharacterColors.color(p.highlight, alpha: 0.175), location: 0.675),
            Gradient.Stop(color: CharacterColors.color(p.highlight, alpha: 0.047), location: 0.85),
            Gradient.Stop(color: CharacterColors.color(p.highlight, alpha: 0), location: 1),
        ])
        // MSL robeColor: mix(accent·0.72, min(accent·1.45, 1), clamp(0.4·y + 0.6, 0, 1)) — linear in y from y = −1.5 to
        // y = 1 and flat beyond. The painter's gradient axis runs from the hood peak (y = 1.38, location 0) to below the
        // hem (y = −1.55, location 1), so y = 1 sits at 0.38/2.93 ≈ 0.1297 and y = −1.5 at 2.88/2.93 ≈ 0.9829.
        let robeTop = CharacterColors.scaled(p.accent, by: 1.45)
        let robeBottom = CharacterColors.scaled(p.accent, by: 0.72)
        robeGradient = Gradient(stops: [
            Gradient.Stop(color: CharacterColors.color(robeTop), location: 0),
            Gradient.Stop(color: CharacterColors.color(robeTop), location: 0.1297),
            Gradient.Stop(color: CharacterColors.color(robeBottom), location: 0.9829),
            Gradient.Stop(color: CharacterColors.color(robeBottom), location: 1),
        ])
        let interiorTop = CharacterColors.scaled(robeTop, by: 0.45)
        let interiorBottom = CharacterColors.scaled(robeBottom, by: 0.45)
        robeInteriorGradient = Gradient(stops: [
            Gradient.Stop(color: CharacterColors.color(interiorTop), location: 0),
            Gradient.Stop(color: CharacterColors.color(interiorTop), location: 0.1297),
            Gradient.Stop(color: CharacterColors.color(interiorBottom), location: 0.9829),
            Gradient.Stop(color: CharacterColors.color(interiorBottom), location: 1),
        ])
        // mix(accent·1.8, accent, smoothstep(−0.45, 0, d)) with d ≈ 0.76·(ρ − 1) for the (0.72, 0.80) ellipse.
        let faceLight = SIMD4<Float>(p.accent.x * 1.8, p.accent.y * 1.8, p.accent.z * 1.8, p.accent.w)
        darkFaceGradient = Gradient(stops: [
            Gradient.Stop(color: CharacterColors.color(faceLight), location: 0),
            Gradient.Stop(color: CharacterColors.color(faceLight), location: 0.41),
            Gradient.Stop(color: CharacterColors.color(CharacterColors.mix(faceLight, p.accent, 0.247)), location: 0.6),
            Gradient.Stop(color: CharacterColors.color(CharacterColors.mix(faceLight, p.accent, 0.734)), location: 0.8),
            Gradient.Stop(color: accent, location: 1),
        ])
        irisGradient = Gradient(stops: [
            Gradient.Stop(color: iris, location: 0),
            Gradient.Stop(color: CharacterColors.color(CharacterColors.darkened(p.iris, by: 0.35)), location: 1),
        ])
        irisHaloGradient = Gradient(stops: [
            Gradient.Stop(color: CharacterColors.color(p.iris, alpha: 0.6), location: 0),
            Gradient.Stop(color: CharacterColors.color(p.iris, alpha: 0.6), location: 0.55),
            Gradient.Stop(color: CharacterColors.color(p.iris, alpha: 0.25), location: 0.78),
            Gradient.Stop(color: CharacterColors.color(p.iris, alpha: 0), location: 1),
        ])
        // exp(−d / 0.35) sampled at d = 0, 0.35, 0.70, 0.90 for a halo circle of radius 1.9 (body edge at r = 1).
        glowHaloGradient = Gradient(stops: [
            Gradient.Stop(color: CharacterColors.color(p.glow, alpha: 1.0), location: 0),
            Gradient.Stop(color: CharacterColors.color(p.glow, alpha: 1.0), location: 0.526),
            Gradient.Stop(color: CharacterColors.color(p.glow, alpha: 0.37), location: 0.71),
            Gradient.Stop(color: CharacterColors.color(p.glow, alpha: 0.135), location: 0.89),
            Gradient.Stop(color: CharacterColors.color(p.glow, alpha: 0), location: 1),
        ])
        softGlowGradient = Gradient(stops: [
            Gradient.Stop(color: CharacterColors.color(p.glow, alpha: 1.0), location: 0),
            Gradient.Stop(color: CharacterColors.color(p.glow, alpha: 0.45), location: 0.4),
            Gradient.Stop(color: CharacterColors.color(p.glow, alpha: 0), location: 1),
        ])
        accent2GlowGradient = Gradient(stops: [
            Gradient.Stop(color: CharacterColors.color(p.accent2, alpha: 1.0), location: 0),
            Gradient.Stop(color: CharacterColors.color(p.accent2, alpha: 0.4), location: 0.45),
            Gradient.Stop(color: CharacterColors.color(p.accent2, alpha: 0), location: 1),
        ])
        cheekGradient = Gradient(stops: [
            Gradient.Stop(color: CharacterColors.color(p.cheek, alpha: 1.0), location: 0),
            Gradient.Stop(color: CharacterColors.color(p.cheek, alpha: 0.78), location: 0.35),
            Gradient.Stop(color: CharacterColors.color(p.cheek, alpha: 0.30), location: 0.7),
            Gradient.Stop(color: CharacterColors.color(p.cheek, alpha: 0), location: 1),
        ])
        lidShadowGradient = Gradient(colors: [lidShadow, CharacterColors.color(p.outline, alpha: 0)])
        baseGradient = Gradient(colors: [accent, CharacterColors.color(CharacterColors.darkened(p.accent, by: 0.35))])
        shoulderShadowGradient = Gradient(stops: [
            Gradient.Stop(color: CharacterColors.color(p.shadow, alpha: 0.28), location: 0),
            Gradient.Stop(color: CharacterColors.color(p.shadow, alpha: 0.14), location: 0.5),
            Gradient.Stop(color: CharacterColors.color(p.shadow, alpha: 0), location: 1),
        ])
        brainGradient = Gradient(colors: [CharacterColors.color(p.accent),
                                          CharacterColors.color(CharacterColors.mix(p.accent, p.accent2, 0.4))])
        bookGradient = Gradient(colors: [CharacterColors.color(CharacterColors.darkened(p.accent2, by: 0.3)), accent2])

        staticBody = CharacterPaths.isDynamic(design.bodyShape) ? nil : CharacterPaths.body(shape: design.bodyShape, wiggle: 0)
        moonCrescent = CharacterPaths.moonCrescent()
        domeGlass = CharacterPaths.domeGlass()
        robeStarField = CharacterPaths.robeStarField()
        robeOpening = CharacterPaths.robeOpening()
        robeFrontMask = CharacterPaths.robeFrontMask()
        let cap = CharacterPaths.capMask()
        capMask = cap
        capShadowNearPath = cap.applying(CGAffineTransform(translationX: 0, y: -0.035))
        capShadowFarPath = cap.applying(CGAffineTransform(translationX: 0, y: -0.07))
        haloCircle = CharacterPaths.circle(center: .zero, radius: 1.9)
        unitDisc = CharacterPaths.unitDisc()
    }

    /// True when these resources were built from `design`'s palette, silhouette and features.
    func matches(_ design: CharacterDesign) -> Bool {
        bodyShape == design.bodyShape && features == design.features && palette == design.palette
    }
}
