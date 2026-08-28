import ARKit
import CoreVideo
import Metal
import MetalKit
import simd

final class TransparencyRenderer: NSObject, MTKViewDelegate {
    struct Uniforms {
        var displayTransform: matrix_float3x3
        var eyeOffsetMeters: SIMD2<Float>
        var focalLengthPixels: SIMD2<Float>
        var viewportSizePixels: SIMD2<Float>
        var referenceDepthMeters: Float
        var strength: Float
        var depthEnabled: UInt32
        var debug: UInt32
    }

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let textureCache: CVMetalTextureCache
    private let fallbackDepthTexture: MTLTexture
    private let lock = NSLock()

    weak var view: MTKView?
    private var latestFrame: ARFrame?
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

    func setFrame(_ frame: ARFrame) {
        lock.lock()
        latestFrame = frame
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
        guard let frame = latestFrame else {
            lock.unlock()
            return
        }
        let eye = eyeOffset
        let strengthValue = strength
        let parallax = parallaxEnabled
        let depthVal = depthEnabled
        let debug = debugOverlay
        let referenceDepth = referenceDepthMeters
        lock.unlock()

        let image = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(image) >= 2 else { return }
        guard let yTexture = makeTexture(image, plane: 0, pixelFormat: .r8Unorm),
              let cbcrTexture = makeTexture(image, plane: 1, pixelFormat: .rg8Unorm) else { return }

        let depthBuffer = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
        let depthTexture = depthBuffer.flatMap { makeTexture($0, plane: 0, pixelFormat: .r32Float) }

        let viewportSize = (view.drawableSize.width > 0 && view.drawableSize.height > 0)
            ? view.drawableSize
            : CGSize(width: 1179, height: 2556)

        // ARKit's calibrated displayTransform maps view coordinates to camera texture coordinates
        let affineTransform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
        let matrix = matrix_float3x3(
            SIMD3<Float>(Float(affineTransform.a), Float(affineTransform.b), 0),
            SIMD3<Float>(Float(affineTransform.c), Float(affineTransform.d), 0),
            SIMD3<Float>(Float(affineTransform.tx), Float(affineTransform.ty), 1)
        )

        let intrinsics = frame.camera.intrinsics

        let uniforms = Uniforms(
            displayTransform: matrix,
            eyeOffsetMeters: parallax ? SIMD2<Float>(eye.x, eye.y) : .zero,
            focalLengthPixels: SIMD2<Float>(intrinsics[0][0], intrinsics[1][1]),
            viewportSizePixels: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)),
            referenceDepthMeters: max(referenceDepth, 0.1),
            strength: strengthValue,
            depthEnabled: (depthVal && depthTexture != nil) ? 1 : 0,
            debug: debug ? 1 : 0
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

    float3 baseSensorUV = u.displayTransform * float3(in.uv, 1.0f);

    float depthMeters = u.referenceDepthMeters;
    if (u.depthEnabled != 0) {
        float sampledDepth = depth.sample(linearSampler, baseSensorUV.xy).r;
        if (isfinite(sampledDepth) && sampledDepth >= 0.15f && sampledDepth <= 12.0f) {
            depthMeters = sampledDepth;
        }
    }

    float2 pixelShift = u.eyeOffsetMeters * u.focalLengthPixels / max(depthMeters, 0.15f);
    float2 uvShift = (pixelShift / max(u.viewportSizePixels, float2(1.0f, 1.0f))) * u.strength;
    float2 shiftedViewportUV = in.uv - float2(uvShift.x, -uvShift.y);

    float3 sampleSensorUV = u.displayTransform * float3(shiftedViewportUV, 1.0f);

    float y = luma.sample(linearSampler, sampleSensorUV.xy).r;
    float2 cbcr = chroma.sample(linearSampler, sampleSensorUV.xy).rg;

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
