#include <metal_stdlib>
using namespace metal;

// 与 Swift 的五组 SIMD4 完全同构，避免跨语言的隐式结构体填充。
struct AuroraUniforms {
    float4 geometry;    // drawable width, height, corner radius, core width (physical pixels)
    float4 style;       // glow radius, brightness, unused, unused
    float4 animation;   // flow phase, breathing multiplier, energy phase, opacity
    float4 feedback;    // feedback RGB, tint amount
    float4 emphasis;    // extra intensity, strip width, inset, unused
};

struct RasterData {
    float4 position [[position]];
};

// 四个互不重叠的矩形只覆盖边缘；屏幕中央不执行片元 Shader。
vertex RasterData auroraVertex(uint vertexID [[vertex_id]], constant AuroraUniforms &u [[buffer(0)]]) {
    constexpr float2 corners[] = {float2(0, 0), float2(1, 0), float2(0, 1), float2(0, 1), float2(1, 0), float2(1, 1)};
    float2 size = u.geometry.xy;
    float band = min(u.emphasis.y, min(size.x, size.y) * 0.5);
    uint strip = vertexID / 6;
    float2 origin;
    float2 extent;
    if (strip == 0) {
        origin = float2(0, 0);
        extent = float2(size.x, band);
    } else if (strip == 1) {
        origin = float2(0, size.y - band);
        extent = float2(size.x, band);
    } else if (strip == 2) {
        origin = float2(0, band);
        extent = float2(band, max(size.y - 2 * band, 0.0));
    } else {
        origin = float2(size.x - band, band);
        extent = float2(band, max(size.y - 2 * band, 0.0));
    }
    float2 pixel = origin + corners[vertexID % 6] * extent;
    RasterData output;
    output.position = float4(pixel.x / size.x * 2 - 1, 1 - pixel.y / size.y * 2, 0, 1);
    return output;
}

// 顶部保留两个圆弧，底部两角直接连接；按实际周长保持渐变连续。
float perimeterPosition(float2 p, float2 lo, float2 hi, float r) {
    const float quarter = M_PI_F * 0.5 * r;
    float topHorizontal = hi.x - lo.x - 2 * r;
    float bottomHorizontal = hi.x - lo.x;
    float vertical = hi.y - lo.y - r;
    float perimeter = topHorizontal + bottomHorizontal + 2 * vertical + 2 * quarter;
    float distance;
    if (p.x < lo.x + r && p.y < lo.y + r) {
        float angle = atan2(p.y - lo.y - r, p.x - lo.x - r);
        angle = angle < 0 ? angle + 2 * M_PI_F : angle;
        distance = topHorizontal + bottomHorizontal + 2 * vertical + quarter + (angle - M_PI_F) * r;
    } else if (p.x > hi.x - r && p.y < lo.y + r) {
        float angle = atan2(p.y - lo.y - r, p.x - hi.x + r);
        distance = topHorizontal + (angle + M_PI_F * 0.5) * r;
    } else {
        float4 edgeDistance = abs(float4(p.y - lo.y, p.x - hi.x, p.y - hi.y, p.x - lo.x));
        float nearest = min(min(edgeDistance.x, edgeDistance.y), min(edgeDistance.z, edgeDistance.w));
        if (nearest == edgeDistance.x) {
            distance = clamp(p.x - lo.x - r, 0.0, topHorizontal);
        } else if (nearest == edgeDistance.y) {
            distance = topHorizontal + quarter + clamp(p.y - lo.y - r, 0.0, vertical);
        } else if (nearest == edgeDistance.z) {
            distance = topHorizontal + quarter + vertical + clamp(hi.x - p.x, 0.0, bottomHorizontal);
        } else {
            distance = topHorizontal + quarter + vertical + bottomHorizontal + clamp(hi.y - p.y, 0.0, vertical);
        }
    }
    return distance / perimeter;
}

float3 auroraPalette(float phase) {
    constexpr float3 colors[] = {
        float3(0.0, 229.0 / 255.0, 1.0),
        float3(41.0 / 255.0, 121.0 / 255.0, 1.0),
        float3(121.0 / 255.0, 80.0 / 255.0, 1.0),
        float3(176.0 / 255.0, 68.0 / 255.0, 1.0),
        float3(240.0 / 255.0, 77.0 / 255.0, 1.0)
    };
    float position = fract(phase) * 5;
    uint index = uint(floor(position));
    return mix(colors[index], colors[(index + 1) % 5], smoothstep(0.0, 1.0, fract(position)));
}

fragment float4 auroraFragment(RasterData input [[stage_in]], constant AuroraUniforms &u [[buffer(0)]]) {
    float2 p = input.position.xy;
    float2 lo = float2(u.emphasis.z);
    float2 hi = u.geometry.xy - lo;
    float r = min(u.geometry.z, min(hi.x - lo.x, hi.y - lo.y) * 0.5 - 1);
    // 下半部使用零圆角距离场，让左下、右下光线在屏幕边缘形成直角。
    float cornerRadius = p.y < u.geometry.y * 0.5 ? r : 0.0;
    float2 q = abs(p - u.geometry.xy * 0.5) - ((hi - lo) * 0.5 - cornerRadius);
    float signedDistance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - cornerRadius;
    float d = abs(signedDistance);
    float halfCore = u.geometry.w * 0.5;
    float glow = u.style.x;
    if (d > glow + halfCore + 1) {
        return float4(0);
    }

    float t = perimeterPosition(p, lo, hi, r);
    float3 color = auroraPalette(t - u.animation.x);
    float delta = fract(t - u.animation.z + 0.5) - 0.5;
    float energy = smoothstep(-0.075, -0.015, delta) * (1 - smoothstep(0.0, 0.035, delta));
    float core = 1 - smoothstep(halfCore - 0.6, halfCore + 0.6, d);
    float innerDistance = max(d - halfCore, 0.0);
    float middle = exp(-0.5 * pow(innerDistance / 4.5, 2.0));
    float outer = exp(-0.5 * pow(innerDistance / (glow * 0.42), 2.0));
    float cutoff = 1 - smoothstep(glow * 0.65, glow, innerDistance);
    // 外侧仅保留核心线抗锯齿，光晕全部向桌面内部衰减。
    float insideMask = 1 - smoothstep(halfCore, halfCore + 0.8, signedDistance);
    float alpha = (1 - (1 - core * 0.96) * (1 - middle * 0.34) * (1 - outer * 0.18)) * cutoff * insideMask;
    color = mix(color, u.feedback.rgb, u.feedback.a);
    color = mix(color, float3(0.8, 0.98, 1), core * (0.12 + energy * 0.25) * (1 - u.feedback.a));
    float brightness = u.style.y * mix(u.animation.y, 1.0, u.feedback.a);
    alpha = saturate(alpha * brightness * (1 + energy * 0.18 + u.emphasis.x) * u.animation.w);
    // WindowServer 采用预乘 alpha；透明像素的 RGB 必须同时归零。
    return float4(color * alpha, alpha);
}
