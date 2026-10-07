import SwiftUI
import CoreGraphics
import simd

/// Pure SwiftUI `Canvas` painter (CONTRACT §4.5). `draw` is a pure function of the pose and the design:
/// it keeps no state between frames, and all colours / gradients / static paths come from the
/// per-kind `CanvasResources` cache so nothing but `Path`s is allocated per frame.
enum CharacterPainter {

    /// Draws one frame. `size` is the Canvas size in points; the body radius and origin follow `CanonicalSpace`.
    @MainActor
    static func draw(pose: CharacterPose, design: CharacterDesign, in context: inout GraphicsContext,
                     size: CGSize, quality: CanvasQuality) {
        guard size.width >= 2, size.height >= 2 else { return }
        let resources = CharacterColors.resources(for: design)
        let scene = CanvasScene(pose: pose, design: design, size: size, quality: quality, resources: resources)
        scene.draw(in: &context)
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

        let unitPath = resources.staticBody ?? CharacterPaths.body(shape: design.bodyShape, wiggle: CGFloat(b.wiggle))

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
    func draw(in ctx: inout GraphicsContext) {
        drawGlow(in: &ctx)
        if features.contains(.dome) { drawDomeBase(in: &ctx) }
        if features.contains(.hood) { drawRobeBack(in: &ctx) }
        if features.contains(.legs) { drawLegs(in: &ctx) }
        if features.contains(.arms) { drawArms(in: &ctx) }
        drawBody(in: &ctx)
        if features.contains(.innerFlame) { drawInnerFlame(in: &ctx) }
        if features.contains(.darkFace) { drawDarkFace(in: &ctx) }
        if features.contains(.hood) { drawRobeFront(in: &ctx) }
        if features.contains(.leaves) { drawCapAndLeaves(in: &ctx) }
        if features.contains(.brain) { drawBrain(in: &ctx) }
        if features.contains(.moonMark) { drawMoonMark(in: &ctx) }
        if features.contains(.cloudCurl) { drawCloudCurl(in: &ctx) }
        drawFace(in: &ctx)
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
            // Blurred, slightly inflated copy of the silhouette; the blur gives the exp(−d/0.35) falloff.
            let inflated = bodyUnitPath.applying(CGAffineTransform(scaleX: 1.08, y: 1.08))
            let glowPath = body.path(inflated)
            let blur = radius * 0.22
            let color = res.glow
            let alpha = Double(glowAlpha)
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: blur))
                layer.opacity = alpha
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
        // Highlight ellipse at (−0.35, 0.45), radii (0.35, 0.22), tilted 30° so it follows the upper-left curvature.
        let highlight = body.path(CharacterPaths.ellipse(center: CGPoint(x: -0.35, y: 0.45), rx: 0.35, ry: 0.22, rotation: 0.5236))
        let silhouette = bodyPath
        let shading = bodyShading
        let highlightColor = res.highlightSoft
        let rimSoft = res.rimShadowSoft
        let rim = res.rimShadow
        let softWidth = body.length(0.30)
        let rimWidth = body.length(0.16)
        ctx.drawLayer { layer in
            layer.clip(to: silhouette)
            layer.fill(silhouette, with: shading)
            layer.fill(highlight, with: .color(highlightColor))
            // Rim darkening: strokes centred on the edge, clipped to the inside → 0.08 (and a softer 0.15) band.
            layer.stroke(silhouette, with: .color(rimSoft), lineWidth: softWidth)
            layer.stroke(silhouette, with: .color(rim), lineWidth: rimWidth)
        }
    }

    /// `.innerFlame`: lighter drop at scale 0.58, offset (0, −0.18), `palette.accent` α 0.85; `accessory2` swells it.
    func drawInnerFlame(in ctx: inout GraphicsContext) {
        let k: CGFloat = 0.58 * (1 + 0.10 * CGFloat(min(max(pose.body.accessory2, 0), 1)))
        let unit = CharacterPaths.dropBody(wiggle: wiggle + 0.9)
            .applying(CGAffineTransform(scaleX: k, y: k).concatenating(CGAffineTransform(translationX: 0, y: -0.18)))
        ctx.fill(body.path(unit), with: .color(res.innerFlame))
    }

    /// `.darkFace`: dark inner ellipse at (0, −0.08), radii (0.72, 0.80), `palette.accent`.
    func drawDarkFace(in ctx: inout GraphicsContext) {
        let unit = CharacterPaths.ellipse(center: CGPoint(x: 0, y: -0.08), rx: 0.72, ry: 0.80)
        ctx.fill(body.path(unit), with: .color(res.accent))
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
        ctx.fill(body.path(CharacterPaths.capsule(from: start, to: end, radius: 0.16)), with: bodyShading)
        ctx.fill(body.path(CharacterPaths.circle(center: end, radius: 0.19)), with: bodyShading)
        // Soft shadow where the arm meets the body (the body is drawn over the inner half).
        ctx.fill(body.path(CharacterPaths.circle(center: CGPoint(x: side * 0.95, y: -0.20), radius: 0.22)),
                 with: .color(res.shoulderShadow))
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
