import SwiftUI
import AVFoundation

struct MirrorPreview: NSViewRepresentable {
    let capture: MirrorCapture
    let zoom: Double

    func makeNSView(context: Context) -> MirrorPreviewView {
        let view = MirrorPreviewView()
        view.capture = capture
        view.zoom = zoom
        view.updateSession()
        return view
    }

    func updateNSView(_ nsView: MirrorPreviewView, context: Context) {
        nsView.capture = capture
        nsView.zoom = zoom
        nsView.updateSession()
    }
}

final class MirrorPreviewView: NSView {
    var capture: MirrorCapture? {
        didSet { updateSession() }
    }
    var zoom: Double = 1.0 {
        didSet { updateZoom() }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
    }

    override func makeBackingLayer() -> CALayer {
        let preview = AVCaptureVideoPreviewLayer()
        preview.videoGravity = .resizeAspectFill
        return preview
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

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateZoom()
    }

    override func layout() {
        super.layout()
        updateZoom()
    }

    func updateSession() {
        guard let previewLayer = previewLayer, let session = capture?.session else { return }
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        updateZoom()
    }

    func updateZoom() {
        guard let previewLayer = previewLayer else { return }
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}
