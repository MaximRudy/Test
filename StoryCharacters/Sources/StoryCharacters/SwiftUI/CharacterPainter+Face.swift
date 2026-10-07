import SwiftUI
import CoreGraphics

/// Face features (CONTRACT §3.1–§3.4). All positions are computed in head space (face-layout units scaled by
/// `faceScale`, shifted by `faceOffsetY`) and mapped through the head transform.
extension CanvasScene {

    func drawFace(in ctx: inout GraphicsContext) {
        drawCheeks(in: &ctx)
        drawEyes(in: &ctx)
        drawBrows(in: &ctx)
        drawMouth(in: &ctx)
    }

    // MARK: - Cheeks (§3.4)

    func drawCheeks(in ctx: inout GraphicsContext) {
        let f = pose.face
        let r = CGFloat(layout.cheekRadius) * s
        let cx = CGFloat(layout.cheekX) * s
        let cy = oy + CGFloat(layout.cheekY) * s
        drawCheek(center: CGPoint(x: -cx, y: cy), radius: r, alpha: 0.22 + 0.6 * f.blush + 0.3 * f.lowerLidL, in: &ctx)
        drawCheek(center: CGPoint(x: cx, y: cy), radius: r, alpha: 0.22 + 0.6 * f.blush + 0.3 * f.lowerLidR, in: &ctx)
    }

    private func drawCheek(center: CGPoint, radius: CGFloat, alpha: Float, in ctx: inout GraphicsContext) {
        let a = min(max(alpha, 0), 1)
        guard a > 0.01, radius > 0.001 else { return }
        let saved = ctx.opacity
        ctx.opacity = Double(a)
        ctx.fill(head.path(CharacterPaths.circle(center: center, radius: radius)),
                 with: .radialGradient(res.cheekGradient, center: head.point(center),
                                       startRadius: 0, endRadius: head.length(radius)))
        ctx.opacity = saved
    }

    // MARK: - Eyes (§3.1)

    func drawEyes(in ctx: inout GraphicsContext) {
        let f = pose.face
        let eyeScale = CGFloat(max(f.eyeScale, 0.05))
        let ex = CGFloat(layout.eyeOffsetX) * s
        let ey = oy + CGFloat(layout.eyeY) * s
        var rxL = CGFloat(layout.eyeRadiusX) * s * eyeScale
        var rxR = rxL
        let ry = CGFloat(layout.eyeRadiusY) * s * eyeScale
        // The eye on the far side of a head turn is foreshortened.
        let turn = CGFloat(f.headTurn)
        let foreshorten = 1 - 0.15 * min(abs(turn), 1)
        if turn > 0 {
            rxL *= foreshorten
        } else if turn < 0 {
            rxR *= foreshorten
        }
        let irisR = CGFloat(layout.irisRadius) * s * eyeScale
        let pupilR = CGFloat(layout.pupilRadius) * s * eyeScale * CGFloat(max(f.pupil, 0))
        let gaze = CGPoint(x: CGFloat(min(max(f.gazeX, -1), 1)), y: CGFloat(min(max(f.gazeY, -1), 1)))
        drawEye(center: CGPoint(x: -ex, y: ey), rx: rxL, ry: ry, open: CGFloat(f.eyeOpenL), lowerLid: CGFloat(f.lowerLidL),
                irisR: irisR, pupilR: pupilR, gaze: gaze, in: &ctx)
        drawEye(center: CGPoint(x: ex, y: ey), rx: rxR, ry: ry, open: CGFloat(f.eyeOpenR), lowerLid: CGFloat(f.lowerLidR),
                irisR: irisR, pupilR: pupilR, gaze: gaze, in: &ctx)
    }

    private func drawEye(center c: CGPoint, rx: CGFloat, ry baseRy: CGFloat, open: CGFloat, lowerLid: CGFloat,
                         irisR: CGFloat, pupilR: CGFloat, gaze: CGPoint, in ctx: inout GraphicsContext) {
        guard rx > 0.001, baseRy > 0.001 else { return }
        let o = min(max(open, 0), 1.3)
        let ry = o > 1 ? baseRy * o : baseRy
        let q = min(max(lowerLid, 0), 1)
        let topY = c.y - ry + 2 * ry * min(o, 1)
        let bottomY = c.y - ry + 2 * ry * 0.55 * q

        // Closed (or squeezed shut) eye: a soft lash line where the lids meet — a quadratic from (−0.9·rx, y0) to
        // (+0.9·rx, y0) whose middle sits at y0 + amp, i.e. y = y0 + amp·(1 − xn²) (same curve as the MSL).
        // A relaxed closure (blink, sleep, wink) sags into a ∪ (amp −0.04); a cheek-squeezed one (laughing, giggle:
        // lowerLid ≥ 0.45) blends into the happy ^ ^ arch (amp +0.05).
        if o < 0.04 || topY - bottomY < 0.02 {
            let lineY = o < 0.04 ? c.y - ry * 0.2 : (topY + bottomY) / 2
            let happy = CharacterPaths.smoothstep(0.45, 0.85, q)
            let amp: CGFloat = -0.04 + 0.09 * happy
            let y0: CGFloat = lineY + 0.02 - 0.04 * happy
            var line = Path()
            line.move(to: CGPoint(x: c.x - rx * 0.9, y: y0))
            line.addQuadCurve(to: CGPoint(x: c.x + rx * 0.9, y: y0), control: CGPoint(x: c.x, y: y0 + 2 * amp))
            ctx.stroke(head.path(line), with: .color(res.browColor),
                       style: StrokeStyle(lineWidth: head.length(0.035), lineCap: .round))
            return
        }

        let darkFace = features.contains(.darkFace)
        let ellipse = head.path(CharacterPaths.ellipse(center: c, rx: rx, ry: ry))
        let band = head.path(Path(CGRect(x: c.x - rx - 0.02, y: bottomY, width: 2 * rx + 0.04, height: topY - bottomY)))

        // Iris never leaves the eye: offset by gaze · (rx − irisR, ry − irisR) · 0.85.
        let ix = c.x + gaze.x * max(rx - irisR, 0) * 0.85
        let iy = c.y + gaze.y * max(ry - irisR, 0) * 0.85
        let irisCenter = CGPoint(x: ix, y: iy)
        let irisPath = head.path(CharacterPaths.circle(center: irisCenter, radius: irisR))
        let irisShading = GraphicsContext.Shading.radialGradient(res.irisGradient, center: head.point(irisCenter),
                                                                 startRadius: 0, endRadius: head.length(irisR))
        // Limbal ring entirely inside the iris, covering [irisR − 0.015, irisR] like the MSL.
        let limbalWidth = head.length(0.015)
        let limbalPath = head.path(CharacterPaths.circle(center: irisCenter, radius: max(irisR - 0.0075, 0.001)))
        let pupilPath = head.path(CharacterPaths.circle(center: irisCenter, radius: max(pupilR, 0.001)))

        // Highlights follow the gaze at 25 %.
        let gx = (ix - c.x) * 0.25
        let gy = (iy - c.y) * 0.25
        let bigHighlight = head.path(CharacterPaths.circle(center: CGPoint(x: c.x - 0.38 * rx + gx, y: c.y + 0.42 * ry + gy),
                                                           radius: 0.30 * irisR))
        let smallHighlight = head.path(CharacterPaths.circle(center: CGPoint(x: c.x + 0.30 * rx + gx, y: c.y - 0.30 * ry + gy),
                                                             radius: 0.13 * irisR))
        var sparklePath: Path? = nil
        if features.contains(.eyeSparkles) {
            var stars = Path()
            CharacterPaths.addStar4(to: &stars, center: CGPoint(x: c.x + 0.1 * rx + gx, y: c.y + 0.1 * ry + gy), radius: 0.12 * irisR, inner: 0.3)
            CharacterPaths.addStar4(to: &stars, center: CGPoint(x: c.x - 0.2 * rx + gx, y: c.y - 0.35 * ry + gy), radius: 0.12 * irisR, inner: 0.3)
            sparklePath = head.path(stars)
        }
        var haloPath: Path? = nil
        var haloShading: GraphicsContext.Shading? = nil
        if darkFace {
            haloPath = head.path(CharacterPaths.circle(center: irisCenter, radius: 1.6 * irisR))
            haloShading = .radialGradient(res.irisHaloGradient, center: head.point(irisCenter),
                                          startRadius: 0, endRadius: head.length(1.6 * irisR))
        }

        // 1-px-ish soft shadow hugging the top lid.
        let shadowH = 0.18 * ry
        let lidRect = head.path(Path(CGRect(x: c.x - rx - 0.02, y: topY - shadowH, width: 2 * rx + 0.04, height: shadowH + 0.03)))
        let lidShading = GraphicsContext.Shading.linearGradient(res.lidShadowGradient,
                                                                startPoint: head.point(c.x, topY),
                                                                endPoint: head.point(c.x, topY - shadowH))

        // Clip a context copy (no offscreen layer) to the visible region: ellipse ∩ lid band.
        var eye = ctx
        eye.clip(to: ellipse)
        eye.clip(to: band)
        eye.fill(ellipse, with: .color(darkFace ? res.accent : res.sclera))
        if let haloPath, let haloShading {
            eye.fill(haloPath, with: haloShading)
        }
        eye.fill(irisPath, with: irisShading)
        eye.stroke(limbalPath, with: .color(res.limbalRing), lineWidth: limbalWidth)
        eye.fill(pupilPath, with: .color(res.pupil))
        eye.fill(bigHighlight, with: .color(res.eyeHighlight))
        eye.fill(smallHighlight, with: .color(res.eyeHighlight))
        if let sparklePath {
            eye.fill(sparklePath, with: .color(res.eyeHighlight))
        }
        eye.fill(lidRect, with: lidShading)
    }

    // MARK: - Brows (§3.2)

    func drawBrows(in ctx: inout GraphicsContext) {
        let f = pose.face
        let ex = CGFloat(layout.eyeOffsetX) * s
        let baseY = oy + CGFloat(layout.browY) * s
        let halfLength = CGFloat(layout.browLength) * s / 2
        let thickness = CGFloat(layout.browThickness) * s
        let raiseL = CGFloat(min(max(f.browRaiseL, -1), 1))
        let raiseR = CGFloat(min(max(f.browRaiseR, -1), 1))
        // Raise −1 squashes the thickness × 0.8.
        let thickL = thickness * (raiseL < 0 ? 1 + 0.2 * raiseL : 1)
        let thickR = thickness * (raiseR < 0 ? 1 + 0.2 * raiseR : 1)
        // Positive tilt = inner ends up (y-up, counter-clockwise positive): left +0.55·tilt, right −0.55·tilt.
        let angleL = 0.55 * CGFloat(f.browTiltL)
        let angleR = -0.55 * CGFloat(f.browTiltR)
        drawBrow(center: CGPoint(x: -ex, y: baseY + 0.12 * raiseL), halfLength: halfLength, thickness: thickL, angle: angleL, in: &ctx)
        drawBrow(center: CGPoint(x: ex, y: baseY + 0.12 * raiseR), halfLength: halfLength, thickness: thickR, angle: angleR, in: &ctx)
    }

    private func drawBrow(center: CGPoint, halfLength: CGFloat, thickness: CGFloat, angle: CGFloat, in ctx: inout GraphicsContext) {
        guard halfLength > 0.001, thickness > 0.001 else { return }
        let path = head.path(CharacterPaths.brow(center: center, halfLength: halfLength, angle: angle))
        ctx.stroke(path, with: .color(res.browColor),
                   style: StrokeStyle(lineWidth: head.length(thickness), lineCap: .round, lineJoin: .round))
    }

    // MARK: - Mouth (§3.3)

    func drawMouth(in ctx: inout GraphicsContext) {
        let f = pose.face
        let m = f.mouth
        let open = CGFloat(min(max(m.open, 0), 1))
        let press = CGFloat(min(max(m.press, 0), 1))
        let round = CGFloat(min(max(m.round, 0), 1))
        let width = CGFloat(min(max(m.width, -1), 1))
        let smile = CGFloat(min(max(m.smile, -1), 1))
        let upperTeeth = CGFloat(min(max(m.upperTeeth, 0), 1))
        let lowerTeeth = CGFloat(min(max(m.lowerTeeth, 0), 1))
        let tongue = CGFloat(min(max(m.tongue, 0), 1))

        let bigW = CGFloat(layout.mouthWidth) * s
        let bigH = CGFloat(layout.mouthHeight) * s
        let center = CGPoint(x: 0.10 * CGFloat(f.headTurn),
                             y: oy + CGFloat(layout.mouthY) * s + 0.05 * CGFloat(f.headNod) - 0.03 * open)
        let w = max(0.01, bigW * (1 + 0.45 * width) * (1 - 0.55 * round) * (1 - 0.5 * press))
        let h = max(0.004, (0.02 + bigH * open * (1 + 0.4 * round)) * (1 - 0.85 * press))
        let place = CGAffineTransform(translationX: center.x, y: center.y)

        let mouthPath = head.path(CharacterPaths.mouth(halfWidth: w, halfHeight: h, smile: smile, restWidth: bigW).applying(place))

        // Teeth and tongue fade in with the jaw, smoothstep(0.02, 0.05, open) (same gate as the MSL), so a closed
        // mouth stays a clean lip line.
        let interiorGate = CharacterPaths.smoothstep(0.02, 0.05, open)
        var upperPath: Path? = nil
        var lowerPath: Path? = nil
        var tonguePath: Path? = nil
        if interiorGate > 0.01 {
            if upperTeeth > 0.02 {
                upperPath = head.path(CharacterPaths.teethBand(upper: true, halfWidth: w, halfHeight: h, smile: smile,
                                                               restWidth: bigW, amount: upperTeeth).applying(place))
            }
            if lowerTeeth > 0.02 {
                lowerPath = head.path(CharacterPaths.teethBand(upper: false, halfWidth: w, halfHeight: h, smile: smile,
                                                               restWidth: bigW, amount: lowerTeeth).applying(place))
            }
            if tongue > 0.02 {
                // Tongue ellipse bent by the same smile warp lift(x) as the lips (the MSL evaluates it in warped space).
                tonguePath = head.path(CharacterPaths.tongue(halfWidth: w, halfHeight: h, amount: tongue, smile: smile,
                                                             restWidth: bigW).applying(place))
            }
        }

        // Clip a context copy (no offscreen layer) to the mouth.
        var inner = ctx
        inner.clip(to: mouthPath)
        inner.fill(mouthPath, with: .color(res.mouthInner))
        inner.opacity *= Double(interiorGate)
        if let upperPath {
            inner.fill(upperPath, with: .color(res.teeth))
        }
        if let lowerPath {
            inner.fill(lowerPath, with: .color(res.teeth))
        }
        if let tonguePath {
            inner.fill(tonguePath, with: .color(res.tongue))
        }

        // Lip line fades in with the opening (and press); the stroke bulges with press.
        let lipFade = min(1, open * 8 + press)
        if lipFade > 0.01 {
            let saved = ctx.opacity
            ctx.opacity = Double(lipFade)
            ctx.stroke(mouthPath, with: .color(res.lipLine),
                       style: StrokeStyle(lineWidth: head.length(0.012 * (1 + press)), lineCap: .round, lineJoin: .round))
            ctx.opacity = saved
        }
    }
}
