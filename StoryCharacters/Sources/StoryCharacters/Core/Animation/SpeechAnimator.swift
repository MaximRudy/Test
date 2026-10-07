import Foundation

/// Turns a `LipSyncSample` into a talking head.
///
/// * Mouth: `mouth = viseme + restingMouth · (1 − 0.6·open)` so the emotion's smile persists while talking.
/// * Head motion (scaled by `RigConfiguration.speechHeadMotion`): `headNod −= 0.25·wordOnset`,
///   brows `+0.15·energy`, body `offsetY += 0.015·energy`, glow `+0.15·energy`, eyes widen ×1.03 on onsets.
/// Energy and onset are lightly low-passed so steppy drivers never produce frame-to-frame jumps.
struct SpeechAnimator: Sendable, Equatable {
    private var energy: Float = 0
    private var onset: Float = 0
    private var mouth: MouthShape = .zero

    init() {}

    mutating func reset() {
        energy = 0
        onset = 0
        mouth = .zero
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

        let resting = pose.face.mouth
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
        // A hint of head tilt rhythm keeps long narration from looking stiff.
        pose.face.headTilt += 0.02 * e * sin(pose.time * 2.1)
    }
}
