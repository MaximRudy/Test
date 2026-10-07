import Foundation

// MARK: - VisemeKeyframe

/// One viseme held for `duration` seconds starting at `time` (seconds relative to the track start).
/// `weight` scales the articulation amplitude (1 = full viseme shape, 0.6 = soft/unstressed).
public struct VisemeKeyframe: Sendable, Equatable {
    public var time: TimeInterval
    public var viseme: Viseme
    public var duration: TimeInterval
    public var weight: Float

    public init(time: TimeInterval, viseme: Viseme, duration: TimeInterval, weight: Float) {
        self.time = time
        self.viseme = viseme
        self.duration = duration
        self.weight = weight
    }

    /// End time of the keyframe (relative to the track start).
    public var end: TimeInterval { time + duration }
}

// MARK: - LipSyncTrack

/// A timeline of viseme keyframes with coarticulated sampling.
///
/// Neighbouring keyframes cross-fade with a smoothstep ramp centred on their shared boundary. The ramp
/// half-width is `min(0.06 s, 40 % of the shorter neighbour)` with a 0.035 s floor so that sampling at
/// 1/120 s never jumps more than ~0.3 in any mouth channel (measured worst case ≈ 0.27). Vowels dominate: a consonant overlapping a vowel
/// is attenuated to 80 %. Where keyframe weights sum to less than one (gaps, attenuated consonants) the
/// remainder is treated as silence (closed mouth), so the mouth closes naturally between words.
public struct LipSyncTrack: Sendable, Equatable {
    /// Keyframes sorted by `time`.
    public var keyframes: [VisemeKeyframe]
    /// Total length of the track in seconds (end of the last keyframe).
    public var duration: TimeInterval

    /// Largest ramp half-width (seconds). Also the look-around window used while sampling.
    static let maxRampHalfWidth: TimeInterval = 0.06
    /// Smallest ramp half-width (seconds). Guarantees continuity for very short keyframes.
    static let minRampHalfWidth: TimeInterval = 0.035

    public init(keyframes: [VisemeKeyframe]) {
        let cleaned = keyframes
            .filter { $0.duration.isFinite && $0.time.isFinite && $0.duration > 0 }
            .sorted { $0.time < $1.time }
        self.keyframes = cleaned
        var end: TimeInterval = 0
        for kf in cleaned { end = max(end, kf.end) }
        self.duration = end
    }

    /// A track with no keyframes (samples as silence).
    public static let empty = LipSyncTrack(keyframes: [])

    public var isEmpty: Bool { keyframes.isEmpty }

    /// Times (relative to the track start) at which a word begins: the first non-silent keyframe
    /// and every non-silent keyframe that directly follows a silence.
    public var wordOnsetTimes: [TimeInterval] {
        var result: [TimeInterval] = []
        var previousWasSilence = true
        for kf in keyframes {
            if kf.viseme == .sil {
                previousWasSilence = true
            } else {
                if previousWasSilence { result.append(kf.time) }
                previousWasSilence = false
            }
        }
        return result
    }

    // MARK: Sampling

    /// Coarticulated mouth at `t` seconds relative to the track start.
    /// Returns the blended `MouthShape` and a speech energy (0.35 + 0.65 · vowel open-ness, 0 for silence).
    public func sample(at t: TimeInterval) -> (mouth: MouthShape, energy: Float) {
        let count = keyframes.count
        guard count > 0, t.isFinite else { return (.zero, 0) }
        let window = LipSyncTrack.maxRampHalfWidth

        // Pass 1: how much vowel is active here (drives consonant attenuation) and the first relevant index.
        var vowelCoverage: Float = 0
        var firstIndex = -1
        var k = 0
        while k < count {
            let kf = keyframes[k]
            if kf.time - window > t { break }
            if kf.end + window >= t {
                if firstIndex < 0 { firstIndex = k }
                if kf.viseme.isVowel {
                    vowelCoverage += envelope(index: k, at: t)
                }
            }
            k += 1
        }
        guard firstIndex >= 0 else { return (.zero, 0) }
        let consonantFactor: Float = 1 - 0.2 * min(1, vowelCoverage)

        // Pass 2: weighted blend.
        var accumulated = SIMD8<Float>.zero
        var totalWeight: Float = 0
        var energy: Float = 0
        k = firstIndex
        while k < count {
            let kf = keyframes[k]
            if kf.time - window > t { break }
            if kf.end + window >= t {
                var w = envelope(index: k, at: t)
                if w > 0 {
                    let viseme = kf.viseme
                    if viseme != .sil && !viseme.isVowel { w *= consonantFactor }
                    totalWeight += w
                    if viseme != .sil {
                        let shape = viseme.shape
                        let amplitude = w * kf.weight
                        accumulated += shape.v * amplitude
                        energy += w * (0.35 + 0.65 * shape.open * kf.weight)
                    }
                }
            }
            k += 1
        }
        if totalWeight > 1 {
            let inverse = 1 / totalWeight
            accumulated *= inverse
            energy *= inverse
        }
        return (MouthShape(v: accumulated), min(1, max(0, energy)))
    }

    /// Smoothstep envelope of keyframe `index` at time `t`: rises around its start, falls around its end.
    /// Symmetric ramps on a shared boundary sum to exactly one.
    @inline(__always)
    private func envelope(index: Int, at t: TimeInterval) -> Float {
        let kf = keyframes[index]
        let d = kf.duration
        let dPrev = index > 0 ? keyframes[index - 1].duration : d
        let dNext = index + 1 < keyframes.count ? keyframes[index + 1].duration : d
        let rIn = LipSyncTrack.rampHalfWidth(d, dPrev)
        let rOut = LipSyncTrack.rampHalfWidth(d, dNext)
        let rise = LipSyncTrack.smoothstep((t - (kf.time - rIn)) / (2 * rIn))
        let fall = 1 - LipSyncTrack.smoothstep((t - (kf.end - rOut)) / (2 * rOut))
        return Float(rise * fall)
    }

    @inline(__always)
    static func rampHalfWidth(_ a: TimeInterval, _ b: TimeInterval) -> TimeInterval {
        max(minRampHalfWidth, min(maxRampHalfWidth, 0.4 * min(a, b)))
    }

    @inline(__always)
    static func smoothstep(_ x: TimeInterval) -> TimeInterval {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }

    // MARK: Transforms

    /// Uniformly rescales times and durations so the track lasts `newDuration` seconds.
    public func retimed(toDuration newDuration: TimeInterval) -> LipSyncTrack {
        guard duration > 0, newDuration > 0, newDuration.isFinite else {
            var copy = self
            copy.duration = max(0, newDuration.isFinite ? newDuration : 0)
            return copy
        }
        let scale = newDuration / duration
        var copy = self
        for i in 0..<copy.keyframes.count {
            copy.keyframes[i].time *= scale
            copy.keyframes[i].duration *= scale
        }
        copy.duration = newDuration
        return copy
    }

    /// Moves every keyframe by `offset` seconds (the duration grows/shrinks accordingly).
    public func shifted(by offset: TimeInterval) -> LipSyncTrack {
        var copy = self
        for i in 0..<copy.keyframes.count {
            copy.keyframes[i].time += offset
        }
        copy.duration = max(0, duration + offset)
        return copy
    }

    /// Cuts the track at `newDuration`: later keyframes are dropped, the crossing one is shortened.
    func clipped(toDuration newDuration: TimeInterval) -> LipSyncTrack {
        guard newDuration < duration else { return self }
        guard newDuration > 0 else { return .empty }
        var kept: [VisemeKeyframe] = []
        kept.reserveCapacity(keyframes.count)
        for kf in keyframes {
            if kf.time >= newDuration { break }
            var copy = kf
            if copy.end > newDuration { copy.duration = newDuration - copy.time }
            if copy.duration > 0 { kept.append(copy) }
        }
        var track = LipSyncTrack(keyframes: kept)
        track.duration = newDuration
        return track
    }

    /// Appends a silence keyframe at the end (used to close the mouth after sentence-final punctuation).
    func appendingSilence(_ length: TimeInterval) -> LipSyncTrack {
        guard length > 0 else { return self }
        var copy = self
        if let last = copy.keyframes.last, last.viseme == .sil {
            copy.keyframes[copy.keyframes.count - 1].duration = last.duration + length
        } else {
            copy.keyframes.append(VisemeKeyframe(time: copy.duration, viseme: .sil, duration: length, weight: 1))
        }
        copy.duration += length
        return copy
    }

    /// Concatenates `other` after this track (times of `other` are offset by this track's duration).
    func appending(_ other: LipSyncTrack) -> LipSyncTrack {
        guard !other.isEmpty else { return self }
        guard !isEmpty else { return other }
        var combined = keyframes
        combined.reserveCapacity(keyframes.count + other.keyframes.count)
        let offset = duration
        for kf in other.keyframes {
            combined.append(VisemeKeyframe(time: kf.time + offset, viseme: kf.viseme, duration: kf.duration, weight: kf.weight))
        }
        return LipSyncTrack(keyframes: combined)
    }
}
