import AVFoundation
import CoreMedia

final class AudioManager: NSObject, @unchecked Sendable {

    private var session: AVCaptureSession?
    private let audioQueue = DispatchQueue(label: "com.youtuberecorder.audio", qos: .userInteractive)

    var onAudioSample: ((CMSampleBuffer) -> Void)?

    /// Start capture with an optional specific microphone device.
    func startCapture(device: AVCaptureDevice? = nil) throws {
        let session = AVCaptureSession()

        let mic: AVCaptureDevice
        if let device {
            mic = device
        } else {
            guard let defaultMic = AVCaptureDevice.default(for: .audio) else {
                throw AudioError.noMicrophoneFound
            }
            mic = defaultMic
        }

        let input = try AVCaptureDeviceInput(device: mic)
        guard session.canAddInput(input) else { throw AudioError.cannotAddInput }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: audioQueue)
        guard session.canAddOutput(output) else { throw AudioError.cannotAddOutput }
        session.addOutput(output)

        self.session = session
        audioQueue.async { session.startRunning() }
    }

    func stopCapture() {
        audioQueue.async { [weak self] in
            self?.session?.stopRunning()
            self?.session = nil
        }
    }

    enum AudioError: LocalizedError {
        case noMicrophoneFound, cannotAddInput, cannotAddOutput
        var errorDescription: String? {
            switch self {
            case .noMicrophoneFound: return "No microphone found"
            case .cannotAddInput:    return "Cannot add audio input"
            case .cannotAddOutput:   return "Cannot add audio output"
            }
        }
    }
}

extension AudioManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        onAudioSample?(sampleBuffer)
    }
}
