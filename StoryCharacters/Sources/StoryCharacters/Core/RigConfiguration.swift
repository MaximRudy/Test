import Foundation

/// Tunables for `CharacterRig`.
public struct RigConfiguration: Sendable, Equatable {
    /// Honour the system "Reduce Motion" setting by damping idle motion and gestures.
    public var respectsReduceMotion: Bool
    /// 0 = blink only, 1 = normal liveliness, 2 = very lively.
    public var idleVariety: Float
    /// Scale of talking-head motion (nods on word onsets, brow emphasis). 0 disables.
    public var speechHeadMotion: Float
    /// Base share of time the character looks at the viewer when no `lookTarget` is set.
    public var cameraBias: Float
    /// Clamp for the simulation step after a pause (seconds). Prevents springs from exploding when the view resumes.
    public var maxDeltaTime: Float
    /// Default BCP-47 language for `speak(_:)` when none is passed and auto-detection fails (nil = system locale).
    public var speechLanguage: String?
    /// Seconds of inactivity before the character starts getting sleepy on its own (0 = never).
    public var autoSleepAfter: TimeInterval

    public init(respectsReduceMotion: Bool = true,
                idleVariety: Float = 1,
                speechHeadMotion: Float = 1,
                cameraBias: Float = 0.6,
                maxDeltaTime: Float = 1.0 / 15.0,
                speechLanguage: String? = nil,
                autoSleepAfter: TimeInterval = 0) {
        self.respectsReduceMotion = respectsReduceMotion
        self.idleVariety = idleVariety
        self.speechHeadMotion = speechHeadMotion
        self.cameraBias = cameraBias
        self.maxDeltaTime = maxDeltaTime
        self.speechLanguage = speechLanguage
        self.autoSleepAfter = autoSleepAfter
    }
}
