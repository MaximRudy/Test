import Foundation

/// Schedules and shapes blinks.
///
/// * Poisson-ish intervals with mean `3.8 s / blinkRate`, 12 % of blinks are immediately followed by a second one.
/// * Blink curve: close 70 ms → hold 40 ms → open 120 ms (all stretched by `blinkHeaviness`).
/// * `blinkHeaviness` also lets the lids rest a little lower with a slow drowsy drift.
/// * `suppress(for:)` blocks new blinks (used for 1.2 s after entering `.surprised`).
struct BlinkController: Sendable, Equatable {
    private var rng: RigRandom
    private var nextBlinkAt: Float = 1.2
    private var blinkStart: Float = 0
    private var isBlinking = false
    private var doubleBlinkPending = false
    private var suppressUntil: Float = -1
    private var pendingSuppression: Float = 0
    private var hasScheduled = false

    static let closeDuration: Float = 0.070
    static let holdDuration: Float = 0.040
    static let openDuration: Float = 0.120

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
    }

    /// Returns the eye-open multiplier (0 closed … 1 open) for `time` (rig-local seconds).
    mutating func update(time: Float, dt: Float, blinkRate: Float, heaviness: Float) -> Float {
        if pendingSuppression > 0 {
            suppressUntil = time + pendingSuppression
            pendingSuppression = 0
        }
        if !hasScheduled {
            hasScheduled = true
            nextBlinkAt = time + rng.nextFloat(in: 0.8 ... 2.4)
        }

        let heavy = min(max(heaviness, 0), 1)
        let stretch = 1 + 1.2 * heavy
        let close = BlinkController.closeDuration * stretch
        let hold = BlinkController.holdDuration * stretch
        let open = BlinkController.openDuration * stretch
        let total = close + hold + open

        // Start a blink when due (not while suppressed).
        if !isBlinking && time >= nextBlinkAt && time >= suppressUntil {
            isBlinking = true
            blinkStart = time
        }

        var multiplier: Float = 1
        if isBlinking {
            let t = time - blinkStart
            if t < close {
                multiplier = 1 - RigCurves.smoothstep(t / close)
            } else if t < close + hold {
                multiplier = 0
            } else if t < total {
                multiplier = RigCurves.smoothstep((t - close - hold) / open)
            } else {
                multiplier = 1
                isBlinking = false
                scheduleNext(after: time, blinkRate: blinkRate)
            }
        }

        // Drowsy lids: rest slightly lower and drift slowly when heaviness > 0.
        if heavy > 0 {
            let drift = 0.5 + 0.5 * sin(time * 0.9)
            let rest = 1 - 0.25 * heavy * drift
            multiplier *= rest
        }
        return multiplier
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
