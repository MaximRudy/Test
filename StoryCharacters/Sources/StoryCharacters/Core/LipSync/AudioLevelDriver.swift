import Foundation
import AVFoundation
import Accelerate
import QuartzCore
import os

/// Lip-sync from external audio (server TTS, music, microphone): loudness opens the jaw, spectral brightness
/// (zero-crossing rate as a cheap centroid proxy) chooses between front vowels (`ih`/`e`) and back vowels
/// (`oh`/`ou`). `ingest(_:)` is lock-protected and safe to call from an `AVAudioEngine` tap; `sample(at:)`
/// applies attack 30 ms / release 90 ms smoothing and derives word-onset pulses from loudness rises.
@MainActor
public final class AudioLevelDriver: LipSyncSource {

    /// Analysis result shared between the audio thread and the main actor.
    private struct State: Sendable {
        var rms: Float = 0
        var zeroCrossingRate: Float = 0
        var updatedAt: TimeInterval = 0
        var generation: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    private weak var engine: AVAudioEngine?
    private weak var tappedNode: AVAudioNode?
    private var tappedBus: AVAudioNodeBus = 0
    private var isTapInstalled = false

    // Smoothed values (main actor).
    private var loudness: Float = 0
    private var brightness: Float = 0.5
    private var lastSampleTime: TimeInterval?
    private var lastLoudTime: TimeInterval = -1
    private var onsetTime: TimeInterval = -1
    private var belowOnsetThreshold = true

    private static let attack: Float = 0.030
    private static let release: Float = 0.090
    /// Analysis older than this (seconds) is treated as silence.
    private static let staleAfter: TimeInterval = 0.3
    private static let onsetDecay: TimeInterval = 0.25
    private static let onsetHigh: Float = 0.30
    private static let onsetLow: Float = 0.12
    private static let speakingHold: TimeInterval = 0.25

    private static let backQuiet = Viseme.ou.shape
    private static let backLoud = Viseme.oh.shape
    private static let frontQuiet = Viseme.ih.shape
    private static let frontLoud = Viseme.e.shape

    public init() {}

    // MARK: Ingest (any thread)

    /// Computes RMS and zero-crossing rate of a float PCM buffer and stores them under a lock.
    /// Safe to call from an audio render/tap thread; integer formats are ignored.
    nonisolated public func ingest(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channels = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return }
        let stride = buffer.stride
        let length = vDSP_Length(frameCount)

        var rmsSum: Float = 0
        var crossingsSum: Float = 0
        var channel = 0
        while channel < channelCount {
            let pointer = channels[channel]
            var rms: Float = 0
            vDSP_rmsqv(pointer, stride, &rms, length)
            var lastCrossing: vDSP_Length = 0
            var crossings: vDSP_Length = 0
            vDSP_nzcros(pointer, stride, length, &lastCrossing, &crossings, length)
            rmsSum += rms
            crossingsSum += Float(crossings)
            channel += 1
        }
        let count = Float(channelCount)
        let rms = rmsSum / count
        let zcr = crossingsSum / (count * Float(frameCount))
        let now = CACurrentMediaTime()
        state.withLock { s in
            s.rms = rms
            s.zeroCrossingRate = zcr
            s.updatedAt = now
            s.generation &+= 1
        }
    }

    // MARK: Engine tap

    /// Installs a 1024-frame tap on `node` that feeds `ingest`. The caller owns and starts the engine.
    public func attach(to engine: AVAudioEngine, node: AVAudioNode, bus: AVAudioNodeBus = 0) {
        detach()
        self.engine = engine
        let format = node.outputFormat(forBus: bus)
        node.installTap(onBus: bus, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.ingest(buffer)
        }
        tappedNode = node
        tappedBus = bus
        isTapInstalled = true
    }

    /// Removes the tap installed by `attach`.
    public func detach() {
        if isTapInstalled, let node = tappedNode {
            node.removeTap(onBus: tappedBus)
        }
        isTapInstalled = false
        tappedNode = nil
        engine = nil
    }

    // MARK: Sampling (main actor)

    public func sample(at time: TimeInterval) -> LipSyncSample {
        guard time.isFinite else { return .silent }
        let snapshot = state.withLock { $0 }
        let fresh = snapshot.updatedAt > 0 && (time - snapshot.updatedAt) < AudioLevelDriver.staleAfter && (time - snapshot.updatedAt) > -1
        let rms = fresh ? snapshot.rms : 0

        // Loudness in dBFS mapped to 0...1 (-48 dB → 0, -12 dB → 1).
        let decibels = 20 * log10(max(rms, 0.00001))
        let loudTarget = min(1, max(0, (decibels + 48) / 36))
        let brightTarget = min(1, max(0, (snapshot.zeroCrossingRate - 0.02) / 0.12))

        // Attack / release smoothing.
        var dt: Float = 0
        if let last = lastSampleTime, time > last {
            dt = Float(min(time - last, 0.25))
        }
        lastSampleTime = time
        if dt <= 0 {
            loudness = loudTarget
            if fresh && rms > 0.001 { brightness = brightTarget }
        } else {
            let tau = loudTarget > loudness ? AudioLevelDriver.attack : AudioLevelDriver.release
            let alpha = 1 - exp(-dt / tau)
            loudness += (loudTarget - loudness) * alpha
            if fresh && rms > 0.001 {
                let brightAlpha = 1 - exp(-dt / 0.06)
                brightness += (brightTarget - brightness) * brightAlpha
            }
        }

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

    /// Resets smoothing state (e.g. when switching audio sources).
    public func reset() {
        loudness = 0
        brightness = 0.5
        lastSampleTime = nil
        lastLoudTime = -1
        onsetTime = -1
        belowOnsetThreshold = true
        state.withLock { s in
            s.rms = 0
            s.zeroCrossingRate = 0
            s.updatedAt = 0
        }
    }
}
