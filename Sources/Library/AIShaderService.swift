import Foundation
import Metal

/// Generates a Metal wallpaper shader from a text prompt using the Anthropic API. The model is
/// asked for ONLY a `shade(uv,res,time,mouse)` function, which we validate (compile) before use.
enum AIShaderService {
    /// The Anthropic API key (entered by the user in Settings). Stored in UserDefaults.
    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "anthropicAPIKey") }
    }
    static var hasKey: Bool { !apiKey.isEmpty }

    enum AIError: LocalizedError {
        case noKey, badResponse(String), noShader, wontCompile(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add your Anthropic API key in Settings → AI Wallpapers first."
            case .badResponse(let m): return "The AI request failed: \(m)"
            case .noShader: return "The model didn’t return a usable shader. Try rephrasing."
            case .wontCompile(let m): return "The generated shader didn’t compile. Try again.\n\(m)"
            }
        }
    }

    private static let system = """
    You write a single Metal Shading Language (MSL) fragment-shader function for a live desktop \
    wallpaper. Output ONLY this function, with EXACTLY this signature and nothing else (no \
    #include, no other functions, no markdown fences, no explanation):

    float4 shade(float2 uv, float2 res, float time, float2 mouse) { ... }

    Where: uv is the pixel coordinate normalized 0..1 (origin bottom-left); res is the resolution \
    in pixels; time is seconds since start; mouse is the cursor normalized 0..1. Return an opaque \
    color (alpha 1). Make it smoothly ANIMATED using `time`, visually striking, and tasteful as a \
    desktop background. Use only standard MSL math (sin, cos, fract, mix, length, smoothstep, etc.). \
    Keep it under ~60 lines.
    """

    /// Call the API and return a validated `shade(...)` MSL function.
    static func generate(prompt: String) async throws -> String {
        guard hasKey else { throw AIError.noKey }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 1500,
            "system": system,
            "messages": [["role": "user", "content": "Make a wallpaper shader: \(prompt)"]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String } ?? "HTTP \(http.statusCode)"
            throw AIError.badResponse(msg)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String else {
            throw AIError.badResponse("unexpected response")
        }
        let shade = extractShade(text)
        guard !shade.isEmpty else { throw AIError.noShader }
        if let err = compileError(shade) { throw AIError.wontCompile(err) }
        return shade
    }

    /// Pull the `shade(...)` function out of a model reply (strip markdown fences if present),
    /// tolerant of extra whitespace / a language tag after the opening fence.
    private static func extractShade(_ text: String) -> String {
        var s = text
        if let open = s.range(of: "```") {
            var inner = String(s[open.upperBound...])
            if let nl = inner.firstIndex(of: "\n") {       // drop an optional "metal" language tag
                let firstLine = inner[..<nl].trimmingCharacters(in: .whitespaces)
                if firstLine.count <= 6, !firstLine.contains("(") { inner = String(inner[inner.index(after: nl)...]) }
            }
            if let close = inner.range(of: "```") { inner = String(inner[..<close.lowerBound]) }
            s = inner
        }
        // Match the function start tolerant of spacing: `float4   shade (`.
        if let r = s.range(of: "float4\\s+shade\\s*\\(", options: .regularExpression) {
            return String(s[r.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    /// nil if the shader compiles; otherwise the compiler error.
    private static func compileError(_ shade: String) -> String? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }   // can't validate → allow
        let source = MetalRenderer.shaderHeader + "\n" + shade + "\n" + MetalRenderer.shaderFooter
        do { _ = try device.makeLibrary(source: source, options: nil); return nil }
        catch { return error.localizedDescription }
    }
}
