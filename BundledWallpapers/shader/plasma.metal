// A LucidWallpaper Metal shader. Provide a `shade` function:
//   float4 shade(float2 uv, float2 res, float time, float2 mouse)
// uv     – normalized 0..1 (bottom-left origin)
// res    – drawable size in pixels
// time   – seconds since the wallpaper started
// mouse  – cursor position, normalized 0..1
float4 shade(float2 uv, float2 res, float time, float2 mouse) {
    float2 p = uv * 4.0;
    float v = sin(p.x + time)
            + sin(p.y + time * 1.3)
            + sin((p.x + p.y) * 0.7 + time);
    // Ripple toward the cursor.
    v += 1.4 * sin(length(uv - mouse) * 14.0 - time * 2.5);
    float3 col = 0.5 + 0.5 * cos(v + float3(0.0, 2.1, 4.2));
    return float4(col, 1.0);
}
