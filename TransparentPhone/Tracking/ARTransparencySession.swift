import ARKit
import AVFoundation
import Foundation
import simd

/// Single ARKit session for the complete illusion.
///
/// ARWorldTrackingConfiguration can simultaneously track the rear camera world and
/// the user's front-camera face. This is preferable to independently running a
/// TrueDepth session and a rear AVCaptureMultiCam session because ARKit gives us a
/// common world coordinate system, synchronized frames, camera intrinsics and (on
/// LiDAR devices) scene depth.
final class ARTransparencySession: NSObject, ARSessionDelegate {
    let session = ARSession()

    var onFrame: ((CVPixelBuffer, CVPixelBuffer?, simd_float3x3, CGSize) -> Void)?
    var onEyeOffset: ((SIMD3<Float>) -> Void)?
    var onTracking: ((TrackingQuality) -> Void)?
    var onCalibrationProgress: ((Double) -> Void)?
    var onError: ((String) -> Void)?

    private var neutralEye = SIMD3<Float>(0, 0, 0.55)
    private var filteredEye = SIMD3<Float>(0, 0, 0.55)
    private var lastEye = SIMD3<Float>(0, 0, 0.55)
    private var lastTimestamp: TimeInterval = 0
    private var calibrationSamples: [SIMD3<Float>] = []
    private var calibrating = false

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            onError?("AR world tracking is not supported on this device.")
            return
        }

        guard ARWorldTrackingConfiguration.supportsUserFaceTracking else {
            onError?("This device does not support simultaneous rear-camera world tracking and TrueDepth face tracking.")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.run() }
                else { self?.onError?("Camera permission was denied.") }
            }
        default:
            onError?("Camera permission is unavailable. Enable it in Settings.")
        }
    }

    func stop() {
        session.pause()
    }

    func beginCalibration() {
        calibrationSamples.removeAll(keepingCapacity: true)
        calibrating = true
        onCalibrationProgress?(0)
    }

    private func run() {
        beginCalibration()
        session.delegate = self

        let configuration = ARWorldTrackingConfiguration()
        configuration.userFaceTrackingEnabled = true
        configuration.worldAlignment = .gravity

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard case .normal = frame.camera.trackingState else {
            onTracking?(.limited)
            return
        }

        let depth = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
        onFrame?(frame.capturedImage, depth, frame.camera.intrinsics, frame.camera.imageResolution)

        guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else {
            onTracking?(.limited)
            return
        }

        // Eye transforms are relative to the face. Convert both eyes to ARKit's
        // world coordinate system, then into the rear-camera coordinate system.
        let leftWorld = simd_mul(face.transform, face.leftEyeTransform).columns.3.xyz
        let rightWorld = simd_mul(face.transform, face.rightEyeTransform).columns.3.xyz
        let eyeWorld = (leftWorld + rightWorld) * 0.5
        let eyeCamera = simd_mul(simd_inverse(frame.camera.transform), SIMD4<Float>(eyeWorld, 1)).xyz

        let timestamp = frame.timestamp
        let dt = Float(max(1.0 / 120.0, timestamp - lastTimestamp))
        lastTimestamp = timestamp
        filteredEye = smooth(raw: eyeCamera, dt: dt)
        lastEye = eyeCamera

        if calibrating {
            calibrationSamples.append(filteredEye)
            let progress = min(1.0, Double(calibrationSamples.count) / 30.0)
            onCalibrationProgress?(progress)
            if calibrationSamples.count >= 30 {
                neutralEye = calibrationSamples.reduce(.zero, +) / Float(calibrationSamples.count)
                calibrating = false
                onCalibrationProgress?(1)
            }
        }

        onEyeOffset?(filteredEye - neutralEye)
        onTracking?(.normal)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        onError?("AR session failed: \(error.localizedDescription)")
    }

    func sessionWasInterrupted(_ session: ARSession) {
        onTracking?(.limited)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        onTracking?(.limited)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal: onTracking?(.normal)
        case .limited: onTracking?(.limited)
        case .notAvailable: onTracking?(.unavailable)
        @unknown default: onTracking?(.limited)
        }
    }

    private func smooth(raw: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
        let velocity = (raw - lastEye) / dt
        let speed = simd_length(velocity)
        let cutoff = 1.2 + 0.018 * speed
        let tau = 1.0 / (2.0 * Float.pi * max(cutoff, 0.001))
        let alpha = 1.0 / (1.0 + tau / max(dt, 0.0001))
        filteredEye += (raw - filteredEye) * alpha
        return filteredEye
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}
