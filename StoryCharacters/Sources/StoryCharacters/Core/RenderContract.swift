import Foundation
import CoreGraphics
import simd

/// Which renderer draws the character.
public enum CharacterRenderer: String, CaseIterable, Identifiable, Sendable {
    /// Metal when a GPU device is available (always on real devices and the simulator), SwiftUI otherwise.
    case automatic
    /// `MTKView` + SDF fragment shader. Resolution independent, ~0 CPU per frame.
    case metal
    /// Pure SwiftUI `Canvas` + `TimelineView`. Works in previews, widgets and anywhere Metal is undesirable.
    case swiftUI

    public var id: String { rawValue }
}

/// Shared mapping between body-radius units (y up, origin at the body centre) and view points (y down).
public enum CanonicalSpace {
    /// Body radius in points for a view of `size`.
    public static func bodyRadius(in size: CGSize, design: CharacterDesign) -> CGFloat {
        0.5 * min(size.width, size.height) * CGFloat(design.frame.radiusScale)
    }

    /// Body origin in view coordinates (points, y down).
    public static func origin(in size: CGSize, design: CharacterDesign) -> CGPoint {
        let r = bodyRadius(in: size, design: design)
        return CGPoint(x: size.width / 2, y: size.height / 2 - CGFloat(design.frame.centerOffsetY) * r)
    }
}

/// GPU-side snapshot of a pose + design. Layout is 35 × float4 (560 bytes) and must match
/// `struct CharacterUniforms` in `Metal/Shaders/CharacterShaders.metal` field-for-field, in order.
/// Only `SIMD4<Float>` members are allowed so Swift and MSL layouts agree without padding surprises.
public struct CharacterUniforms: Equatable {
    /// width, height (points × scale = pixels), aspect (w / h), time (s)
    public var viewport: SIMD4<Float>
    /// offsetX, offsetY, scaleX, scaleY
    public var transform: SIMD4<Float>
    /// tilt, breathe, glow, wiggle
    public var bodyParams: SIMD4<Float>
    /// armL, armR, accessory, accessory2
    public var armsAccessory: SIMD4<Float>
    /// legL, legR, bounce, spare
    public var legsBounce: SIMD4<Float>
    /// eyeOpenL, eyeOpenR, gazeX, gazeY
    public var eyesA: SIMD4<Float>
    /// pupil, eyeScale, lowerLidL, lowerLidR
    public var eyesB: SIMD4<Float>
    /// browRaiseL, browRaiseR, browTiltL, browTiltR
    public var brows: SIMD4<Float>
    /// blush, headTilt, headTurn, headNod
    public var head: SIMD4<Float>
    /// open, width, smile, round
    public var mouthA: SIMD4<Float>
    /// upperTeeth, lowerTeeth, tongue, press
    public var mouthB: SIMD4<Float>
    /// tears, sweat, hearts, zzz
    public var fxA: SIMD4<Float>
    /// question, exclamation, sparkleBurst, sparkleRate (pose)
    public var fxB: SIMD4<Float>
    /// eyeOffsetX, eyeY, eyeRadiusX, eyeRadiusY
    public var layoutA: SIMD4<Float>
    /// irisRadius, pupilRadius, browY, browLength
    public var layoutB: SIMD4<Float>
    /// browThickness, mouthY, mouthWidth, mouthHeight
    public var layoutC: SIMD4<Float>
    /// cheekX, cheekY, cheekRadius, faceScale
    public var layoutD: SIMD4<Float>
    /// faceOffsetY, radiusScale, centerOffsetY, spare
    public var layoutE: SIMD4<Float>
    /// bodyShape (BodyShape.rawValue), features (DesignFeatures.rawValue), glowStrength, sparkleRate (design)
    public var style: SIMD4<Float>
    /// floatAmplitude, floatFrequency, wobbleAmplitude, flickerRate
    public var idle: SIMD4<Float>
    public var colBodyTop: SIMD4<Float>
    public var colBodyBottom: SIMD4<Float>
    public var colHighlight: SIMD4<Float>
    public var colShadow: SIMD4<Float>
    public var colAccent: SIMD4<Float>
    public var colAccent2: SIMD4<Float>
    public var colIris: SIMD4<Float>
    public var colPupil: SIMD4<Float>
    public var colSclera: SIMD4<Float>
    public var colCheek: SIMD4<Float>
    public var colGlow: SIMD4<Float>
    public var colMouthInner: SIMD4<Float>
    public var colTongue: SIMD4<Float>
    public var colTeeth: SIMD4<Float>
    public var colOutline: SIMD4<Float>

    /// Number of float4 slots; `MemoryLayout<CharacterUniforms>.stride` must equal `slotCount * 16`.
    public static let slotCount = 35

    public init(pose: CharacterPose, design: CharacterDesign, viewportSize: SIMD2<Float>, time: Float) {
        let f = pose.face
        let m = pose.face.mouth
        let b = pose.body
        let e = pose.effects
        let l = design.face
        let p = design.palette

        viewport = SIMD4<Float>(viewportSize.x, viewportSize.y, viewportSize.x / max(viewportSize.y, 1), time)
        transform = SIMD4<Float>(b.offsetX, b.offsetY, b.scaleX, b.scaleY)
        bodyParams = SIMD4<Float>(b.tilt, b.breathe, b.glow, b.wiggle)
        armsAccessory = SIMD4<Float>(b.armL, b.armR, b.accessory, b.accessory2)
        legsBounce = SIMD4<Float>(b.legL, b.legR, b.bounce, b.spare)
        eyesA = SIMD4<Float>(f.eyeOpenL, f.eyeOpenR, f.gazeX, f.gazeY)
        eyesB = SIMD4<Float>(f.pupil, f.eyeScale, f.lowerLidL, f.lowerLidR)
        brows = SIMD4<Float>(f.browRaiseL, f.browRaiseR, f.browTiltL, f.browTiltR)
        head = SIMD4<Float>(f.blush, f.headTilt, f.headTurn, f.headNod)
        mouthA = SIMD4<Float>(m.open, m.width, m.smile, m.round)
        mouthB = SIMD4<Float>(m.upperTeeth, m.lowerTeeth, m.tongue, m.press)
        fxA = SIMD4<Float>(e.tears, e.sweat, e.hearts, e.zzz)
        fxB = SIMD4<Float>(e.question, e.exclamation, e.sparkleBurst, e.sparkleRate)
        layoutA = SIMD4<Float>(l.eyeOffsetX, l.eyeY, l.eyeRadiusX, l.eyeRadiusY)
        layoutB = SIMD4<Float>(l.irisRadius, l.pupilRadius, l.browY, l.browLength)
        layoutC = SIMD4<Float>(l.browThickness, l.mouthY, l.mouthWidth, l.mouthHeight)
        layoutD = SIMD4<Float>(l.cheekX, l.cheekY, l.cheekRadius, l.faceScale)
        layoutE = SIMD4<Float>(l.faceOffsetY, design.frame.radiusScale, design.frame.centerOffsetY, 0)
        style = SIMD4<Float>(Float(design.bodyShape.rawValue), Float(design.features.rawValue), design.glowStrength, design.sparkleRate)
        idle = SIMD4<Float>(design.idle.floatAmplitude, design.idle.floatFrequency, design.idle.wobbleAmplitude, design.idle.flickerRate)
        colBodyTop = p.bodyTop
        colBodyBottom = p.bodyBottom
        colHighlight = p.highlight
        colShadow = p.shadow
        colAccent = p.accent
        colAccent2 = p.accent2
        colIris = p.iris
        colPupil = p.pupil
        colSclera = p.sclera
        colCheek = p.cheek
        colGlow = p.glow
        colMouthInner = p.mouthInner
        colTongue = p.tongue
        colTeeth = p.teeth
        colOutline = p.outline
    }
}
