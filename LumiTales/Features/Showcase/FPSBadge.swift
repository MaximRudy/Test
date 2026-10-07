import SwiftUI
import StoryCharacters

/// Frames-per-second badge labelled with the active renderer.
///
/// The figure is the rate at which the stage renderer (Metal or Canvas) actually produced poses: both
/// renderers call `rig.pose(at:)` exactly once per drawn frame, which stamps `rig.currentPose.time`. An
/// invisible `TimelineView` behind the badge, capped at 60 Hz like the renderers, samples that stamp and
/// counts how many distinct values appear per half-second window, so GPU stalls and dropped frames show up.
/// `currentPose` is `@ObservationIgnored`, so sampling it never invalidates SwiftUI; the per-tick work is one
/// `Color.clear` evaluation, and the visible glass label is re-rendered at most twice a second.
struct FPSBadge: View {
    let rig: CharacterRig
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
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: isPaused)) { timeline in
                Color.clear
                    .onChange(of: counter.tick(timeline.date.timeIntervalSinceReferenceDate,
                                               renderTime: rig.currentPose.time)) { _, measured in
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
/// `tick` returns the latest half-second average of rendered frames; it changes at most twice a second.
final class FrameCounter {
    private var frames = 0
    private var windowStart: TimeInterval = 0
    private var lastTick: TimeInterval = -1
    private var lastRenderTime: Float = -1
    private var fps = 0

    /// Registers one sampling tick at `now` and returns the most recent half-second average.
    /// `renderTime` is the renderer's latest pose timestamp; a frame is counted only when it has changed
    /// since the previous tick. A repeated `now` (the timeline content re-evaluated without a new tick)
    /// is ignored.
    func tick(_ now: TimeInterval, renderTime: Float) -> Int {
        if now == lastTick {
            return fps
        }
        lastTick = now
        let rendered = renderTime != lastRenderTime
        lastRenderTime = renderTime
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
        if rendered {
            frames += 1
        }
        if elapsed >= 0.5 {
            fps = Int((Double(frames) / elapsed).rounded())
            frames = 0
            windowStart = now
        }
        return fps
    }
}
