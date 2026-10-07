import Foundation
import SwiftUI
import UIKit
import Metal
import MetalKit

/// SwiftUI view that renders a `CharacterRig` with Metal (`MTKView` + SDF shaders).
/// Transparent: the app background shows through around the character and its glow.
@MainActor
public struct CharacterMetalView: View {
    private let rig: CharacterRig
    private let preferredFramesPerSecond: Int
    private let isPaused: Bool

    public init(rig: CharacterRig, preferredFramesPerSecond: Int = 60, isPaused: Bool = false) {
        self.rig = rig
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.isPaused = isPaused
    }

    public var body: some View {
        let languageCode = Locale.current.language.languageCode?.identifier
        let label = rig.design.kind.displayName(languageCode: languageCode)
            + ", "
            + rig.emotion.displayName(languageCode: languageCode)
        return CharacterMetalRepresentable(rig: rig,
                                           preferredFramesPerSecond: preferredFramesPerSecond,
                                           isPaused: isPaused)
            .accessibilityLabel(Text(label))
    }
}

/// `MTKView` that reports window changes (for pausing offscreen) and tracks the screen scale.
@MainActor
final class CharacterMTKView: MTKView {
    var onWindowChange: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let scale = window?.screen.scale, scale > 0 {
            contentScaleFactor = scale
        }
        onWindowChange?()
    }
}

/// Bridges `CharacterMTKView` into SwiftUI; the coordinator is the renderer (CONTRACT §4.4 configuration).
@MainActor
struct CharacterMetalRepresentable: UIViewRepresentable {
    let rig: CharacterRig
    let preferredFramesPerSecond: Int
    let isPaused: Bool

    func makeCoordinator() -> CharacterMetalRenderer {
        CharacterMetalRenderer(rig: rig)
    }

    func makeUIView(context: Context) -> CharacterMTKView {
        let view = CharacterMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isOpaque = false
        view.layer.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = preferredFramesPerSecond
        view.isPaused = isPaused
        let scale = UITraitCollection.current.displayScale
        if scale > 0 {
            view.contentScaleFactor = scale
        }
        let renderer = context.coordinator
        renderer.isPaused = isPaused
        view.onWindowChange = { [weak renderer] in
            renderer?.viewDidChangeWindow()
        }
        renderer.attach(to: view)
        return view
    }

    func updateUIView(_ view: CharacterMTKView, context: Context) {
        if view.preferredFramesPerSecond != preferredFramesPerSecond {
            view.preferredFramesPerSecond = preferredFramesPerSecond
        }
        context.coordinator.isPaused = isPaused
    }

    static func dismantleUIView(_ view: CharacterMTKView, coordinator: CharacterMetalRenderer) {
        view.isPaused = true
        view.onWindowChange = nil
        view.delegate = nil
    }
}
