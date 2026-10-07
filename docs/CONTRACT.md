# StoryCharacters / LumiTales — Module Contract

This document is the single source of truth for every module. Implementers of different modules
work in parallel against it; reviewers verify against it. **Contract files are read-only** for
implementers (see §1). If you believe the contract needs a change, finish your module against the
contract as written and report a *contract change request* in your output.

## 0. Ground rules

* **No Swift compiler is available in this environment.** Write code as if Xcode 26 (Swift 6.2
  toolchain, iOS 26 SDK) compiles it with zero errors. Prefer long-stable, well-known APIs
  (SwiftUI iOS 17+, Observation, Metal 3 / MetalKit, AVFoundation, Accelerate). Avoid guessing new
  API names; when unsure between two spellings pick the one you are *certain* exists.
* Package language mode is **Swift 5** (`.swiftLanguageMode(.v5)`), app target `SWIFT_VERSION = 5.0`,
  but write concurrency-clean code anyway:
  * every UI-facing class is `@MainActor`; `CharacterRig`, drivers, renderers, players are `@MainActor`;
  * callbacks arriving on other threads (AVSpeechSynthesizer delegate, AVAudioEngine taps, CADisplayLink
    from a non-main runloop) must hop with `Task { @MainActor in … }` / `DispatchQueue.main.async` or
    hand data over via `OSAllocatedUnfairLock`. **Never call a `@MainActor` method synchronously from a
    nonisolated context** — that is a compile error even in Swift 5 mode;
  * `MTKViewDelegate` conformance: mark the methods `nonisolated` and wrap the body in
    `MainActor.assumeIsolated { … }`;
  * value types are `Sendable`; closures stored on `@MainActor` classes need no `@Sendable`.
* Everything another module or the app uses must be `public`. Internal helpers stay internal.
* Hot paths (`pose(at:)`, uniforms, Canvas drawing) must not allocate per frame (no `[Float]`
  temporaries, no string formatting, no `Date()`); use value types and SIMD.
* Run `python3 tools/check.py` before you finish and fix every **error** it reports.
* Imports: Core must not import UIKit/SwiftUI/Metal (Foundation, simd, CoreGraphics, QuartzCore,
  AVFoundation are fine). Renderers may import anything.
* Comments and identifiers in English; user-facing strings in both Russian and English where a
  language code is available (Russian is the primary market).

## 1. Repository layout and file ownership

```
LumiTales.xcodeproj/                 # iOS 26 app project (objectVersion 77, synchronized folders) — owned by the orchestrator
LumiTales/                           # App target sources (module "App")
  App/                               # LumiTalesApp.swift, RootView.swift, AppTheme.swift
  Features/Showcase/                 # ShowcaseView and sub-views
  Features/Story/                    # StoryView, StoryPlayerView, GeneratorView
  Resources/Assets.xcassets          # AppIcon, AccentColor
StoryCharacters/                     # local Swift package (library "StoryCharacters")
  Package.swift                      # CONTRACT — read-only
  Sources/StoryCharacters/
    Core/CharacterKind.swift         # CONTRACT — read-only
    Core/Pose.swift                  # CONTRACT — read-only
    Core/Viseme.swift                # CONTRACT — read-only
    Core/Emotion.swift               # CONTRACT — read-only
    Core/Gesture.swift               # CONTRACT — read-only
    Core/CharacterDesign.swift       # CONTRACT — read-only
    Core/RenderContract.swift        # CONTRACT — read-only
    Core/RigConfiguration.swift      # CONTRACT — read-only
    Core/LipSync/LipSyncContract.swift # CONTRACT — read-only
    Core/Animation/                  # module "Core" — CharacterRig, springs, idle, gestures, emotion profiles
    Core/LipSync/                    # module "LipSync" — tracks, estimator, drivers (except LipSyncContract.swift)
    Characters/                      # module "Characters" — CharacterCatalog + one file per character
    Metal/                           # module "Metal" — MTKView wrapper, renderer, shaders, MSL fallback source
    Metal/Shaders/CharacterShaders.metal
    SwiftUI/                         # module "Canvas" — Canvas renderer, CharacterView facade
    Story/                           # module "Story" — script parser, library, generator, StoryPlayer
    Resources/Stories/*.json         # module "Story" — bundled tagged stories
  Tests/StoryCharactersTests/        # each module adds <Module>Tests.swift
tools/check.py                       # structural checks (brace balance, duplicates, uniforms parity, required API)
docs/                                # this contract + architecture docs
```

## 2. Canonical space, time and clocks

* **Canonical space**: origin at the body centre, **y up**, unit = body radius *R*. The body silhouette
  fits the unit circle (star tips may reach 1.05). Hoods, arms, domes extend beyond it.
* **View mapping** (both renderers, see `CanonicalSpace`):
  `R = 0.5 · min(w, h) · design.frame.radiusScale`,
  origin in view points = `(w/2, h/2 − design.frame.centerOffsetY · R)` (view y is down).
  The Metal shader does the same in normalized device coordinates using `layoutE.y/.z`.
* **Body transform order**: scale (`scaleX`, `scaleY`) about the anchor → rotate by `tilt` about the
  anchor → translate by `(offsetX, offsetY)`. Anchor = `(0, −1)` (feet) for grounded designs
  (no `.floats`), `(0, 0)` for floaters.
* **Head transform**: face features are additionally rotated by `face.headTilt` about `(0, face.faceOffsetY)`,
  shifted by `(0.10 · headTurn, 0.06 · headNod)`, and the eye on the far side of a turn is foreshortened:
  `rx · (1 − 0.15 · |headTurn|)` for the eye in the direction opposite to `headTurn`.
* **Clock**: rig time **is** `CACurrentMediaTime()` (seconds, monotonic). Both renderers call
  `rig.pose(at: CACurrentMediaTime())` exactly once per frame. Drivers also use `CACurrentMediaTime()`
  as their reference, so speech callbacks and frames share one clock. The rig clamps
  `dt = min(time − lastTime, configuration.maxDeltaTime)`; the first call uses `dt = 0`.
* **Colours**: sRGB floats, straight alpha. Metal uses `.bgra8Unorm` (not `_srgb`) so values pass
  through unchanged and match SwiftUI `Color(.sRGB, …)`. Output of the fragment shader is
  **premultiplied** alpha over a transparent clear colour; the blend state is
  `src = .one, dst = .oneMinusSourceAlpha` for both RGB and alpha.

## 3. Face & body geometry (shared by Metal and Canvas — the two must look the same)

All lengths in *R* units; `s = face.faceScale`; `oy = face.faceOffsetY`. Apply the head transform (§2) after computing positions.

### 3.1 Eyes
* Centres `(±face.eyeOffsetX·s, oy + face.eyeY·s)`; radii `rx = eyeRadiusX·s·eyeScale`, `ry = eyeRadiusY·s·eyeScale`.
* Opening `o = eyeOpen` (0…1.3): visible region = ellipse ∩ { y ≤ cy − ry + 2·ry·min(o, 1) }; for `o > 1`
  additionally scale `ry` by `o` (wide eyes). Edge of the lid is soft (anti-aliased), lid colour = body colour (no separate eyelid).
* Lower-lid squint `q = lowerLid` (0…1): visible region ∩ { y ≥ cy − ry + 2·ry·0.55·q }. Squint also lifts the
  cheek: cheek alpha += 0.3·q.
* Sclera fills the visible region (`palette.sclera`; for `.darkFace` designs the sclera is `palette.accent` and the iris glows: add `0.6·iris` colour as an outer halo of radius `1.6·irisR`).
* Iris centre = eye centre + `gaze · (rx − irisR, ry − irisR) · 0.85` (so it never leaves the eye); `irisR = face.irisRadius·s·eyeScale`.
  Iris is a radial gradient: `palette.iris` at the centre → 35 % darker at the rim; thin dark limbal ring (`palette.pupil` α 0.35, width 0.015).
* Pupil radius `face.pupilRadius·s·eyeScale·pupil`, colour `palette.pupil`.
* Highlights (white, α 0.95): big one at `(−0.38·rx, +0.42·ry)` radius `0.30·irisR`; small one at `(+0.30·rx, −0.30·ry)` radius `0.13·irisR`.
  Highlights follow gaze at 25 %. `.eyeSparkles` adds two 4-point star highlights radius `0.12·irisR` at `(+0.1·rx, +0.1·ry)` and `(−0.2·rx, −0.35·ry)`.
* Eye outline: none, except a 1-px soft shadow (α 0.18, `palette.outline`) hugging the top lid for depth.

### 3.2 Brows
* Centre `(±face.eyeOffsetX·s, oy + face.browY·s + 0.12·raise)`, half-length `face.browLength·s/2`, thickness `face.browThickness·s`.
* Angle (radians, y up): left brow `+0.55·browTiltL`, right brow `−0.55·browTiltR` (positive tilt = inner ends up = sad/worried).
* Rendered as a capsule in `palette.outline` (α 0.9), slightly curved upwards (sagitta 0.03) — a bezier/arc in Canvas, a bent capsule or two-segment capsule in MSL.
* Raise −1 also squashes thickness ×0.8 (angry brows are flatter).

### 3.3 Mouth (viseme-driven)
Let `m = face.mouth`, `W = face.mouthWidth·s`, `H = face.mouthHeight·s`.
* Centre `(0.10·headTurn, oy + face.mouthY·s + 0.05·headNod − 0.03·m.open)`.
* Half width `w = W · (1 + 0.45·m.width) · (1 − 0.55·m.round) · (1 − 0.5·m.press)`.
* Half height `h = (0.02 + H·m.open·(1 + 0.4·m.round)) · (1 − 0.85·m.press)`.
* Boundary point at parameter θ ∈ [0, 2π):
  `x = w·cos θ`; `yBase = h·sin θ · (sin θ > 0 ? 0.70 : 1.00)` (upper lip flatter);
  `lift(x) = m.smile · 0.6·W · ((x/w)² − 0.33)`; `y = yBase + lift(x)`.
  Corners rise for smiles, the centre dips; frowns invert. Canvas: sample 32 points → smooth closed Catmull-Rom/cubic path. MSL: same warp applied inversely to the pixel (`p.y −= lift(p.x)`) then an ellipse SDF with the upper/lower asymmetry.
* Fill `palette.mouthInner`. Lip line: stroke of the boundary, `palette.outline` α 0.35, width 0.012 — fade in with `m.open` (α · min(1, m.open·8 + m.press)); when `open ≈ 0 && press ≈ 0` the mouth is just this thin line (a smile/frown curve).
* Upper teeth: band from the top of the interior down `0.45·h·m.upperTeeth`, `palette.teeth`, clipped to the mouth. Lower teeth: band from the bottom up `0.35·h·m.lowerTeeth`.
* Tongue: ellipse centred `(0, −h·(1 − 0.45·m.tongue))`, radii `(0.55·w, 0.45·h·m.tongue)`, `palette.tongue`, clipped.
* Press (`pp` viseme): the shape collapses towards a 0.02-tall line with a slight bulge of the lips (stroke width × (1 + press)).

### 3.4 Cheeks
Soft radial blobs at `(±face.cheekX·s, oy + face.cheekY·s)`, radius `face.cheekRadius·s`,
colour `palette.cheek`, alpha `0.22 + 0.6·blush + 0.3·lowerLid` (clamped to 1), Gaussian falloff.

### 3.5 Body shapes (unit silhouettes before the body transform)
* `round`: circle r = 1.
* `star`: 5 points, outer radius 1.05, inner 0.52, corner rounding 0.12, one point straight up.
* `drop`: circle r = 0.85 at (0, −0.15) smoothly joined to a tip at (0, 1.05); the tip bends with `wiggle`: tip x = 0.18·sin(wiggle). Sides are convex (bezier control points at (±0.78, 0.55)).
* `hood`: drop whose tip curls to the upper-right: tip path (0, 0.9) → (0.25, 1.25) → (0.55, 1.05), tube radius tapering 0.22 → 0.08. `.darkFace` designs draw a dark inner ellipse at (0, −0.08) radii (0.72, 0.80) in `palette.accent`.
* `cloud`: union of circles (0,0,0.75), (−0.55,−0.10,0.55), (0.55,−0.10,0.55), (−0.25,0.35,0.50), (0.30,0.40,0.48), flattened below y = −0.70; `.cloudCurl` adds a spiral curl at (−0.45, 0.75).
* `flame`: drop whose boundary radius is modulated `r·(1 + 0.06·sin(5θ + 3·wiggle) + 0.03·sin(9θ − 2·wiggle))` for θ in the upper half only; tip x also sways 0.22·sin(wiggle). `.innerFlame` draws a lighter drop at scale 0.58 offset (0, −0.18) in `palette.accent` with α 0.85.
* Shading for all shapes: vertical gradient `bodyTop` (y = +1) → `bodyBottom` (y = −1); soft highlight ellipse at (−0.35, 0.45) radii (0.35, 0.22) rotated −30°, `palette.highlight` α 0.35; rim darkening within 0.08 of the edge towards `palette.shadow` (α 0.35); outer glow = `palette.glow` with alpha `glowStrength·body.glow·exp(−d/0.35)·0.7` outside the silhouette (d = distance to edge in R units).
* Breathing: renderers add `scaleY += 0.025·breathe·idle.breathDepth`, `scaleX −= 0.015·breathe·idle.breathDepth` on top of `body.scale*`.

### 3.6 Limbs & accessories
* Arms (`.arms`): capsules from `(±0.92, −0.20)` to `(±1.32, −0.20 + 0.90·arm)`, radius 0.16, body colour (bottom gradient), slight shadow where they meet the body. Hands: circle r = 0.19 at the far end.
* Legs (`.legs`): rounded boxes 0.26 × 0.30 at `(±0.36, −1.12 + 0.25·leg)`, corner 0.1, `bodyBottom` darkened 15 %.
* Hood (`.hood`): robe behind the body — teardrop circle r = 1.28 at (0, −0.25) with a hood peak at (0, 1.38) in `palette.accent`; face opening ellipse at (0, 0.05) radii (0.80, 0.84) through which the body shows; robe front below y = −0.55 drawn **over** the body (the star peeks out of the opening). `.starPattern` sprinkles ~40 tiny stars (hash-positioned, `palette.accent2`, α 0.7) on the robe. Hood sways with `wiggle` (peak x = 0.08·sin(wiggle)).
* Book & wand (`.bookAndWand`): book = rounded rect 0.50 × 0.38, corner 0.06, at (−0.98, −0.45) rotated 15°, cover `palette.accent2`, page edge `palette.teeth`, a small glowing star on the cover (α = 0.5 + 0.5·accessory); wand = capsule (0.85, −0.30) → (1.25, 0.35) radius 0.05 in `palette.shadow` with a 4-point star at the tip, glow α = accessory2.
* Brain (`.brain`): six smooth-unioned circles forming two lobes around (0, 0.62), overall radius 0.30·(1 + 0.08·accessory), `palette.accent` with `palette.accent2` grooves; pulses with `accessory`.
* Moon mark (`.moonMark`): crescent (circle r 0.17 at (0, 0.55) minus circle r 0.14 at (0.08, 0.60)) in `palette.accent2`, glow α 0.4 + 0.6·accessory.
* Dome (`.dome`): drawn around the body: glass = circle r 1.55 at (0, 0.10) ∪ rect x ∈ [−1.55, 1.55], y ∈ [−1.30, 0.10]; fill `palette.accent2` α 0.10, rim stroke α 0.35 width 0.03, specular streak (a thin tilted capsule on the upper-left, white α 0.35), bottom reflection; base = rounded box 3.40 × 0.50 at y = −1.55 in `palette.accent` with a darker nameplate 1.10 × 0.22; fireflies = the sparkle field constrained to the dome interior with `accessory` boosting their count. Use `frame.radiusScale ≈ 0.42` so it fits.
* Leaves (`.leaves`): cap = part of the body above y = 0.35 in `palette.accent` with a scalloped lower edge (3 bumps); two leaves = ellipses 0.30 × 0.14 at (−0.25, 1.05) rotated −35° and (0.30, 1.08) rotated +40° in `palette.accent2`, wiggle ±8° with `accessory`.
* Cloud curl (`.cloudCurl`): thick spiral stroke (1.25 turns) at (−0.45, 0.75), width 0.14, body colour; bounces with `accessory2`.

### 3.7 Effects
* `tears`: two teardrops r 0.07 at (±(eyeOffsetX+0.05), eyeY − 0.35) sliding down 0.15·fract(time·0.8), colour (0.6, 0.8, 1.0), α = tears.
* `sweat`: single drop at (+0.75, +0.55), α = sweat.
* `hearts`: 3 small hearts rising from (±0.9, 0.9) with α = hearts·sin(πt).
* `zzz`: three "z" glyphs rising to the upper right (Canvas: `Text`; MSL: three small tilted rounded boxes) α = zzz.
* `question` / `exclamation`: glyph above the head at (0.75, 1.35) α = value (Canvas: Text; MSL: SDF of a "?"/"!" built from a circle+capsule).
* `sparkleBurst`: adds 20 extra sparkles radiating from the centre for 0.6 s.

### 3.8 Sparkle field (identical formula in Swift and MSL)
```
N = 40 (+20 burst)         i in 0..<N
seed  = fract(sin(i * 12.9898) * 43758.5453)
seed2 = fract(seed * 7.1 + 0.37)
T     = 2.2 + 1.8 * seed2                          // life period (s)
t     = fract(time / T + seed)                     // 0..1 life
ang   = seed * 6.2831853 + time * 0.15 * (seed2 > 0.5 ? 1 : -1)
rad   = 1.10 + 0.60 * fract(seed * 3.3)            // R units
pos   = (cos(ang) * rad, sin(ang) * rad * 0.6 + (t - 0.5) * 0.6)
size  = 0.05 * (0.6 + fract(seed * 5.5)) * sin(π t)
alpha = sin(π t) * rate                            // rate = pose.effects.sparkleRate
colour = mix(palette.glow, white, 0.5), 4-point star shape, additive blend
```
Burst particles use `rate = sparkleBurst`, `rad = 0.3 + 1.4·t`, lifetime 0.6 s.

## 4. Module APIs

### 4.1 Core (Core/Animation) — `CharacterRig` and everything that animates

```swift
@MainActor @Observable public final class CharacterRig {
    public let design: CharacterDesign
    public var configuration: RigConfiguration
    public private(set) var emotion: Emotion              // observable, changes rarely
    public private(set) var emotionIntensity: Float
    public private(set) var isSpeaking: Bool               // observable
    public private(set) var activeGesture: Gesture?        // observable
    /// Normalized look target in [-1, 1]² (x right, y up) relative to the view; nil = autonomous gaze.
    public var lookTarget: SIMD2<Float>?
    public var onSpeechEvent: ((SpeechEvent) -> Void)?
    /// Last evaluated pose. MUST be `@ObservationIgnored` so per-frame updates do not invalidate SwiftUI views.
    @ObservationIgnored public private(set) var currentPose: CharacterPose

    public init(kind: CharacterKind, configuration: RigConfiguration = RigConfiguration())
    public init(design: CharacterDesign, configuration: RigConfiguration = RigConfiguration())

    public func set(emotion: Emotion, intensity: Float = 1)
    public func play(_ gesture: Gesture)
    public func cancelGesture()
    /// Replaces the built-in speech driver as the mouth source while non-nil (e.g. AudioLevelDriver for server TTS).
    public func attach(lipSync: LipSyncSource?)
    /// Speaks with the built-in SpeechSynthesisDriver using the design's VoiceStyle and the current emotion's Prosody.
    public func speak(_ text: String, language: String? = nil)
    public func stopSpeaking()
    /// Tap reaction chosen by personality (surprisePop / giggle / shy / wink).
    public func poke()
    /// Converts a view point into `lookTarget` using `CanonicalSpace`.
    public func lookAt(viewPoint: CGPoint, in size: CGSize)
    public func clearLookTarget()
    /// Advances the simulation to `time` (CACurrentMediaTime seconds) and returns the pose. Calling twice with the same time returns the same pose.
    @discardableResult public func pose(at time: TimeInterval) -> CharacterPose
    public func reset()
}
```
Required internals (file names are suggestions, types must exist):
* `Springs.swift` — `struct Spring<V: PoseVector>` critically/under-damped second-order spring with
  `stiffness`, `damping`, `value`, `velocity`, `mutating func update(target:dt:)`; a `struct ScalarSpring`.
  Semi-implicit Euler with sub-stepping when `dt > 1/60`.
* `Noise.swift` — `enum SmoothNoise` cheap 1-D sum-of-sines noise `value(_ t: Float, seed: Float) -> Float` in −1…1, C¹-continuous.
* `EmotionProfiles.swift` — `extension EmotionProfile { public static func profile(for emotion: Emotion) -> EmotionProfile }` and `public static let neutral`; follow §6.
* `BlinkController.swift` — Poisson-ish scheduler (mean interval 3.8 s / blinkRate, 12 % double blinks), blink curve close 70 ms, hold 40 ms, open 120 ms; produces an eye-open multiplier 0…1 per eye; respects `blinkHeaviness`; no blinking for 1.2 s after entering `.surprised`.
* `GazeController.swift` — saccades every 1.5…4 s to targets within radius 0.35·gazeWander, 60 ms saccade, micro-drift noise 0.02, returns to the viewer with probability `cameraBias`; `lookTarget` overrides with a fast spring; while speaking, bias to the viewer +0.3.
* `IdleMotion.swift` — breathing (sin at `breathRate`), float bob (`idle.floatAmplitude·floatAmplitude`), wobble tilt, flicker/wiggle phase accumulation (`body.wiggle += dt·2π·(0.8 + flickerRate)`), micro-expressions every 6…14 s (tiny brow raise, quick smile, look-around, head tilt), auto-sleep after `configuration.autoSleepAfter`.
* `Gestures.swift` — `struct GestureClip { let gesture: Gesture; let duration: TimeInterval; func evaluate(u: Float) -> CharacterPose /* additive delta */ }` for all 14 gestures with smooth (C¹) curves that start and end at zero delta; `GesturePlayer` plays one clip at a time with a 120 ms cross-fade when interrupted.
* `SpeechAnimator.swift` — turns `LipSyncSample` into talking-head motion: `headNod −= 0.25·wordOnset`, brow raise `+0.15·energy`, body `offsetY += 0.015·energy`, glow `+0.15·energy`, eyes widen 1.03 on word onsets; scaled by `configuration.speechHeadMotion`. Blends the viseme mouth with the emotion's resting mouth: `mouth = viseme + emotionMouth · (1 − 0.6·open)` so smiles persist while talking.
* Pose composition order per frame: emotion springs (face/body/effects targets from the profile, stiffness × `transitionStiffness`) → idle motion (additive) → gaze → blink (multiplicative on eyeOpen) → speech animator (mouth replace + additive head motion) → gesture delta (additive) → clamp to sane ranges (eyeOpen 0…1.3, open 0…1, scale 0.5…1.6, alpha-like channels 0…1).
* Reduce Motion (`UIAccessibility.isReduceMotionEnabled` read via a `@MainActor` helper that Core can access without importing UIKit — use `#if canImport(UIKit)`; Core may import UIKit **only** inside that helper file) damps idle amplitude ×0.3 and gesture deltas ×0.5.

### 4.2 LipSync (Core/LipSync)

```swift
public struct VisemeKeyframe: Sendable, Equatable { public var time: TimeInterval; public var viseme: Viseme; public var duration: TimeInterval; public var weight: Float; public init(time:viseme:duration:weight:) }
public struct LipSyncTrack: Sendable, Equatable {
    public var keyframes: [VisemeKeyframe]      // sorted by time
    public var duration: TimeInterval
    public init(keyframes: [VisemeKeyframe])
    /// Coarticulated blend at t (relative to track start): weights from a smoothstep ramp of min(0.06 s, 40 % of the shorter neighbour), vowels dominate consonants (consonant weight × 0.8 when overlapping a vowel). Returns (mouth, energy) with energy = 0.35 + 0.65·open-ness of vowels, 0 for sil.
    public func sample(at t: TimeInterval) -> (mouth: MouthShape, energy: Float)
    public func retimed(toDuration: TimeInterval) -> LipSyncTrack
    public func shifted(by: TimeInterval) -> LipSyncTrack
}
public enum TextVisemeEstimator {
    /// Grapheme→viseme rules for Russian (Cyrillic) and English (Latin); other scripts fall back to English rules. Handles digraphs (th, sh, ch, ng, qu; Russian soft/hard signs modify the previous consonant's duration), doubled letters merge, punctuation produces `sil` pauses (comma 0.18 s, period/!/? 0.35 s, ellipsis 0.5 s), spaces 0.04 s.
    public static func visemes(forWord word: String, languageCode: String) -> [VisemeKeyframe]   // times relative to word start
    public static func track(for text: String, languageCode: String?, totalDuration: TimeInterval?) -> LipSyncTrack
    /// "ru" if the text contains Cyrillic letters, else "en".
    public static func detectLanguage(of text: String) -> String
}
@MainActor public final class LipSyncMixer: LipSyncSource {
    public init()
    public func schedule(_ track: LipSyncTrack, startingAt time: TimeInterval)   // absolute CACurrentMediaTime seconds; later schedules append/replace overlapping ranges
    public func clear()
    public var isActive: Bool
    public func sample(at time: TimeInterval) -> LipSyncSample       // includes wordOnset pulses (decay 250 ms) when a scheduled track marked as a word starts
}
@MainActor public final class SpeechSynthesisDriver: NSObject, LipSyncSource {
    public var onEvent: ((SpeechEvent) -> Void)?
    public private(set) var isSpeaking: Bool
    public override init()
    public func speak(_ text: String, languageCode: String, voice: VoiceStyle, prosody: Prosody)
    public func stop()
    public func pause()
    public func resume()
    public func sample(at time: TimeInterval) -> LipSyncSample
}
```
`SpeechSynthesisDriver` internals: owns an `AVSpeechSynthesizer`, a `LipSyncMixer`, and a nonisolated
`NSObject` delegate proxy (`AVSpeechSynthesizerDelegate`) that hops to the main actor. On
`willSpeakRangeOfSpeechString` it estimates the word's visemes and schedules them from *now* with an
adaptive seconds-per-character estimate (EMA of measured inter-word intervals, initial
`0.075 / rate` s per character for Russian, `0.065 / rate` for English), clipping each word's track
to the measured gap once the next word arrives. On `didFinish`/`didCancel` it clears the mixer and sets
`isSpeaking = false`. Voice selection: first available of `voice.preferredVoiceIdentifiers`, else the best
`AVSpeechSynthesisVoice` for the language (prefer `.premium`/`.enhanced` quality). Rate =
`AVSpeechUtteranceDefaultSpeechRate · voice.rate · prosody.rate` clamped to the min/max constants;
pitch = `voice.pitch · prosody.pitch` clamped 0.5…2.0. Activates `AVAudioSession` (`.playback`,
`.duckOthers`) lazily and deactivates on finish with `notifyOthersOnDeactivation`.

```swift
@MainActor public final class AudioLevelDriver: LipSyncSource {
    public init()
    /// Thread-safe; call from an AVAudioEngine tap or any audio thread. Computes RMS and spectral centroid (vDSP) and stores them under an OSAllocatedUnfairLock.
    nonisolated public func ingest(_ buffer: AVAudioPCMBuffer)
    public func attach(to engine: AVAudioEngine, node: AVAudioNode, bus: AVAudioNodeBus = 0)   // installs a tap that calls ingest
    public func detach()
    public func sample(at time: TimeInterval) -> LipSyncSample   // maps loudness→open, centroid→(ih/e vs oh/ou), with attack 30 ms / release 90 ms smoothing
}
public struct TimedWord: Sendable, Equatable { public var text: String; public var start: TimeInterval; public var end: TimeInterval; public init(text:start:end:) }
@MainActor public final class TimedTranscriptDriver: LipSyncSource {
    public init(words: [TimedWord], languageCode: String)
    public func start(at time: TimeInterval)   // absolute clock time that corresponds to transcript time 0
    public func stop()
    public func sample(at time: TimeInterval) -> LipSyncSample
}
```

### 4.3 Characters

```swift
public enum CharacterCatalog {
    public static func design(for kind: CharacterKind) -> CharacterDesign
    public static var all: [CharacterDesign] { get }      // in CharacterKind.presentationOrder
    public static let lumi: CharacterDesign
    public static let spark: CharacterDesign
    public static let nox: CharacterDesign
    public static let lumie: CharacterDesign
    public static let ember: CharacterDesign
    public static let drop: CharacterDesign
    public static let puff: CharacterDesign
    public static let sprout: CharacterDesign
    /// Suggested app background gradient (top, bottom) per character.
    public static func backgroundColors(for kind: CharacterKind) -> (top: SIMD4<Float>, bottom: SIMD4<Float>)
}
```
Follow §5 exactly (palettes, features, layouts). One file per character plus `CharacterCatalog.swift`.

### 4.4 Metal

```swift
public enum MetalAvailability { public static var isSupported: Bool { get } }   // MTLCreateSystemDefaultDevice() != nil, cached
public struct CharacterMetalView: View {
    public init(rig: CharacterRig, preferredFramesPerSecond: Int = 60, isPaused: Bool = false)
    public var body: some View { get }
}
```
Internals: `UIViewRepresentable` wrapping `MTKView` (`isOpaque = false`, `layer.isOpaque = false`,
`backgroundColor = .clear`, `clearColor = (0,0,0,0)`, `colorPixelFormat = .bgra8Unorm`, `framebufferOnly = true`,
`enableSetNeedsDisplay = false`, `isPaused` bound, `preferredFramesPerSecond` bound, `contentScaleFactor = screen scale`).
`CharacterMetalRenderer: NSObject, MTKViewDelegate` (`@MainActor`, delegate methods `nonisolated` +
`MainActor.assumeIsolated`): per device cache of `MTLLibrary` + pipeline states (static dictionary keyed by
`ObjectIdentifier(device)`), triple-buffered uniforms (`MTLBuffer` ring of 3 × 560 bytes, or `setFragmentBytes`
since 560 B < 4 KB — `setFragmentBytes` is preferred), one full-screen triangle draw for the character and one
instanced draw (60 instances) for sparkles; no per-frame allocations. Library loading order:
1. `device.makeDefaultLibrary(bundle: Bundle.module)`; 2. `device.makeDefaultLibrary()`;
3. `device.makeLibrary(source: CharacterShaderSource.msl, options: nil)` (fallback). Shader file
`Metal/Shaders/CharacterShaders.metal`; `Metal/CharacterShaderSource.swift` holds the identical source as a
raw string literal (`#"""…"""#`); a test asserts they are byte-identical.
Shader entry points: `characterVertex`, `characterFragment`, `sparkleVertex`, `sparkleFragment`.
`struct CharacterUniforms` in MSL mirrors §RenderContract exactly (35 float4, same names, same order);
bound at fragment buffer index 0 (`[[buffer(0)]]`) and vertex buffer index 0 for sparkles.
Blending: premultiplied over transparent (§2). Anti-aliasing with `fwidth`.
The view calls `rig.pose(at: CACurrentMediaTime())` in `draw(in:)` and builds `CharacterUniforms(pose:design:viewportSize:time:)`.
Pauses when `isPaused` or the view's window is nil.

### 4.5 Canvas (SwiftUI renderer) + facade

```swift
public enum CanvasQuality: String, CaseIterable, Sendable { case balanced, high }
public struct CharacterCanvasView: View {
    public init(rig: CharacterRig, quality: CanvasQuality = .high, isPaused: Bool = false)
}
public struct CharacterView: View {    // facade: picks Metal if available and requested
    public init(rig: CharacterRig, renderer: CharacterRenderer = .automatic, isPaused: Bool = false)
}
enum CharacterPainter { static func draw(pose: CharacterPose, design: CharacterDesign, in context: inout GraphicsContext, size: CGSize, quality: CanvasQuality) }  // internal, pure function
```
`CharacterCanvasView` = `TimelineView(.animation(minimumInterval: 1.0/60.0, paused: isPaused)) { _ in Canvas { ctx, size in … } }`;
inside the Canvas closure call `rig.pose(at: CACurrentMediaTime())` and `CharacterPainter.draw`.
Do **not** read any observable rig property in `body` (only inside the Canvas closure). `.high` quality draws
the glow with a blurred layer (`GraphicsContext.addFilter(.blur(radius:))` inside `drawLayer`), `.balanced`
uses a radial gradient halo. Paths are built in unit space and transformed with `CGAffineTransform`
(scale R, flip y, translate to origin). Add `accessibilityLabel` = "<name>, <emotion>".

### 4.6 Story

```swift
public struct StorySegment: Sendable, Equatable, Identifiable { public let id: Int; public var text: String; public var emotion: Emotion?; public var gesture: Gesture?; public var pauseAfter: TimeInterval }
public struct StoryScript: Sendable, Equatable {
    public var title: String; public var languageCode: String; public var segments: [StorySegment]
    /// Tag grammar inside the text: `[happy]` (any Emotion rawValue), `[gesture:wave]` (any Gesture rawValue), `[pause:0.6]`, `[br]` = new segment. Sentences are split on . ! ? … ; tags apply to the segment that follows them.
    public static func parse(_ tagged: String, title: String, languageCode: String) -> StoryScript
    public var plainText: String { get }
}
public struct Story: Sendable, Identifiable, Codable, Equatable { public var id: String; public var title: String; public var languageCode: String; public var narrator: CharacterKind; public var summary: String; public var ageRange: String; public var tagged: String; public var script: StoryScript { get } }
public enum StoryLibrary { public static func bundledStories() -> [Story] }   // decodes Resources/Stories/*.json from Bundle.module; never crashes on a bad file (skips it)
public struct StoryPrompt: Sendable, Equatable { public var heroName: String; public var setting: String; public var theme: String; public var languageCode: String; public var narrator: CharacterKind }
public protocol StoryGenerating: Sendable { func generateStory(_ prompt: StoryPrompt) async throws -> Story }
public struct TemplateStoryGenerator: StoryGenerating { public init(); ... }    // offline: 6–8 sentence tale assembled from templates with emotion/gesture tags, ru + en
@MainActor @Observable public final class StoryPlayer {
    public enum State: Sendable, Equatable { case idle, playing, paused, finished }
    public private(set) var state: State
    public private(set) var story: Story?
    public private(set) var segmentIndex: Int
    public private(set) var spokenRange: NSRange?          // current word within segment text
    public var progress: Double { get }
    public init(rig: CharacterRig)
    public func load(_ story: Story)
    public func play(); public func pause(); public func resume(); public func stop(); public func skipForward(); public func skipBackward()
}
```
Bundled stories: at least 3 Russian and 1 English original short tales (8–14 sentences) with varied
emotion/gesture tags, each starring a different narrator. JSON shape = `Story` fields.

### 4.7 App (LumiTales target)

* `LumiTalesApp` (`@main`), `RootView` (TabView: Showcase, Stories), `AppTheme` (night-sky gradients per
  character via `CharacterCatalog.backgroundColors`, Liquid Glass styling where confident: `.glassEffect()`,
  `.buttonStyle(.glass)`, `GlassEffectContainer`).
* **Showcase**: horizontal character carousel (8 cards with live mini-`CharacterView`s paused until visible),
  big stage with `CharacterView`, tap → `poke()`, drag → `lookAt`, renderer segmented control (Metal /
  SwiftUI / Auto), emotion grid (14), gesture bar (14), speech panel (TextField + "Say" + sample phrases ru/en +
  stop), quality toggle for Canvas, FPS badge (count frames inside a `TimelineView` or `CADisplayLink`).
* **Stories**: list of bundled stories + "Generate" form (`StoryPrompt`) → `StoryPlayerView`: character on top,
  karaoke text (current segment, spoken word highlighted using `spokenRange`), controls, progress.
* Scene-phase handling: pause renderers in background.
* No third-party dependencies. No network.

## 5. Character design bible

Shared cuteness rules: eyes big and low on the face, irises ≥ 70 % of the eye, two highlights, small mouth
low, visible blush, soft gradients, squash & stretch, always-glowing. Colours as `0xRRGGBB`.

| kind | body | features | palette (bodyTop, bodyBottom, highlight, shadow, accent, accent2, iris, pupil, sclera, cheek, glow, mouthInner, tongue, teeth, outline) |
|---|---|---|---|
| lumi | star | hood, bookAndWand, starPattern, floats | FFE066, FFB224, FFF6C2, E08A12, 1E1748, 7B5CFF, 2B1B12, 120A06, FFFFFF, FFB088, FFD36A, 5A2415, FF7E8A, FFFFFF, 4A2A10 |
| spark | drop | brain, arms, legs, jelly | FFE873, FFC531, FFF8D0, E79A1A, B9A0EC, 8E6FD6, 4A2A6E, 1D0F33, FFFFFF, FF9FB0, FFD866, 6B2E4A, FF8DA1, FFFFFF, 6A3E12 |
| nox | hood | darkFace, moonMark, floats, eyeSparkles | FF6AD5, 4C5BFF, FFD0F5, 2B1E78, 150B33, FFF1B5, B86BFF, 1A0A33, 2A1550, FF7FD8, B06CFF, 0E0620, FF6FAE, FFFFFF, 2A1550 |
| lumie | flame | dome, flicker, innerFlame, floats | FFE07A, FFB13D, FFF9DC, E68A1E, 7A4E2A, DFF5FF, 3B2412, 140B05, FFFFFF, FFA573, FFC95A, 6A2E1A, FF8E8E, FFFFFF, 5C3A14 |
| ember | flame | arms, legs, flicker, innerFlame | FFD93D, FF7A1A, FFF3B0, D8450C, FFF0A0, FF4D1C, 5A2E0F, 1A0A02, FFFFFF, FF8A6A, FF9A3A, 6E1E12, FF6B6B, FFFFFF, 7A3A10 |
| drop | drop | arms, legs, jelly | 7FD8FF, 2A8CFF, E6F9FF, 1E5BD6, BDEBFF, 1266D1, C04B6E, 2A0C1A, FFFFFF, FF9FC0, 6FC3FF, 1E3F8A, FF7FA3, FFFFFF, 1B4FA8 |
| puff | cloud | arms, legs, cloudCurl, floats | FFFFFF, D9E2F5, FFFFFF, A9B6D9, EEF3FF, C6D2F0, 4E7BFF, 142152, FFFFFF, FFA3C2, E0ECFF, 3B3F7A, FF86A8, FFFFFF, 7F8DB3 |
| sprout | round | arms, legs, leaves | D9893C, 9C5A22, F3C58C, 6E3B12, 6DBE45, 3F9A2E, 7A4414, 1C0C03, FFFFFF, FF9E7E, B7E07A, 5A2A10, FF8080, FFFFFF, 4F2A0E |

Per-character notes:
* **Lumi** (ref 1): face centred in the star (`eyeOffsetX 0.30, eyeY 0.05, eyeRadius 0.17×0.20, mouthY −0.28, mouthWidth 0.18, cheekX 0.40`), `frame.radiusScale 0.50`, `centerOffsetY −0.05`. Idle: hood sway, book glow breathing, wand sparkles, gentle float (0.03). Personality: warm storyteller — energy 0.5, curiosity 0.7. Voice pitch 1.15, rate 0.95. Signature: on `.thinking` taps the wand to the chin (accessory2 pulses), on `.excited` star tips flare (glow 1.6).
* **Spark** (ref 2): `eyeOffsetX 0.36, eyeY −0.02, eyeRadius 0.21×0.25, irisRadius 0.165, mouthY −0.42, mouthWidth 0.16`, brain at the top; `frame.radiusScale 0.56`. Idle: jelly wobble, flame tip wiggle. Personality: bright, curious — energy 0.7, curiosity 0.9, playfulness 0.7. Voice pitch 1.35, rate 1.0. Signature: `.thinking` → brain pulses (accessory 1) and glows; `.excited` → tip wiggles 2× faster.
* **Nox** (ref 3): eyes huge and glowing: `eyeRadius 0.26×0.28, irisRadius 0.22, pupilRadius 0.11, eyeOffsetX 0.36, eyeY −0.05, mouthY −0.45, mouthWidth 0.12`, face dark; `frame.radiusScale 0.56, centerOffsetY −0.1`. Idle: slow float 0.05, stardust trail (sparkleRate 0.6). Personality: mysterious, gentle — energy 0.35, shyness 0.5. Voice pitch 1.05, rate 0.9. Signature: moon mark brightens with emotion arousal; eyes dim when `.sleepy`.
* **Lumie** (ref 4): small flame in a jar: `frame.radiusScale 0.40, centerOffsetY 0.25`; face `eyeRadius 0.19×0.22, eyeY 0.0, mouthY −0.38`. Idle: flicker 1.2 Hz, fireflies (sparkleRate 0.7 confined to the dome), float 0.04. Personality: cosy, sleepy-ish — energy 0.4, shyness 0.3. Voice pitch 1.25, rate 0.9. Signature: `.happy/.love` → dome fills with fireflies (accessory 1); `.scared` → flame shrinks (scale 0.85).
* **Ember**: `eyeRadius 0.20×0.23, eyeY 0.0, mouthY −0.38, mouthWidth 0.24` (big open-mouth smiles), legs; flicker 1.6 Hz. Personality: energetic — energy 0.9, playfulness 0.8. Voice pitch 1.2, rate 1.1.
* **Drop**: `eyeRadius 0.21×0.24, mouthWidth 0.22`; jelly wobble strong (idle.wobbleAmplitude 0.05). Personality: cheerful — energy 0.6, playfulness 0.7. Voice pitch 1.3, rate 1.0.
* **Puff**: cloud `eyeOffsetX 0.42, eyeY 0.02, eyeRadius 0.20×0.23`, floats 0.05 at 0.6 Hz. Personality: dreamy — energy 0.45, curiosity 0.6. Voice pitch 1.4, rate 0.95 (airy).
* **Sprout**: `eyeY 0.02, eyeRadius 0.21×0.24, mouthY −0.36`, cap + leaves. Personality: calm, kind — energy 0.4, shyness 0.4. Voice pitch 1.1, rate 0.9.

Background gradients (top → bottom): lumi 1B1240→3A1F6E, spark 2E1A5E→4A2A8A, nox 0B0624→2B1458, lumie 0E1B2E→223B5A, ember 2A0F1E→5A1F28, drop 0E2A4A→1E4E8A, puff 2A2E55→4F5A9A, sprout 13261A→2E5A32.

## 6. Emotion design guide (targets for `EmotionProfile.profile(for:)`)

| emotion | eyes (open, scale, pupil, lowerLid) | brows (raise L/R, tilt L/R) | mouth (smile, open, width) | body | effects / idle |
|---|---|---|---|---|---|
| neutral | 1.0, 1.0, 1.0, 0 | 0, 0 / 0, 0 | 0.25, 0, 0 | — | sparkle 0.35 |
| happy | 1.0, 1.0, 1.05, 0.35 | 0.2, 0.2 / −0.1, −0.1 | 0.85, 0.08, 0.3 | scaleY 1.02, glow 1.15 | blush 0.4, energy 0.6 |
| excited | 1.15, 1.08, 1.3, 0.1 | 0.6, 0.6 / 0, 0 | 0.9, 0.35, 0.4 | scaleY 1.05, glow 1.5, bounce idle | sparkle 0.8, energy 1.0, stiffness 1.6 |
| laughing | 0.15, 1.0, 1.0, 0.9 | 0.3, 0.3 / −0.2, −0.2 | 1.0, 0.55, 0.5 | tilt ±, scaleY 0.97, head back (headNod 0.3) | blush 0.5, energy 0.9, giggle bob |
| surprised | 1.3, 1.15, 0.75, 0 | 0.9, 0.9 / 0.1, 0.1 | 0.0, 0.5, −0.3 (round 0.7) | scaleY 1.06 scaleX 0.97 | exclamation 1, stiffness 2.5, no blink 1.2 s |
| curious | 1.05, 1.0, 1.1, 0 | 0.5, 0.0 / 0, 0 (asymmetric) | 0.3, 0.1, 0 | headTilt 0.18, tilt 0.06 | question 0.8, gazeWander 0.8 |
| thinking | 0.85, 1.0, 1.0, 0.1 | 0.3, −0.2 / 0.2, 0 | 0.1, 0.0, −0.3 (pucker) | headTilt −0.12, gaze up-right (0.45, 0.4) | question 0.5, energy 0.3 |
| sad | 0.7, 1.0, 1.1, 0.0 | −0.1, −0.1 / 0.8, 0.8 | −0.6, 0.05, −0.2 | offsetY −0.05, scaleY 0.96, tilt 0, head down (headNod −0.3) | tears 0.6, glow 0.7, energy 0.15, stiffness 0.5 |
| scared | 1.25, 1.1, 0.7, 0 | 0.7, 0.7 / 0.6, 0.6 | −0.3, 0.3, 0.4 (wobbly) | scaleX 0.95 scaleY 0.95, offsetY −0.03, trembling idle (noise ×3) | sweat 0.8, glow 0.8, stiffness 2.0 |
| sleepy | 0.35, 1.0, 1.0, 0.2 | −0.15, −0.15 / 0.3, 0.3 | 0.1, 0.0, −0.1 | offsetY −0.04, tilt 0.1, head down −0.25, breath slow 0.12 Hz deep | zzz 0.8, glow 0.6, energy 0.1, blink heavy 0.55 |
| grumpy | 0.75, 1.0, 0.85, 0.3 | −0.7, −0.7 / −0.8, −0.8 | −0.5, 0.0, −0.3 | scaleX 1.04 scaleY 0.97, arms down −0.4 | glow 0.9, energy 0.35, hue shift −0.03 |
| shy | 0.85, 1.0, 1.15, 0.25 | 0.3, 0.3 / 0.4, 0.4 | 0.45, 0.0, −0.2 | headTurn −0.4, headTilt 0.15, offsetX −0.04, arms up 0.3 (hands to face) | blush 1.0, energy 0.3, cameraBias 0.2 |
| love | 0.9, 1.05, 1.45, 0.3 | 0.4, 0.4 / 0.3, 0.3 | 0.8, 0.1, 0.1 | scaleY 1.03, glow 1.4, float ×1.5 | hearts 1, blush 0.8, hue shift +0.04 |
| listening | 1.05, 1.0, 1.05, 0 | 0.35, 0.35 / 0, 0 | 0.4, 0.05, 0.1 | headTilt 0.12, lean in offsetY 0.02 | cameraBias 0.95, blink 0.8, energy 0.35 |

Intensity `k` (0…1) in `set(emotion:intensity:)` interpolates the profile from `neutral`.

## 7. Lip-sync quality requirements

* Visemes drive jaw, width, rounding, teeth, tongue and lip press (never only `open`).
* Coarticulation: neighbouring visemes overlap; no frame-to-frame jumps > 0.35 in any mouth channel.
* Word onsets produce `wordOnset` pulses (talking-head nods, brow emphasis); sentence-final punctuation
  closes the mouth within 120 ms; questions raise the brows on the last word.
* Works with three sources: on-device TTS (AVSpeechSynthesizer word callbacks), external audio
  (amplitude + spectral centroid), and server word timings (`TimedTranscriptDriver`).
* Russian and English grapheme rules; unknown scripts degrade gracefully (English rules).

## 8. Performance requirements

* Metal: one full-screen triangle + one instanced sparkle draw; `setFragmentBytes` for the 560-byte
  uniforms; no per-frame allocations; shader ≤ ~400 ALU ops per pixel; pauses offscreen/background.
* Canvas: ≤ ~60 paths per frame, paths sampled with ≤ 48 points, gradients created from palette
  (`Gradient` values can be cached per design in a static dictionary keyed by `CharacterKind`), blur
  only for `.high` glow; `TimelineView` paused when `isPaused`.
* Rig: `pose(at:)` is O(1) with no allocations; springs are stable for `dt ≤ 1/15`.

## 9. Tests (Tests/StoryCharactersTests)

XCTest. Each module adds a file: PoseVector arithmetic; `MemoryLayout<CharacterUniforms>.stride == 560`;
viseme table ranges; estimator produces vowels for "мама"/"hello"; `LipSyncTrack.sample` continuity
(step 1/120 s, max channel delta < 0.35); spring convergence; rig smoothness when switching emotions
every 0.5 s at 60 fps (max per-frame delta on `eyeOpen`, `mouth.open`, `scaleY` below 0.25); gesture
clips start/end at zero delta; `StoryScript.parse` tags; `StoryLibrary.bundledStories().count >= 4`;
catalog has all 8 kinds, every palette alpha == 1 except where documented; shader source parity.
Tests must not require a GPU, a window or audio hardware.
