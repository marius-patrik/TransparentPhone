import AVFoundation
import CoreMedia
import Foundation

final class MirrorCapture: NSObject, ObservableObject {
    let session = AVCaptureSession()
    let previewLayer = AVCaptureVideoPreviewLayer()

    @Published private(set) var isRunning = false
    @Published private(set) var cameraName = "Discovering camera..."
    @Published private(set) var permissionDenied = false

    private let queue = DispatchQueue(label: "transparent-mirror.capture", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let visionHandler: (CVPixelBuffer, CMTime) -> Void
    private var configured = false
    private var notificationObservers: [NSObjectProtocol] = []

    init(visionHandler: @escaping (CVPixelBuffer, CMTime) -> Void) {
        self.visionHandler = visionHandler
        super.init()
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        setupNotifications()
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.permissionDenied = false }
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.permissionDenied = false
                        self.configureAndStart()
                    } else {
                        self.permissionDenied = true
                        self.cameraName = "Permission denied"
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.permissionDenied = true
                self.cameraName = "Permission denied in System Settings"
            }
        @unknown default:
            DispatchQueue.main.async { self.permissionDenied = true }
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
            guard !self.session.isRunning else {
                DispatchQueue.main.async { self.isRunning = true }
                return
            }
            self.session.startRunning()
            let running = self.session.isRunning
            DispatchQueue.main.async {
                self.isRunning = running
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        defer {
            session.commitConfiguration()
            updateMirroring()
        }

        guard let device = preferredCamera() else {
            DispatchQueue.main.async { self.cameraName = "No camera found" }
            return
        }

        do {
            for input in session.inputs {
                session.removeInput(input)
            }
            for out in session.outputs {
                session.removeOutput(out)
            }

            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                DispatchQueue.main.async { self.cameraName = "Cannot add camera input" }
                return
            }
            session.addInput(input)

            if session.canAddOutput(output) {
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: queue)
                session.addOutput(output)
            }

            let name = device.localizedName
            DispatchQueue.main.async { self.cameraName = name }
        } catch {
            DispatchQueue.main.async { self.cameraName = "Camera error: \(error.localizedDescription)" }
        }
    }

    func updateMirroring() {
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    private func preferredCamera() -> AVCaptureDevice? {
        if let defaultDevice = AVCaptureDevice.default(for: .video) {
            return defaultDevice
        }
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .externalUnknown]
        if #available(macOS 14.0, *) {
            types.append(.continuityCamera)
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first(where: { $0.position == .front }) ?? discovery.devices.first
    }

    private func setupNotifications() {
        let center = NotificationCenter.default
        let connectObs = center.addObserver(forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                self.configure()
                if self.isRunning && !self.session.isRunning {
                    self.session.startRunning()
                    let running = self.session.isRunning
                    DispatchQueue.main.async { self.isRunning = running }
                }
            }
        }
        let disconnectObs = center.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                self.configure()
            }
        }
        let runtimeErrorObs = center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                if self.isRunning {
                    self.session.startRunning()
                    let running = self.session.isRunning
                    DispatchQueue.main.async { self.isRunning = running }
                }
            }
        }
        notificationObservers = [connectObs, disconnectObs, runtimeErrorObs]
    }
}

extension MirrorCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            visionHandler(pixelBuffer, timestamp)
        }
    }
}
