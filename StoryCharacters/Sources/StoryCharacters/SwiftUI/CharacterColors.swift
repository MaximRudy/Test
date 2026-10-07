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

    static let white = SIMD4<Float>(1, 1, 1, 1)
    static let tear = SIMD4<Float>(0.6, 0.8, 1.0, 1.0)

    // MARK: - Cache

    @MainActor private static var cache: [CharacterKind: CanvasResources] = [:]

    /// Cached colours, gradients and static unit paths for a design. One instance per `CharacterKind`
    /// (the catalog's designs are static, so the kind identifies the palette and the static geometry).
    @MainActor
    static func resources(for design: CharacterDesign) -> CanvasResources {
        if let cached = cache[design.kind] {
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
    let highlightSoft: Color      // highlight α 0.35
    let rimShadow: Color          // shadow α 0.35
    let rimShadowSoft: Color      // shadow α 0.12
    let limbalRing: Color         // pupil α 0.35
    let browColor: Color          // outline α 0.9
    let lipLine: Color            // outline α 0.35
    let lidShadow: Color          // outline α 0.18
    let legColor: Color           // bodyBottom darkened 15 %
    let shoulderShadow: Color     // shadow α 0.25
    let robeStar: Color           // accent2 α 0.7
    let accentDark: Color         // accent darkened 30 %
    let accent2Dark: Color        // accent2 darkened 35 %
    let glassFill: Color          // accent2 α 0.10
    let glassRim: Color           // accent2 α 0.35
    let specular: Color           // white α 0.35
    let reflection: Color         // white α 0.15
    let innerFlame: Color         // accent α 0.85
    let tearColor: Color          // (0.6, 0.8, 1.0)
    let sparkle: Color            // mix(glow, white, 0.5)
    let wandColor: Color          // shadow
    let glyph: Color              // white
    let glyphShadow: Color        // outline α 0.6

    // Gradients.
    let bodyGradient: Gradient         // bodyTop (y = +1) → bodyBottom (y = −1)
    let robeGradient: Gradient         // accent → accent darkened 25 %
    let irisGradient: Gradient         // iris → 35 % darker at the rim
    let irisHaloGradient: Gradient     // iris α 0.6 → 0
    let glowHaloGradient: Gradient     // glow, exp(−d/0.35) outside the unit circle, for a circle of radius 1.9
    let softGlowGradient: Gradient     // glow α 1 → 0 (accessory glows, burst)
    let accent2GlowGradient: Gradient  // accent2 α 1 → 0 (moon / wand)
    let cheekGradient: Gradient        // cheek α 1 with Gaussian falloff → 0
    let lidShadowGradient: Gradient    // outline α 0.18 → 0
    let baseGradient: Gradient         // accent → accent darkened 35 % (dome base)

    // Static unit-space paths.
    let staticBody: Path?
    let moonCrescent: Path
    let domeGlass: Path
    let robeStarField: Path
    let robeOpening: Path
    let robeFrontMask: Path
    let capMask: Path
    let haloCircle: Path               // circle r 1.9 at the origin

    init(design: CharacterDesign) {
        let p = design.palette
        kind = design.kind

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
        highlightSoft = CharacterColors.color(p.highlight, alpha: 0.35)
        rimShadow = CharacterColors.color(p.shadow, alpha: 0.35)
        rimShadowSoft = CharacterColors.color(p.shadow, alpha: 0.12)
        limbalRing = CharacterColors.color(p.pupil, alpha: 0.35)
        browColor = CharacterColors.color(p.outline, alpha: 0.9)
        lipLine = CharacterColors.color(p.outline, alpha: 0.35)
        lidShadow = CharacterColors.color(p.outline, alpha: 0.18)
        legColor = CharacterColors.color(CharacterColors.darkened(p.bodyBottom, by: 0.15))
        shoulderShadow = CharacterColors.color(p.shadow, alpha: 0.25)
        robeStar = CharacterColors.color(p.accent2, alpha: 0.7)
        accentDark = CharacterColors.color(CharacterColors.darkened(p.accent, by: 0.30))
        accent2Dark = CharacterColors.color(CharacterColors.darkened(p.accent2, by: 0.35))
        glassFill = CharacterColors.color(p.accent2, alpha: 0.10)
        glassRim = CharacterColors.color(p.accent2, alpha: 0.35)
        specular = CharacterColors.color(CharacterColors.white, alpha: 0.35)
        reflection = CharacterColors.color(CharacterColors.white, alpha: 0.15)
        innerFlame = CharacterColors.color(p.accent, alpha: 0.85)
        tearColor = CharacterColors.color(CharacterColors.tear)
        sparkle = CharacterColors.color(CharacterColors.mix(p.glow, CharacterColors.white, 0.5))
        wandColor = CharacterColors.color(p.shadow)
        glyph = CharacterColors.color(CharacterColors.white)
        glyphShadow = CharacterColors.color(p.outline, alpha: 0.6)

        bodyGradient = Gradient(colors: [bodyTop, bodyBottom])
        robeGradient = Gradient(colors: [accent, CharacterColors.color(CharacterColors.darkened(p.accent, by: 0.25))])
        irisGradient = Gradient(stops: [
            Gradient.Stop(color: iris, location: 0),
            Gradient.Stop(color: iris, location: 0.45),
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

        staticBody = CharacterPaths.isDynamic(design.bodyShape) ? nil : CharacterPaths.body(shape: design.bodyShape, wiggle: 0)
        moonCrescent = CharacterPaths.moonCrescent()
        domeGlass = CharacterPaths.domeGlass()
        robeStarField = CharacterPaths.robeStarField()
        robeOpening = CharacterPaths.robeOpening()
        robeFrontMask = CharacterPaths.robeFrontMask()
        capMask = CharacterPaths.capMask()
        haloCircle = CharacterPaths.circle(center: .zero, radius: 1.9)
    }
}
