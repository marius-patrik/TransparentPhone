import SwiftUI
import AVFoundation
import Combine

@MainActor
final class MirrorModel: ObservableObject {
    @Published var showControls = true
    @Published var showTracking = false
    @Published var eyeTrackingEnabled = true
    @Published var mirrorScale: Double = 1.0
    @Published var zoom: Double = 1.0

    let capture: MirrorCapture
    let tracker: MirrorFaceTracker
    private var cancellables = Set<AnyCancellable>()

    init() {
        let tracker = MirrorFaceTracker()
        self.tracker = tracker
        self.capture = MirrorCapture { [weak tracker] buffer, timestamp in
            tracker?.process(buffer, timestamp: timestamp)
        }

        // Forward capture state changes (isRunning, cameraName, permissionDenied)
        capture.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward tracker state changes (face/eye tracking confidence and landmarks)
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
