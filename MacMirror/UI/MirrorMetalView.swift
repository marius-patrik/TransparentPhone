import SwiftUI
import MetalKit

struct MirrorMetalView: NSViewRepresentable {
    let renderer: MirrorRenderer?
    let zoom: Double

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        if let renderer = renderer {
            view.device = renderer.device
            view.delegate = renderer
        }
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        if let renderer = renderer {
            if nsView.device !== renderer.device {
                nsView.device = renderer.device
            }
            if nsView.delegate !== renderer {
                nsView.delegate = renderer
            }
            renderer.zoom = Float(zoom)
        }
    }
}
