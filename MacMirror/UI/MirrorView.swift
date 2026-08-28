import SwiftUI
import AppKit

struct MirrorView: View {
    @ObservedObject var model: MirrorModel

    var body: some View {
        ZStack {
            // Dark base background
            Color.black.ignoresSafeArea()

            // Layer 1: Hardware-backed preview layer
            MirrorPreview(capture: model.capture, zoom: model.zoom)
                .ignoresSafeArea()

            // Layer 2: Direct CIImage-rendered mirrored camera frame
            if let frame = model.capture.latestFrame {
                Image(decorative: frame, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(model.zoom)
                    .ignoresSafeArea()
            } else if model.capture.isRunning {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Connecting to \(model.capture.cameraName)...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            // Tracking visualization overlay
            if model.showTracking && model.eyeTrackingEnabled {
                TrackingOverlay(state: model.tracker.state)
            }

            // Top & bottom control bars
            if model.showControls {
                VStack(spacing: 0) {
                    // Top Bar
                    HStack(spacing: 12) {
                        Label("Transparent Mirror", systemImage: "person.crop.rectangle")
                            .font(.headline)

                        Spacer()

                        Circle()
                            .fill(model.capture.isRunning ? .green : .red)
                            .frame(width: 8, height: 8)

                        Text(model.capture.cameraName)
                            .foregroundStyle(.secondary)

                        if model.capture.frameCount > 0 {
                            Text("\(model.capture.frameCount) frames")
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.3), in: Capsule())
                        }

                        Button(model.capture.isRunning ? "Stop" : "Start") {
                            if model.capture.isRunning {
                                model.stop()
                            } else {
                                model.start()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)

                    Spacer()

                    // Bottom Bar
                    HStack {
                        Toggle("Eye tracking", isOn: $model.eyeTrackingEnabled)
                        Toggle("Tracking overlay", isOn: $model.showTracking)

                        Spacer()

                        Text(model.trackingLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(value: $model.zoom, in: 1.0...2.5) {
                            Text("Zoom")
                        }
                        .frame(width: 150)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                }
            }

            // Permission Denied / Action Overlay
            if model.capture.permissionDenied {
                permissionDeniedOverlay
            }
        }
        .onAppear {
            model.start()
        }
        .onDisappear {
            model.stop()
        }
        .keyboardShortcut("t", modifiers: [.command])
    }

    @ViewBuilder
    private var permissionDeniedOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Camera Permission Required")
                .font(.title2.bold())

            Text("Transparent Mirror needs access to your Mac's camera. Please enable Camera permissions in System Settings.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            Button("Open Privacy & Security Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

struct TrackingOverlay: View {
    let state: EyeTrackingState

    var body: some View {
        GeometryReader { geo in
            let leftX = (1.0 - state.leftEye.x) * geo.size.width
            let leftY = (1.0 - state.leftEye.y) * geo.size.height
            let rightX = (1.0 - state.rightEye.x) * geo.size.width
            let rightY = (1.0 - state.rightEye.y) * geo.size.height

            let faceWidth = state.faceBounds.width * geo.size.width
            let faceHeight = state.faceBounds.height * geo.size.height
            let faceCenterX = (1.0 - state.faceBounds.midX) * geo.size.width
            let faceCenterY = (1.0 - state.faceBounds.midY) * geo.size.height

            if state.confidence > 0 {
                Rectangle()
                    .stroke(.green.opacity(0.7), lineWidth: 1.5)
                    .frame(width: faceWidth, height: faceHeight)
                    .position(x: faceCenterX, y: faceCenterY)

                Circle()
                    .fill(.cyan)
                    .frame(width: 8, height: 8)
                    .position(x: leftX, y: leftY)

                Circle()
                    .fill(.cyan)
                    .frame(width: 8, height: 8)
                    .position(x: rightX, y: rightY)
            }
        }
        .allowsHitTesting(false)
    }
}
