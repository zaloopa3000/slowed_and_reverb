#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Optional overlay effects for the GIF screen (see GifEffect.swift).

/// Big square pixels: every block shows the color at its center.
[[ stitchable ]] half4 gifPixelate(float2 position, SwiftUI::Layer layer, float blockSize) {
    float2 center = floor(position / blockSize) * blockSize + blockSize * 0.5;
    return layer.sample(center);
}

/// CRT tube: dark scanline every third row, RGB aperture-grille tint, soft vignette.
[[ stitchable ]] half4 gifCRT(float2 position, half4 color, float2 viewSize) {
    float scanline = fmod(position.y, 3.0) < 1.0 ? 0.72 : 1.0;
    float2 uv = position / viewSize - 0.5;
    float vignette = 1.0 - dot(uv, uv) * 0.9;

    int column = int(fmod(position.x, 3.0));
    half3 grille = column == 0 ? half3(1.08h, 0.94h, 0.94h)
                 : column == 1 ? half3(0.94h, 1.08h, 0.94h)
                 :               half3(0.94h, 0.94h, 1.08h);

    color.rgb *= half(scanline * vignette) * grille;
    return color;
}

/// Worn VHS tape: wobbling red/blue channel split, grain and a slowly rolling bright band.
[[ stitchable ]] half4 gifVHS(float2 position, SwiftUI::Layer layer, float time, float2 viewSize) {
    float shift = 2.5 + sin(position.y * 0.045 + time * 2.7) * 1.5;
    half4 base = layer.sample(position);
    half red = layer.sample(position + float2(shift, 0)).r;
    half blue = layer.sample(position - float2(shift, 0)).b;

    float rollY = fract(time * 0.12) * viewSize.y;
    float band = exp(-pow((position.y - rollY) / (viewSize.y * 0.04), 2.0)) * 0.18;
    float grain = fract(sin(dot(position + time * 60.0, float2(12.9898, 78.233))) * 43758.5453) - 0.5;

    half3 rgb = half3(red, base.g, blue) + half(band) + half(grain * 0.07);
    return half4(clamp(rgb, 0.0h, 1.0h), base.a);
}

/// Neon duotone in the player's palette: shadows → deep violet, mids → hot pink, highlights → cyan.
[[ stitchable ]] half4 gifNeon(float2 position, half4 color) {
    half luminance = dot(color.rgb, half3(0.299h, 0.587h, 0.114h));
    half3 dark = half3(0.10h, 0.05h, 0.25h);
    half3 mid = half3(0.95h, 0.30h, 0.55h);
    half3 light = half3(0.55h, 0.90h, 1.00h);
    half3 mapped = luminance < 0.5h ? mix(dark, mid, luminance * 2.0h)
                                    : mix(mid, light, (luminance - 0.5h) * 2.0h);
    return half4(mapped * color.a, color.a);
}
