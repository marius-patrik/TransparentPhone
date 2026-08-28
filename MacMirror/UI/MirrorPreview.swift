import SwiftUI
import AVFoundation

struct MirrorPreview: NSViewRepresentable {
    let capture: MirrorCapture
    let zoom: Double

    func makeNSView(context: Context) -> MirrorPreviewView {
        let view = MirrorPreviewView()
        view.capture = capture
        view.zoom = zoom
        view.setupLayer()
        return view
    }

    func updateNSView(_ nsView: MirrorPreviewView, context: Context) {
        nsView.capture = capture
        nsView.zoom = zoom
        nsView.setupLayer()
    }
}

final class MirrorPreviewView: NSView {
    var capture: MirrorCapture? {
        didSet { setupLayer() }
    }
    var zoom: Double = 1.0 {
        didSet { updateLayerFrame() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override func layout() {
        super.layout()
        updateLayerFrame()
    }

    func setupLayer() {
        guard let capture = capture else { return }
        if capture.previewLayer.superlayer !== layer {
            capture.previewLayer.removeFromSuperlayer()
            layer?.addSublayer(capture.previewLayer)
        }
        updateLayerFrame()
    }

    private func updateLayerFrame() {
        guard let capture = capture else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let z = max(1.0, min(3.0, zoom))
        if z > 1.001 {
            let w = bounds.width * CGFloat(z)
            let h = bounds.height * CGFloat(z)
            let x = (bounds.width - w) * 0.5
            let y = (bounds.height - h) * 0.5
            capture.previewLayer.frame = CGRect(x: x, y: y, width: w, height: h)
        } else {
            capture.previewLayer.frame = bounds
        }

        capture.updateMirroring()
        CATransaction.commit()
    }
}
