import Foundation
import Metal

/// Whether a Metal device exists on this machine. Evaluated once and cached.
public enum MetalAvailability {
    private static let cachedSupport: Bool = MTLCreateSystemDefaultDevice() != nil

    /// `true` when `MTLCreateSystemDefaultDevice()` returns a device (every real iOS device and the simulator).
    public static var isSupported: Bool { cachedSupport }
}
