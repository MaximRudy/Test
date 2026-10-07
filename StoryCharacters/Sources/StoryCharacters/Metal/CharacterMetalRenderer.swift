import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

/// Errors raised while building the per-device GPU objects.
enum CharacterMetalError: Error {
    case missingFunction(String)
    case commandQueueUnavailable
}

/// GPU objects shared by every renderer that draws on the same `MTLDevice`: one long-lived command queue,
/// the shader library and the two pipeline states (character over transparent, additive sparkles).
@MainActor
final class CharacterMetalResources {
    let device: MTLDevice
    let library: MTLLibrary
    let commandQueue: MTLCommandQueue
    let characterPipeline: MTLRenderPipelineState
    let sparklePipeline: MTLRenderPipelineState

    /// Pixel format of every `MTKView` driven by `CharacterMetalRenderer` (CONTRACT §2: non-sRGB so colours pass through).
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    init(device: MTLDevice, library: MTLLibrary) throws {
        self.device = device
        self.library = library
        guard let queue = device.makeCommandQueue() else {
            throw CharacterMetalError.commandQueueUnavailable
        }
        queue.label = "StoryCharacters.characters"
        self.commandQueue = queue
        guard let characterVertex = library.makeFunction(name: "characterVertex") else {
            throw CharacterMetalError.missingFunction("characterVertex")
        }
        guard let characterFragment = library.makeFunction(name: "characterFragment") else {
            throw CharacterMetalError.missingFunction("characterFragment")
        }
        guard let sparkleVertex = library.makeFunction(name: "sparkleVertex") else {
            throw CharacterMetalError.missingFunction("sparkleVertex")
        }
        guard let sparkleFragment = library.makeFunction(name: "sparkleFragment") else {
            throw CharacterMetalError.missingFunction("sparkleFragment")
        }

        // Character: premultiplied alpha over a transparent clear (src = one, dst = oneMinusSourceAlpha).
        let characterDescriptor = MTLRenderPipelineDescriptor()
        characterDescriptor.label = "StoryCharacters.character"
        characterDescriptor.vertexFunction = characterVertex
        characterDescriptor.fragmentFunction = characterFragment
        characterDescriptor.colorAttachments[0].pixelFormat = CharacterMetalResources.pixelFormat
        characterDescriptor.colorAttachments[0].isBlendingEnabled = true
        characterDescriptor.colorAttachments[0].rgbBlendOperation = .add
        characterDescriptor.colorAttachments[0].alphaBlendOperation = .add
        characterDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        characterDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        characterDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        characterDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        characterPipeline = try device.makeRenderPipelineState(descriptor: characterDescriptor)

        // Sparkles: additive colour; alpha still accumulates as a union so the layer stays premultiplied-correct.
        let sparkleDescriptor = MTLRenderPipelineDescriptor()
        sparkleDescriptor.label = "StoryCharacters.sparkles"
        sparkleDescriptor.vertexFunction = sparkleVertex
        sparkleDescriptor.fragmentFunction = sparkleFragment
        sparkleDescriptor.colorAttachments[0].pixelFormat = CharacterMetalResources.pixelFormat
        sparkleDescriptor.colorAttachments[0].isBlendingEnabled = true
        sparkleDescriptor.colorAttachments[0].rgbBlendOperation = .add
        sparkleDescriptor.colorAttachments[0].alphaBlendOperation = .add
        sparkleDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        sparkleDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        sparkleDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        sparkleDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        sparklePipeline = try device.makeRenderPipelineState(descriptor: sparkleDescriptor)
    }
}

/// Draws a `CharacterRig` into an `MTKView`: one full-screen triangle evaluates the SDF character,
/// one instanced draw (60 quads) adds the sparkle field. Zero per-frame heap allocations.
///
/// `MTKViewDelegate` callbacks are `nonisolated` and hop onto the main actor with
/// `MainActor.assumeIsolated` (MetalKit always calls them on the main thread).
@MainActor
public final class CharacterMetalRenderer: NSObject, MTKViewDelegate {
    /// The rig being drawn. `pose(at: CACurrentMediaTime())` is called exactly once per frame.
    /// `CharacterMetalView` swaps it in place when it is handed a different rig, so the view keeps its identity.
    public internal(set) var rig: CharacterRig

    /// Pauses the view's display link. The view is also paused while it has no window.
    public var isPaused: Bool = false {
        didSet { applyPauseState() }
    }

    /// Number of sparkle instances (40 ambient + 20 burst, CONTRACT §3.8).
    public static let sparkleInstanceCount = 60

    private weak var view: MTKView?
    private var resources: CharacterMetalResources?
    private var uniforms: CharacterUniforms

    /// Command queue, library and pipeline states per device, shared by every renderer.
    private static var resourceCache: [ObjectIdentifier: CharacterMetalResources] = [:]

    /// Devices on which every library source failed: later attaches skip the (expensive) loading chain.
    private static var failedDevices: Set<ObjectIdentifier> = []

    public init(rig: CharacterRig) {
        self.rig = rig
        self.uniforms = CharacterUniforms(pose: rig.currentPose,
                                          design: rig.design,
                                          viewportSize: SIMD2<Float>(1, 1),
                                          time: 0)
        super.init()
    }

    // MARK: Setup

    /// Binds the renderer to a view: resolves the device, builds or reuses the cached GPU objects,
    /// becomes the view's delegate and applies the pause state.
    public func attach(to view: MTKView) {
        self.view = view
        let device = view.device ?? MTLCreateSystemDefaultDevice()
        if let device {
            if view.device == nil {
                view.device = device
            }
            view.colorPixelFormat = CharacterMetalResources.pixelFormat
            resources = CharacterMetalRenderer.resources(for: device)
        } else {
            resources = nil
        }
        view.delegate = self
        applyPauseState()
    }

    /// Re-evaluates the pause state; call when the view's window changes.
    public func viewDidChangeWindow() {
        applyPauseState()
    }

    /// `true` once a command queue, a library and both pipeline states exist for the attached device.
    public var isReady: Bool { resources != nil }

    private func applyPauseState() {
        guard let view else { return }
        view.isPaused = isPaused || view.window == nil
    }

    private static func resources(for device: MTLDevice) -> CharacterMetalResources? {
        let key = ObjectIdentifier(device as AnyObject)
        if let cached = resourceCache[key] {
            return cached
        }
        if failedDevices.contains(key) {
            return nil
        }
        guard let built = buildResources(device: device) else {
            failedDevices.insert(key)
            return nil
        }
        resourceCache[key] = built
        return built
    }

    /// Library loading chain (CONTRACT §4.4): package bundle → process default library → runtime compile.
    /// A source is used only if it has all four entry points and both pipeline states build from it;
    /// otherwise the next source is tried.
    private static func buildResources(device: MTLDevice) -> CharacterMetalResources? {
        if let library = try? device.makeDefaultLibrary(bundle: Bundle.module),
           let built = makeResources(device: device, library: library) {
            return built
        }
        if let library = device.makeDefaultLibrary(),
           let built = makeResources(device: device, library: library) {
            return built
        }
        let options = MTLCompileOptions()
        if let library = try? device.makeLibrary(source: CharacterShaderSource.msl, options: options),
           let built = makeResources(device: device, library: library) {
            return built
        }
        return nil
    }

    private static func makeResources(device: MTLDevice, library: MTLLibrary) -> CharacterMetalResources? {
        guard hasCharacterFunctions(library) else { return nil }
        return try? CharacterMetalResources(device: device, library: library)
    }

    private static func hasCharacterFunctions(_ library: MTLLibrary) -> Bool {
        let names = library.functionNames
        return names.contains("characterVertex")
            && names.contains("characterFragment")
            && names.contains("sparkleVertex")
            && names.contains("sparkleFragment")
    }

    // MARK: MTKViewDelegate

    nonisolated public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // The drawable size is read from the view on every frame; nothing to cache here.
    }

    nonisolated public func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            self.render(in: view)
        }
    }

    // MARK: Frame

    private func render(in view: MTKView) {
        guard !isPaused, view.window != nil else { return }
        guard let resources else { return }
        let size = view.drawableSize
        guard size.width >= 1, size.height >= 1 else { return }
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }

        let pose = rig.pose(at: CACurrentMediaTime())
        // Shader time = the rig's local time (`CharacterPose.time`), the same clock the Canvas renderer
        // uses, so sparkles and effects stay in phase when switching renderers.
        let design = rig.design
        uniforms = CharacterUniforms(pose: pose,
                                     design: design,
                                     viewportSize: SIMD2<Float>(Float(size.width), Float(size.height)),
                                     time: pose.time)
        // §3.5: the renderers own `idle.breathDepth`. `CharacterUniforms` leaves `layoutE.w` spare, so the renderer
        // stores the depth there and the shader scales `bodyParams.y` (breathe) by it, like the Canvas renderer.
        uniforms.layoutE.w = design.idle.breathDepth

        guard let commandBuffer = resources.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        var frameUniforms = uniforms
        withUnsafeBytes(of: &frameUniforms) { raw in
            guard let base = raw.baseAddress else { return }
            // Character: full-screen triangle, uniforms at fragment buffer 0 (560 B < 4 KB → setFragmentBytes).
            encoder.setRenderPipelineState(resources.characterPipeline)
            encoder.setFragmentBytes(base, length: raw.count, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            // Sparkles: 60 instanced quads (6 vertices each), uniforms at vertex and fragment buffer 0.
            encoder.setRenderPipelineState(resources.sparklePipeline)
            encoder.setVertexBytes(base, length: raw.count, index: 0)
            encoder.setFragmentBytes(base, length: raw.count, index: 0)
            encoder.drawPrimitives(type: .triangle,
                                   vertexStart: 0,
                                   vertexCount: 6,
                                   instanceCount: CharacterMetalRenderer.sparkleInstanceCount)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
