import AVFoundation
import CoreImage
import Foundation

final class MirrorCapture: NSObject, ObservableObject {
    let session = AVCaptureSession()
    let previewLayer = AVCaptureVideoPreviewLayer()

    @Published private(set) var isRunning = false
    @Published private(set) var cameraName = "No camera"
    @Published private(set) var permissionDenied = false

    private let queue = DispatchQueue(label: "transparent-mirror.capture", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let visionHandler: (CVPixelBuffer, CMTime) -> Void
    private var configured = false

    init(visionHandler: @escaping (CVPixelBuffer, CMTime) -> Void) {
        self.visionHandler = visionHandler
        super.init()
        previewLayer.videoGravity = .resizeAspectFill
    }

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureAndStart()
                    } else {
                        self.permissionDenied = true
                    }
                }
            }
        default:
            permissionDenied = true
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    private func configureAndStart() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.configure()
                self.configured = true
            }
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = self.session.isRunning
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        defer { session.commitConfiguration() }

        guard let device = preferredCamera() else {
            DispatchQueue.main.async { self.cameraName = "No camera" }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { return }
            session.addInput(input)

            guard session.canAddOutput(output) else { return }
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(output)

            if let connection = output.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
            if let connection = previewLayer.connection {
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }

            previewLayer.session = session
            DispatchQueue.main.async { self.cameraName = device.localizedName }
        } catch {
            DispatchQueue.main.async { self.cameraName = "Camera error" }
        }
    }

    private func preferredCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .front
        )
        return discovery.devices.first(where: { $0.position == .front }) ?? discovery.devices.first
    }
}

extension MirrorCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        visionHandler(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
