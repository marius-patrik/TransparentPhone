import AVFoundation
import CoreVideo
import Metal
import MetalKit

final class MirrorRenderer: NSObject, MTKViewDelegate {
    struct Uniforms {
        var zoom: Float
    }

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let textureCache: CVMetalTextureCache
    private let lock = NSLock()

    private var currentPixelBuffer: CVPixelBuffer?
    var zoom: Float = 1.0

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let validCache = cache else { return nil }
        self.textureCache = validCache

        guard let library = try? device.makeLibrary(source: MirrorShaderSource, options: nil),
              let vertexFunc = library.makeFunction(name: "mirror_vertex"),
              let fragmentFunc = library.makeFunction(name: "mirror_fragment") else {
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

    func setPixelBuffer(_ buffer: CVPixelBuffer) {
        lock.lock()
        currentPixelBuffer = buffer
        lock.unlock()
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor else { return }

        lock.lock()
        guard let buffer = currentPixelBuffer else {
            lock.unlock()
            return
        }
        let z = zoom
        lock.unlock()

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        var textureRef: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            buffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &textureRef
        )
        guard status == kCVReturnSuccess,
              let textureRef,
              let texture = CVMetalTextureGetTexture(textureRef) else {
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)

        var uniforms = Uniforms(zoom: max(1.0, min(3.0, z)))
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

private let MirrorShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float zoom;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut mirror_vertex(uint id [[vertex_id]]) {
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

fragment float4 mirror_fragment(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> videoTexture [[texture(0)]],
    constant Uniforms& u [[buffer(0)]]) {

    constexpr sampler s(address::clamp_to_edge, filter::linear);

    float2 centered = in.uv - 0.5f;
    float2 zoomed = centered / max(u.zoom, 1.0f) + 0.5f;

    // Horizontal mirror flip
    float2 mirrorUV = float2(1.0f - zoomed.x, zoomed.y);

    return videoTexture.sample(s, mirrorUV);
}
"""
