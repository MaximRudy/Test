import Foundation

/// Schedules and shapes blinks.
///
/// * Poisson-ish intervals with mean `3.8 s / blinkRate`, 12 % of blinks are immediately followed by a second one.
/// * Blink curve: close 70 ms → hold 40 ms → open 120 ms (all stretched by `blinkHeaviness`). The durations are
///   latched when a blink starts, so an emotion change mid-blink never re-times it (no eyelid flutter).
/// * `blinkHeaviness` also lets the lids rest a little lower with a slow drowsy drift. The profile value switches in
///   one step, so it is low-passed by a spring before it touches the lids.
/// * `suppress(for:)` blocks new blinks (used for 1.2 s after entering `.surprised`) and re-opens a blink that is
///   still closing or shut.
struct BlinkController: Sendable, Equatable {
    private var rng: RigRandom
    private var nextBlinkAt: Float = 1.2
    private var blinkStart: Float = 0
    private var isBlinking = false
    private var doubleBlinkPending = false
    private var suppressUntil: Float = -1
    private var pendingSuppression: Float = 0
    private var hasScheduled = false
    // Phase lengths of the blink in flight (latched at its start).
    private var closeLength: Float = BlinkController.closeDuration
    private var holdLength: Float = BlinkController.holdDuration
    private var openLength: Float = BlinkController.openDuration
    /// ≥ 0 while an aborted blink re-opens from this multiplier; < 0 otherwise.
    private var reopenFrom: Float = -1
    private var reopenStart: Float = 0
    /// Blink multiplier of the previous update (before the drowsy rest factor).
    private var lastBlinkMultiplier: Float = 1
    /// Smoothed `blinkHeaviness`.
    private var heaviness = ScalarSpring(value: 0, stiffness: BlinkController.heavinessStiffness)

    static let closeDuration: Float = 0.070
    static let holdDuration: Float = 0.040
    static let openDuration: Float = 0.120
    /// Critically damped, settles in ≈ 0.7 s.
    static let heavinessStiffness: Float = 20

    init(seed: UInt64 = 7) {
        rng = RigRandom(seed: seed)
    }

    /// Prevents new blinks from starting for `duration` seconds from the next update.
    mutating func suppress(for duration: Float) {
        pendingSuppression = max(pendingSuppression, duration)
    }

    mutating func reset() {
        isBlinking = false
        doubleBlinkPending = false
        suppressUntil = -1
        pendingSuppression = 0
        hasScheduled = false
        nextBlinkAt = 1.2
        closeLength = BlinkController.closeDuration
        holdLength = BlinkController.holdDuration
        openLength = BlinkController.openDuration
        reopenFrom = -1
        reopenStart = 0
        lastBlinkMultiplier = 1
        heaviness.snap(to: 0)
    }

    /// Returns the eye-open multiplier (0 closed … 1 open) for `time` (rig-local seconds).
    mutating func update(time: Float, dt: Float, blinkRate: Float, heaviness targetHeaviness: Float) -> Float {
        if !hasScheduled {
            hasScheduled = true
            nextBlinkAt = time + rng.nextFloat(in: 0.8 ... 2.4)
        }
        heaviness.update(target: RigCurves.clamp(targetHeaviness, 0, 1), dt: dt)
        let heavy = RigCurves.clamp(heaviness.value, 0, 1)

        if pendingSuppression > 0 {
            suppressUntil = time + pendingSuppression
            pendingSuppression = 0
            doubleBlinkPending = false
            // A blink that is still closing (or shut) re-opens right away from where the lids are now.
            if isBlinking && reopenFrom < 0 && time - blinkStart < closeLength + holdLength {
                reopenFrom = lastBlinkMultiplier
                reopenStart = time
            }
        }

        // Start a blink when due (not while suppressed). Its timing is latched here.
        if !isBlinking && time >= nextBlinkAt && time >= suppressUntil {
            isBlinking = true
            blinkStart = time
            reopenFrom = -1
            let stretch = 1 + 1.2 * heavy
            closeLength = BlinkController.closeDuration * stretch
            holdLength = BlinkController.holdDuration * stretch
            openLength = BlinkController.openDuration * stretch
        }

        var multiplier: Float = 1
        if isBlinking {
            if reopenFrom >= 0 {
                let u = (time - reopenStart) / openLength
                if u >= 1 {
                    finishBlink(at: time, blinkRate: blinkRate)
                } else {
                    multiplier = reopenFrom + (1 - reopenFrom) * RigCurves.smoothstep(u)
                }
            } else {
                let t = time - blinkStart
                if t < closeLength {
                    multiplier = 1 - RigCurves.smoothstep(t / closeLength)
                } else if t < closeLength + holdLength {
                    multiplier = 0
                } else if t < closeLength + holdLength + openLength {
                    multiplier = RigCurves.smoothstep((t - closeLength - holdLength) / openLength)
                } else {
                    finishBlink(at: time, blinkRate: blinkRate)
                }
            }
        }
        lastBlinkMultiplier = multiplier

        // Drowsy lids: rest slightly lower and drift slowly when heaviness > 0.
        if heavy > 0.0001 {
            let drift = 0.5 + 0.5 * sin(time * 0.9)
            let rest = 1 - 0.25 * heavy * drift
            multiplier *= rest
        }
        return multiplier
    }

    private mutating func finishBlink(at time: Float, blinkRate: Float) {
        isBlinking = false
        reopenFrom = -1
        scheduleNext(after: time, blinkRate: blinkRate)
    }

    private mutating func scheduleNext(after time: Float, blinkRate: Float) {
        let rate = max(0.05, blinkRate)
        if doubleBlinkPending {
            doubleBlinkPending = false
            nextBlinkAt = time + 0.12
            return
        }
        let mean = 3.8 / rate
        var interval = rng.nextInterval(mean: mean, minimum: 0.6)
        if rng.chance(0.12) {
            doubleBlinkPending = true
            // Shorten a little so the pair reads as one "double blink".
            interval = max(0.6, interval * 0.8)
        }
        nextBlinkAt = time + interval
    }
}
