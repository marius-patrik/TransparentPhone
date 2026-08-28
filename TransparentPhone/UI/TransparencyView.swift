import SwiftUI
import MetalKit

struct TransparencyView: UIViewRepresentable {
    let pipeline: TransparencyPipeline

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: pipeline.device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        pipeline.attach(view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
