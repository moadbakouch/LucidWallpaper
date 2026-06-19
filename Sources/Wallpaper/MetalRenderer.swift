import AppKit
import Metal
import QuartzCore

/// Renders a fragment shader as a wallpaper via CAMetalLayer. Wallpapers supply a
/// Shadertoy-like `shade(uv, res, time, mouse)` function (MSL); we wrap it with a
/// fullscreen-triangle vertex shader and uniforms.
@MainActor
final class MetalRenderer: NSObject, WallpaperRenderer {
    private final class MetalHostView: NSView {
        let metalLayer = CAMetalLayer()
        override func makeBackingLayer() -> CALayer { metalLayer }
        override func layout() {
            super.layout()
            let scale = window?.backingScaleFactor ?? 2
            metalLayer.contentsScale = scale
            metalLayer.drawableSize = CGSize(width: max(1, bounds.width * scale),
                                             height: max(1, bounds.height * scale))
        }
    }

    private struct Uniforms { var res: SIMD2<Float>; var time: Float; var mouse: SIMD2<Float>; var brightness: Float }

    private let host = MetalHostView()
    private let device = MTLCreateSystemDefaultDevice()
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var displayLink: CADisplayLink?
    private var startTime = CACurrentMediaTime()
    private var lastDraw: CFTimeInterval = 0
    private var paused = false
    private var fpsCap = 0
    private var mouse = SIMD2<Float>(0.5, 0.5)
    /// User-adjustable universal shader controls (apply to any shader).
    private var speed: Float = 1
    private var brightness: Float = 1

    var view: NSView { host }
    private var metalLayer: CAMetalLayer { host.metalLayer }

    override init() {
        super.init()
        host.wantsLayer = true
        queue = device?.makeCommandQueue()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
    }

    func load(_ item: WallpaperItem) {
        let shade = (try? String(contentsOf: item.contentURL, encoding: .utf8)) ?? Self.defaultShade
        buildPipeline(shade: shade)
        startTime = CACurrentMediaTime()
        startDisplayLink()
    }

    func play() {
        paused = false
        displayLink?.isPaused = false   // stop firing the vsync callback entirely while paused
    }
    func pause() {
        paused = true
        displayLink?.isPaused = true
    }
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func updateMouse(normalized point: CGPoint) {
        mouse = SIMD2<Float>(Float(point.x), Float(point.y))
    }

    // Universal shader controls (Speed / Brightness), driven like Lively properties.
    func setProperties(_ values: [String: LivelyValue]) { for (k, v) in values { applyParam(k, v) } }
    func setProperty(_ name: String, value: LivelyValue) { applyParam(name, value) }
    private func applyParam(_ name: String, _ value: LivelyValue) {
        guard case .number(let d) = value else { return }
        switch name {
        case "speed": speed = Float(d)
        case "brightness": brightness = Float(d)
        default: break
        }
    }

    func setFrameRateCap(_ fps: Int) {
        fpsCap = fps
        applyFrameRateRange()
    }

    /// Ask the OS to fire the display link fewer times (true power saving - on a 120 Hz panel
    /// a 30 fps cap is ~4× fewer GPU passes), not just skip draws inside a full-rate callback.
    private func applyFrameRateRange() {
        guard let displayLink else { return }
        if fpsCap > 0 {
            let f = Float(fpsCap)
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: f, maximum: f, preferred: f)
        } else {
            displayLink.preferredFrameRateRange = .default
        }
    }

    // MARK: Rendering

    private func startDisplayLink() {
        displayLink?.invalidate()
        let link = host.displayLink(target: self, selector: #selector(render))
        link.isPaused = paused   // honor a pause requested before the link existed
        if fpsCap > 0 {
            let f = Float(fpsCap)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: f, maximum: f, preferred: f)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func render() {
        guard !paused, let pipeline, let queue,
              let drawable = metalLayer.nextDrawable() else { return }
        let now = CACurrentMediaTime()
        if fpsCap > 0, now - lastDraw < 1.0 / Double(fpsCap) - 0.001 { return }
        lastDraw = now

        var u = Uniforms(res: SIMD2(Float(metalLayer.drawableSize.width), Float(metalLayer.drawableSize.height)),
                         time: Float(now - startTime) * speed,
                         mouse: mouse,
                         brightness: brightness)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    /// Capture the current frame. A CAMetalLayer can't be read via `cacheDisplay` (the default
    /// renderer snapshot), so render one frame into an offscreen readable texture and read it
    /// back. Powers shader/AI-wallpaper thumbnails and the snapshot debug hook.
    func snapshot(_ completion: @escaping (NSImage?) -> Void) {
        guard let device, let queue, let pipeline else { completion(nil); return }
        var w = Int(metalLayer.drawableSize.width), h = Int(metalLayer.drawableSize.height)
        if w <= 0 || h <= 0 { w = 640; h = 360 }                  // not yet laid out (offscreen)
        let cap = 1280
        if max(w, h) > cap { let s = Double(cap) / Double(max(w, h)); w = max(1, Int(Double(w) * s)); h = max(1, Int(Double(h) * s)) }

        // Render to a private render target (GPU-only, like a drawable), then blit to a shared
        // texture for CPU readback. Rendering straight to a .shared texture doesn't reliably land.
        let rtDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        rtDesc.usage = [.renderTarget]; rtDesc.storageMode = .private
        let readDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        readDesc.usage = [.shaderRead]; readDesc.storageMode = .shared
        guard let rt = device.makeTexture(descriptor: rtDesc),
              let readTex = device.makeTexture(descriptor: readDesc) else { completion(nil); return }

        var u = Uniforms(res: SIMD2(Float(w), Float(h)),
                         time: Float(CACurrentMediaTime() - startTime) * speed,
                         mouse: mouse, brightness: brightness)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = rt
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { completion(nil); return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        guard let blit = cmd.makeBlitCommandEncoder() else { completion(nil); return }
        blit.copy(from: rt, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: readTex, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()   // one-off on-demand capture; brief GPU wait, off the hot path
        let bytesPerRow = w * 4
        var raw = [UInt8](repeating: 0, count: bytesPerRow * h)
        readTex.getBytes(&raw, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        completion(MetalRenderer.image(bgra: raw, width: w, height: h))
    }

    nonisolated private static func image(bgra: [UInt8], width: Int, height: Int) -> NSImage? {
        var data = bgra
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: info), let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    private func buildPipeline(shade: String) {
        guard let device else { return }
        let source = Self.shaderHeader + "\n" + shade + "\n" + Self.shaderFooter
        do {
            let library = try device.makeLibrary(source: source, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "lw_vertex")
            desc.fragmentFunction = library.makeFunction(name: "lw_fragment")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("[LucidWallpaper] shader compile failed: %@", "\(error)")
            pipeline = nil
            // Fall back to the built-in shader so a bad import shows something, not a black screen.
            if shade != Self.defaultShade { buildPipeline(shade: Self.defaultShade) }
        }
    }

    nonisolated static let shaderHeader = """
    #include <metal_stdlib>
    using namespace metal;
    struct LWVertexOut { float4 position [[position]]; float2 uv; };
    struct LWUniforms { float2 res; float time; float2 mouse; float brightness; };
    vertex LWVertexOut lw_vertex(uint vid [[vertex_id]]) {
        float2 p[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        LWVertexOut o;
        o.position = float4(p[vid], 0.0, 1.0);
        o.uv = p[vid] * 0.5 + 0.5;
        return o;
    }
    """

    nonisolated static let shaderFooter = """
    fragment float4 lw_fragment(LWVertexOut in [[stage_in]], constant LWUniforms& u [[buffer(0)]]) {
        float4 c = shade(in.uv, u.res, u.time, u.mouse);
        return float4(c.rgb * u.brightness, 1.0);
    }
    """

    /// Bundled sample shader (also the fallback) - an interactive plasma.
    static let defaultShade = """
    float4 shade(float2 uv, float2 res, float time, float2 mouse) {
        float2 p = uv * 4.0;
        float v = sin(p.x + time) + sin(p.y + time * 1.3) + sin((p.x + p.y) * 0.7 + time);
        v += 1.2 * sin(length(uv - mouse) * 12.0 - time * 2.5);
        float3 col = 0.5 + 0.5 * cos(v + float3(0.0, 2.1, 4.2));
        return float4(col, 1.0);
    }
    """
}
