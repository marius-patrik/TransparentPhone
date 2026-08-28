import Combine
import Foundation

@MainActor
final class TransparencyModel: ObservableObject {
    @Published var running = false
    @Published var trackingQuality: TrackingQuality = .unavailable
    @Published var parallax = true
    @Published var depthReprojection = true
    @Published var strength: Float = 1.0
    @Published var debugOverlay = false
    @Published var calibrationProgress: Double = 1.0
    @Published var errorMessage: String?

    let pipeline = TransparencyPipeline()

    init() {
        pipeline.onTracking = { [weak self] quality in
            Task { @MainActor in
                self?.trackingQuality = quality
            }
        }
        pipeline.onCalibrationProgress = { [weak self] progress in
            Task { @MainActor in
                self?.calibrationProgress = progress
            }
        }
        pipeline.onError = { [weak self] message in
            Task { @MainActor in
                self?.errorMessage = message
                self?.running = false
            }
        }
    }

    func start() {
        guard !running else { return }
        errorMessage = nil
        pipeline.start(parallax: parallax, depth: depthReprojection, strength: strength)
        running = true
    }

    func stop() {
        pipeline.stop()
        running = false
        trackingQuality = .unavailable
    }

    func calibrate() {
        pipeline.calibrateViewer()
    }

    func setStrength(_ value: Float) {
        strength = value
        pipeline.setStrength(value)
    }
}
