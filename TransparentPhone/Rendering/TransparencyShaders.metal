#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float3x3 displayTransform;
    float2 eyeOffsetMeters;
    float2 focalLengthPixels;
    float2 viewportSizePixels;
    float referenceDepthMeters;
    float strength;
    uint depthEnabled;
    uint debug;
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

    // 1. Map viewport coordinate to camera sensor coordinates using ARKit's calibrated displayTransform
    float3 baseSensorUV = u.displayTransform * float3(in.uv, 1.0f);

    // 2. Sample LiDAR scene depth (if available and enabled)
    float depthMeters = u.referenceDepthMeters;
    if (u.depthEnabled != 0) {
        float sampledDepth = depth.sample(linearSampler, baseSensorUV.xy).r;
        if (isfinite(sampledDepth) && sampledDepth >= 0.15f && sampledDepth <= 12.0f) {
            depthMeters = sampledDepth;
        }
    }

    // 3. Calculate viewport disparity shift:
    // When the viewer moves right (+X), background objects appear shifted to the right in the window frame.
    // Pinhole relationship: delta_uv = (f / viewport_dim) * delta_eye / depth
    float2 pixelShift = u.eyeOffsetMeters * u.focalLengthPixels / max(depthMeters, 0.15f);
    float2 uvShift = (pixelShift / max(u.viewportSizePixels, float2(1.0f, 1.0f))) * u.strength;

    // Shift the sampled viewport coordinate
    float2 shiftedViewportUV = in.uv - float2(uvShift.x, -uvShift.y);

    // 4. Map the shifted viewport UV to camera sensor coordinates
    float3 sampleSensorUV = u.displayTransform * float3(shiftedViewportUV, 1.0f);

    // 5. Sample full-range YCbCr camera planes
    float y = luma.sample(linearSampler, sampleSensorUV.xy).r;
    float2 cbcr = chroma.sample(linearSampler, sampleSensorUV.xy).rg;

    // BT.709 full-range YCbCr -> RGB conversion matrix
    const float4x4 ycbcrToRGB = float4x4(
        float4(1.0000f,  1.0000f,  1.0000f,  0.0000f),
        float4(0.0000f, -0.3441f,  1.7720f,  0.0000f),
        float4(1.4020f, -0.7141f,  0.0000f,  0.0000f),
        float4(-0.7010f, 0.5291f, -0.8860f, 1.0000f)
    );

    float4 color = ycbcrToRGB * float4(y, cbcr.x, cbcr.y, 1.0f);

    // Optional debug grid overlay
    if (u.debug != 0) {
        float2 grid = abs(fract(in.uv * 20.0f) - 0.5f);
        float line = 1.0f - smoothstep(0.47f, 0.50f, max(grid.x, grid.y));
        color.rgb = mix(color.rgb, float3(1.0f, 0.25f, 0.05f), line * 0.25f);
    }

    return float4(clamp(color.rgb, 0.0f, 1.0f), 1.0f);
}
