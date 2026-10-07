import SwiftUI

/// Renderer facade (CONTRACT §4.5): Metal when it is requested (`.metal` or `.automatic`) and a GPU device exists,
/// the SwiftUI `Canvas` renderer otherwise (e.g. `.metal` on a host without Metal falls back instead of going blank).
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
        case .metal, .automatic:
            return MetalAvailability.isSupported
        case .swiftUI:
            return false
        }
    }
}
