import SwiftUI
import CoreGraphics

/// Unit-space `Path` builders shared by the Canvas renderer (CONTRACT §3).
///
/// Every path is built in canonical space: origin at the body centre, **y up**, unit = body radius.
/// The painter maps them to view points with a `CGAffineTransform` (scale R, flip y, translate), so the
/// builders never see view coordinates. All functions are pure and allocation-light (a `Path` is the only
/// heap object they create).
enum CharacterPaths {

    // MARK: - Constants

    static let twoPi: CGFloat = 2 * CGFloat.pi
    static let halfPi: CGFloat = CGFloat.pi / 2

    // MARK: - Primitive helpers

    /// Appends a circular arc from `startAngle` to `endAngle` (radians, y-up, counter-clockwise when the
    /// sweep is positive) as cubic Bézier segments of at most 90°. Independent of any `clockwise` flag
    /// semantics, so the result is the same whatever coordinate flip is applied later.
    /// When `connect` is true the arc starts with a line from the current point, otherwise with a move.
    static func addArc(to path: inout Path, center: CGPoint, radius: CGFloat,
                       startAngle: CGFloat, endAngle: CGFloat, connect: Bool) {
        let sweep = endAngle - startAngle
        // A non-finite angle or radius (NaN from a corrupt pose) must not reach `Int(_:)`, which traps.
        guard sweep.isFinite, startAngle.isFinite, radius.isFinite, center.x.isFinite, center.y.isFinite else { return }
        let segmentCount = min(16, max(1, ceil(abs(sweep) / halfPi - 0.0001)))
        let segments = Int(segmentCount)
        let step = sweep / CGFloat(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var a0 = startAngle
        let start = CGPoint(x: center.x + radius * cos(a0), y: center.y + radius * sin(a0))
        if connect {
            path.addLine(to: start)
        } else {
            path.move(to: start)
        }
        for _ in 0..<segments {
            let a1 = a0 + step
            let p0 = CGPoint(x: center.x + radius * cos(a0), y: center.y + radius * sin(a0))
            let p3 = CGPoint(x: center.x + radius * cos(a1), y: center.y + radius * sin(a1))
            let c1 = CGPoint(x: p0.x - k * radius * sin(a0), y: p0.y + k * radius * cos(a0))
            let c2 = CGPoint(x: p3.x + k * radius * sin(a1), y: p3.y - k * radius * cos(a1))
            path.addCurve(to: p3, control1: c1, control2: c2)
            a0 = a1
        }
    }

    /// Closed Catmull-Rom spline through `count` points converted to cubic Béziers.
    /// The first point of the path equals the last (C⁰ and C¹ closed). The point at index `corner`
    /// (if any) is kept as a sharp corner: the segments meeting there use one-sided (chord) tangents.
    static func closedSpline(count: Int, corner: Int = -1, point: (Int) -> CGPoint) -> Path {
        var path = Path()
        guard count >= 3 else { return path }
        var p0 = point(count - 1)
        var p1 = point(0)
        var p2 = point(1)
        path.move(to: p1)
        for i in 0..<count {
            let p3 = point((i + 2) % count)
            let c1: CGPoint
            if i == corner {
                c1 = CGPoint(x: p1.x + (p2.x - p1.x) / 3, y: p1.y + (p2.y - p1.y) / 3)
            } else {
                c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            }
            let c2: CGPoint
            if (i + 1) % count == corner {
                c2 = CGPoint(x: p2.x - (p2.x - p1.x) / 3, y: p2.y - (p2.y - p1.y) / 3)
            } else {
                c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            }
            path.addCurve(to: p2, control1: c1, control2: c2)
            p0 = p1
            p1 = p2
            p2 = p3
        }
        path.closeSubpath()
        return path
    }

    /// Rotation about the origin followed by a translation (rotate first, then move).
    static func placement(x: CGFloat, y: CGFloat, rotation: CGFloat) -> CGAffineTransform {
        if rotation == 0 {
            return CGAffineTransform(translationX: x, y: y)
        }
        return CGAffineTransform(rotationAngle: rotation).concatenating(CGAffineTransform(translationX: x, y: y))
    }

    static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func fract(_ x: CGFloat) -> CGFloat { x - floor(x) }

    /// Deterministic hash in 0..<1 (same formula as the sparkle field, §3.8).
    static func hash(_ i: Int) -> CGFloat { fract(sin(CGFloat(i) * 12.9898) * 43758.5453) }

    // MARK: - Basic shapes

    static func circle(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    static func ellipse(center: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat = 0) -> Path {
        let rect = CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)
        return Path(ellipseIn: rect).applying(placement(x: center.x, y: center.y, rotation: rotation))
    }

    static func rect(_ r: CGRect) -> Path {
        Path(r)
    }

    /// Stadium shape between two points.
    static func capsule(from a: CGPoint, to b: CGPoint, radius r: CGFloat) -> Path {
        var dx = b.x - a.x
        var dy = b.y - a.y
        let len = sqrt(dx * dx + dy * dy)
        if len < 1e-6 {
            return circle(center: a, radius: r)
        }
        dx /= len
        dy /= len
        let nx = -dy
        let ny = dx
        let nAngle = atan2(ny, nx)
        var path = Path()
        path.move(to: CGPoint(x: a.x + nx * r, y: a.y + ny * r))
        path.addLine(to: CGPoint(x: b.x + nx * r, y: b.y + ny * r))
        addArc(to: &path, center: b, radius: r, startAngle: nAngle, endAngle: nAngle - CGFloat.pi, connect: true)
        path.addLine(to: CGPoint(x: a.x - nx * r, y: a.y - ny * r))
        addArc(to: &path, center: a, radius: r, startAngle: nAngle - CGFloat.pi, endAngle: nAngle - twoPi, connect: true)
        path.closeSubpath()
        return path
    }

    static func roundedBox(center: CGPoint, width: CGFloat, height: CGFloat, corner: CGFloat, rotation: CGFloat = 0) -> Path {
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        let c = min(corner, min(width, height) / 2)
        return Path(roundedRect: rect, cornerSize: CGSize(width: c, height: c), style: .circular)
            .applying(placement(x: center.x, y: center.y, rotation: rotation))
    }

    /// Four-point star (sparkle / highlight) with tips up, right, down, left.
    static func star4(center: CGPoint, radius: CGFloat, inner: CGFloat = 0.36) -> Path {
        var path = Path()
        addStar4(to: &path, center: center, radius: radius, inner: inner)
        return path
    }

    /// Appends a four-point star as a new subpath (used to batch many sparkles into one fill).
    static func addStar4(to path: inout Path, center: CGPoint, radius: CGFloat, inner: CGFloat = 0.36) {
        let ri = radius * inner
        let d = ri * 0.70710678
        path.move(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x + d, y: center.y + d))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x + d, y: center.y - d))
        path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x - d, y: center.y - d))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x - d, y: center.y + d))
        path.closeSubpath()
    }

    /// Heart with the point at the bottom; `size` ≈ half width.
    static func heart(center c: CGPoint, size s: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - 0.9 * s))
        path.addCurve(to: CGPoint(x: c.x - s, y: c.y + 0.25 * s),
                      control1: CGPoint(x: c.x - 0.55 * s, y: c.y - 0.55 * s),
                      control2: CGPoint(x: c.x - s, y: c.y - 0.2 * s))
        path.addCurve(to: CGPoint(x: c.x, y: c.y + 0.35 * s),
                      control1: CGPoint(x: c.x - s, y: c.y + 0.85 * s),
                      control2: CGPoint(x: c.x - 0.25 * s, y: c.y + 0.95 * s))
        path.addCurve(to: CGPoint(x: c.x + s, y: c.y + 0.25 * s),
                      control1: CGPoint(x: c.x + 0.25 * s, y: c.y + 0.95 * s),
                      control2: CGPoint(x: c.x + s, y: c.y + 0.85 * s))
        path.addCurve(to: CGPoint(x: c.x, y: c.y - 0.9 * s),
                      control1: CGPoint(x: c.x + s, y: c.y - 0.2 * s),
                      control2: CGPoint(x: c.x + 0.55 * s, y: c.y - 0.55 * s))
        path.closeSubpath()
        return path
    }

    /// Crescent = big circle minus a smaller offset circle.
    static func crescent(center: CGPoint, radius: CGFloat, cutCenter: CGPoint, cutRadius: CGFloat) -> Path {
        circle(center: center, radius: radius).subtracting(circle(center: cutCenter, radius: cutRadius))
    }

    /// Open spiral polyline (to be stroked) from `startRadius` down to `endRadius` over `turns` turns.
    static func spiral(center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, turns: CGFloat,
                       startAngle: CGFloat = CGFloat.pi, samples: Int = 40) -> Path {
        var path = Path()
        let n = max(2, samples)
        for i in 0...n {
            let u = CGFloat(i) / CGFloat(n)
            let a = startAngle + twoPi * turns * u
            let r = startRadius + (endRadius - startRadius) * u
            let p = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
            if i == 0 {
                path.move(to: p)
            } else {
                path.addLine(to: p)
            }
        }
        return path
    }

    /// Brow centre line: a shallow upward arc from (-halfLength, 0) to (+halfLength, 0), sagitta `sagitta`,
    /// rotated by `angle` (radians, y-up, counter-clockwise positive) and moved to `center`. Stroke it with
    /// the brow thickness and round caps to get the §3.2 curved capsule.
    static func brow(center: CGPoint, halfLength: CGFloat, angle: CGFloat, sagitta: CGFloat = 0.03) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -halfLength, y: 0))
        path.addQuadCurve(to: CGPoint(x: halfLength, y: 0), control: CGPoint(x: 0, y: sagitta * 2))
        return path.applying(placement(x: center.x, y: center.y, rotation: angle))
    }

    // MARK: - Teardrop family

    /// Circle of `radius` at `center` whose upper part tapers smoothly into `tip`.
    /// `sideControl` is the right-hand Bézier control point (mirrored about `center.x` for the left side);
    /// `tipControl` is the (dx, dy) offset of the control points next to the tip.
    static func teardrop(center c: CGPoint, radius r: CGFloat, tip: CGPoint,
                         sideControl: CGPoint, tipControl: CGPoint, sideAngle: CGFloat = 0.0873) -> Path {
        let pr = CGPoint(x: c.x + r * cos(sideAngle), y: c.y + r * sin(sideAngle))
        let pl = CGPoint(x: c.x - r * cos(sideAngle), y: c.y + r * sin(sideAngle))
        var path = Path()
        path.move(to: pl)
        // Around the bottom: angle increases from (π − sideAngle) through 3π/2 to (2π + sideAngle).
        addArc(to: &path, center: c, radius: r, startAngle: CGFloat.pi - sideAngle, endAngle: twoPi + sideAngle, connect: true)
        path.addCurve(to: tip,
                      control1: CGPoint(x: sideControl.x, y: sideControl.y),
                      control2: CGPoint(x: tip.x + tipControl.x, y: tip.y - tipControl.y))
        path.addCurve(to: pl,
                      control1: CGPoint(x: tip.x - tipControl.x, y: tip.y - tipControl.y),
                      control2: CGPoint(x: 2 * c.x - sideControl.x, y: sideControl.y))
        path.closeSubpath()
        return path
    }

    /// Small falling drop (tears, sweat): circle `radius` at `center`, tip pointing up.
    static func smallDrop(center: CGPoint, radius: CGFloat) -> Path {
        teardrop(center: center, radius: radius,
                 tip: CGPoint(x: center.x, y: center.y + radius * 2.3),
                 sideControl: CGPoint(x: center.x + radius * 0.92, y: center.y + radius * 0.9),
                 tipControl: CGPoint(x: radius * 0.18, y: radius * 0.7),
                 sideAngle: 0.17)
    }

    // MARK: - Body silhouettes (§3.5)

    /// `round`: unit circle.
    static func roundBody() -> Path {
        circle(center: .zero, radius: 1)
    }

    /// `star`: five points, outer radius 1.05, inner 0.52, corner rounding 0.12, one point straight up.
    static func starBody(points: Int = 5, outer: CGFloat = 1.05, inner: CGFloat = 0.52, rounding: CGFloat = 0.12) -> Path {
        let n = max(3, points) * 2
        func vertex(_ i: Int) -> CGPoint {
            let idx = ((i % n) + n) % n
            let r = idx % 2 == 0 ? outer : inner
            let a = halfPi + CGFloat(idx) * (twoPi / CGFloat(n))
            return CGPoint(x: r * cos(a), y: r * sin(a))
        }
        var path = Path()
        for i in 0..<n {
            let v = vertex(i)
            let prev = vertex(i - 1)
            let next = vertex(i + 1)
            var dpx = prev.x - v.x
            var dpy = prev.y - v.y
            let lp = sqrt(dpx * dpx + dpy * dpy)
            var dnx = next.x - v.x
            var dny = next.y - v.y
            let ln = sqrt(dnx * dnx + dny * dny)
            dpx /= lp
            dpy /= lp
            dnx /= ln
            dny /= ln
            let d = min(rounding, min(lp, ln) * 0.5)
            let a = CGPoint(x: v.x + dpx * d, y: v.y + dpy * d)
            let b = CGPoint(x: v.x + dnx * d, y: v.y + dny * d)
            if i == 0 {
                path.move(to: a)
            } else {
                path.addLine(to: a)
            }
            path.addQuadCurve(to: b, control: v)
        }
        path.closeSubpath()
        return path
    }

    /// `drop`: circle r 0.85 at (0, −0.15) joined to a tip at (0.18·sin(wiggle), 1.05); convex sides.
    static func dropBody(wiggle: CGFloat) -> Path {
        let tipX = 0.18 * sin(wiggle)
        return teardrop(center: CGPoint(x: 0, y: -0.15), radius: 0.85,
                        tip: CGPoint(x: tipX, y: 1.05),
                        sideControl: CGPoint(x: 0.78, y: 0.55),
                        tipControl: CGPoint(x: 0.12, y: 0.23))
    }

    /// Radius of the drop circle (r 0.85 at (0, −0.15)) seen from the origin at polar angle `theta`.
    static func dropCircleRadius(sin s: CGFloat) -> CGFloat {
        (-0.3 * s + sqrt(0.09 * s * s + 2.8)) / 2
    }

    /// Point at `t` on the cubic Bézier `p0 → p3`.
    static func cubicPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let k0 = u * u * u
        let k1 = 3 * u * u * t
        let k2 = 3 * u * t * t
        let k3 = t * t * t
        return CGPoint(x: k0 * p0.x + k1 * p1.x + k2 * p2.x + k3 * p3.x,
                       y: k0 * p0.y + k1 * p1.y + k2 * p2.y + k3 * p3.y)
    }

    /// Samples per side and around the bottom arc of `dropOutlinePoint` (total 48, the §8 maximum).
    static let dropSideSamples = 12
    static let dropArcSamples = 24
    static var dropOutlineCount: Int { 2 * dropSideSamples + dropArcSamples }

    /// Point `i` (0 ..< 48) of the straight `drop` outline (same geometry as `dropBody(wiggle: 0)`: circle r 0.85
    /// at (0, −0.15), convex sides with control points (±0.78, 0.55), tip at (0, 1.05)), counter-clockwise:
    /// index 0 is the tip, 1 ..< 12 run down the left side, 12 ..< 36 go around the bottom arc starting at the left
    /// side point, 36 ..< 48 climb the right side back towards the tip.
    static func dropOutlinePoint(_ i: Int) -> CGPoint {
        let r: CGFloat = 0.85
        let cy: CGFloat = -0.15
        let sideAngle: CGFloat = 0.0873
        let sideX = r * cos(sideAngle)
        let sideY = cy + r * sin(sideAngle)
        let tip = CGPoint(x: 0, y: 1.05)
        let side = dropSideSamples
        let arc = dropArcSamples
        if i < side {
            let t = CGFloat(i) / CGFloat(side)
            return cubicPoint(tip, CGPoint(x: -0.12, y: 0.82), CGPoint(x: -0.78, y: 0.55), CGPoint(x: -sideX, y: sideY), t)
        }
        if i < side + arc {
            let u = CGFloat(i - side) / CGFloat(arc)
            let angle = CGFloat.pi - sideAngle + (CGFloat.pi + 2 * sideAngle) * u
            return CGPoint(x: r * cos(angle), y: cy + r * sin(angle))
        }
        let t = CGFloat(i - side - arc) / CGFloat(side)
        return cubicPoint(CGPoint(x: sideX, y: sideY), CGPoint(x: 0.78, y: 0.55), CGPoint(x: 0.12, y: 0.82), tip, t)
    }

    /// Point `i` of the `flame` outline: the drop outline pushed radially by
    /// `1 + (0.06·sin(5θ + 3w) + 0.03·sin(9θ − 2w) + flicker·sin(flickerPhase + 7y)) · smoothstep(−0.15, 0.25, y)`
    /// (the MSL `sdFlame` modulation, which fades in smoothly instead of switching on at the equator), then the upper
    /// part sways sideways by `0.22·sin(w)` so the tip leans.
    static func flamePoint(_ i: Int, wiggle w: CGFloat, flickerPhase: CGFloat = 0, flicker: CGFloat = 0) -> CGPoint {
        let p = dropOutlinePoint(i)
        let theta = atan2(p.y, p.x)
        let upper = smoothstep(-0.15, 0.25, p.y)
        let m = 0.06 * sin(5 * theta + 3 * w) + 0.03 * sin(9 * theta - 2 * w) + flicker * sin(flickerPhase + 7 * p.y)
        let k = 1 + m * upper
        let y = p.y * k
        return CGPoint(x: p.x * k + 0.22 * sin(w) * smoothstep(0.1, 1.05, y), y: y)
    }

    /// `flame` (§3.5): drop with a pointed tip whose upper boundary is modulated by two sine tongues (plus the
    /// `.flicker` ripple of amplitude `flicker`, phase `flickerPhase`) and whose tip sways with `wiggle`.
    static func flameBody(wiggle w: CGFloat, flickerPhase: CGFloat = 0, flicker: CGFloat = 0) -> Path {
        closedSpline(count: dropOutlineCount, corner: 0) { i in
            flamePoint(i, wiggle: w, flickerPhase: flickerPhase, flicker: flicker)
        }
    }

    /// `hood`: rounded drop whose tip curls to the upper right as a tapering tube
    /// (0, 0.9) → (0.25, 1.25) → (0.55, 1.05), radius 0.22 → 0.08. Static (no wiggle), so cacheable.
    static func hoodBody() -> Path {
        let samples = 40
        let body = closedSpline(count: samples) { i in
            let theta = twoPi * CGFloat(i) / CGFloat(samples)
            let s = sin(theta)
            var r = dropCircleRadius(sin: s)
            if s > 0 {
                r += 0.30 * s * s
            }
            return CGPoint(x: r * cos(theta), y: r * s)
        }
        // Tapering tube along a quadratic Bézier.
        let p0 = CGPoint(x: 0, y: 0.9)
        let p1 = CGPoint(x: 0.25, y: 1.25)
        let p2 = CGPoint(x: 0.55, y: 1.05)
        let steps = 10
        func q(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
                           y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y)
        }
        func normal(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            var dx = 2 * u * (p1.x - p0.x) + 2 * t * (p2.x - p1.x)
            var dy = 2 * u * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
            let l = max(sqrt(dx * dx + dy * dy), 1e-6)
            dx /= l
            dy /= l
            return CGPoint(x: -dy, y: dx)
        }
        func radius(_ t: CGFloat) -> CGFloat { 0.22 - 0.14 * t }
        var tube = Path()
        for k in 0...steps {
            let t = CGFloat(k) / CGFloat(steps)
            let c = q(t)
            let n = normal(t)
            let r = radius(t)
            let p = CGPoint(x: c.x - n.x * r, y: c.y - n.y * r)
            if k == 0 {
                tube.move(to: p)
            } else {
                tube.addLine(to: p)
            }
        }
        // Round cap around the tip.
        let tipC = q(1)
        let tipN = normal(1)
        let tipR = radius(1)
        let dirAngle = atan2(tipN.y, tipN.x) - halfPi
        for k in 1..<8 {
            let a = dirAngle - halfPi + CGFloat.pi * CGFloat(k) / 8
            tube.addLine(to: CGPoint(x: tipC.x + tipR * cos(a), y: tipC.y + tipR * sin(a)))
        }
        for k in stride(from: steps, through: 0, by: -1) {
            let t = CGFloat(k) / CGFloat(steps)
            let c = q(t)
            let n = normal(t)
            let r = radius(t)
            tube.addLine(to: CGPoint(x: c.x + n.x * r, y: c.y + n.y * r))
        }
        // Round cap at the start (from +n through −tangent to −n): a flat end would leave its outer corner
        // ≈ 0.05 outside the dome as a sharp step in the union.
        let startC = q(0)
        let startN = normal(0)
        let startR = radius(0)
        let startAngle = atan2(startN.y, startN.x)
        for k in 1..<8 {
            let a = startAngle + CGFloat.pi * CGFloat(k) / 8
            tube.addLine(to: CGPoint(x: startC.x + startR * cos(a), y: startC.y + startR * sin(a)))
        }
        tube.closeSubpath()
        return body.union(tube)
    }

    /// `cloud`: union of five circles flattened below y = −0.70.
    static func cloudBody() -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: -0.75, y: -0.75, width: 1.5, height: 1.5))
        p.addEllipse(in: CGRect(x: -0.55 - 0.55, y: -0.10 - 0.55, width: 1.1, height: 1.1))
        p.addEllipse(in: CGRect(x: 0.55 - 0.55, y: -0.10 - 0.55, width: 1.1, height: 1.1))
        p.addEllipse(in: CGRect(x: -0.25 - 0.50, y: 0.35 - 0.50, width: 1.0, height: 1.0))
        p.addEllipse(in: CGRect(x: 0.30 - 0.48, y: 0.40 - 0.48, width: 0.96, height: 0.96))
        let keep = Path(CGRect(x: -2, y: -0.70, width: 4, height: 4))
        return p.intersection(keep)
    }

    /// Unit silhouette for a body shape. `wiggle` is the pose's wiggle phase (radians); `flicker` / `flickerPhase`
    /// drive the `.flicker` ripple of flame bodies (0 = none).
    static func body(shape: BodyShape, wiggle: CGFloat, flickerPhase: CGFloat = 0, flicker: CGFloat = 0) -> Path {
        switch shape {
        case .round: return roundBody()
        case .star: return starBody()
        case .drop: return dropBody(wiggle: wiggle)
        case .hood: return hoodBody()
        case .cloud: return cloudBody()
        case .flame: return flameBody(wiggle: wiggle, flickerPhase: flickerPhase, flicker: flicker)
        }
    }

    /// True when the silhouette depends on the pose (and therefore cannot be cached).
    static func isDynamic(_ shape: BodyShape) -> Bool {
        switch shape {
        case .drop, .flame: return true
        case .round, .star, .hood, .cloud: return false
        }
    }

    // MARK: - Mouth (§3.3)

    /// Boundary point of the mouth at parameter `theta` in mouth-local coordinates (centre at the origin).
    static func mouthPoint(theta: CGFloat, halfWidth w: CGFloat, halfHeight h: CGFloat,
                           smile: CGFloat, restWidth bigW: CGFloat) -> CGPoint {
        let s = sin(theta)
        let x = w * cos(theta)
        let yBase = h * s * (s > 0 ? 0.70 : 1.00)
        let u = w > 1e-6 ? x / w : 0
        let lift = smile * 0.6 * bigW * (u * u - 0.33)
        return CGPoint(x: x, y: yBase + lift)
    }

    /// Smooth closed mouth outline sampled with 32 points.
    static func mouth(halfWidth w: CGFloat, halfHeight h: CGFloat, smile: CGFloat, restWidth bigW: CGFloat) -> Path {
        let n = 32
        return closedSpline(count: n) { i in
            mouthPoint(theta: twoPi * CGFloat(i) / CGFloat(n), halfWidth: w, halfHeight: h, smile: smile, restWidth: bigW)
        }
    }

    /// 33 samples (θ = 0 … 2π inclusive) — the first equals the last. Used by tests; the painter samples inline.
    static func mouthSamples(halfWidth w: CGFloat, halfHeight h: CGFloat, smile: CGFloat, restWidth bigW: CGFloat) -> [CGPoint] {
        let n = 32
        var out: [CGPoint] = []
        out.reserveCapacity(n + 1)
        for i in 0...n {
            let theta = i == n ? 0 : twoPi * CGFloat(i) / CGFloat(n)
            out.append(mouthPoint(theta: theta, halfWidth: w, halfHeight: h, smile: smile, restWidth: bigW))
        }
        return out
    }

    /// Band that covers everything above (upper teeth) or below (lower teeth) a parabola following the
    /// smile warp, in mouth-local coordinates. Clip it to the mouth when filling.
    static func teethBand(upper: Bool, halfWidth w: CGFloat, halfHeight h: CGFloat, smile: CGFloat,
                          restWidth bigW: CGFloat, amount: CGFloat) -> Path {
        let a = w > 1e-6 ? smile * 0.6 * bigW / (w * w) : 0
        let base: CGFloat = upper ? (0.70 * h - 0.45 * h * amount) : (-h + 0.35 * h * amount)
        let c = base - 0.33 * smile * 0.6 * bigW
        let ext = w + 0.02
        let edge = a * ext * ext + c
        let far: CGFloat = upper ? (h + bigW) : -(h + bigW)
        var path = Path()
        path.move(to: CGPoint(x: -ext, y: far))
        path.addLine(to: CGPoint(x: -ext, y: edge))
        path.addQuadCurve(to: CGPoint(x: ext, y: edge), control: CGPoint(x: 0, y: c - a * ext * ext))
        path.addLine(to: CGPoint(x: ext, y: far))
        path.closeSubpath()
        return path
    }

    // MARK: - Accessories (§3.6)

    /// Lumi's robe: teardrop circle r 1.28 at (0, −0.25) with a hood peak at (peakX, 1.38).
    static func robe(peakX: CGFloat) -> Path {
        teardrop(center: CGPoint(x: 0, y: -0.25), radius: 1.28,
                 tip: CGPoint(x: peakX, y: 1.38),
                 sideControl: CGPoint(x: 1.15, y: 0.75),
                 tipControl: CGPoint(x: 0.22, y: 0.38))
    }

    /// Face opening of the robe: ellipse at (0, 0.05) radii (0.80, 0.84).
    static func robeOpening() -> Path {
        ellipse(center: CGPoint(x: 0, y: 0.05), rx: 0.80, ry: 0.84)
    }

    /// Collar region of the robe drawn over the body: everything below y = −0.55 + 0.05·x² (the MSL collar curve).
    /// A quadratic Bézier with evenly spaced x is exactly that parabola: end points (±2.5, −0.2375), control (0, −0.8625).
    static func robeFrontMask() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -2.5, y: -0.2375))
        path.addQuadCurve(to: CGPoint(x: 2.5, y: -0.2375), control: CGPoint(x: 0, y: -0.8625))
        path.addLine(to: CGPoint(x: 2.5, y: -3))
        path.addLine(to: CGPoint(x: -2.5, y: -3))
        path.closeSubpath()
        return path
    }

    /// Grid cell size (R units) of the `.starPattern` field: one star per cell.
    static let starCellSize: CGFloat = 0.28

    /// Integer hash of a grid cell, 24-bit result in [0, 1). Pure integer arithmetic, bit-identical to the MSL
    /// `cellHash`, so both renderers place the robe stars at the same spots.
    static func cellHash(x: Int32, y: Int32, salt: UInt32) -> CGFloat {
        var h = UInt32(bitPattern: x) &* 73856093
        h ^= UInt32(bitPattern: y) &* 19349663
        h ^= salt &* 83492791
        h ^= h >> 16
        h = h &* 2146121005
        h ^= h >> 15
        h = h &* 2221713035
        h ^= h >> 16
        return CGFloat(h & 0xFFFFFF) / 16777216
    }

    /// Robe star field (`.starPattern`): one tiny four-point star per 0.28 R grid cell, hash-placed in the middle half
    /// of its cell, tip radius 0.022 + 0.02·h — the field the MSL `starPattern` evaluates per pixel. Only cells that can
    /// show on the robe are kept (≈ 50 stars); the painter clips the field to the robe and, behind the body, away from
    /// the face opening. Static.
    static func robeStarField() -> Path {
        var path = Path()
        let cs = starCellSize
        for iy in Int32(-6)...Int32(5) {
            for ix in Int32(-5)...Int32(4) {
                let h1: CGFloat = cellHash(x: ix, y: iy, salt: 1)
                let h2: CGFloat = cellHash(x: ix, y: iy, salt: 2)
                let h3: CGFloat = cellHash(x: ix, y: iy, salt: 3)
                let cellX = CGFloat(ix) + 0.5
                let cellY = CGFloat(iy) + 0.5
                let x: CGFloat = (cellX + (h1 - 0.5) * 0.5) * cs
                let y: CGFloat = (cellY + (h2 - 0.5) * 0.5) * cs
                // Robe = circle r 1.28 at (0, −0.25) plus the hood peak up to y ≈ 1.4.
                let dy: CGFloat = y + 0.25
                let r2: CGFloat = x * x + dy * dy
                let inPeak = abs(x) < 0.6 && y > 0 && y < 1.45
                let onRobe = r2 < 1.7424 || inPeak
                // Fully inside the face opening and above the collar: never visible.
                let ex: CGFloat = x / 0.75
                let ey: CGFloat = (y - 0.05) / 0.79
                let e2: CGFloat = ex * ex + ey * ey
                let hidden = e2 < 1 && y > -0.45
                if !onRobe || hidden { continue }
                addStar4(to: &path, center: CGPoint(x: x, y: y), radius: 0.022 + 0.02 * h3, inner: 0.36)
            }
        }
        return path
    }

    /// Nox's crescent: circle r 0.17 at (0, 0.55) minus circle r 0.14 at (0.08, 0.60). Static.
    static func moonCrescent() -> Path {
        crescent(center: CGPoint(x: 0, y: 0.55), radius: 0.17, cutCenter: CGPoint(x: 0.08, y: 0.60), cutRadius: 0.14)
    }

    /// Lumie's bell jar: circle r 1.55 at (0, 0.10) ∪ rect x ∈ [−1.55, 1.55], y ∈ [−1.30, 0.10]. Static.
    static func domeGlass() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -1.55, y: -1.30))
        path.addLine(to: CGPoint(x: -1.55, y: 0.10))
        addArc(to: &path, center: CGPoint(x: 0, y: 0.10), radius: 1.55, startAngle: CGFloat.pi, endAngle: 0, connect: true)
        path.addLine(to: CGPoint(x: 1.55, y: -1.30))
        path.closeSubpath()
        return path
    }

    /// Height of Sprout's scalloped cap edge at `x`: `0.35 − 0.09·(0.5 + 0.5·cos 10x)` (same as the MSL edge) —
    /// three shallow 0.09-deep bumps across the face that never hang below y = 0.26.
    static func capEdgeY(_ x: CGFloat) -> CGFloat {
        0.35 - 0.09 * (0.5 + 0.5 * cos(10 * x))
    }

    /// Sprout's cap: everything above the scalloped edge `capEdgeY` (3 bumps across the body). Clip to the body.
    /// Static. The edge is 24 cubic Hermite segments over x ∈ [−1.2, 1.2] using the exact slope `0.45·sin 10x`.
    static func capMask() -> Path {
        var path = Path()
        let x0: CGFloat = -1.2
        let x1: CGFloat = 1.2
        let n = 24
        let dx = (x1 - x0) / CGFloat(n)
        path.move(to: CGPoint(x: -1.6, y: 2.5))
        path.addLine(to: CGPoint(x: -1.6, y: 0.35))
        path.addLine(to: CGPoint(x: x0, y: capEdgeY(x0)))
        for i in 0..<n {
            let xa = x0 + dx * CGFloat(i)
            let xb = xa + dx
            let ya = capEdgeY(xa)
            let yb = capEdgeY(xb)
            let slopeA = 0.45 * sin(10 * xa)
            let slopeB = 0.45 * sin(10 * xb)
            path.addCurve(to: CGPoint(x: xb, y: yb),
                          control1: CGPoint(x: xa + dx / 3, y: ya + slopeA * dx / 3),
                          control2: CGPoint(x: xb - dx / 3, y: yb - slopeB * dx / 3))
        }
        path.addLine(to: CGPoint(x: 1.6, y: 0.35))
        path.addLine(to: CGPoint(x: 1.6, y: 2.5))
        path.closeSubpath()
        return path
    }

    /// Unit disc (radius 1 at the origin): filled through a context transform to draw soft gradient ellipses.
    static func unitDisc() -> Path {
        Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2))
    }

    /// Spark's brain: six circles forming two lobes around `center`, overall radius `radius`.
    /// `inset` (unit-space length) shrinks every circle by that amount: the union of the shrunk circles is the
    /// `d < −inset` level set of the MSL `drawBrain` distance (a min of the circle distances), so the painter can
    /// build the brain's rim bands from it.
    static func brain(center c: CGPoint, radius r: CGFloat, inset: CGFloat = 0) -> Path {
        let k = r / 0.30
        var path = Path()
        func blob(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
            let bx = c.x + x * k
            let by = c.y + y * k
            let br = radius * k - inset
            guard br > 0 else { return }
            path.addEllipse(in: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2))
        }
        blob(-0.13, 0.03, 0.165)
        blob(0.13, 0.03, 0.165)
        blob(-0.21, -0.06, 0.115)
        blob(0.21, -0.06, 0.115)
        blob(-0.08, 0.14, 0.135)
        blob(0.08, 0.14, 0.135)
        return path
    }

    /// Grooves of the brain (to be stroked): central fissure + two short curls per lobe. The fissure starts at
    /// (0, −0.16)·k, below the brain's lower edge at x = 0 (≈ −0.07·k), so the stroke must be clipped to `brain`
    /// (as the MSL clips the grooves to the brain coverage).
    static func brainGrooves(center c: CGPoint, radius r: CGFloat) -> Path {
        let k = r / 0.30
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - 0.16 * k))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + 0.26 * k), control: CGPoint(x: c.x + 0.03 * k, y: c.y + 0.05 * k))
        path.move(to: CGPoint(x: c.x - 0.22 * k, y: c.y + 0.02 * k))
        path.addQuadCurve(to: CGPoint(x: c.x - 0.06 * k, y: c.y + 0.10 * k), control: CGPoint(x: c.x - 0.16 * k, y: c.y + 0.16 * k))
        path.move(to: CGPoint(x: c.x + 0.22 * k, y: c.y + 0.02 * k))
        path.addQuadCurve(to: CGPoint(x: c.x + 0.06 * k, y: c.y + 0.10 * k), control: CGPoint(x: c.x + 0.16 * k, y: c.y + 0.16 * k))
        path.move(to: CGPoint(x: c.x - 0.14 * k, y: c.y - 0.12 * k))
        path.addQuadCurve(to: CGPoint(x: c.x - 0.04 * k, y: c.y - 0.02 * k), control: CGPoint(x: c.x - 0.14 * k, y: c.y - 0.02 * k))
        path.move(to: CGPoint(x: c.x + 0.14 * k, y: c.y - 0.12 * k))
        path.addQuadCurve(to: CGPoint(x: c.x + 0.04 * k, y: c.y - 0.02 * k), control: CGPoint(x: c.x + 0.14 * k, y: c.y - 0.02 * k))
        return path
    }
}
