import SwiftUI

/// Renderer facade (CONTRACT §4.5): Metal when requested (or `.automatic` on a device that has a GPU),
/// the SwiftUI `Canvas` renderer otherwise.
public struct CharacterView: View {
    private let rig: CharacterRig
    private let renderer: CharacterRenderer
    private let isPaused: Bool

    public init(rig: CharacterRig, renderer: CharacterRenderer = .automatic, isPaused: Bool = false) {
        self.rig = rig
        self.renderer = renderer
        self.isPaused = isPaused
    }

    public var body: some View {
        if usesMetal {
            CharacterMetalView(rig: rig, preferredFramesPerSecond: 60, isPaused: isPaused)
        } else {
            CharacterCanvasView(rig: rig, quality: .high, isPaused: isPaused)
        }
    }

    private var usesMetal: Bool {
        switch renderer {
        case .metal:
            return true
        case .swiftUI:
            return false
        case .automatic:
            return MetalAvailability.isSupported
        }
    }
}
