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

    private func drawText(_ string: String, at p: CGPoint, size: CGFloat, alpha: Double, in ctx: inout GraphicsContext) {
        guard alpha > 0.01, size > 1 else { return }
        let font = Font.system(size: size, weight: .heavy, design: .rounded)
        let shadow = ctx.resolve(Text(verbatim: string).font(font).foregroundStyle(res.glyphShadow))
        let main = ctx.resolve(Text(verbatim: string).font(font).foregroundStyle(res.glyph))
        let saved = ctx.opacity
        ctx.opacity = min(alpha, 1)
        ctx.draw(shadow, at: CGPoint(x: p.x + size * 0.05, y: p.y + size * 0.05), anchor: .center)
        ctx.draw(main, at: p, anchor: .center)
        ctx.opacity = saved
    }

    // MARK: - Sparkle field (§3.8)

    /// 40 ambient sparkles (+20 for a burst, + up to 20 fireflies for `.dome` designs), 4-point stars, additive blend.
    /// Alpha is quantised into four bins so the whole field costs at most four fills.
    func drawSparkles(in ctx: inout GraphicsContext, clip: Path?) {
        let rate = min(max(pose.effects.sparkleRate, 0), 1)
        let burst = min(max(pose.effects.sparkleBurst, 0), 1)
        let boost = features.contains(.dome) ? Int((min(max(pose.body.accessory, 0), 1) * 20).rounded()) : 0
        guard rate > 0.01 || burst > 0.01 else { return }

        var bin0 = Path()
        var bin1 = Path()
        var bin2 = Path()
        var bin3 = Path()
        let t = pose.time

        func fract(_ x: Float) -> Float { x - x.rounded(.down) }

        func emit(_ x: Float, _ y: Float, _ size: Float, _ alpha: Float) {
            guard alpha > 0.04, size > 0.002 else { return }
            let center = CGPoint(x: CGFloat(x), y: CGFloat(y))
            let r = CGFloat(size)
            switch min(3, Int(alpha * 4)) {
            case 0: CharacterPaths.addStar4(to: &bin0, center: center, radius: r)
            case 1: CharacterPaths.addStar4(to: &bin1, center: center, radius: r)
            case 2: CharacterPaths.addStar4(to: &bin2, center: center, radius: r)
            default: CharacterPaths.addStar4(to: &bin3, center: center, radius: r)
            }
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
            for i in 40..<60 {
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

        let m = base.matrix
        let p0 = bin0.applying(m)
        let p1 = bin1.applying(m)
        let p2 = bin2.applying(m)
        let p3 = bin3.applying(m)
        let color = res.sparkle
        ctx.drawLayer { layer in
            if let clip {
                layer.clip(to: clip)
            }
            layer.blendMode = .plusLighter
            if !p0.isEmpty {
                layer.opacity = 0.25
                layer.fill(p0, with: .color(color))
            }
            if !p1.isEmpty {
                layer.opacity = 0.5
                layer.fill(p1, with: .color(color))
            }
            if !p2.isEmpty {
                layer.opacity = 0.75
                layer.fill(p2, with: .color(color))
            }
            if !p3.isEmpty {
                layer.opacity = 1.0
                layer.fill(p3, with: .color(color))
            }
        }
    }
}
