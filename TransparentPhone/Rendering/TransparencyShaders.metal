#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 eyeOffsetMeters;
    float2 focalLengthPixels;
    float referenceDepthMeters;
    float strength;
    uint depthEnabled;
    uint debug;
    float imageAspect;
    float viewAspect;
    float parallaxSign;
    uint rotationQuarterTurns;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut fullscreen_vertex(uint id [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0f, -1.0f), float2(1.0f, -1.0f), float2(-1.0f, 1.0f), float2(1.0f, 1.0f)
    };
    const float2 uv[4] = {
        float2(0.0f, 1.0f), float2(1.0f, 1.0f), float2(0.0f, 0.0f), float2(1.0f, 0.0f)
    };
    VertexOut out;
    out.position = float4(positions[id], 0.0f, 1.0f);
    out.uv = uv[id];
    return out;
}

fragment float4 transparent_fragment(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> luma [[texture(0)]],
    texture2d<float, access::sample> chroma [[texture(1)]],
    texture2d<float, access::sample> depth [[texture(2)]],
    constant Uniforms& u [[buffer(0)]]) {

    constexpr sampler linearSampler(address::clamp_to_edge, filter::linear);

    // 1. Display UV space: (0,0) top-left, (1,1) bottom-right
    float2 displayUV = in.uv;

    // 2. Aspect ratio correction: crop camera to display aspect ratio without stretching
    if (u.imageAspect > u.viewAspect) {
        float visible = u.viewAspect / max(u.imageAspect, 0.0001f);
        displayUV.x = (displayUV.x - 0.5f) * visible + 0.5f;
    } else {
        float visible = u.imageAspect / max(u.viewAspect, 0.0001f);
        displayUV.y = (displayUV.y - 0.5f) * visible + 0.5f;
    }

    // 3. Map display UV to sensor UV
    float2 sensorUV = (u.rotationQuarterTurns == 1)
        ? float2(displayUV.y, 1.0f - displayUV.x)
        : displayUV;

    // 4. Sample LiDAR scene depth (if available and enabled)
    float depthMeters = u.referenceDepthMeters;
    if (u.depthEnabled != 0) {
        float sampledDepth = depth.sample(linearSampler, sensorUV).r;
        if (isfinite(sampledDepth) && sampledDepth >= 0.15f && sampledDepth <= 12.0f) {
            depthMeters = sampledDepth;
        }
    }

    // 5. Calculate pinhole disparity shift
    float2 pixelShift = u.eyeOffsetMeters * u.focalLengthPixels / max(depthMeters, 0.15f);
    float2 uvShift = pixelShift / float2(luma.get_width(), luma.get_height());

    float2 rotatedShift = (u.rotationQuarterTurns == 1)
        ? float2(uvShift.y, -uvShift.x)
        : float2(uvShift.x, -uvShift.y);

    float2 sampleUV = sensorUV + rotatedShift * u.parallaxSign * u.strength;

    // 6. Sample YCbCr and convert to RGB
    float y = luma.sample(linearSampler, sampleUV).r;
    float2 cbcr = chroma.sample(linearSampler, sampleUV).rg;

    const float4x4 ycbcrToRGB = float4x4(
        float4(1.0000f,  1.0000f,  1.0000f,  0.0000f),
        float4(0.0000f, -0.3441f,  1.7720f,  0.0000f),
        float4(1.4020f, -0.7141f,  0.0000f,  0.0000f),
        float4(-0.7010f, 0.5291f, -0.8860f, 1.0000f)
    );

    float4 color = ycbcrToRGB * float4(y, cbcr.x, cbcr.y, 1.0f);

    if (u.debug != 0) {
        float2 grid = abs(fract(in.uv * 20.0f) - 0.5f);
        float line = 1.0f - smoothstep(0.47f, 0.50f, max(grid.x, grid.y));
        color.rgb = mix(color.rgb, float3(1.0f, 0.25f, 0.05f), line * 0.25f);
    }

    return float4(clamp(color.rgb, 0.0f, 1.0f), 1.0f);
}
