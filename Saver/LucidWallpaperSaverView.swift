import ScreenSaver
import AVFoundation
import WebKit
import Metal
import QuartzCore

/// Screensaver that plays the user's current LucidWallpaper wallpaper. Reads the shared
/// library.json from Application Support and renders video / image / web / shader content.
final class LucidWallpaperSaverView: ScreenSaverView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var webView: WKWebView?
    private var shader: SaverShader?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
        loadWallpaper()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
        loadWallpaper()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1.0 / 60.0
    }

    override func startAnimation() { super.startAnimation(); player?.play() }
    override func stopAnimation() { super.stopAnimation(); player?.pause() }

    /// Drives shader rendering; video/web animate themselves so this is a no-op for them.
    override func animateOneFrame() {
        shader?.draw()
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
        webView?.frame = bounds
        shader?.resize(to: bounds.size, scale: window?.backingScaleFactor ?? 2)
    }

    // MARK: Content

    private func loadWallpaper() {
        guard let item = currentWallpaper() else { return }
        switch item.kind {
        case "video":
            setupVideo(item.url)
        case "image":
            setupImage(item.url)
        case "shader":
            setupShader(item.url)
        case "web":
            setupWeb(item.url, isFile: item.url.isFileURL)
        default:
            break
        }
    }

    private func setupVideo(_ url: URL) {
        let queue = AVQueuePlayer()
        queue.isMuted = true
        let template = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: queue, templateItem: template)
        let pl = AVPlayerLayer(player: queue)
        pl.videoGravity = .resizeAspectFill
        pl.frame = bounds
        layer?.addSublayer(pl)
        player = queue
        playerLayer = pl
        queue.play()
    }

    private func setupImage(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let imageLayer = CALayer()
        imageLayer.frame = bounds
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.contents = image
        layer?.addSublayer(imageLayer)
    }

    private func setupShader(_ url: URL) {
        let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard let s = SaverShader(shade: source.isEmpty ? nil : source) else { return }
        layer?.addSublayer(s.metalLayer)
        s.resize(to: bounds.size, scale: window?.backingScaleFactor ?? 2)
        shader = s
    }

    private func setupWeb(_ url: URL, isFile: Bool) {
        let web = WKWebView(frame: bounds)
        web.autoresizingMask = [.width, .height]
        if isFile {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            web.load(URLRequest(url: url))
        }
        addSubview(web)
        webView = web
    }

    // MARK: Shared library

    private struct SaverItem { let kind: String; let url: URL }

    private func currentWallpaper() -> SaverItem? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let libURL = base.appendingPathComponent("LucidWallpaper/library.json")
        guard let data = try? Data(contentsOf: libURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        let currentID = root["currentItemID"] as? String
        let chosen = items.first { ($0["id"] as? String) == currentID } ?? items.first
        guard let item = chosen,
              let kind = item["kind"] as? String,
              let urlString = item["contentURL"] as? String,
              let url = URL(string: urlString) else { return nil }
        return SaverItem(kind: kind, url: url)
    }
}

/// Minimal Metal fragment-shader renderer for the screensaver. Mirrors the app's MetalRenderer
/// wrapping (a `shade(uv,res,time,mouse)` function) but driven by the screensaver's frame loop.
private final class SaverShader {
    let metalLayer = CAMetalLayer()
    private let device = MTLCreateSystemDefaultDevice()
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private let startTime = CACurrentMediaTime()

    private struct Uniforms { var res: SIMD2<Float>; var time: Float; var mouse: SIMD2<Float> }

    init?(shade: String?) {
        guard let device else { return nil }
        queue = device.makeCommandQueue()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        let source = Self.header + "\n" + (shade ?? Self.defaultShade) + "\n" + Self.footer
        guard let lib = try? device.makeLibrary(source: source, options: nil) else {
            // Fall back to the built-in plasma so the screensaver never shows a blank screen.
            let fallback = Self.header + "\n" + Self.defaultShade + "\n" + Self.footer
            guard let lib2 = try? device.makeLibrary(source: fallback, options: nil),
                  let p = Self.makePipeline(device, lib2) else { return nil }
            pipeline = p
            return
        }
        guard let p = Self.makePipeline(device, lib) else { return nil }
        pipeline = p
    }

    func resize(to size: CGSize, scale: CGFloat) {
        metalLayer.frame = CGRect(origin: .zero, size: size)
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: max(1, size.width * scale),
                                         height: max(1, size.height * scale))
    }

    func draw() {
        guard let pipeline, let queue, let drawable = metalLayer.nextDrawable() else { return }
        var u = Uniforms(res: SIMD2(Float(metalLayer.drawableSize.width), Float(metalLayer.drawableSize.height)),
                         time: Float(CACurrentMediaTime() - startTime),
                         mouse: SIMD2(0.5, 0.5))
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

    private static func makePipeline(_ device: MTLDevice, _ lib: MTLLibrary) -> MTLRenderPipelineState? {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "lw_vertex")
        desc.fragmentFunction = lib.makeFunction(name: "lw_fragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: desc)
    }

    private static let header = """
    #include <metal_stdlib>
    using namespace metal;
    struct LWVertexOut { float4 position [[position]]; float2 uv; };
    struct LWUniforms { float2 res; float time; float2 mouse; };
    vertex LWVertexOut lw_vertex(uint vid [[vertex_id]]) {
        float2 p[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        LWVertexOut o;
        o.position = float4(p[vid], 0.0, 1.0);
        o.uv = p[vid] * 0.5 + 0.5;
        return o;
    }
    """

    private static let footer = """
    fragment float4 lw_fragment(LWVertexOut in [[stage_in]], constant LWUniforms& u [[buffer(0)]]) {
        return shade(in.uv, u.res, u.time, u.mouse);
    }
    """

    private static let defaultShade = """
    float4 shade(float2 uv, float2 res, float time, float2 mouse) {
        float2 p = uv * 4.0;
        float v = sin(p.x + time) + sin(p.y + time * 1.3) + sin((p.x + p.y) * 0.7 + time);
        float3 col = 0.5 + 0.5 * cos(v + float3(0.0, 2.1, 4.2));
        return float4(col, 1.0);
    }
    """
}
