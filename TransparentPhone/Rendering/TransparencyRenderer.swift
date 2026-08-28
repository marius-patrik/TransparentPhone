import ARKit
import CoreVideo
import Metal
import MetalKit
import simd

final class TransparencyRenderer: NSObject, MTKViewDelegate {
    struct Uniforms {
        var eyeOffsetMeters: SIMD2<Float>
        var focalLengthPixels: SIMD2<Float>
        var referenceDepthMeters: Float
        var strength: Float
        var depthEnabled: UInt32
        var debug: UInt32
        var imageAspect: Float
        var viewAspect: Float
        var parallaxSign: Float
        var rotationQuarterTurns: UInt32
    }

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let textureCache: CVMetalTextureCache
    private let fallbackDepthTexture: MTLTexture
    private let lock = NSLock()

    weak var view: MTKView?
    private var latestImage: CVPixelBuffer?
    private var latestDepth: CVPixelBuffer?
    private var latestIntrinsics = matrix_identity_float3x3
    private var latestResolution = CGSize(width: 1920, height: 1440)
    private var eyeOffset = SIMD3<Float>.zero

    var referenceDepthMeters: Float = 1.5
    var parallaxEnabled = true
    var depthEnabled = true
    var strength: Float = 1.0
    var debugOverlay = false

    init?(device: MTLDevice) {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else { return nil }
        self.commandQueue = commandQueue

        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard cacheStatus == kCVReturnSuccess, let validCache = cache else { return nil }
        self.textureCache = validCache

        // Create a 1x1 fallback float texture for depth map when none is supplied
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: 1,
            height: 1,
            mipmapped: false
        )
        textureDesc.usage = [.shaderRead]
        guard let fallback = device.makeTexture(descriptor: textureDesc) else { return nil }
        var defaultDepth: Float = 1.5
        fallback.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &defaultDepth,
            bytesPerRow: MemoryLayout<Float>.size
        )
        self.fallbackDepthTexture = fallback

        // Load shader library either from precompiled default library, bundle resource, or runtime source
        var library: MTLLibrary?
        if let defaultLib = device.makeDefaultLibrary() {
            library = defaultLib
        } else if let shaderURL = Bundle.main.url(forResource: "TransparencyShaders", withExtension: "metal"),
                  let source = try? String(contentsOf: shaderURL, encoding: .utf8) {
            library = try? device.makeLibrary(source: source, options: nil)
        } else {
            library = try? device.makeLibrary(source: TransparencyShadersSource, options: nil)
        }

        guard let shaderLib = library,
              let vertexFunc = shaderLib.makeFunction(name: "fullscreen_vertex"),
              let fragmentFunc = shaderLib.makeFunction(name: "transparent_fragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.pipeline = pipeline
        super.init()
    }

    func setFrame(_ image: CVPixelBuffer, depth: CVPixelBuffer?, intrinsics: simd_float3x3, resolution: CGSize) {
        lock.lock()
        latestImage = image
        latestDepth = depth
        latestIntrinsics = intrinsics
        latestResolution = resolution
        lock.unlock()
    }

    func setEye(_ eye: SIMD3<Float>) {
        lock.lock()
        eyeOffset = eye
        lock.unlock()
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor else { return }

        lock.lock()
        guard let image = latestImage else {
            lock.unlock()
            return
        }
        let depth = latestDepth
        let intrinsics = latestIntrinsics
        let resolution = latestResolution
        let eye = eyeOffset
        let strengthValue = strength
        let parallax = parallaxEnabled
        let depthVal = depthEnabled
        let debug = debugOverlay
        let referenceDepth = referenceDepthMeters
        lock.unlock()

        guard CVPixelBufferGetPlaneCount(image) >= 2 else { return }
        guard let yTexture = makeTexture(image, plane: 0, pixelFormat: .r8Unorm),
              let cbcrTexture = makeTexture(image, plane: 1, pixelFormat: .rg8Unorm) else { return }
        let depthTexture = depth.flatMap { makeTexture($0, plane: 0, pixelFormat: .r32Float) }

        let uniforms = Uniforms(
            eyeOffsetMeters: parallax ? SIMD2<Float>(eye.x, eye.y) : .zero,
            focalLengthPixels: SIMD2<Float>(intrinsics[0][0], intrinsics[1][1]),
            referenceDepthMeters: max(referenceDepth, 0.1),
            strength: strengthValue,
            depthEnabled: (depthVal && depthTexture != nil) ? 1 : 0,
            debug: debug ? 1 : 0,
            imageAspect: Float(resolution.height / max(resolution.width, 1)),
            viewAspect: Float(view.drawableSize.width / max(view.drawableSize.height, 1)),
            parallaxSign: -1.0,
            rotationQuarterTurns: 1
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(yTexture, index: 0)
        encoder.setFragmentTexture(cbcrTexture, index: 1)
        encoder.setFragmentTexture(depthTexture ?? fallbackDepthTexture, index: 2)
        var mutable = uniforms
        encoder.setFragmentBytes(&mutable, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func makeTexture(_ buffer: CVPixelBuffer, plane: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let width = CVPixelBufferGetWidthOfPlane(buffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(buffer, plane)
        var textureRef: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, buffer, nil, pixelFormat, width, height, plane, &textureRef
        )
        guard status == kCVReturnSuccess, let textureRef else { return nil }
        return CVMetalTextureGetTexture(textureRef)
    }
}

private let TransparencyShadersSource = """
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

    float2 displayUV = in.uv;

    if (u.imageAspect > u.viewAspect) {
        float visible = u.viewAspect / max(u.imageAspect, 0.0001f);
        displayUV.x = (displayUV.x - 0.5f) * visible + 0.5f;
    } else {
        float visible = u.imageAspect / max(u.viewAspect, 0.0001f);
        displayUV.y = (displayUV.y - 0.5f) * visible + 0.5f;
    }

    float2 sensorUV = (u.rotationQuarterTurns == 1)
        ? float2(displayUV.y, 1.0f - displayUV.x)
        : displayUV;

    float depthMeters = u.referenceDepthMeters;
    if (u.depthEnabled != 0) {
        float sampledDepth = depth.sample(linearSampler, sensorUV).r;
        if (isfinite(sampledDepth) && sampledDepth >= 0.15f && sampledDepth <= 12.0f) {
            depthMeters = sampledDepth;
        }
    }

    float2 pixelShift = u.eyeOffsetMeters * u.focalLengthPixels / max(depthMeters, 0.15f);
    float2 uvShift = pixelShift / float2(luma.get_width(), luma.get_height());

    float2 rotatedShift = (u.rotationQuarterTurns == 1)
        ? float2(uvShift.y, -uvShift.x)
        : float2(uvShift.x, -uvShift.y);

    float2 sampleUV = sensorUV + rotatedShift * u.parallaxSign * u.strength;

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
"""
