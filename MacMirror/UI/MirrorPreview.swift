import SwiftUI
import AVFoundation

struct MirrorPreview: NSViewRepresentable {
    let capture: MirrorCapture
    let zoom: Double

    func makeNSView(context: Context) -> MirrorPreviewView {
        let view = MirrorPreviewView()
        view.capture = capture
        view.zoom = zoom
        return view
    }

    func updateNSView(_ nsView: MirrorPreviewView, context: Context) {
        nsView.capture = capture
        nsView.zoom = zoom
    }
}

final class MirrorPreviewView: NSView {
    var capture: MirrorCapture? {
        didSet { applyConfiguration() }
    }
    var zoom: Double = 1.0 {
        didSet { applyConfiguration() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    override func makeBackingLayer() -> CALayer {
        let preview = AVCaptureVideoPreviewLayer()
        preview.videoGravity = .resizeAspectFill
        return preview
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        applyConfiguration()
    }

    override func layout() {
        super.layout()
        applyConfiguration()
    }

    private func applyConfiguration() {
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else { return }
        if previewLayer.session !== capture?.session {
            previewLayer.session = capture?.session
        }
        previewLayer.videoGravity = .resizeAspectFill
        if let connection = previewLayer.connection {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        let z = max(1.0, min(3.0, zoom))
        previewLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        previewLayer.setAffineTransform(CGAffineTransform(scaleX: CGFloat(z), y: CGFloat(z)))
    }
}
