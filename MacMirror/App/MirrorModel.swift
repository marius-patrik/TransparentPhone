import SwiftUI
import AVFoundation
import Combine
import Metal

@MainActor
final class MirrorModel: ObservableObject {
    @Published var showControls = true
    @Published var showTracking = false
    @Published var eyeTrackingEnabled = true
    @Published var mirrorScale: Double = 1.0
    @Published var zoom: Double = 1.0

    let capture: MirrorCapture
    let tracker: MirrorFaceTracker
    let renderer: MirrorRenderer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let tracker = MirrorFaceTracker()
        self.tracker = tracker
        self.capture = MirrorCapture()

        if let device = MTLCreateSystemDefaultDevice() {
            self.renderer = MirrorRenderer(device: device)
        } else {
            self.renderer = nil
        }

        let rendererRef = self.renderer
        capture.onFrame = { buffer in
            rendererRef?.setPixelBuffer(buffer)
        }
        capture.visionHandler = { [weak tracker] buffer, timestamp in
            tracker?.process(buffer, timestamp: timestamp)
        }

        // Forward capture state changes
        capture.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward tracker state changes
        tracker.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var trackingLabel: String {
        tracker.state.confidence > 0.5 ? "Eyes tracked" : "Searching for face"
    }

    func start() { capture.requestAndStart() }
    func stop() { capture.stop() }
}
