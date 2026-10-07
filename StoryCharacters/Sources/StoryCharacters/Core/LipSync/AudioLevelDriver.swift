import Foundation
import AVFoundation
import Accelerate
import QuartzCore
import os

/// Lip-sync from external audio (server TTS, music, microphone).
///
/// `ingest(_:)` (any thread, e.g. an `AVAudioEngine` tap) splits each buffer into ~10 ms blocks and measures every
/// block's loudness (RMS, vDSP) and spectral centroid (512-point FFT over 100 Hz ... 8 kHz, in Hz, so the result
/// does not depend on the sample rate). The blocks are queued under an `OSAllocatedUnfairLock` and replayed on the
/// rig clock from the moment their buffer arrives. iOS delivers tap buffers only every ~100 ms, so this keeps
/// syllable-rate jaw motion visible; the cost is that the mouth trails the audio by about one tap buffer.
///
/// `sample(at:)` maps loudness → jaw opening and centroid → front (`ih`/`e`) versus back (`oh`/`ou`) vowels with
/// attack 30 ms / release 90 ms smoothing, and derives word-onset pulses from loudness rises. When buffers stop
/// arriving the input counts as silence 30 ms after the last queued block.
@MainActor
public final class AudioLevelDriver: LipSyncSource {

    private let blocks = OSAllocatedUnfairLock(initialState: AudioBlockRing())
    private let analyzer = SpectralCentroidAnalyzer()
    /// Node and bus of the installed tap (a Sendable `let`, so `deinit` can remove the tap).
    private let tap = TapRegistration()

    // Smoothed values (main actor).
    private var loudness: Float = 0
    private var brightness: Float = 0.5
    private var lastSampleTime: TimeInterval?
    private var lastLoudTime: TimeInterval = -1
    private var onsetTime: TimeInterval = -1
    private var belowOnsetThreshold = true

    private static let attack: Float = 0.030
    private static let release: Float = 0.090
    private static let brightnessTau: Float = 0.06
    private static let onsetDecay: TimeInterval = 0.25
    private static let onsetHigh: Float = 0.30
    private static let onsetLow: Float = 0.12
    private static let speakingHold: TimeInterval = 0.25
    /// Requested tap size (iOS usually delivers ~100 ms buffers regardless; `ingest` handles any size).
    private static let tapBufferSize: AVAudioFrameCount = 1024

    private static let backQuiet = Viseme.ou.shape
    private static let backLoud = Viseme.oh.shape
    private static let frontQuiet = Viseme.ih.shape
    private static let frontLoud = Viseme.e.shape

    public init() {}

    deinit {
        // A tap left behind would make the next `installTap` on that bus raise an exception.
        tap.remove()
    }

    // MARK: Ingest (any thread)

    /// Analyses a float PCM buffer (RMS and spectral centroid per ~10 ms block) and queues the blocks under a lock.
    /// Safe to call from an audio tap thread; call it at the audio's real-time pace. Integer formats are ignored.
    nonisolated public func ingest(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channels = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate
        guard channelCount > 0, sampleRate > 0, sampleRate.isFinite else { return }
        let stride = buffer.stride
        let now = CACurrentMediaTime()

        // ~10 ms blocks, but never more than `maxBlocksPerBuffer` blocks per buffer.
        let maxBlocks = AudioLevelTuning.maxBlocksPerBuffer
        let nominalFrames = max(16, Int((sampleRate * AudioLevelTuning.blockSeconds).rounded()))
        let blockFrames = max(nominalFrames, (frameCount + maxBlocks - 1) / maxBlocks)
        let channelScale = 1 / Float(channelCount)
        let halfWindow = SpectralCentroidAnalyzer.size / 2

        var levels = SIMD64<Float>(repeating: 0)
        var centroids = SIMD64<Float>(repeating: 0)
        var blockCount = 0
        var blockStart = 0
        while blockStart < frameCount && blockCount < maxBlocks {
            let length = min(blockFrames, frameCount - blockStart)
            var sum: Float = 0
            var channel = 0
            while channel < channelCount {
                var rms: Float = 0
                vDSP_rmsqv(channels[channel] + blockStart * stride, stride, &rms, vDSP_Length(length))
                sum += rms
                channel += 1
            }
            let level = sum * channelScale
            levels[blockCount] = level
            if level > AudioLevelTuning.voicedLevel {
                // Analysis window centred on the block, kept inside the buffer (zero-padded only when the whole
                // buffer is shorter than the window).
                let windowEnd = min(frameCount, max(SpectralCentroidAnalyzer.size, blockStart + length / 2 + halfWindow))
                centroids[blockCount] = analyzer.centroid(of: channels, channelCount: channelCount, stride: stride,
                                                          endFrame: windowEnd, sampleRate: sampleRate)
            }
            blockCount += 1
            blockStart += length
        }

        let queuedLevels = levels
        let queuedCentroids = centroids
        let queuedCount = blockCount
        let blockDuration = Double(blockFrames) / sampleRate
        let bufferDuration = Double(frameCount) / sampleRate
        blocks.withLock { ring in
            ring.enqueue(levels: queuedLevels, centroids: queuedCentroids, count: queuedCount,
                         blockDuration: blockDuration, bufferDuration: bufferDuration, now: now)
        }
    }

    // MARK: Engine tap

    /// Installs a tap on `node` that feeds `ingest`. The caller owns and starts the engine. Does nothing when the
    /// node's output format is not configured yet (sample rate or channel count 0).
    public func attach(to engine: AVAudioEngine, node: AVAudioNode, bus: AVAudioNodeBus = 0) {
        detach()
        let format = node.outputFormat(forBus: bus)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        node.installTap(onBus: bus, bufferSize: AudioLevelDriver.tapBufferSize, format: format,
                        block: AudioLevelDriver.makeTapBlock(for: self))
        tap.set(node: node, bus: bus)
    }

    /// Removes the tap installed by `attach`.
    public func detach() {
        tap.remove()
    }

    /// Built outside the main actor so the block is never main-actor isolated: it runs on the engine's tap thread.
    nonisolated private static func makeTapBlock(for driver: AudioLevelDriver) -> AVAudioNodeTapBlock {
        return { [weak driver] buffer, _ in
            driver?.ingest(buffer)
        }
    }

    // MARK: Sampling (main actor)

    public func sample(at time: TimeInterval) -> LipSyncSample {
        guard time.isFinite else { return .silent }
        let block = blocks.withLock { ring in
            ring.lookup(at: time, tolerance: AudioLevelTuning.staleTolerance)
        }
        let rms = block.isFresh ? block.level : 0
        let voiced = block.isFresh && rms > AudioLevelTuning.voicedLevel && block.centroid > 0

        // Loudness in dBFS mapped to 0...1 (-48 dB → 0, -12 dB → 1).
        let decibels = 20 * log10(max(rms, 0.00001))
        let loudTarget = min(1, max(0, (decibels + 48) / 36))
        let brightTarget = AudioLevelTuning.brightness(forCentroid: block.centroid)

        // Attack / release smoothing. The same time sampled twice leaves the state unchanged.
        if let last = lastSampleTime, time >= last {
            if time > last {
                let dt = Float(min(time - last, 0.25))
                let tau = loudTarget > loudness ? AudioLevelDriver.attack : AudioLevelDriver.release
                loudness += (loudTarget - loudness) * (1 - exp(-dt / tau))
                if voiced {
                    brightness += (brightTarget - brightness) * (1 - exp(-dt / AudioLevelDriver.brightnessTau))
                }
            }
        } else {
            // First sample, or the clock went backwards: start from the current input.
            loudness = loudTarget
            if voiced { brightness = brightTarget }
        }
        lastSampleTime = time

        // Word onsets: a rise through the high threshold after a dip below the low one.
        if loudness < AudioLevelDriver.onsetLow {
            belowOnsetThreshold = true
        } else if belowOnsetThreshold && loudness > AudioLevelDriver.onsetHigh {
            belowOnsetThreshold = false
            onsetTime = time
        }
        var onsetPulse: Float = 0
        if onsetTime >= 0 {
            let elapsed = time - onsetTime
            if elapsed >= 0 && elapsed < AudioLevelDriver.onsetDecay {
                let remaining = Float(1 - elapsed / AudioLevelDriver.onsetDecay)
                onsetPulse = remaining * remaining
            }
        }

        if loudness > 0.03 { lastLoudTime = time }
        let speaking = loudness > 0.03 || (lastLoudTime >= 0 && time - lastLoudTime < AudioLevelDriver.speakingHold)

        // Mouth: back vowels for dark sound, front vowels for bright sound; louder = more open.
        let back = MouthShape.lerp(AudioLevelDriver.backQuiet, AudioLevelDriver.backLoud, loudness)
        let front = MouthShape.lerp(AudioLevelDriver.frontQuiet, AudioLevelDriver.frontLoud, loudness)
        var mouth = MouthShape.lerp(back, front, brightness) * loudness
        mouth.smile = 0

        return LipSyncSample(mouth: mouth, energy: loudness, isSpeaking: speaking, wordOnset: onsetPulse)
    }

    /// Resets smoothing state and drops queued analysis (e.g. when switching audio sources).
    public func reset() {
        loudness = 0
        brightness = 0.5
        lastSampleTime = nil
        lastLoudTime = -1
        onsetTime = -1
        belowOnsetThreshold = true
        blocks.withLock { ring in
            ring.removeAll()
        }
    }
}

// MARK: - Tuning

/// Constants of the audio analysis (shared by the audio thread and the main actor, hence not actor-isolated).
enum AudioLevelTuning {
    /// Analysis block length in seconds.
    static let blockSeconds: Double = 0.01
    /// Upper bound of blocks per buffer (longer buffers use longer blocks). Must not exceed `AudioBlockRing.capacity`.
    static let maxBlocksPerBuffer = 48
    /// How long after the last queued block the input still counts as present.
    static let staleTolerance: TimeInterval = 0.03
    /// Block RMS above which the spectral centroid is measured and used (≈ −50 dBFS).
    static let voicedLevel: Float = 0.003
    /// Centroid (Hz) mapped to brightness 0: back rounded vowels (u ≈ 620 Hz, o ≈ 770 Hz).
    static let darkCentroid: Float = 700
    /// Centroid (Hz) mapped to brightness 1: front vowels (e ≈ 1480 Hz, i ≈ 1550 Hz) and fricatives.
    static let brightCentroid: Float = 1600

    /// Maps a spectral centroid in Hz to 0 (oh/ou) ... 1 (ih/e).
    static func brightness(forCentroid hertz: Float) -> Float {
        guard hertz.isFinite else { return 0 }
        return min(1, max(0, (hertz - darkCentroid) / (brightCentroid - darkCentroid)))
    }
}

// MARK: - Block queue

/// One analysed block as seen by `sample(at:)`.
struct AudioBlockSample: Sendable, Equatable {
    var level: Float = 0
    var centroid: Float = 0
    var isFresh = false
}

/// Fixed-capacity FIFO of analysed ~10 ms audio blocks scheduled on the rig clock. Inline SIMD storage, so
/// queueing from the audio thread never touches the heap.
struct AudioBlockRing: Sendable {
    static let capacity = 64

    private var starts = SIMD64<Double>(repeating: 0)
    private var levels = SIMD64<Float>(repeating: 0)
    private var centroids = SIMD64<Float>(repeating: 0)
    /// Index of the oldest block.
    private var head = 0
    private(set) var count = 0
    /// Clock time at which the newest queued block ends (0 = nothing queued yet).
    private(set) var end: TimeInterval = 0

    init() {}

    mutating func removeAll() {
        head = 0
        count = 0
        end = 0
    }

    /// Queues the `count` blocks of one buffer lasting `bufferDuration` seconds. Playback starts when the previously
    /// queued audio ends, or `now` if that is earlier. If more than one buffer's worth is already waiting (the feed
    /// runs faster than real time) the queue is dropped and playback resynchronises to `now`.
    mutating func enqueue(levels newLevels: SIMD64<Float>, centroids newCentroids: SIMD64<Float>, count blockCount: Int,
                          blockDuration: TimeInterval, bufferDuration: TimeInterval, now: TimeInterval) {
        guard blockCount > 0, bufferDuration > 0 else { return }
        var start = max(now, end)
        if start - now > bufferDuration {
            removeAll()
            start = now
        }
        let n = min(blockCount, AudioBlockRing.capacity)
        var b = 0
        while b < n {
            append(start: start + Double(b) * blockDuration, level: newLevels[b], centroid: newCentroids[b])
            b += 1
        }
        end = start + bufferDuration
    }

    private mutating func append(start: TimeInterval, level: Float, centroid: Float) {
        let capacity = AudioBlockRing.capacity
        let index: Int
        if count < capacity {
            index = (head + count) % capacity
            count += 1
        } else {
            // Full: overwrite the oldest block.
            index = head
            head = (head + 1) % capacity
        }
        starts[index] = start
        levels[index] = level
        centroids[index] = centroid
    }

    /// The newest block that has started by `time`; not fresh when nothing is queued for `time` (before the first
    /// block, or more than `tolerance` after the last one ended).
    func lookup(at time: TimeInterval, tolerance: TimeInterval) -> AudioBlockSample {
        guard count > 0, time <= end + tolerance else { return AudioBlockSample() }
        var i = count - 1
        while i >= 0 {
            let index = (head + i) % AudioBlockRing.capacity
            if starts[index] <= time {
                return AudioBlockSample(level: levels[index], centroid: centroids[index], isFresh: true)
            }
            i -= 1
        }
        return AudioBlockSample()
    }
}

// MARK: - Spectral centroid

/// Magnitude-weighted spectral centroid (Hz) of a 512-point Hann-windowed FFT restricted to 100 Hz ... 8 kHz.
/// The FFT setup and scratch buffers are allocated once; `centroid(of:...)` is serialised by a lock and does not
/// allocate.
final class SpectralCentroidAnalyzer: @unchecked Sendable {
    static let log2Size: vDSP_Length = 9
    static let size = 512
    static let lowestFrequency: Double = 100
    static let highestFrequency: Double = 8000

    private let lock = NSLock()
    private let setup: FFTSetup?
    private let window: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>
    private let imag: UnsafeMutablePointer<Float>

    init() {
        let size = SpectralCentroidAnalyzer.size
        setup = vDSP_create_fftsetup(SpectralCentroidAnalyzer.log2Size, FFTRadix(kFFTRadix2))
        window = UnsafeMutablePointer<Float>.allocate(capacity: size)
        real = UnsafeMutablePointer<Float>.allocate(capacity: size / 2)
        imag = UnsafeMutablePointer<Float>.allocate(capacity: size / 2)
        window.initialize(repeating: 0, count: size)
        real.initialize(repeating: 0, count: size / 2)
        imag.initialize(repeating: 0, count: size / 2)
        var i = 0
        while i < size {
            window[i] = 0.5 - 0.5 * cos(2 * Float.pi * Float(i) / Float(size))
            i += 1
        }
    }

    deinit {
        if let setup = setup {
            vDSP_destroy_fftsetup(setup)
        }
        window.deallocate()
        real.deallocate()
        imag.deallocate()
    }

    /// Centroid of the mono mix of `channelCount` non-interleaved channels over the 512 frames that end at
    /// `endFrame` (frames before 0 count as silence; `endFrame` must not exceed the buffer length).
    /// Returns 0 for a silent window.
    func centroid(of channels: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int, stride: Int,
                  endFrame: Int, sampleRate: Double) -> Float {
        guard let setup = setup, channelCount > 0, sampleRate > 0, endFrame > 0 else { return 0 }
        lock.lock()
        defer { lock.unlock() }

        let size = SpectralCentroidAnalyzer.size
        let half = size / 2
        let start = endFrame - size
        let channelScale = 1 / Float(channelCount)
        // Window and pack even/odd samples into the split-complex layout `vDSP_fft_zrip` expects.
        var n = 0
        while n < size {
            let frame = start + n
            var value: Float = 0
            if frame >= 0 {
                var channel = 0
                while channel < channelCount {
                    value += channels[channel][frame * stride]
                    channel += 1
                }
            }
            value *= channelScale * window[n]
            if n & 1 == 0 {
                real[n >> 1] = value
            } else {
                imag[n >> 1] = value
            }
            n += 1
        }
        var split = DSPSplitComplex(realp: real, imagp: imag)
        vDSP_fft_zrip(setup, &split, 1, SpectralCentroidAnalyzer.log2Size, FFTDirection(FFT_FORWARD))

        // Bin k (1 ..< half) is (real[k], imag[k]); bin 0 packs DC and Nyquist and is skipped.
        let binWidth = sampleRate / Double(size)
        let lowBin = max(1, Int((SpectralCentroidAnalyzer.lowestFrequency / binWidth).rounded(.up)))
        let highBin = min(half - 1, Int(SpectralCentroidAnalyzer.highestFrequency / binWidth))
        guard highBin > lowBin else { return 0 }
        var weighted: Float = 0
        var total: Float = 0
        var k = lowBin
        while k <= highBin {
            let re = real[k]
            let im = imag[k]
            let magnitude = (re * re + im * im).squareRoot()
            weighted += magnitude * Float(k)
            total += magnitude
            k += 1
        }
        guard total > 1e-9 else { return 0 }
        return Float(binWidth) * weighted / total
    }
}

// MARK: - Tap bookkeeping

/// Remembers which node/bus carries the driver's tap so it can be removed from `detach()` or `deinit`.
final class TapRegistration: @unchecked Sendable {
    private let lock = NSLock()
    private weak var node: AVAudioNode?
    private var bus: AVAudioNodeBus = 0

    init() {}

    func set(node: AVAudioNode, bus: AVAudioNodeBus) {
        lock.lock()
        self.node = node
        self.bus = bus
        lock.unlock()
    }

    /// Removes the tap if one is registered; safe to call repeatedly and from any thread.
    func remove() {
        lock.lock()
        let node = self.node
        let bus = self.bus
        self.node = nil
        lock.unlock()
        node?.removeTap(onBus: bus)
    }
}
