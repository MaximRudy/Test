import Foundation

/// Turns a `LipSyncSample` into a talking head.
///
/// * Mouth: `mouth = viseme + restingMouth · (1 − 0.6·open)` so the emotion's smile persists while talking.
///   While an utterance is in progress the resting mouth's *opening* channels (jaw, rounding, teeth, tongue) are
///   faded to 30 %: open-mouthed emotions (surprised, laughing, excited) would otherwise hold the mouth open in
///   every pause, and sentence ends could not close it (§7). Smile, width and lip press stay whole. The speaking
///   flag is smoothed over ≈ 150 ms so the fade never pops.
/// * Head motion (scaled by `RigConfiguration.speechHeadMotion`): `headNod −= 0.25·wordOnset`,
///   brows `+0.15·energy`, body `offsetY += 0.015·energy`, glow `+0.15·energy`, eyes widen ×1.03 on onsets,
///   plus a slow head-tilt / head-turn rhythm so long narration does not look stiff.
/// Energy and onset are lightly low-passed so steppy drivers never produce frame-to-frame jumps.
struct SpeechAnimator: Sendable, Equatable {
    /// Share of the resting mouth's opening kept while an utterance is in progress.
    static let restingOpeningWhileSpeaking: Float = 0.3
    /// Time constant of the smoothed speaking flag (seconds).
    static let speakingTau: Float = 0.15

    private var energy: Float = 0
    private var onset: Float = 0
    private var mouth: MouthShape = .zero
    /// Smoothed `isSpeaking` (0 … 1).
    private var speaking: Float = 0

    init() {}

    mutating func reset() {
        energy = 0
        onset = 0
        mouth = .zero
        speaking = 0
    }

    /// Applies the sample to `pose` (mouth replace + additive head motion).
    mutating func apply(sample: LipSyncSample, headMotion: Float, dt: Float, to pose: inout CharacterPose) {
        // Attack 30 ms / release 110 ms for energy; onsets follow quickly and release in ~100 ms.
        let eTau: Float = sample.energy > energy ? 0.03 : 0.11
        let oTau: Float = sample.wordOnset > onset ? 0.02 : 0.10
        energy += (sample.energy - energy) * (dt > 0 ? min(1, dt / eTau) : 1)
        onset += (sample.wordOnset - onset) * (dt > 0 ? min(1, dt / oTau) : 1)
        // Mouth channels: a very light smoothing (≈ 1 frame) guards against hard jumps from external sources.
        let mTau: Float = 0.018
        let mk: Float = dt > 0 ? min(1, dt / mTau) : 1
        mouth = mouth + (sample.mouth - mouth) * mk
        // The speaking weight only moves with time, so a repeated or backwards timestamp never pops the mouth.
        let speakingTarget: Float = sample.isSpeaking ? 1 : 0
        if dt > 0 {
            speaking += (speakingTarget - speaking) * min(1, dt / SpeechAnimator.speakingTau)
        }

        var resting = pose.face.mouth
        let keep = 1 - (1 - SpeechAnimator.restingOpeningWhileSpeaking) * RigCurves.clamp(speaking, 0, 1)
        resting.open *= keep
        resting.round *= keep
        resting.upperTeeth *= keep
        resting.lowerTeeth *= keep
        resting.tongue *= keep
        let open = RigCurves.clamp(mouth.open, 0, 1)
        var blended = mouth + resting * (1 - 0.6 * open)
        // Lip press (p/b/m) wins over the resting smile's opening.
        blended.open = RigCurves.clamp(blended.open * (1 - 0.7 * RigCurves.clamp(mouth.press, 0, 1)), 0, 1)
        pose.face.mouth = blended

        let k = max(0, headMotion)
        guard k > 0 else { return }
        let e = RigCurves.clamp(energy, 0, 1) * k
        let o = RigCurves.clamp(onset, 0, 1) * k
        pose.face.headNod -= 0.25 * o
        pose.face.browRaiseL += 0.15 * e
        pose.face.browRaiseR += 0.15 * e
        pose.body.offsetY += 0.015 * e
        pose.body.glow += 0.15 * e
        let widen = 1 + 0.03 * o
        pose.face.eyeOpenL *= widen
        pose.face.eyeOpenR *= widen
        // Head tilt / turn rhythm while talking (≈ 1.5° tilt and a small sideways drift at typical energy).
        pose.face.headTilt += 0.045 * e * sin(pose.time * 2.1)
        pose.face.headTurn += 0.12 * e * SmoothNoise.value(pose.time * 0.6, seed: 5.5)
    }
}
