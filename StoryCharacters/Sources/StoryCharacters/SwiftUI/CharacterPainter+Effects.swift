import SwiftUI
import CoreGraphics

/// Comic effects (CONTRACT §3.7) and the sparkle field (§3.8).
extension CanvasScene {

    // MARK: - Effects (§3.7)

    func drawEffects(in ctx: inout GraphicsContext) {
        let e = pose.effects
        if e.tears > 0.01 { drawTears(alpha: e.tears, in: &ctx) }
        if e.sweat > 0.01 { drawSweat(alpha: e.sweat, in: &ctx) }
        if e.hearts > 0.01 { drawHearts(alpha: e.hearts, in: &ctx) }
        if e.zzz > 0.01 { drawZzz(alpha: e.zzz, in: &ctx) }
        if e.question > 0.01 { drawGlyph("?", alpha: e.question, in: &ctx) }
        if e.exclamation > 0.01 { drawGlyph("!", alpha: e.exclamation, in: &ctx) }
    }

    /// Two teardrops r 0.07 under the eyes sliding down 0.15·fract(time·0.8).
    private func drawTears(alpha: Float, in ctx: inout GraphicsContext) {
        let x = (CGFloat(layout.eyeOffsetX) + 0.05) * s
        let slide = 0.15 * CharacterPaths.fract(time * 0.8)
        let y = oy + CGFloat(layout.eyeY) * s - 0.35 - slide
        var drops = CharacterPaths.smallDrop(center: CGPoint(x: -x, y: y), radius: 0.07)
        drops.addPath(CharacterPaths.smallDrop(center: CGPoint(x: x, y: y), radius: 0.07))
        let saved = ctx.opacity
        ctx.opacity = Double(min(alpha, 1))
        ctx.fill(head.path(drops), with: .color(res.tearColor))
        ctx.opacity = saved
    }

    /// Single sweat drop at (+0.75, +0.55).
    private func drawSweat(alpha: Float, in ctx: inout GraphicsContext) {
        let slide = 0.10 * CharacterPaths.fract(time * 0.9)
        let drop = CharacterPaths.smallDrop(center: CGPoint(x: 0.75, y: 0.55 - slide), radius: 0.07)
        let saved = ctx.opacity
        ctx.opacity = Double(min(alpha, 1))
        ctx.fill(head.path(drop), with: .color(res.tearColor))
        ctx.opacity = saved
    }

    /// Three small hearts rising from (±0.9, 0.9), α = hearts · sin(πt).
    private func drawHearts(alpha: Float, in ctx: inout GraphicsContext) {
        let saved = ctx.opacity
        for i in 0..<3 {
            let k = CGFloat(i)
            let t = CharacterPaths.fract(time * 0.55 + k / 3)
            let side: CGFloat = i % 2 == 0 ? 1 : -1
            let x = side * (0.9 + 0.08 * sin(time * 2 + k))
            let y = 0.9 + 0.75 * t
            let a = Double(alpha) * Double(sin(CGFloat.pi * t))
            guard a > 0.01 else { continue }
            let size: CGFloat = 0.10 + 0.03 * k
            ctx.opacity = min(a, 1)
            ctx.fill(base.path(CharacterPaths.heart(center: CGPoint(x: x, y: y), size: size)), with: .color(res.tongue))
        }
        ctx.opacity = saved
    }

    /// Three "z" glyphs drifting to the upper right.
    private func drawZzz(alpha: Float, in ctx: inout GraphicsContext) {
        for i in 0..<3 {
            let k = CGFloat(i)
            let t = CharacterPaths.fract(time * 0.45 + k / 3)
            let p = base.point(0.70 + 0.22 * k + 0.25 * t, 1.25 + 0.30 * k + 0.45 * t)
            let size = radius * (0.20 + 0.07 * k) * (0.8 + 0.4 * t)
            let a = Double(alpha) * Double(sin(CGFloat.pi * t))
            drawText("z", at: p, size: size, alpha: a, in: &ctx)
        }
    }

    /// "?" / "!" above the head at (0.75, 1.35).
    private func drawGlyph(_ glyph: String, alpha: Float, in ctx: inout GraphicsContext) {
        let bob = 0.03 * sin(time * 3)
        let p = base.point(0.75, 1.35 + bob)
        drawText(glyph, at: p, size: radius * 0.55, alpha: Double(alpha), in: &ctx)
    }

    /// Point size the glyphs are resolved at; they are scaled to the requested size through the context transform,
    /// so the font never changes from frame to frame (a continuously changing size would rebuild fonts every frame).
    static let glyphFontSize: CGFloat = 48
    static let glyphFont = Font.system(size: 48, weight: .heavy, design: .rounded)

    private func drawText(_ string: String, at p: CGPoint, size: CGFloat, alpha: Double, in ctx: inout GraphicsContext) {
        guard alpha > 0.01, size > 1 else { return }
        // Resolved once without a foreground style; the shadow and the glyph are drawn by switching `shading`.
        var resolved = ctx.resolve(Text(verbatim: string).font(CanvasScene.glyphFont))
        let k = size / CanvasScene.glyphFontSize
        var c = ctx
        c.opacity = min(alpha, 1)
        c.translateBy(x: p.x, y: p.y)
        c.scaleBy(x: k, y: k)
        let offset = CanvasScene.glyphFontSize * 0.05
        resolved.shading = .color(res.glyphShadow)
        c.draw(resolved, at: CGPoint(x: offset, y: offset), anchor: .center)
        resolved.shading = .color(res.glyph)
        c.draw(resolved, at: .zero, anchor: .center)
    }

    // MARK: - Sparkle field (§3.8)

    /// 40 ambient sparkles (+20 burst slots), 4-point stars. For `.dome` designs the first `round(20·accessory)`
    /// burst slots become extra ambient fireflies (seeds 40…), exactly like the Metal `sparkleVertex`; only the
    /// remaining slots draw burst particles.
    /// Alpha is quantised into eight bins drawn at their mid value (error ≤ ±1/16 around `sin(πt)·rate`), so the
    /// whole field costs at most eight fills. Sparkles blend additively (`.plusLighter`: premultiplied
    /// `colour·α` is added to the destination), matching §3.8 and the Metal sparkle pipeline (source/destination
    /// RGB factors `.one`), through a clipped context copy — no offscreen layer. The star's waist (inner radius
    /// 0.36) is wider than the Metal star's, which stands in for the Metal fragment's soft core glow: along the
    /// diagonals the Canvas edge sits at 0.36·size, the Metal star+core half-coverage contour at ≈ 0.3·size.
    func drawSparkles(in ctx: inout GraphicsContext, clip: Path?) {
        let rate = min(max(pose.effects.sparkleRate, 0), 1)
        let burst = min(max(pose.effects.sparkleBurst, 0), 1)
        let accessory = pose.body.accessory
        let boost = features.contains(.dome) && accessory.isFinite ? Int((min(max(accessory, 0), 1) * 20).rounded()) : 0
        guard rate > 0.01 || burst > 0.01 else { return }

        var bins = SparkleBins()
        let t = pose.time

        func fract(_ x: Float) -> Float { x - x.rounded(.down) }

        func emit(_ x: Float, _ y: Float, _ size: Float, _ alpha: Float) {
            guard alpha > 0.04, size > 0.002 else { return }
            bins.add(alpha: alpha, center: CGPoint(x: CGFloat(x), y: CGFloat(y)), radius: CGFloat(size))
        }

        if rate > 0.01 {
            for i in 0..<(40 + boost) {
                let fi = Float(i)
                let seed = fract(sin(fi * 12.9898) * 43758.5453)
                let seed2 = fract(seed * 7.1 + 0.37)
                let period: Float = 2.2 + 1.8 * seed2
                let life = fract(t / period + seed)
                let spin: Float = seed2 > 0.5 ? 1 : -1
                let ang = seed * 6.2831853 + t * 0.15 * spin
                let rad: Float = 1.10 + 0.60 * fract(seed * 3.3)
                let x = cos(ang) * rad
                let y = sin(ang) * rad * 0.6 + (life - 0.5) * 0.6
                let pulse = sin(Float.pi * life)
                let size = 0.05 * (0.6 + fract(seed * 5.5)) * pulse
                emit(x, y, size, pulse * rate)
            }
        }
        if burst > 0.01 {
            // Slots 40..<(40 + boost) are already drawn as fireflies above (boost ∈ 0...20, so the range is valid).
            for i in (40 + boost)..<60 {
                let fi = Float(i)
                let seed = fract(sin(fi * 12.9898) * 43758.5453)
                let seed2 = fract(seed * 7.1 + 0.37)
                let life = fract(t / 0.6 + seed)
                let spin: Float = seed2 > 0.5 ? 1 : -1
                let ang = seed * 6.2831853 + t * 0.15 * spin
                let rad: Float = 0.3 + 1.4 * life
                let x = cos(ang) * rad
                let y = sin(ang) * rad * 0.6 + (life - 0.5) * 0.6
                let pulse = sin(Float.pi * life)
                let size = 0.05 * (0.6 + fract(seed * 5.5)) * pulse
                emit(x, y, size, pulse * burst)
            }
        }

        var c = ctx
        if let clip {
            c.clip(to: clip)
        }
        c.blendMode = .plusLighter
        let m = base.matrix
        let color = res.sparkle
        for k in 0..<SparkleBins.count {
            let path = bins.path(k)
            guard !path.isEmpty else { continue }
            c.opacity = SparkleBins.opacity(k)
            c.fill(path.applying(m), with: .color(color))
        }
    }
}

/// Eight alpha bins for the sparkle field (unit-space star paths). A sparkle of alpha `a` goes into bin
/// `min(7, Int(a·8))`, which is filled at the bin's mid value `(k + 0.5)/8`.
struct SparkleBins {
    static let count = 8

    private var bin0 = Path()
    private var bin1 = Path()
    private var bin2 = Path()
    private var bin3 = Path()
    private var bin4 = Path()
    private var bin5 = Path()
    private var bin6 = Path()
    private var bin7 = Path()

    /// Fill opacity of bin `k`.
    static func opacity(_ k: Int) -> Double {
        (Double(k) + 0.5) / Double(count)
    }

    /// Bin index for `alpha` (0 for anything non-positive or non-finite).
    static func index(alpha: Float) -> Int {
        guard alpha.isFinite, alpha > 0 else { return 0 }
        return min(count - 1, Int(min(alpha, 1) * Float(count)))
    }

    mutating func add(alpha: Float, center: CGPoint, radius: CGFloat) {
        switch SparkleBins.index(alpha: alpha) {
        case 0: CharacterPaths.addStar4(to: &bin0, center: center, radius: radius)
        case 1: CharacterPaths.addStar4(to: &bin1, center: center, radius: radius)
        case 2: CharacterPaths.addStar4(to: &bin2, center: center, radius: radius)
        case 3: CharacterPaths.addStar4(to: &bin3, center: center, radius: radius)
        case 4: CharacterPaths.addStar4(to: &bin4, center: center, radius: radius)
        case 5: CharacterPaths.addStar4(to: &bin5, center: center, radius: radius)
        case 6: CharacterPaths.addStar4(to: &bin6, center: center, radius: radius)
        default: CharacterPaths.addStar4(to: &bin7, center: center, radius: radius)
        }
    }

    func path(_ k: Int) -> Path {
        switch k {
        case 0: return bin0
        case 1: return bin1
        case 2: return bin2
        case 3: return bin3
        case 4: return bin4
        case 5: return bin5
        case 6: return bin6
        default: return bin7
        }
    }
}
