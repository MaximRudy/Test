import SwiftUI
import CoreGraphics

/// Accessories (CONTRACT §3.6): robe, book & wand, brain, moon mark, dome, cap & leaves, cloud curl.
extension CanvasScene {

    private func clamp01(_ x: Float) -> CGFloat {
        CGFloat(min(max(x, 0), 1))
    }

    // MARK: - Robe / hood (Lumi)

    /// Robe behind the body: teardrop r 1.28 at (0, −0.25) with the peak at (0.08·sin(wiggle), 1.38). The face
    /// opening (ellipse (0, 0.05), radii (0.80, 0.84)) shows the hood interior — the robe colour at 45 %, as the MSL
    /// `robeColor(…, interior)` — and the body is drawn on top of it through a clip to the opening (see `draw(in:)`).
    /// `.starPattern` sprinkles the static grid star field on the robe outside the opening (MSL: `robeCov·(1 − opening)`).
    func drawRobeBack(in ctx: inout GraphicsContext) {
        let robePath = body.path(CharacterPaths.robe(peakX: 0.08 * sin(wiggle)))
        let openingPath = body.path(res.robeOpening)
        ctx.fill(robePath, with: robeShading)
        ctx.fill(openingPath, with: robeInteriorShading)
        if features.contains(.starPattern) {
            var stars = ctx
            stars.clip(to: robePath)
            stars.clip(to: openingPath, options: .inverse)
            stars.fill(body.path(res.robeStarField), with: .color(res.robeStar))
        }
    }

    /// Robe front (collar below y = −0.55 + 0.05·x²) drawn over the body so the star peeks out of the opening; the
    /// star field continues on it (MSL: `robeStars·front`).
    func drawRobeFront(in ctx: inout GraphicsContext) {
        let robePath = body.path(CharacterPaths.robe(peakX: 0.08 * sin(wiggle)))
        var c = ctx
        c.clip(to: body.path(res.robeFrontMask))
        c.fill(robePath, with: robeShading)
        if features.contains(.starPattern) {
            var stars = c
            stars.clip(to: robePath)
            stars.fill(body.path(res.robeStarField), with: .color(res.robeStar))
        }
        // Thin trim along the robe edge for definition.
        c.stroke(robePath, with: .color(res.accent2Dark), lineWidth: body.length(0.03))
    }

    private var robeShading: GraphicsContext.Shading {
        .linearGradient(res.robeGradient, startPoint: body.point(0, 1.38), endPoint: body.point(0, -1.55))
    }

    private var robeInteriorShading: GraphicsContext.Shading {
        .linearGradient(res.robeInteriorGradient, startPoint: body.point(0, 1.38), endPoint: body.point(0, -1.55))
    }

    // MARK: - Book & wand (Lumi)

    func drawBookAndWand(in ctx: inout GraphicsContext) {
        let accessory = clamp01(pose.body.accessory)
        let accessory2 = clamp01(pose.body.accessory2)

        // Book: rounded rect 0.50 × 0.38, corner 0.06, at (−0.98, −0.45) rotated 15°.
        let bookT = CharacterPaths.placement(x: -0.98, y: -0.45, rotation: 0.2618)
        let cover = CharacterPaths.roundedBox(center: .zero, width: 0.50, height: 0.38, corner: 0.06).applying(bookT)
        let pageEdge = CharacterPaths.roundedBox(center: CGPoint(x: 0.215, y: 0.0), width: 0.05, height: 0.32, corner: 0.015).applying(bookT)
        let starCenterUnit = CGPoint(x: -0.04, y: 0.02).applying(bookT)
        let coverStar = CharacterPaths.star4(center: starCenterUnit, radius: 0.09, inner: 0.4)
        let coverGlow = CharacterPaths.circle(center: starCenterUnit, radius: 0.24)
        ctx.fill(body.path(cover), with: .color(res.accent2))
        ctx.fill(body.path(pageEdge), with: .color(res.teeth))
        let saved = ctx.opacity
        ctx.opacity = Double(0.5 + 0.5 * accessory)
        ctx.fill(body.path(coverGlow), with: .radialGradient(res.softGlowGradient, center: body.point(starCenterUnit),
                                                             startRadius: 0, endRadius: body.length(0.24)))
        ctx.fill(body.path(coverStar), with: .color(res.highlight))
        ctx.opacity = saved

        // Wand: capsule (0.85, −0.30) → (1.25, 0.35), r 0.05, with a 4-point star at the tip; glow α = accessory2.
        let wand = CharacterPaths.capsule(from: CGPoint(x: 0.85, y: -0.30), to: CGPoint(x: 1.25, y: 0.35), radius: 0.05)
        ctx.fill(body.path(wand), with: .color(res.wandColor))
        let tip = CGPoint(x: 1.28, y: 0.40)
        if accessory2 > 0.02 {
            ctx.opacity = Double(accessory2)
            ctx.fill(body.path(CharacterPaths.circle(center: tip, radius: 0.28)),
                     with: .radialGradient(res.softGlowGradient, center: body.point(tip), startRadius: 0, endRadius: body.length(0.28)))
            ctx.opacity = saved
        }
        ctx.fill(body.path(CharacterPaths.star4(center: tip, radius: 0.11 + 0.03 * accessory2, inner: 0.38)), with: .color(res.highlight))
    }

    // MARK: - Brain (Spark)

    /// Six-circle brain around (0, 0.62), radius 0.30·k with k = 1 + 0.08·accessory, pulsing accent2 halo — shaded like
    /// the MSL `drawBrain`: a vertical shade towards accent2 (brain-frame y: accent at +0.18·k → 40 % accent2 at
    /// −0.42·k), the accent2 grooves clipped to the brain, then rim darkening towards accent2·0.8 within 0.04 of the
    /// edge (two bands bounded by the inset brain paths).
    func drawBrain(in ctx: inout GraphicsContext) {
        let accessory = clamp01(pose.body.accessory)
        let k: CGFloat = 1 + 0.08 * accessory
        let r: CGFloat = 0.30 * k
        let c = CGPoint(x: 0, y: 0.62)
        if accessory > 0.02 {
            let saved = ctx.opacity
            ctx.opacity = Double(accessory * 0.6)
            ctx.fill(body.path(CharacterPaths.circle(center: c, radius: r * 1.7)),
                     with: .radialGradient(res.accent2GlowGradient, center: body.point(c), startRadius: 0, endRadius: body.length(r * 1.7)))
            ctx.opacity = saved
        }
        let brainPath = body.path(CharacterPaths.brain(center: c, radius: r))
        ctx.fill(brainPath, with: .linearGradient(res.brainGradient,
                                                  startPoint: body.point(c.x, c.y + 0.18 * k),
                                                  endPoint: body.point(c.x, c.y - 0.42 * k)))
        var inside = ctx
        inside.clip(to: brainPath)
        inside.stroke(body.path(CharacterPaths.brainGrooves(center: c, radius: r)), with: .color(res.accent2),
                      style: StrokeStyle(lineWidth: body.length(0.025), lineCap: .round, lineJoin: .round))
        var rimOuter = inside
        rimOuter.clip(to: body.path(CharacterPaths.brain(center: c, radius: r, inset: 0.04)), options: .inverse)
        rimOuter.fill(brainPath, with: .color(res.brainRimOuter))
        var rimInner = inside
        rimInner.clip(to: body.path(CharacterPaths.brain(center: c, radius: r, inset: 0.015)), options: .inverse)
        rimInner.fill(brainPath, with: .color(res.brainRimInner))
    }

    // MARK: - Moon mark (Nox)

    func drawMoonMark(in ctx: inout GraphicsContext) {
        let accessory = clamp01(pose.body.accessory)
        let c = CGPoint(x: -0.03, y: 0.56)
        let saved = ctx.opacity
        ctx.opacity = Double((0.4 + 0.6 * accessory) * 0.8)
        ctx.fill(body.path(CharacterPaths.circle(center: c, radius: 0.40)),
                 with: .radialGradient(res.accent2GlowGradient, center: body.point(c), startRadius: 0, endRadius: body.length(0.40)))
        ctx.opacity = saved
        ctx.fill(body.path(res.moonCrescent), with: .color(res.accent2))
    }

    // MARK: - Dome (Lumie)

    /// Wooden base: rounded box 3.40 × 0.50 at y = −1.55 with a darker nameplate 1.10 × 0.22. Static space.
    func drawDomeBase(in ctx: inout GraphicsContext) {
        let basePath = base.path(CharacterPaths.roundedBox(center: CGPoint(x: 0, y: -1.55), width: 3.40, height: 0.50, corner: 0.12))
        ctx.fill(basePath, with: .linearGradient(res.baseGradient, startPoint: base.point(0, -1.30), endPoint: base.point(0, -1.80)))
        let plate = base.path(CharacterPaths.roundedBox(center: CGPoint(x: 0, y: -1.55), width: 1.10, height: 0.22, corner: 0.05))
        ctx.fill(plate, with: .color(res.accentDark))
    }

    /// Glass bell: fill accent2 α 0.10, rim α 0.35 width 0.03, specular streak, bottom reflection; `accessory` shimmers.
    func drawDomeGlass(in ctx: inout GraphicsContext) {
        let glass = base.path(res.domeGlass)
        ctx.fill(glass, with: .color(res.glassFill))
        ctx.stroke(glass, with: .color(res.glassRim), lineWidth: base.length(0.03))
        let streak = CharacterPaths.capsule(from: CGPoint(x: -1.12, y: 0.50), to: CGPoint(x: -0.70, y: 1.20), radius: 0.045)
        ctx.fill(base.path(streak), with: .color(res.specular))
        let reflection = CharacterPaths.ellipse(center: CGPoint(x: 0, y: -1.20), rx: 1.15, ry: 0.06)
        ctx.fill(base.path(reflection), with: .color(res.reflection))
        let accessory = clamp01(pose.body.accessory)
        if accessory > 0.02 {
            let saved = ctx.opacity
            ctx.opacity = Double(accessory * 0.5)
            let shimmer = CharacterPaths.capsule(from: CGPoint(x: 1.05, y: 0.20), to: CGPoint(x: 0.85, y: 0.95), radius: 0.03)
            ctx.fill(base.path(shimmer), with: .color(res.specular))
            ctx.opacity = saved
        }
    }

    // MARK: - Cap & leaves (Sprout)

    func drawCapAndLeaves(in ctx: inout GraphicsContext) {
        let accessory = clamp01(pose.body.accessory)
        let capPath = body.path(res.capMask)
        var c = ctx
        c.clip(to: bodyPath)
        // Faint shadow under the scalloped edge (MSL: shadow α 0.25 fading over 0.07): two stacked fills of the
        // cap shape shifted down 0.07 (α 0.06) and 0.035 (α 0.15), ≈ 0.20 right under the edge.
        c.fill(body.path(res.capShadowFarPath), with: .color(res.capShadowFar))
        c.fill(body.path(res.capShadowNearPath), with: .color(res.capShadowNear))
        c.fill(capPath, with: .color(res.accent))
        c.stroke(capPath, with: .color(res.accentDark), lineWidth: body.length(0.03))
        // Stem.
        ctx.fill(body.path(CharacterPaths.capsule(from: CGPoint(x: 0, y: 0.90), to: CGPoint(x: 0.03, y: 1.10), radius: 0.035)),
                 with: .color(res.accentDark))
        // Leaves: ellipses 0.30 × 0.14 at (−0.25, 1.05) rotated −35° and (0.30, 1.08) rotated +40°, wiggle ±8° with accessory.
        let wiggleAngle = 0.1396 * sin(time * 2.5) * accessory
        let angleL = -0.6109 + wiggleAngle
        let angleR = 0.6981 - wiggleAngle
        let cL = CGPoint(x: -0.25, y: 1.05)
        let cR = CGPoint(x: 0.30, y: 1.08)
        ctx.fill(body.path(CharacterPaths.ellipse(center: cL, rx: 0.15, ry: 0.07, rotation: angleL)), with: .color(res.accent2))
        ctx.fill(body.path(CharacterPaths.ellipse(center: cR, rx: 0.15, ry: 0.07, rotation: angleR)), with: .color(res.accent2))
        var veins = Path()
        veins.move(to: CGPoint(x: cL.x - 0.12 * cos(angleL), y: cL.y - 0.12 * sin(angleL)))
        veins.addLine(to: CGPoint(x: cL.x + 0.12 * cos(angleL), y: cL.y + 0.12 * sin(angleL)))
        veins.move(to: CGPoint(x: cR.x - 0.12 * cos(angleR), y: cR.y - 0.12 * sin(angleR)))
        veins.addLine(to: CGPoint(x: cR.x + 0.12 * cos(angleR), y: cR.y + 0.12 * sin(angleR)))
        ctx.stroke(body.path(veins), with: .color(res.accentDark),
                   style: StrokeStyle(lineWidth: body.length(0.012), lineCap: .round))
    }

    // MARK: - Cloud curl (Puff)

    /// Thick spiral stroke (1.25 turns) at (−0.45, 0.75), width 0.14, body colour; bounces with `accessory2`.
    func drawCloudCurl(in ctx: inout GraphicsContext) {
        let bounce = 0.06 * sin(time * 4) * clamp01(pose.body.accessory2)
        let c = CGPoint(x: -0.45, y: 0.75 + bounce)
        let spiral = body.path(CharacterPaths.spiral(center: c, startRadius: 0.30, endRadius: 0.05, turns: 1.25,
                                                     startAngle: CGFloat.pi * 0.9))
        ctx.stroke(spiral, with: .color(res.rimShadowSoft),
                   style: StrokeStyle(lineWidth: body.length(0.18), lineCap: .round, lineJoin: .round))
        ctx.stroke(spiral, with: bodyShading,
                   style: StrokeStyle(lineWidth: body.length(0.14), lineCap: .round, lineJoin: .round))
    }
}
