import Foundation
import Metal
import MetalKit

final class TransparencyPipeline {
    let device: MTLDevice

    private let arSession = ARTransparencySession()
    private var renderer: TransparencyRenderer?
    private weak var view: MTKView?
    private var started = false

    var onTracking: ((TrackingQuality) -> Void)?
    var onCalibrationProgress: ((Double) -> Void)?
    var onError: ((String) -> Void)?

    var debugOverlay = false {
        didSet { renderer?.debugOverlay = debugOverlay }
    }

    init() {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal is unavailable") }
        self.device = device
        renderer = TransparencyRenderer(device: device)

        arSession.onFrame = { [weak self] frame in
            self?.renderer?.setFrame(frame)
        }
        arSession.onEyeOffset = { [weak self] offset in
            self?.renderer?.setEye(offset)
        }
        arSession.onTracking = { [weak self] quality in
            self?.onTracking?(quality)
        }
        arSession.onCalibrationProgress = { [weak self] progress in
            self?.onCalibrationProgress?(progress)
        }
        arSession.onError = { [weak self] message in
            self?.onError?(message)
        }
    }

    func prepare() {
        renderer?.parallaxEnabled = true
        renderer?.depthEnabled = true
    }

    func attach(view: MTKView) {
        self.view = view
        view.delegate = renderer
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = false
        renderer?.view = view
    }

    func start(parallax: Bool, depth: Bool, strength: Float) {
        renderer?.parallaxEnabled = parallax
        renderer?.depthEnabled = depth
        renderer?.strength = strength
        started = true
        arSession.start()
    }

    func stop() {
        guard started else { return }
        started = false
        arSession.stop()
    }

    func setParallax(_ enabled: Bool) { renderer?.parallaxEnabled = enabled }
    func setDepth(_ enabled: Bool) { renderer?.depthEnabled = enabled }
    func setStrength(_ value: Float) { renderer?.strength = value }
    func calibrateViewer() { arSession.beginCalibration() }
}
