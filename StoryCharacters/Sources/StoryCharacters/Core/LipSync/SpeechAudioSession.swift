import Foundation
import AVFoundation

/// App-wide owner of the `AVAudioSession` activation used for speech.
///
/// `AVAudioSession` is one per app, so activation is reference-counted across every `SpeechSynthesisDriver`
/// instead of being tracked per driver. The first `acquire()` configures the session (`.playback`, `.spokenAudio`,
/// `.duckOthers`) and activates it. When the last holder calls `release()`, deactivation (with
/// `.notifyOthersOnDeactivation`) is scheduled `deactivationDelayNanoseconds` later, and any `acquire()` before then
/// cancels it. The delayed deactivation belongs to this coordinator, not to a driver. So it still runs when the
/// driver that spoke last has been deallocated, and it never stops audio that another driver started meanwhile.
@MainActor
enum SpeechAudioSession {
    /// Delay before the session is released once nobody speaks. Story playback speaks one sentence per utterance;
    /// releasing between sentences would un-duck and re-duck other apps' audio every time.
    static let deactivationDelayNanoseconds: UInt64 = 1_500_000_000

    /// Number of current holders (drivers between `speak` and the end of their utterance).
    private(set) static var userCount = 0
    /// True while the session counts as active (bookkeeping; see `controlsPlatformSession`).
    private(set) static var isActive = false
    /// When false only the bookkeeping runs and `AVAudioSession` is never touched (unit tests).
    static var controlsPlatformSession = true
    /// True only when this coordinator really activated `AVAudioSession` and must deactivate it.
    private static var platformActivated = false
    private static var deactivationTask: Task<Void, Never>?

    /// True while a delayed deactivation is scheduled.
    static var isDeactivationPending: Bool { deactivationTask != nil }

    /// Takes one hold on the session and activates it if needed. Cancels a pending deactivation.
    static func acquire() {
        userCount += 1
        cancelPendingDeactivation()
        activateIfNeeded()
    }

    /// Returns one hold. When nobody holds the session any more, deactivation is scheduled after the delay.
    static func release() {
        guard userCount > 0 else { return }
        userCount -= 1
        if userCount == 0 {
            scheduleDeactivation()
        }
    }

    private static func activateIfNeeded() {
        guard !isActive else { return }
        guard controlsPlatformSession else {
            isActive = true
            return
        }
        #if os(iOS) || os(tvOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            isActive = true
            platformActivated = true
        } catch {
            // Activation is retried on the next `acquire()`; speech still plays with the current session.
            isActive = false
        }
        #endif
    }

    private static func scheduleDeactivation() {
        cancelPendingDeactivation()
        guard isActive else { return }
        deactivationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: SpeechAudioSession.deactivationDelayNanoseconds)
            guard !Task.isCancelled else { return }
            SpeechAudioSession.deactivationTask = nil
            if SpeechAudioSession.userCount == 0 {
                SpeechAudioSession.deactivate()
            }
        }
    }

    private static func cancelPendingDeactivation() {
        deactivationTask?.cancel()
        deactivationTask = nil
    }

    private static func deactivate() {
        guard isActive else { return }
        isActive = false
        guard platformActivated else { return }
        platformActivated = false
        #if os(iOS) || os(tvOS) || os(visionOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Another player in the app may still be using the session; leaving it active is correct then.
        }
        #endif
    }
}
