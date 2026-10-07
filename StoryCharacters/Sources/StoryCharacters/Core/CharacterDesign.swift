import Foundation
import simd

/// Silhouette family of the body. Both renderers implement every case.
public enum BodyShape: Int, CaseIterable, Codable, Sendable {
    /// Circle (Sprout).
    case round = 0
    /// Rounded five-point star (Lumi).
    case star = 1
    /// Teardrop with a soft tip (Spark, Drop).
    case drop = 2
    /// Hooded wisp: teardrop whose tip curls over (Nox).
    case hood = 3
    /// Puffy cloud made of overlapping circles (Puff).
    case cloud = 4
    /// Flame: teardrop with wavy, flickering sides (Ember, Lumie).
    case flame = 5
}

public extension SIMD4 where Scalar == Float {
    /// sRGB colour from `0xRRGGBB`.
    init(hex: UInt32, alpha: Float = 1) {
        self.init(Float((hex >> 16) & 0xFF) / 255,
                  Float((hex >> 8) & 0xFF) / 255,
                  Float(hex & 0xFF) / 255,
                  alpha)
    }
}

/// Colour set of a character. All colours are sRGB with straight (non-premultiplied) alpha.
public struct Palette: Sendable, Equatable {
    public var bodyTop: SIMD4<Float>
    public var bodyBottom: SIMD4<Float>
    public var highlight: SIMD4<Float>
    public var shadow: SIMD4<Float>
    /// Primary accessory colour (robe, brain, dark face, wood, inner flame, cap...).
    public var accent: SIMD4<Float>
    /// Secondary accessory colour (robe trim, moon, glass, leaf...).
    public var accent2: SIMD4<Float>
    public var iris: SIMD4<Float>
    public var pupil: SIMD4<Float>
    public var sclera: SIMD4<Float>
    public var cheek: SIMD4<Float>
    public var glow: SIMD4<Float>
    public var mouthInner: SIMD4<Float>
    public var tongue: SIMD4<Float>
    public var teeth: SIMD4<Float>
    /// Dark line colour for brows, lips and tiny details.
    public var outline: SIMD4<Float>

    public init(bodyTop: SIMD4<Float>, bodyBottom: SIMD4<Float>, highlight: SIMD4<Float>, shadow: SIMD4<Float>,
                accent: SIMD4<Float>, accent2: SIMD4<Float>, iris: SIMD4<Float>, pupil: SIMD4<Float>, sclera: SIMD4<Float>,
                cheek: SIMD4<Float>, glow: SIMD4<Float>, mouthInner: SIMD4<Float>, tongue: SIMD4<Float>, teeth: SIMD4<Float>,
                outline: SIMD4<Float>) {
        self.bodyTop = bodyTop
        self.bodyBottom = bodyBottom
        self.highlight = highlight
        self.shadow = shadow
        self.accent = accent
        self.accent2 = accent2
        self.iris = iris
        self.pupil = pupil
        self.sclera = sclera
        self.cheek = cheek
        self.glow = glow
        self.mouthInner = mouthInner
        self.tongue = tongue
        self.teeth = teeth
        self.outline = outline
    }
}

/// Face geometry in body-radius units (body fits a circle of radius 1 centred at the origin, y up).
public struct FaceLayout: Sendable, Equatable {
    /// Half distance between the eye centres.
    public var eyeOffsetX: Float
    /// Eye centre height.
    public var eyeY: Float
    public var eyeRadiusX: Float
    public var eyeRadiusY: Float
    public var irisRadius: Float
    public var pupilRadius: Float
    /// Brow centre height at rest.
    public var browY: Float
    public var browLength: Float
    public var browThickness: Float
    /// Mouth centre height.
    public var mouthY: Float
    /// Mouth half width at rest.
    public var mouthWidth: Float
    /// Mouth half height when fully open.
    public var mouthHeight: Float
    public var cheekX: Float
    public var cheekY: Float
    public var cheekRadius: Float
    /// Uniform scale applied to all face features.
    public var faceScale: Float
    /// Vertical shift of the whole face (hooded / tall designs).
    public var faceOffsetY: Float

    public init(eyeOffsetX: Float = 0.40, eyeY: Float = 0.10, eyeRadiusX: Float = 0.20, eyeRadiusY: Float = 0.24,
                irisRadius: Float = 0.15, pupilRadius: Float = 0.085, browY: Float = 0.45, browLength: Float = 0.26,
                browThickness: Float = 0.05, mouthY: Float = -0.32, mouthWidth: Float = 0.22, mouthHeight: Float = 0.20,
                cheekX: Float = 0.52, cheekY: Float = -0.12, cheekRadius: Float = 0.15, faceScale: Float = 1,
                faceOffsetY: Float = 0) {
        self.eyeOffsetX = eyeOffsetX
        self.eyeY = eyeY
        self.eyeRadiusX = eyeRadiusX
        self.eyeRadiusY = eyeRadiusY
        self.irisRadius = irisRadius
        self.pupilRadius = pupilRadius
        self.browY = browY
        self.browLength = browLength
        self.browThickness = browThickness
        self.mouthY = mouthY
        self.mouthWidth = mouthWidth
        self.mouthHeight = mouthHeight
        self.cheekX = cheekX
        self.cheekY = cheekY
        self.cheekRadius = cheekRadius
        self.faceScale = faceScale
        self.faceOffsetY = faceOffsetY
    }
}

/// How the character is framed inside its view.
public struct FrameLayout: Sendable, Equatable {
    /// Body radius as a fraction of half the view's shorter side (0.62 → body uses 62 % of the available radius; the rest is glow/hood/arms).
    public var radiusScale: Float
    /// Vertical offset of the body origin in body-radius units (positive = up). Lets hooded or jarred designs sit centred.
    public var centerOffsetY: Float

    public init(radiusScale: Float = 0.62, centerOffsetY: Float = 0) {
        self.radiusScale = radiusScale
        self.centerOffsetY = centerOffsetY
    }
}

/// Optional parts and behaviours of a design. Bit values are shared with the Metal shader (`style.y`).
public struct DesignFeatures: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let arms         = DesignFeatures(rawValue: 1 << 0)
    public static let legs         = DesignFeatures(rawValue: 1 << 1)
    /// Hovers and bobs instead of standing on the ground; squash/stretch anchors at the centre.
    public static let floats       = DesignFeatures(rawValue: 1 << 2)
    /// Indigo star-speckled robe/hood drawn around the body with a face opening (Lumi).
    public static let hood         = DesignFeatures(rawValue: 1 << 3)
    /// Lavender brain on the forehead (Spark). `body.accessory` = pulse.
    public static let brain        = DesignFeatures(rawValue: 1 << 4)
    /// Glowing crescent on the forehead (Nox). `body.accessory` = glow.
    public static let moonMark     = DesignFeatures(rawValue: 1 << 5)
    /// Glass bell jar on a wooden base around the body (Lumie). `body.accessory` = shimmer.
    public static let dome         = DesignFeatures(rawValue: 1 << 6)
    /// Green cap with two leaves (Sprout). `body.accessory` = leaf wiggle.
    public static let leaves       = DesignFeatures(rawValue: 1 << 7)
    /// Spiral curl on the top of the cloud (Puff). `body.accessory2` = curl bounce.
    public static let cloudCurl    = DesignFeatures(rawValue: 1 << 8)
    /// Glowing book in the left hand, pencil-wand in the right (Lumi). `accessory` = book open, `accessory2` = wand glow.
    public static let bookAndWand  = DesignFeatures(rawValue: 1 << 9)
    /// The face area is a dark void and the eyes glow (Nox).
    public static let darkFace     = DesignFeatures(rawValue: 1 << 10)
    /// A lighter inner flame inside the body (Ember, Lumie). `accessory2` = intensity.
    public static let innerFlame   = DesignFeatures(rawValue: 1 << 11)
    /// Jelly wobble on motion (Drop, Spark).
    public static let jelly        = DesignFeatures(rawValue: 1 << 12)
    /// Flame flicker on the silhouette (Ember, Lumie).
    public static let flicker      = DesignFeatures(rawValue: 1 << 13)
    /// Tiny star pattern on the body/robe (Lumi).
    public static let starPattern  = DesignFeatures(rawValue: 1 << 14)
    /// Extra star-shaped highlights inside the iris (Nox).
    public static let eyeSparkles  = DesignFeatures(rawValue: 1 << 15)
}

/// Design-level idle motion parameters (the rig multiplies them by the emotion's energy).
public struct IdleStyle: Sendable, Equatable {
    /// Vertical bob amplitude in body-radius units (floaters ≈ 0.04, grounded ≈ 0.01).
    public var floatAmplitude: Float
    /// Bob frequency in Hz.
    public var floatFrequency: Float
    /// Side-to-side body wobble amplitude (radians of tilt).
    public var wobbleAmplitude: Float
    /// Wobble frequency in Hz.
    public var wobbleFrequency: Float
    /// Flame flicker rate in Hz (0 for non-flames).
    public var flickerRate: Float
    /// Breathing depth multiplier.
    public var breathDepth: Float

    public init(floatAmplitude: Float = 0.012, floatFrequency: Float = 0.9, wobbleAmplitude: Float = 0.025,
                wobbleFrequency: Float = 0.5, flickerRate: Float = 0, breathDepth: Float = 1) {
        self.floatAmplitude = floatAmplitude
        self.floatFrequency = floatFrequency
        self.wobbleAmplitude = wobbleAmplitude
        self.wobbleFrequency = wobbleFrequency
        self.flickerRate = flickerRate
        self.breathDepth = breathDepth
    }
}

/// Personality knobs that bias idle behaviour and gesture choice.
public struct Personality: Sendable, Equatable {
    /// 0 calm ... 1 bouncy.
    public var energy: Float
    /// 0 bold ... 1 shy (looks away more, blushes more).
    public var shyness: Float
    /// 0 ... 1 — how often it looks around / tilts its head.
    public var curiosity: Float
    /// 0 ... 1 — how often it giggles / winks on its own.
    public var playfulness: Float

    public init(energy: Float = 0.5, shyness: Float = 0.2, curiosity: Float = 0.5, playfulness: Float = 0.5) {
        self.energy = energy
        self.shyness = shyness
        self.curiosity = curiosity
        self.playfulness = playfulness
    }
}

/// Voice hints for TTS.
public struct VoiceStyle: Sendable, Equatable {
    /// Base pitch multiplier (child-like ≈ 1.3).
    public var pitch: Float
    /// Base rate multiplier.
    public var rate: Float
    /// Preferred `AVSpeechSynthesisVoice` identifiers, first available wins. Empty = system default for the language.
    public var preferredVoiceIdentifiers: [String]

    public init(pitch: Float = 1.2, rate: Float = 0.95, preferredVoiceIdentifiers: [String] = []) {
        self.pitch = pitch
        self.rate = rate
        self.preferredVoiceIdentifiers = preferredVoiceIdentifiers
    }
}

/// Complete static description of a character. Instances are produced by `CharacterCatalog.design(for:)`
/// (module `Characters`). Renderers never hard-code per-character values — everything comes from here.
public struct CharacterDesign: Sendable, Equatable, Identifiable {
    public var kind: CharacterKind
    public var id: CharacterKind { kind }
    public var bodyShape: BodyShape
    public var palette: Palette
    public var face: FaceLayout
    public var frame: FrameLayout
    public var features: DesignFeatures
    public var idle: IdleStyle
    public var personality: Personality
    public var voice: VoiceStyle
    /// Base glow strength 0 ... 2.
    public var glowStrength: Float
    /// Ambient sparkle rate 0 ... 1.
    public var sparkleRate: Float
    /// Short character description by language code ("ru", "en").
    public var tagline: [String: String]

    public init(kind: CharacterKind, bodyShape: BodyShape, palette: Palette, face: FaceLayout = FaceLayout(),
                frame: FrameLayout = FrameLayout(), features: DesignFeatures = [], idle: IdleStyle = IdleStyle(),
                personality: Personality = Personality(), voice: VoiceStyle = VoiceStyle(), glowStrength: Float = 1,
                sparkleRate: Float = 0.35, tagline: [String: String] = [:]) {
        self.kind = kind
        self.bodyShape = bodyShape
        self.palette = palette
        self.face = face
        self.frame = frame
        self.features = features
        self.idle = idle
        self.personality = personality
        self.voice = voice
        self.glowStrength = glowStrength
        self.sparkleRate = sparkleRate
        self.tagline = tagline
    }

    public func localizedTagline(languageCode: String? = Locale.current.language.languageCode?.identifier) -> String {
        tagline[languageCode ?? "en"] ?? tagline["en"] ?? tagline["ru"] ?? ""
    }
}
