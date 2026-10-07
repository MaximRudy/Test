import SwiftUI
import CoreGraphics
import simd

/// Pure SwiftUI `Canvas` painter (CONTRACT §4.5). `draw` is a pure function of the pose and the design:
/// it keeps no state between frames, and all colours / gradients / static paths come from the
/// per-kind `CanvasResources` cache so nothing but `Path`s is allocated per frame.
enum CharacterPainter {

    /// Draws one frame. `size` is the Canvas size in points; the body radius and origin follow `CanonicalSpace`.
    /// `@MainActor` because the per-kind resource cache is main-actor state (the Canvas closure that calls this
    /// already runs on the main actor, since it also calls `rig.pose(at:)`).
    @MainActor
    static func draw(pose: CharacterPose, design: CharacterDesign, in context: inout GraphicsContext,
                     size: CGSize, quality: CanvasQuality) {
        guard size.width >= 2, size.height >= 2 else { return }
        // A non-finite channel (NaN from a broken rig input) would trap in `Int(_:)` conversions further down;
        // fall back to the neutral pose for that frame instead.
        let safePose = isFinite(pose) ? pose : CharacterPose(time: pose.time.isFinite ? pose.time : 0)
        let resources = CharacterColors.resources(for: design)
        let scene = CanvasScene(pose: safePose, design: design, size: size, quality: quality, resources: resources)
        scene.draw(in: &context)
    }

    /// True when every pose channel (and the time) is finite.
    static func isFinite(_ pose: CharacterPose) -> Bool {
        let total = pose.face.v.sum() + pose.face.mouth.v.sum() + pose.body.v.sum() + pose.effects.v.sum() + pose.time
        return total.isFinite
    }
}

/// Unit-space (y up, body-radius units) → view-space (points, y down) mapping.
struct CanvasTransform {
    /// Full matrix: unit point → view point.
    let matrix: CGAffineTransform
    /// Approximate points-per-unit (geometric mean of the scale factors) for stroke widths and radii.
    let unitScale: CGFloat

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: y).applying(matrix)
    }

    func point(_ p: CGPoint) -> CGPoint {
        p.applying(matrix)
    }

    func length(_ l: CGFloat) -> CGFloat {
        l * unitScale
    }

    func path(_ p: Path) -> Path {
        p.applying(matrix)
    }

    /// A transform that first applies `unit` (in unit space) and then this mapping.
    func prepending(_ unit: CGAffineTransform) -> CanvasTransform {
        let det = abs(unit.a * unit.d - unit.b * unit.c)
        return CanvasTransform(matrix: unit.concatenating(matrix), unitScale: unitScale * sqrt(max(det, 1e-8)))
    }
}

/// Everything one frame needs, resolved once: transforms (§2), body silhouette (§3.5), cached resources.
/// Drawing is split across extensions: body (this file), face (`+Face`), accessories (`+Accessories`),
/// effects and sparkles (`+Effects`).
@MainActor
struct CanvasScene {
    let pose: CharacterPose
    let design: CharacterDesign
    let features: DesignFeatures
    let layout: FaceLayout
    let res: CanvasResources
    let quality: CanvasQuality

    /// Body radius R in points.
    let radius: CGFloat
    /// Static mapping (no body transform): sparkles, dome, floating glyphs.
    let base: CanvasTransform
    /// Body transform (§2): scale about the anchor → tilt about the anchor → offset.
    let body: CanvasTransform
    /// Head transform (§2): body transform plus head tilt about (0, faceOffsetY) and turn/nod shift.
    let head: CanvasTransform

    /// Silhouette in unit space (before the body transform) and in view space.
    let bodyUnitPath: Path
    let bodyPath: Path
    /// Vertical body gradient in view space (bodyTop at y = +1 → bodyBottom at y = −1).
    let bodyShading: GraphicsContext.Shading

    /// Pose time (seconds) as CGFloat for ambient motion.
    let time: CGFloat
    /// Wiggle phase (radians).
    let wiggle: CGFloat
    /// Face scale and vertical face offset.
    let s: CGFloat
    let oy: CGFloat
    /// `glowStrength · body.glow · 0.7`, clamped to 0...1.
    let glowAlpha: CGFloat

    init(pose: CharacterPose, design: CharacterDesign, size: CGSize, quality: CanvasQuality, resources: CanvasResources) {
        self.pose = pose
        self.design = design
        self.features = design.features
        self.layout = design.face
        self.res = resources
        self.quality = quality

        let r = CanonicalSpace.bodyRadius(in: size, design: design)
        let origin = CanonicalSpace.origin(in: size, design: design)
        // Scale R, flip y, translate to the origin.
        let view = CGAffineTransform(a: r, b: 0, c: 0, d: -r, tx: origin.x, ty: origin.y)
        let baseTransform = CanvasTransform(matrix: view, unitScale: r)

        let b = pose.body
        let breath = b.breathe * design.idle.breathDepth
        let sx = CGFloat(max(0.05, b.scaleX - 0.015 * breath))
        let sy = CGFloat(max(0.05, b.scaleY + 0.025 * breath))
        let anchorY: CGFloat = design.features.contains(.floats) ? 0 : -1
        var bodyUnit = CGAffineTransform(translationX: 0, y: -anchorY)
        bodyUnit = bodyUnit.concatenating(CGAffineTransform(scaleX: sx, y: sy))
        // Positive tilt leans towards the viewer's right; in y-up unit space that is a clockwise rotation.
        bodyUnit = bodyUnit.concatenating(CGAffineTransform(rotationAngle: CGFloat(-b.tilt)))
        bodyUnit = bodyUnit.concatenating(CGAffineTransform(translationX: CGFloat(b.offsetX), y: anchorY + CGFloat(b.offsetY)))
        let bodyTransform = baseTransform.prepending(bodyUnit)

        let f = pose.face
        let faceOffsetY = CGFloat(design.face.faceOffsetY)
        var headUnit = CGAffineTransform(translationX: 0, y: -faceOffsetY)
        headUnit = headUnit.concatenating(CGAffineTransform(rotationAngle: CGFloat(-f.headTilt)))
        headUnit = headUnit.concatenating(CGAffineTransform(translationX: CGFloat(0.10 * f.headTurn),
                                                             y: faceOffsetY + CGFloat(0.06 * f.headNod)))
        let headTransform = bodyTransform.prepending(headUnit)

        // `.flicker` flames ripple with 0.012·sin(time·(8 + 6·flickerRate) + 7y) (same term as the MSL `sdFlame`).
        let flicker: CGFloat = design.features.contains(.flicker) ? 0.012 : 0
        let flickerPhase = CGFloat(pose.time) * (8 + 6 * CGFloat(design.idle.flickerRate))
        let unitPath = resources.staticBody ?? CharacterPaths.body(shape: design.bodyShape, wiggle: CGFloat(b.wiggle),
                                                                   flickerPhase: flickerPhase, flicker: flicker)

        radius = r
        base = baseTransform
        body = bodyTransform
        head = headTransform
        time = CGFloat(pose.time)
        wiggle = CGFloat(b.wiggle)
        s = CGFloat(design.face.faceScale)
        oy = faceOffsetY
        glowAlpha = CGFloat(min(max(design.glowStrength * b.glow * 0.7, 0), 1))
        bodyUnitPath = unitPath
        bodyPath = unitPath.applying(bodyTransform.matrix)
        bodyShading = .linearGradient(resources.bodyGradient,
                                      startPoint: bodyTransform.point(0, 1),
                                      endPoint: bodyTransform.point(0, -1))
    }

    // MARK: - Frame

    /// Draw order (back → front): glow, dome base, robe back, legs, arms, body (+ inner flame, dark face),
    /// robe front, cap & leaves, brain, moon, cloud curl, face, book & wand, effects, sparkles, dome glass.
    ///
    /// With `.hood` the body layers are drawn through a context clipped to the robe's face opening (§3.6: the body
    /// shows only through the opening, so the star tips sit inside the hood). The face is clipped like the MSL
    /// `faceClip`: to the silhouette, and for hoods also to the opening minus the robe front.
    func draw(in ctx: inout GraphicsContext) {
        let hood = features.contains(.hood)
        drawGlow(in: &ctx)
        if features.contains(.dome) { drawDomeBase(in: &ctx) }
        if hood { drawRobeBack(in: &ctx) }
        if features.contains(.legs) { drawLegs(in: &ctx) }
        if features.contains(.arms) { drawArms(in: &ctx) }
        var inner = ctx
        if hood { inner.clip(to: body.path(res.robeOpening)) }
        drawBody(in: &inner)
        if features.contains(.innerFlame) { drawInnerFlame(in: &inner) }
        if features.contains(.darkFace) { drawDarkFace(in: &inner) }
        if hood { drawRobeFront(in: &ctx) }
        if features.contains(.leaves) { drawCapAndLeaves(in: &ctx) }
        if features.contains(.brain) { drawBrain(in: &ctx) }
        if features.contains(.moonMark) { drawMoonMark(in: &ctx) }
        if features.contains(.cloudCurl) { drawCloudCurl(in: &ctx) }
        var face = inner
        face.clip(to: bodyPath)
        if hood { face.clip(to: body.path(res.robeFrontMask), options: .inverse) }
        drawFace(in: &face)
        if features.contains(.bookAndWand) { drawBookAndWand(in: &ctx) }
        drawEffects(in: &ctx)
        if features.contains(.dome) {
            drawSparkles(in: &ctx, clip: base.path(res.domeGlass))
            drawDomeGlass(in: &ctx)
        } else {
            drawSparkles(in: &ctx, clip: nil)
        }
    }

    // MARK: - Glow (§3.5)

    func drawGlow(in ctx: inout GraphicsContext) {
        guard glowAlpha > 0.01 else { return }
        switch quality {
        case .high:
            // One blurred group: the silhouette (α 1) plus a 0.30-wide outer band (α 0.35), blurred by 0.30 R.
            // Relative to the edge value this gives ≈ 0.37 at d = 0.35 and ≈ 0.06 at d = 0.70, close to
            // exp(−d/0.35) (0.37 / 0.135); the group opacity is boosted so the edge reaches `glowAlpha`.
            // The filter is set on a context copy and the shapes are grouped in one layer, so a single blur runs.
            let glowPath = bodyPath
            let bandWidth = body.length(0.60)
            let color = res.glow
            let bandColor = res.glowBand
            var glowCtx = ctx
            glowCtx.addFilter(.blur(radius: radius * 0.30))
            glowCtx.opacity = Double(min(1, glowAlpha * 1.6))
            glowCtx.drawLayer { layer in
                layer.stroke(glowPath, with: .color(bandColor), lineWidth: bandWidth)
                layer.fill(glowPath, with: .color(color))
            }
        case .balanced:
            let saved = ctx.opacity
            ctx.opacity = Double(glowAlpha)
            ctx.fill(body.path(res.haloCircle),
                     with: .radialGradient(res.glowHaloGradient, center: body.point(0, 0),
                                           startRadius: 0, endRadius: body.length(1.9)))
            ctx.opacity = saved
        }
    }

    // MARK: - Body (§3.5)

    func drawBody(in ctx: inout GraphicsContext) {
        var c = ctx
        c.clip(to: bodyPath)
        c.fill(bodyPath, with: bodyShading)

        // Soft highlight ellipse at (−0.35, 0.45), radii (0.35, 0.22), rotated −30° (§3.5): a unit disc mapped onto
        // the ellipse and filled with a radial gradient, α (1 − smoothstep(0.35, 1, ρ))·0.35 as in the MSL.
        let toEllipse = CGAffineTransform(scaleX: 0.35, y: 0.22)
            .concatenating(CGAffineTransform(rotationAngle: -0.5236))
            .concatenating(CGAffineTransform(translationX: -0.35, y: 0.45))
            .concatenating(body.matrix)
        var h = c
        h.concatenate(toEllipse)
        h.fill(res.unitDisc, with: .radialGradient(res.highlightGradient, center: .zero, startRadius: 0, endRadius: 1))

        // Rim darkening towards `palette.shadow` with α 0.35·rim², rim = (d + 0.08)/0.08 (§3.5): four nested strokes
        // centred on the edge (clipped to the inside, so each covers half its width) build the quadratic ramp —
        // ≈ 0.30 within 0.012 of the edge, 0.19 by 0.03, 0.07 by 0.055, 0.02 by 0.08.
        c.stroke(bodyPath, with: .color(res.rimBand1), lineWidth: body.length(0.160))
        c.stroke(bodyPath, with: .color(res.rimBand2), lineWidth: body.length(0.110))
        c.stroke(bodyPath, with: .color(res.rimBand3), lineWidth: body.length(0.060))
        c.stroke(bodyPath, with: .color(res.rimBand4), lineWidth: body.length(0.024))
    }

    /// `.innerFlame`: lighter drop at scale 0.58, offset (0, −0.18), α 0.85 (`palette.accent`, or `palette.highlight`
    /// for `.dome` designs — see `CanvasResources.innerFlame`); `accessory2` swells it.
    func drawInnerFlame(in ctx: inout GraphicsContext) {
        let k: CGFloat = 0.58 * (1 + 0.10 * CGFloat(min(max(pose.body.accessory2, 0), 1)))
        let unit = CharacterPaths.dropBody(wiggle: wiggle + 0.9)
            .applying(CGAffineTransform(scaleX: k, y: k).concatenating(CGAffineTransform(translationX: 0, y: -0.18)))
        ctx.fill(body.path(unit), with: .color(res.innerFlame))
    }

    /// `.darkFace`: dark inner ellipse at (0, −0.08), radii (0.72, 0.80), `palette.accent`, with the same soft
    /// lighter centre as the MSL (accent × 1.8 fading to accent at the rim).
    func drawDarkFace(in ctx: inout GraphicsContext) {
        let toEllipse = CGAffineTransform(scaleX: 0.72, y: 0.80)
            .concatenating(CGAffineTransform(translationX: 0, y: -0.08))
            .concatenating(body.matrix)
        var c = ctx
        c.concatenate(toEllipse)
        c.fill(res.unitDisc, with: .radialGradient(res.darkFaceGradient, center: .zero, startRadius: 0, endRadius: 1))
    }

    // MARK: - Limbs (§3.6)

    /// `.arms`: capsules from (±0.92, −0.20) to (±1.32, −0.20 + 0.90·arm), r 0.16, hands r 0.19, shoulder shadows.
    func drawArms(in ctx: inout GraphicsContext) {
        drawArm(side: -1, raise: CGFloat(pose.body.armL), in: &ctx)
        drawArm(side: 1, raise: CGFloat(pose.body.armR), in: &ctx)
    }

    private func drawArm(side: CGFloat, raise: CGFloat, in ctx: inout GraphicsContext) {
        let start = CGPoint(x: side * 0.92, y: -0.20)
        let end = CGPoint(x: side * 1.32, y: -0.20 + 0.90 * raise)
        let arm = body.path(CharacterPaths.capsule(from: start, to: end, radius: 0.16))
        ctx.fill(arm, with: bodyShading)
        ctx.fill(body.path(CharacterPaths.circle(center: end, radius: 0.19)), with: bodyShading)
        // Soft contact shadow where the arm meets the body: a radial fade (α 0.28 → 0 over r 0.22) kept inside the
        // arm, so nothing spills onto the background; the body is drawn over its inner half.
        let shoulder = CGPoint(x: side * 0.95, y: -0.20)
        var shade = ctx
        shade.clip(to: arm)
        shade.fill(body.path(CharacterPaths.circle(center: shoulder, radius: 0.22)),
                   with: .radialGradient(res.shoulderShadowGradient, center: body.point(shoulder),
                                         startRadius: 0, endRadius: body.length(0.22)))
    }

    /// `.legs`: rounded boxes 0.26 × 0.30 at (±0.36, −1.12 + 0.25·leg), corner 0.1, bodyBottom darkened 15 %.
    func drawLegs(in ctx: inout GraphicsContext) {
        let left = CharacterPaths.roundedBox(center: CGPoint(x: -0.36, y: -1.12 + 0.25 * CGFloat(pose.body.legL)),
                                             width: 0.26, height: 0.30, corner: 0.1)
        let right = CharacterPaths.roundedBox(center: CGPoint(x: 0.36, y: -1.12 + 0.25 * CGFloat(pose.body.legR)),
                                              width: 0.26, height: 0.30, corner: 0.1)
        ctx.fill(body.path(left), with: .color(res.legColor))
        ctx.fill(body.path(right), with: .color(res.legColor))
    }
}
