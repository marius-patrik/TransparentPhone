import Vision
import CoreMedia
import Foundation
import QuartzCore

struct EyeTrackingState: Sendable {
    var leftEye: CGPoint = .zero
    var rightEye: CGPoint = .zero
    var faceBounds: CGRect = .zero
    var yaw: Double = 0
    var pitch: Double = 0
    var roll: Double = 0
    var confidence: Double = 0
    var timestamp: CMTime = .zero

    var center: CGPoint {
        CGPoint(x: (leftEye.x + rightEye.x) * 0.5, y: (leftEye.y + rightEye.y) * 0.5)
    }
}

final class MirrorFaceTracker: ObservableObject {
    @Published private(set) var state = EyeTrackingState()

    private let queue = DispatchQueue(label: "transparent-mirror.vision", qos: .userInitiated)
    private var lastRequestTime: CFTimeInterval = 0
    private let minInterval: CFTimeInterval = 1.0 / 30.0
    private var isProcessing = false

    func process(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        let now = CACurrentMediaTime()
        guard now - lastRequestTime >= minInterval else { return }
        guard !isProcessing else { return } // Drop frame if previous Vision analysis is still running

        isProcessing = true
        lastRequestTime = now

        queue.async { [weak self] in
            autoreleasepool {
                defer { self?.isProcessing = false }
                guard let self else { return }

                let request = VNDetectFaceLandmarksRequest()
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
                do {
                    try handler.perform([request])
                    guard let face = request.results?.first else {
                        DispatchQueue.main.async {
                            if self.state.confidence > 0 {
                                self.state.confidence = 0
                            }
                        }
                        return
                    }
                    let landmarks = face.landmarks
                    let left = Self.eyeCenter(landmarks?.leftEye)
                    let right = Self.eyeCenter(landmarks?.rightEye)
                    guard let left, let right else { return }

                    let observation = EyeTrackingState(
                        leftEye: left,
                        rightEye: right,
                        faceBounds: face.boundingBox,
                        yaw: Double(face.yaw?.doubleValue ?? 0),
                        pitch: Double(face.pitch?.doubleValue ?? 0),
                        roll: Double(face.roll?.doubleValue ?? 0),
                        confidence: 1,
                        timestamp: timestamp
                    )
                    DispatchQueue.main.async {
                        self.state = Self.smooth(old: self.state, new: observation, alpha: 0.3)
                    }
                } catch {
                    DispatchQueue.main.async {
                        if self.state.confidence > 0 {
                            self.state.confidence = 0
                        }
                    }
                }
            }
        }
    }

    private static func eyeCenter(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
        guard let points = region?.normalizedPoints, !points.isEmpty else { return nil }
        let x = points.reduce(0) { $0 + $1.x } / CGFloat(points.count)
        let y = points.reduce(0) { $0 + $1.y } / CGFloat(points.count)
        return CGPoint(x: x, y: y)
    }

    private static func smooth(old: EyeTrackingState, new: EyeTrackingState, alpha: CGFloat) -> EyeTrackingState {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * alpha }
        return EyeTrackingState(
            leftEye: CGPoint(x: mix(old.leftEye.x, new.leftEye.x), y: mix(old.leftEye.y, new.leftEye.y)),
            rightEye: CGPoint(x: mix(old.rightEye.x, new.rightEye.x), y: mix(old.rightEye.y, new.rightEye.y)),
            faceBounds: new.faceBounds,
            yaw: old.yaw + (new.yaw - old.yaw) * Double(alpha),
            pitch: old.pitch + (new.pitch - old.pitch) * Double(alpha),
            roll: old.roll + (new.roll - old.roll) * Double(alpha),
            confidence: new.confidence,
            timestamp: new.timestamp
        )
    }
}
