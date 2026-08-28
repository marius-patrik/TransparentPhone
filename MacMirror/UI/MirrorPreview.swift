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
        didSet { updatePreviewSession() }
    }
    var zoom: Double = 1.0 {
        didSet { updateZoom() }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override func layout() {
        super.layout()
        updateZoom()
    }

    private func updatePreviewSession() {
        guard let capture = capture else { return }
        if let layer = previewLayer {
            if layer.session !== capture.session {
                layer.session = capture.session
            }
        } else {
            let layer = AVCaptureVideoPreviewLayer(session: capture.session)
            layer.videoGravity = .resizeAspectFill
            if let connection = layer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            self.layer?.addSublayer(layer)
            self.previewLayer = layer
        }
        updateZoom()
    }

    private func updateZoom() {
        guard let previewLayer = previewLayer else {
            updatePreviewSession()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if previewLayer.session !== capture?.session {
            previewLayer.session = capture?.session
        }

        let z = max(1.0, min(3.0, zoom))
        if z > 1.001 {
            let width = bounds.width
            let height = bounds.height
            let scaledWidth = width * CGFloat(z)
            let scaledHeight = height * CGFloat(z)
            let originX = (width - scaledWidth) * 0.5
            let originY = (height - scaledHeight) * 0.5
            previewLayer.frame = CGRect(x: originX, y: originY, width: scaledWidth, height: scaledHeight)
        } else {
            previewLayer.frame = bounds
        }

        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        CATransaction.commit()
    }
}
