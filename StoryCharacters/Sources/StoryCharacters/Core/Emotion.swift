import Foundation

/// Discrete emotional states. The rig blends between them with springs, so switching mid-motion is always smooth.
public enum Emotion: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case neutral
    case happy
    case excited
    case laughing
    case surprised
    case curious
    case thinking
    case sad
    case scared
    case sleepy
    case grumpy
    case shy
    case love
    case listening

    public var id: String { rawValue }

    /// Pleasantness -1 ... 1.
    public var valence: Float {
        switch self {
        case .neutral: return 0
        case .happy: return 0.7
        case .excited: return 0.8
        case .laughing: return 0.9
        case .surprised: return 0.2
        case .curious: return 0.3
        case .thinking: return 0.05
        case .sad: return -0.7
        case .scared: return -0.6
        case .sleepy: return 0.1
        case .grumpy: return -0.5
        case .shy: return 0.3
        case .love: return 0.9
        case .listening: return 0.2
        }
    }

    /// Activation 0 ... 1.
    public var arousal: Float {
        switch self {
        case .neutral: return 0.3
        case .happy: return 0.55
        case .excited: return 0.95
        case .laughing: return 0.85
        case .surprised: return 0.9
        case .curious: return 0.55
        case .thinking: return 0.35
        case .sad: return 0.15
        case .scared: return 0.8
        case .sleepy: return 0.05
        case .grumpy: return 0.45
        case .shy: return 0.35
        case .love: return 0.6
        case .listening: return 0.4
        }
    }

    public var englishName: String {
        switch self {
        case .neutral: return "Neutral"
        case .happy: return "Happy"
        case .excited: return "Excited"
        case .laughing: return "Laughing"
        case .surprised: return "Surprised"
        case .curious: return "Curious"
        case .thinking: return "Thinking"
        case .sad: return "Sad"
        case .scared: return "Scared"
        case .sleepy: return "Sleepy"
        case .grumpy: return "Grumpy"
        case .shy: return "Shy"
        case .love: return "In love"
        case .listening: return "Listening"
        }
    }

    public var russianName: String {
        switch self {
        case .neutral: return "Спокойствие"
        case .happy: return "Радость"
        case .excited: return "Восторг"
        case .laughing: return "Смех"
        case .surprised: return "Удивление"
        case .curious: return "Любопытство"
        case .thinking: return "Задумчивость"
        case .sad: return "Грусть"
        case .scared: return "Испуг"
        case .sleepy: return "Сонливость"
        case .grumpy: return "Ворчливость"
        case .shy: return "Смущение"
        case .love: return "Влюблённость"
        case .listening: return "Внимание"
        }
    }

    public func displayName(languageCode: String? = Locale.current.language.languageCode?.identifier) -> String {
        languageCode == "ru" ? russianName : englishName
    }

    /// SF Symbol for pickers.
    public var symbolName: String {
        switch self {
        case .neutral: return "face.smiling"
        case .happy: return "sun.max"
        case .excited: return "sparkles"
        case .laughing: return "face.smiling.inverse"
        case .surprised: return "exclamationmark.bubble"
        case .curious: return "questionmark.circle"
        case .thinking: return "brain"
        case .sad: return "cloud.rain"
        case .scared: return "bolt"
        case .sleepy: return "moon.zzz"
        case .grumpy: return "cloud.bolt"
        case .shy: return "eye.slash"
        case .love: return "heart"
        case .listening: return "ear"
        }
    }
}

/// Speech prosody hints handed to TTS drivers.
public struct Prosody: Sendable, Equatable {
    /// Speaking-rate multiplier (1 = normal).
    public var rate: Float
    /// Pitch multiplier 0.5 ... 2.0 (maps to `AVSpeechUtterance.pitchMultiplier`).
    public var pitch: Float
    /// Volume 0 ... 1.
    public var volume: Float

    public init(rate: Float = 1, pitch: Float = 1, volume: Float = 1) {
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
    }
}

/// Everything an emotion changes about the character. The table of profiles lives in
/// `Core/Animation/EmotionProfiles.swift` (`EmotionProfile.profile(for:)`).
public struct EmotionProfile: Sendable, Equatable {
    /// Absolute resting face for the emotion (its `mouth` is the resting mouth: smile/frown, slight opening for surprise).
    public var face: FacePose
    /// Absolute resting body (scale 1 = neutral; tilt, arms, glow, accessory channels).
    public var body: BodyPose
    /// Comic overlays (tears, hearts, zzz...).
    public var effects: EffectsPose
    /// Blink-frequency multiplier (1 ≈ one blink every 3.8 s).
    public var blinkRate: Float
    /// How far the lids rest down 0 ... 1 (sleepy ≈ 0.55).
    public var blinkHeaviness: Float
    /// Eye-wander amount 0 ... 1.
    public var gazeWander: Float
    /// Share of time spent looking at the viewer 0 ... 1.
    public var cameraBias: Float
    /// Breathing frequency in Hz.
    public var breathRate: Float
    /// Breathing depth multiplier.
    public var breathDepth: Float
    /// Floating/bobbing amplitude multiplier.
    public var floatAmplitude: Float
    /// Idle motion energy 0 ... 1 (speed and amplitude of wiggles, tilts, micro-expressions).
    public var energy: Float
    /// Micro-expression frequency multiplier.
    public var microExpressionRate: Float
    /// Voice hints.
    public var prosody: Prosody
    /// Hue shift of glow/highlights as a fraction of the hue circle (-0.5 ... 0.5).
    public var glowHueShift: Float
    /// Spring-stiffness multiplier when entering this emotion (surprise snaps, sadness sinks slowly).
    public var transitionStiffness: Float

    public init(face: FacePose = .neutral,
                body: BodyPose = .neutral,
                effects: EffectsPose = .neutral,
                blinkRate: Float = 1,
                blinkHeaviness: Float = 0,
                gazeWander: Float = 0.5,
                cameraBias: Float = 0.6,
                breathRate: Float = 0.22,
                breathDepth: Float = 1,
                floatAmplitude: Float = 1,
                energy: Float = 0.5,
                microExpressionRate: Float = 1,
                prosody: Prosody = Prosody(),
                glowHueShift: Float = 0,
                transitionStiffness: Float = 1) {
        self.face = face
        self.body = body
        self.effects = effects
        self.blinkRate = blinkRate
        self.blinkHeaviness = blinkHeaviness
        self.gazeWander = gazeWander
        self.cameraBias = cameraBias
        self.breathRate = breathRate
        self.breathDepth = breathDepth
        self.floatAmplitude = floatAmplitude
        self.energy = energy
        self.microExpressionRate = microExpressionRate
        self.prosody = prosody
        self.glowHueShift = glowHueShift
        self.transitionStiffness = transitionStiffness
    }
}
