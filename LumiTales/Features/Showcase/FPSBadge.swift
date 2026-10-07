import SwiftUI

/// Counts `TimelineView(.animation)` frames and shows a frames-per-second figure refreshed twice a second.
struct FPSBadge: View {
    var isPaused: Bool

    @State private var counter = FrameCounter()

    var body: some View {
        TimelineView(.animation(paused: isPaused)) { timeline in
            let fps = counter.tick(timeline.date.timeIntervalSinceReferenceDate)
            Text(verbatim: "\(fps) fps")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect()
                .accessibilityLabel(L10n.fps)
                .accessibilityValue(Text(verbatim: "\(fps)"))
        }
    }
}

/// Plain reference type (deliberately not `@Observable`) so per-frame ticks never invalidate SwiftUI.
final class FrameCounter {
    private var frames = 0
    private var windowStart: TimeInterval = 0
    private var fps = 0

    /// Registers one frame at `now` and returns the most recent half-second average.
    func tick(_ now: TimeInterval) -> Int {
        if windowStart == 0 {
            windowStart = now
        }
        let elapsed = now - windowStart
        if elapsed > 2 {
            // Resumed after a pause: restart the window instead of averaging over the gap.
            windowStart = now
            frames = 0
            return fps
        }
        frames += 1
        if elapsed >= 0.5 {
            fps = Int((Double(frames) / elapsed).rounded())
            frames = 0
            windowStart = now
        }
        return fps
    }
}
