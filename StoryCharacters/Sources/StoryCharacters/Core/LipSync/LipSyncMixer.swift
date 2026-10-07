import Foundation

/// Schedules `LipSyncTrack`s on the absolute rig clock (`CACurrentMediaTime()` seconds) and samples them.
///
/// Later schedules replace whatever they overlap: an entry that starts inside the new range is dropped, an
/// entry that started earlier is clipped to the new start (this is how TTS word tracks are trimmed to the
/// measured inter-word gap). Word onsets are inferred from the tracks (first non-silent keyframe and every
/// non-silent keyframe after a silence) and emitted as `wordOnset` pulses that decay to zero within 250 ms.
/// A slew limiter (20 units/s) keeps every mouth channel free of frame-to-frame jumps even when a word
/// track has been squeezed into a very short gap.
@MainActor
public final class LipSyncMixer: LipSyncSource {

    private struct Entry {
        var track: LipSyncTrack
        var start: TimeInterval
        var end: TimeInterval
        var energyGain: Float
    }

    private var entries: [Entry] = []
    private var onsets: [TimeInterval] = []
    private var limiter = MouthSlewLimiter()

    /// Seconds after an entry's end during which `isSpeaking` stays true (covers inter-word gaps).
    private static let speakingTail: TimeInterval = 0.12
    /// Seconds after an entry's end before it is discarded (ramp-out + speaking tail).
    private static let retention: TimeInterval = 0.25
    /// Word-onset pulse length.
    private static let onsetDecay: TimeInterval = 0.25
    private static let mouthLower = SIMD8<Float>(0, -1, -1, 0, 0, 0, 0, 0)
    private static let mouthUpper = SIMD8<Float>(repeating: 1)

    public init() {}

    /// True while at least one scheduled track is pending or playing (finished tracks are pruned by `sample(at:)`).
    public var isActive: Bool { !entries.isEmpty }

    /// Schedules `track` to start at absolute `time`. Overlapping earlier schedules are clipped or replaced.
    public func schedule(_ track: LipSyncTrack, startingAt time: TimeInterval) {
        schedule(track, startingAt: time, energyGain: 1)
    }

    /// Internal variant with an energy multiplier (questions emphasise the last word's brows via `energy`).
    ///
    /// Entries stay ordered by start and never overlap (every schedule drops the entries that start at or after
    /// `time` and clips the one before it), so only the tail is touched: amortised O(1) per call.
    func schedule(_ track: LipSyncTrack, startingAt time: TimeInterval, energyGain: Float) {
        guard !track.isEmpty, time.isFinite else { return }
        while let last = entries.last, last.start >= time {
            entries.removeLast()
        }
        if let lastIndex = entries.indices.last, entries[lastIndex].end > time {
            let clipped = entries[lastIndex].track.clipped(toDuration: time - entries[lastIndex].start)
            if clipped.isEmpty {
                entries.removeLast()
            } else {
                entries[lastIndex].track = clipped
                entries[lastIndex].end = time
            }
        }
        // Onsets are kept sorted: drop the ones the new track replaces, append its own (never before `time`).
        while let last = onsets.last, last >= time {
            onsets.removeLast()
        }
        entries.append(Entry(track: track, start: time, end: time + track.duration, energyGain: max(0, energyGain)))
        for onset in track.wordOnsetTimes {
            onsets.append(time + max(0, onset))
        }
    }

    /// Energy of an entry with gain. Gains above 1 (the last word of a question) also hold the energy near 0.95
    /// for the whole voiced part of the word, so the emphasis survives the clamp to 1 instead of only lifting
    /// already-loud vowels.
    @inline(__always)
    private static func emphasized(_ energy: Float, gain: Float) -> Float {
        guard gain > 1 else { return energy * gain }
        let emphasis = min(1, (gain - 1) / 0.35)
        let voicing = min(1, energy / 0.35)
        return max(energy * gain, 0.95 * emphasis * voicing)
    }

    /// Removes every scheduled track; the mouth closes smoothly on the next samples.
    public func clear() {
        entries.removeAll(keepingCapacity: true)
        onsets.removeAll(keepingCapacity: true)
    }

    public func sample(at time: TimeInterval) -> LipSyncSample {
        guard time.isFinite else { return .silent }
        // Prune finished entries and expired onsets (cheap: both arrays are ordered by time).
        while let first = entries.first, first.end + LipSyncMixer.retention < time {
            entries.removeFirst()
        }
        while let first = onsets.first, first + LipSyncMixer.onsetDecay + 0.05 < time {
            onsets.removeFirst()
        }

        var accumulated = SIMD8<Float>.zero
        var energy: Float = 0
        var speaking = false
        let window = LipSyncTrack.maxRampHalfWidth + 0.01
        for entry in entries {
            if entry.start - window > time { break }
            // Speaking test first: the tail (0.12 s) is longer than the sampling window (0.07 s).
            if time >= entry.start - 0.02 && time <= entry.end + LipSyncMixer.speakingTail {
                speaking = true
            }
            if entry.end + window < time { continue }
            let local = entry.track.sample(at: time - entry.start)
            accumulated += local.mouth.v
            energy += LipSyncMixer.emphasized(local.energy, gain: entry.energyGain)
        }

        var onsetPulse: Float = 0
        for onset in onsets {
            if onset > time { break }   // sorted: the rest are in the future
            let elapsed = time - onset
            if elapsed < LipSyncMixer.onsetDecay {
                let remaining = Float(1 - elapsed / LipSyncMixer.onsetDecay)
                onsetPulse = max(onsetPulse, remaining * remaining)
            }
        }

        let clamped = pointwiseMin(pointwiseMax(accumulated, LipSyncMixer.mouthLower), LipSyncMixer.mouthUpper)
        let limited = limiter.apply(clamped, at: time)
        return LipSyncSample(mouth: MouthShape(v: limited),
                             energy: min(1, max(0, energy)),
                             isSpeaking: speaking,
                             wordOnset: onsetPulse)
    }
}

// MARK: - MouthSlewLimiter

/// Rate-limits per-channel mouth motion to `unitsPerSecond` so that no frame-to-frame jump exceeds ~0.33 at
/// 60 fps (0.17 at 120 fps). After a long gap (> 0.1 s) the limit is wide enough to pass any change through.
struct MouthSlewLimiter {
    static let unitsPerSecond: Float = 20
    static let maxGap: TimeInterval = 0.1

    private var last = SIMD8<Float>.zero
    private var lastTime: TimeInterval = 0
    private var primed = false

    mutating func apply(_ target: SIMD8<Float>, at time: TimeInterval) -> SIMD8<Float> {
        guard primed else {
            primed = true
            last = target
            lastTime = time
            return target
        }
        if time == lastTime { return last }
        if time < lastTime {
            // Clock went backwards (seek / reset): accept the target as-is.
            last = target
            lastTime = time
            return target
        }
        let dt = min(time - lastTime, MouthSlewLimiter.maxGap)
        let maxStep = Float(dt) * MouthSlewLimiter.unitsPerSecond
        let delta = target - last
        let limitedDelta = pointwiseMin(pointwiseMax(delta, SIMD8<Float>(repeating: -maxStep)), SIMD8<Float>(repeating: maxStep))
        last += limitedDelta
        lastTime = time
        return last
    }

    mutating func reset() {
        primed = false
        last = .zero
        lastTime = 0
    }
}
