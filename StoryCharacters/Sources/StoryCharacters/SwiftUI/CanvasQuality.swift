import Foundation

/// Rendering quality of the SwiftUI `Canvas` renderer (CONTRACT §4.5).
///
/// * `.high` draws the body glow with a real Gaussian blur (`GraphicsContext.Filter.blur`) inside a layer.
/// * `.balanced` replaces the blur by a cheap radial-gradient halo — same colour and falloff, no filter pass.
///
/// Everything else (geometry, gradients, effects, sparkles) is identical between the two.
public enum CanvasQuality: String, CaseIterable, Sendable {
    case balanced
    case high
}
