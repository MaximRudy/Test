import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Main-actor access to the system "Reduce Motion" accessibility setting.
/// This is the only Core file allowed to import UIKit (see docs/CONTRACT.md §4.1).
@MainActor
enum ReduceMotion {
    /// True when the user asked for reduced motion. False on platforms without UIKit.
    static var isEnabled: Bool {
        #if canImport(UIKit) && !os(watchOS)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return false
        #endif
    }

    /// Multiplier for idle amplitude under Reduce Motion.
    static let idleScale: Float = 0.3
    /// Multiplier for gesture deltas under Reduce Motion.
    static let gestureScale: Float = 0.5
}
