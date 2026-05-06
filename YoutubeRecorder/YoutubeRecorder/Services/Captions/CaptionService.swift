import Foundation
import Speech
import AVFoundation
import CoreMedia

/// A single caption segment with timing information for SRT export.
struct CaptionSegment: Identifiable, Codable, Sendable {
    let id: UUID
    let startTime: TimeInterval
    var endTime: TimeInterval
    var text: String

    init(startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

/// Real-time speech-to-text service using Apple Speech framework.
/// Accepts CMSampleBuffer audio frames from the recording pipeline
/// and produces streaming transcription results.
final class CaptionService: @unchecked Sendable {

    // MARK: - Public State

    private let stateLock = NSLock()

    private var _isTranscribing = false
    var isTranscribing: Bool {
        get { stateLock.withLock { _isTranscribing } }
        set { stateLock.withLock { _isTranscribing = newValue } }
    }

    private var _currentCaption = ""
    var currentCaption: String {
        get { stateLock.withLock { _currentCaption } }
        set { stateLock.withLock { _currentCaption = newValue } }
    }

    private var _captionSegments: [CaptionSegment] = []
    var captionSegments: [CaptionSegment] {
        get { stateLock.withLock { _captionSegments } }
        set { stateLock.withLock { _captionSegments = newValue } }
    }

    // MARK: - Callbacks

    /// Called on each transcription update (partial or final). Called from background queue.
    var onCaptionUpdate: ((String) -> Void)?

    /// Called when a segment is finalized. Called from background queue.
    var onSegmentFinalized: ((CaptionSegment) -> Void)?

    // MARK: - Private

    private let speechQueue = DispatchQueue(label: "com.youtuberecorder.speech", qos: .userInitiated)
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// The audio format the Speech framework expects — set once from the first buffer
    private var audioFormat: AVAudioFormat?

    /// Recording start time — used to compute segment timestamps
    private var recordingStartTime: Date?

    /// Track the last finalized segment end to compute next segment start
    private var lastSegmentEnd: TimeInterval = 0

    /// Buffer count for debug logging
    private var bufferCount: Int = 0

    /// Locale for speech recognition (defaults to system locale)
    private let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    // MARK: - Public API

    /// Start streaming transcription. Call this when recording begins.
    func startTranscription() {
        speechQueue.async { [weak self] in
            self?.startTranscriptionOnQueue()
        }
    }

    /// Feed an audio sample buffer from the mic/system audio pipeline.
    /// This is called on the audio capture queue — must be fast.
    func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isTranscribing else { return }
        guard let request = recognitionRequest else { return }

        // Convert CMSampleBuffer to AVAudioPCMBuffer for the Speech framework
        guard let pcmBuffer = convertToPCMBuffer(sampleBuffer) else { return }

        request.append(pcmBuffer)

        bufferCount += 1
        if bufferCount % 100 == 0 {
            print("[Captions] Fed \(bufferCount) audio buffers to recognizer")
        }
    }

    /// Stop transcription and finalize all pending segments.
    func stopTranscription() {
        speechQueue.async { [weak self] in
            self?.stopTranscriptionOnQueue()
        }
    }

    /// Reset all state for a new recording session.
    func reset() {
        stateLock.withLock {
            _captionSegments = []
            _currentCaption = ""
            _isTranscribing = false
        }
        lastSegmentEnd = 0
        recordingStartTime = nil
        audioFormat = nil
        bufferCount = 0
    }

    // MARK: - Private Implementation

    private func startTranscriptionOnQueue() {
        guard !isTranscribing else { return }

        speechRecognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[Captions] Speech recognizer not available for locale: \(locale.identifier)")
            return
        }

        // Configure the recognition request for streaming
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        // On macOS 14+, use on-device recognition if available
        if #available(macOS 14, *) {
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
                print("[Captions] Using on-device speech recognition")
            } else {
                print("[Captions] Using server-based speech recognition")
            }
        }

        recordingStartTime = Date()
        lastSegmentEnd = 0

        // Start the recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.currentCaption = text

                // Notify UI
                self.onCaptionUpdate?(text)

                // If this is a final result, create a segment
                if result.isFinal {
                    self.finalizeSegment(text: text)
                    print("[Captions] Final result: \(text)")
                }
            }

            if let error {
                // The recognizer may stop due to silence or rate limits
                let nsError = error as NSError
                print("[Captions] Recognition error: \(nsError.domain) code=\(nsError.code) — \(error.localizedDescription)")

                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                    // "No speech detected" — restart if still recording
                    if self.isTranscribing {
                        print("[Captions] No speech detected, restarting...")
                        self.restartRecognition()
                    }
                } else if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 1101 || nsError.code == 1107) {
                    // Recognition session expired (1101) or rate limited (1107) — restart
                    if self.isTranscribing {
                        print("[Captions] Session expired/limited, restarting...")
                        self.restartRecognition()
                    }
                }
            }
        }

        recognitionRequest = request
        isTranscribing = true
        print("[Captions] Transcription started (locale: \(locale.identifier))")
    }

    private func stopTranscriptionOnQueue() {
        guard isTranscribing else { return }
        isTranscribing = false

        // Finalize any pending partial text
        let pending = currentCaption
        if !pending.isEmpty {
            finalizeSegment(text: pending)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        speechRecognizer = nil

        print("[Captions] Transcription stopped. Total segments: \(captionSegments.count), buffers processed: \(bufferCount)")
    }

    /// Restart recognition (e.g., after a silence timeout).
    /// The Speech framework has a ~60s limit per recognition task.
    private func restartRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        // Small delay to avoid rapid restarts
        Thread.sleep(forTimeInterval: 0.5)

        guard isTranscribing else { return }

        // Re-create the request and task
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        if #available(macOS 14, *) {
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.currentCaption = text
                self.onCaptionUpdate?(text)

                if result.isFinal {
                    self.finalizeSegment(text: text)
                }
            }

            if let error {
                let nsError = error as NSError
                if (nsError.domain == "kAFAssistantErrorDomain") && self.isTranscribing {
                    self.restartRecognition()
                }
            }
        }

        recognitionRequest = request
        print("[Captions] Recognition restarted")
    }

    private func finalizeSegment(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let startDate = recordingStartTime else { return }

        let now = Date()
        let endTime = now.timeIntervalSince(startDate)
        let startTime = lastSegmentEnd

        let segment = CaptionSegment(
            startTime: startTime,
            endTime: endTime,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        stateLock.withLock {
            _captionSegments.append(segment)
            _currentCaption = ""
        }
        lastSegmentEnd = endTime
        onSegmentFinalized?(segment)
    }

    // MARK: - Audio Conversion

    /// Convert a CMSampleBuffer (from AVCaptureAudioDataOutput) to an AVAudioPCMBuffer
    /// suitable for SFSpeechAudioBufferRecognitionRequest.
    private func convertToPCMBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else { return nil }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return nil }

        // Create or reuse the target format (16kHz mono Float32 — optimal for Speech framework)
        if audioFormat == nil {
            audioFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: asbd.mSampleRate,
                channels: 1,
                interleaved: false
            )
            print("[Captions] Audio format: \(asbd.mSampleRate)Hz, \(asbd.mChannelsPerFrame)ch, \(asbd.mBitsPerChannel)bit, flags=\(asbd.mFormatFlags)")
        }

        guard let targetFormat = audioFormat else { return nil }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(numSamples)
        ) else { return nil }
        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        // Get raw audio bytes from the sample buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var dataLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
            totalLengthOut: &dataLength, dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let rawData = dataPointer else { return nil }

        guard let floatChannelData = pcmBuffer.floatChannelData else { return nil }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let bytesPerSample = Int(asbd.mBitsPerChannel / 8)
        let channels = Int(asbd.mChannelsPerFrame)
        let totalSamples = numSamples * channels

        if isFloat && bytesPerSample == 4 {
            // Float32 source — copy channel 0 (or mono)
            let srcPtr = UnsafeRawPointer(rawData).bindMemory(to: Float.self, capacity: totalSamples)
            for i in 0..<numSamples {
                floatChannelData[0][i] = srcPtr[i * channels] // Take first channel
            }
        } else if !isFloat && bytesPerSample == 2 {
            // Int16 source (most common from AVCaptureAudioDataOutput)
            let srcPtr = UnsafeRawPointer(rawData).bindMemory(to: Int16.self, capacity: totalSamples)
            for i in 0..<numSamples {
                floatChannelData[0][i] = Float(srcPtr[i * channels]) / 32768.0
            }
        } else if !isFloat && bytesPerSample == 4 {
            // Int32 source
            let srcPtr = UnsafeRawPointer(rawData).bindMemory(to: Int32.self, capacity: totalSamples)
            for i in 0..<numSamples {
                floatChannelData[0][i] = Float(srcPtr[i * channels]) / Float(Int32.max)
            }
        } else {
            print("[Captions] Unsupported audio format: \(bytesPerSample) bytes/sample, isFloat=\(isFloat)")
            return nil
        }

        return pcmBuffer
    }
}
