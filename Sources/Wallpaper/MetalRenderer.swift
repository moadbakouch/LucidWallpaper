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
