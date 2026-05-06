import ScreenCaptureKit
import CoreMedia
import CoreImage
import AppKit

final class ScreenCaptureManager: NSObject, @unchecked Sendable {

    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "com.youtuberecorder.screen", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.youtuberecorder.systemaudio", qos: .userInteractive)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private let frameLock = NSLock()
    private var _latestSampleBuffer: CMSampleBuffer?
    private var frameCounter: Int = 0

    var onScreenFrame: ((CMSampleBuffer) -> Void)?
    var onPreviewFrame: ((CGImage) -> Void)?
    var onSystemAudioFrame: ((CMSampleBuffer) -> Void)?

    var latestSampleBuffer: CMSampleBuffer? {
        frameLock.withLock { _latestSampleBuffer }
    }

    var captureSize: CGSize {
        guard let buf = latestSampleBuffer,
              let pb = CMSampleBufferGetImageBuffer(buf) else {
            return CGSize(width: 1920, height: 1080)
        }
        return CGSize(width: CVPixelBufferGetWidth(pb),
                      height: CVPixelBufferGetHeight(pb))
    }

    // MARK: - Public

    func availableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays
    }

    /// Start capture. If cropRect is provided (in screen coordinates, bottom-left origin),
    /// only that portion of the display is captured.
    func startCapture(
        display: SCDisplay,
        cropRect: CGRect? = nil,
        frameRate: Int = 30,
        captureSystemAudio: Bool = false,
        qualityPreset: QualityPreset = .original
    ) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excluded = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()

        if let rect = cropRect {
            // Convert from screen coords (bottom-left origin) to display coords (top-left origin)
            let displayH = CGFloat(display.height)
            let sourceRect = CGRect(
                x: rect.origin.x,
                y: displayH - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )
            config.sourceRect = sourceRect
            config.width = Int(rect.width) * 2
            config.height = Int(rect.height) * 2
        } else {
            // Apply quality preset
            if let (w, h) = qualityPreset.resolution(displayWidth: display.width, displayHeight: display.height) {
                config.width = w
                config.height = h
            } else {
                config.width = display.width * 2
                config.height = display.height * 2
            }
        }

        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 5
        config.showsCursor = true

        // System audio capture
        if captureSystemAudio {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.channelCount = 2
            config.sampleRate = 48000
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)

        if captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }

        try await stream.startCapture()
        self.stream = stream
    }

    func stopCapture() async {
        do { try await stream?.stopCapture() }
        catch { print("[ScreenCapture] Stop error: \(error)") }
        stream = nil
    }
}

// MARK: - SCStreamOutput
extension ScreenCaptureManager: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
            frameLock.withLock { _latestSampleBuffer = sampleBuffer }
            onScreenFrame?(sampleBuffer)

            frameCounter += 1
            if frameCounter % 3 == 0,
               let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let ci = CIImage(cvPixelBuffer: pb)
                if let cg = ciContext.createCGImage(ci, from: ci.extent) {
                    onPreviewFrame?(cg)
                }
            }

        case .audio:
            onSystemAudioFrame?(sampleBuffer)

        @unknown default:
            break
        }
    }
}

// MARK: - SCStreamDelegate
extension ScreenCaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCapture] Stopped: \(error.localizedDescription)")
    }
}
