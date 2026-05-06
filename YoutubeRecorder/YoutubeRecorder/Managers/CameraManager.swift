import AVFoundation
import CoreMedia
import CoreImage

final class CameraManager: NSObject, @unchecked Sendable {

    private(set) var session: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "com.youtuberecorder.camera", qos: .userInteractive)

    private let frameLock = NSLock()
    private var _latestPixelBuffer: CVPixelBuffer?
    private var frameCounter = 0
    private let previewContext = CIContext(options: [.useSoftwareRenderer: false])

    let backgroundProcessor = BackgroundProcessor()

    var latestPixelBuffer: CVPixelBuffer? {
        frameLock.withLock { _latestPixelBuffer }
    }

    var onProcessedPreview: ((CGImage) -> Void)?

    // MARK: - Public

    /// Start capture with an optional specific device. Passing nil uses the default camera.
    /// iPhone cameras appear via Continuity Camera as .external devices.
    func startCapture(device: AVCaptureDevice? = nil) throws {
        // Stop existing session
        if session != nil { stopCaptureSync() }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high

        let camera: AVCaptureDevice
        if let device {
            camera = device
        } else {
            guard let defaultCam = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                            for: .video,
                                                            position: .unspecified) else {
                throw CameraError.noCameraFound
            }
            camera = defaultCam
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.alwaysDiscardsLateVideoFrames = true

        guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        session.addOutput(output)

        if let conn = output.connection(with: .video), conn.isVideoMirroringSupported {
            conn.isVideoMirrored = true
        }

        session.commitConfiguration()
        self.session = session
        sessionQueue.async { session.startRunning() }
    }

    func stopCapture() {
        sessionQueue.async { [weak self] in
            self?.session?.stopRunning()
            self?.session = nil
        }
    }

    private func stopCaptureSync() {
        session?.stopRunning()
        session = nil
    }

    enum CameraError: LocalizedError {
        case noCameraFound, cannotAddInput, cannotAddOutput
        var errorDescription: String? {
            switch self {
            case .noCameraFound:  return "No camera found"
            case .cannotAddInput: return "Cannot add camera input"
            case .cannotAddOutput: return "Cannot add camera output"
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let rawBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let processed = backgroundProcessor.process(rawBuffer)
        frameLock.withLock { _latestPixelBuffer = processed }

        frameCounter += 1
        if frameCounter % 2 == 0 {
            let ci = CIImage(cvPixelBuffer: processed)
            if let cg = previewContext.createCGImage(ci, from: ci.extent) {
                onProcessedPreview?(cg)
            }
        }
    }
}
