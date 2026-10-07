import SwiftUI

/// Frames-per-second badge labelled with the active renderer.
///
/// Frames are counted in an invisible `TimelineView(.animation)` behind the badge, so the per-frame work is
/// one `Color.clear` evaluation. The visible glass label is re-rendered only when the half-second average
/// changes (at most twice a second). The figure is the SwiftUI display rate: it matches what the Canvas
/// renderer can achieve, while the Metal renderer draws on its own `MTKView` loop.
struct FPSBadge: View {
    var isPaused: Bool
    var rendererName: String

    @State private var counter = FrameCounter()
    @State private var fps: Int?

    private var fpsText: String {
        if let fps {
            return L10n.framesPerSecond(fps)
        }
        return L10n.framesPerSecondUnknown
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: rendererName)
                .foregroundStyle(.secondary)
            Text(verbatim: fpsText)
                .monospacedDigit()
        }
        .font(.system(.caption, design: .monospaced, weight: .semibold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect()
        .background {
            TimelineView(.animation(paused: isPaused)) { timeline in
                Color.clear
                    .onChange(of: counter.tick(timeline.date.timeIntervalSinceReferenceDate)) { _, measured in
                        fps = measured
                    }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.fps)
        .accessibilityValue(rendererName + ", " + fpsText)
    }
}

/// Plain reference type (deliberately not `@Observable`) so per-frame ticks never invalidate SwiftUI.
/// `tick` returns the latest half-second average; it changes at most twice a second.
final class FrameCounter {
    private var frames = 0
    private var windowStart: TimeInterval = 0
    private var lastTick: TimeInterval = -1
    private var fps = 0

    /// Registers one frame at `now` and returns the most recent half-second average.
    /// A repeated timestamp (the timeline content re-evaluated without a new frame) is not counted.
    func tick(_ now: TimeInterval) -> Int {
        if now == lastTick {
            return fps
        }
        lastTick = now
        if windowStart == 0 {
            windowStart = now
        }
        let elapsed = now - windowStart
        if elapsed > 2 || elapsed < 0 {
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
