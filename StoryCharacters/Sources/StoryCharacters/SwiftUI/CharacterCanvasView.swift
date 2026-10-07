import SwiftUI
import QuartzCore

/// Pure SwiftUI renderer (CONTRACT §4.5): a `TimelineView(.animation)` driving a `Canvas`.
///
/// The Canvas closure is the only place that touches the rig: it calls `rig.pose(at: CACurrentMediaTime())`
/// once per frame and hands the pose to `CharacterPainter.draw`. `body` reads no observable rig property,
/// so per-frame pose updates never invalidate the view hierarchy. The accessibility label
/// ("<name>, <emotion>") lives in a tiny overlay that observes `rig.emotion` on its own.
public struct CharacterCanvasView: View {
    private let rig: CharacterRig
    private let design: CharacterDesign
    private let quality: CanvasQuality
    private let isPaused: Bool
    private let name: String

    public init(rig: CharacterRig, quality: CanvasQuality = .high, isPaused: Bool = false) {
        self.rig = rig
        self.design = rig.design
        self.quality = quality
        self.isPaused = isPaused
        self.name = rig.design.kind.displayName()
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: isPaused)) { _ in
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
                let pose = rig.pose(at: CACurrentMediaTime())
                CharacterPainter.draw(pose: pose, design: design, in: &context, size: size, quality: quality)
            }
        }
        .accessibilityHidden(true)
        .overlay {
            CharacterAccessibilityOverlay(rig: rig, name: name)
        }
    }
}

/// Transparent, non-interactive overlay that carries the accessibility label. It is the only view that
/// reads `rig.emotion`, so an emotion change re-evaluates just this body.
private struct CharacterAccessibilityOverlay: View {
    let rig: CharacterRig
    let name: String

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(name), \(rig.emotion.displayName())"))
            .accessibilityAddTraits(.isImage)
    }
}
