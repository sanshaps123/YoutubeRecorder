import SwiftUI
import AVFoundation
import ScreenCaptureKit

@Observable @MainActor
final class RecordingViewModel {

    // MARK: - UI State
    var status: RecordingStatus = .idle
    var elapsedTime: TimeInterval = 0
    var isWebcamEnabled = true
    var previewImage: CGImage?
    var webcamPreviewImage: CGImage?
    var webcamPosition: CGPoint = CGPoint(x: 0.82, y: 0.82)
    var webcamDiameter: CGFloat = 180
    var selectedBackground: WebcamBackground = .none
    var showBackgroundPicker = false
    var captureMode: CaptureMode = .fullScreen
    var selectedRegion: CGRect = .zero
    var isSystemAudioEnabled = false
    var isCountdownEnabled = true
    var countdownValue: Int = 0
    var qualityPreset: QualityPreset = .original

    // Click highlight & keystroke display
    var isClickHighlightEnabled = false
    var isKeystrokeDisplayEnabled = false

    // Recording mode (switchable at runtime)
    var recordingMode: RecordingMode = .screenAndWebcam

    // Webcam shape
    var webcamShape: WebcamShape = .circle

    // Caption state
    var isCaptionEnabled = false
    var isCaptionOverlayVisible = false
    var currentCaptionText: String = ""
    var captionStyle: CaptionStyle = .default

    // Subscription
    var freeTierTimeRemaining: TimeInterval = 300

    // Device selection
    var availableCameras: [AVCaptureDevice] = []
    var availableMics: [AVCaptureDevice] = []
    var selectedCameraId: String = ""
    var selectedMicId: String = ""

    // Info
    var resolutionText: String = "1920 × 1080"
    var freeStorageText: String = ""

    // Callbacks for AppController (menu bar stop button, webcam panel)
    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?
    var onCountdownStarted: ((Int) -> Void)?
    var onCountdownEnded: (() -> Void)?
    var onPauseChanged: ((Bool) -> Void)?
    var onRecordingModeChanged: ((RecordingMode) -> Void)?
    var onRegionSelectRequested: (() -> Void)?
    var onRegionBorderHide: (() -> Void)?
    var onCaptionOverlayChanged: ((Bool) -> Void)?
    var onFreeTierLimitReached: (() -> Void)?
    var onCaptionStylePickerRequested: (() -> Void)?

    // MARK: - Managers
    let screenManager = ScreenCaptureManager()
    let cameraManager = CameraManager()
    private let audioManager = AudioManager()
    private let composer = VideoComposer()
    let permissionManager = PermissionManager()
    private let settings = SettingsStore.shared

    // Click & keystroke managers
    private let clickHighlightManager = ClickHighlightManager()
    private let keystrokeManager = KeystrokeManager()

    // Caption service
    private let captionService = CaptionService()

    // Subscription manager
    private let subscriptionManager = SubscriptionManager.shared

    private var timer: Timer?
    private var recordingStartDate: Date?
    private var pauseAccumulator: TimeInterval = 0
    private var pauseStartDate: Date?
    private var deviceObservers: [NSObjectProtocol] = []

    init() {
        loadSettings()
        setupCallbacks()
        refreshDevices()
        updateStorageInfo()
        observeDeviceChanges()
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        selectedCameraId = settings.selectedCameraId
        selectedMicId = settings.selectedMicId
        webcamDiameter = settings.webcamDiameter
        webcamPosition = CGPoint(x: settings.webcamPositionX, y: settings.webcamPositionY)
        isWebcamEnabled = settings.isWebcamEnabled
        isSystemAudioEnabled = settings.isSystemAudioEnabled
        isCountdownEnabled = settings.isCountdownEnabled
        qualityPreset = QualityPreset(rawValue: settings.qualityPreset) ?? .original
        isClickHighlightEnabled = settings.isClickHighlightEnabled
        isKeystrokeDisplayEnabled = settings.isKeystrokeDisplayEnabled
        recordingMode = RecordingMode(rawValue: settings.recordingMode) ?? .screenAndWebcam
        webcamShape = WebcamShape(rawValue: settings.webcamShape) ?? .circle

        if let bg = WebcamBackground(rawValue: settings.webcamBackground) {
            selectedBackground = bg
            cameraManager.backgroundProcessor.mode = bg
        }
        isCaptionEnabled = settings.isCaptionEnabled
        isCaptionOverlayVisible = settings.isCaptionOverlayVisible
    }

    private func saveSettings() {
        settings.selectedCameraId = selectedCameraId
        settings.selectedMicId = selectedMicId
        settings.webcamDiameter = webcamDiameter
        settings.webcamPositionX = webcamPosition.x
        settings.webcamPositionY = webcamPosition.y
        settings.isWebcamEnabled = isWebcamEnabled
        settings.isSystemAudioEnabled = isSystemAudioEnabled
        settings.isCountdownEnabled = isCountdownEnabled
        settings.webcamBackground = selectedBackground.rawValue
        settings.qualityPreset = qualityPreset.rawValue
        settings.isClickHighlightEnabled = isClickHighlightEnabled
        settings.isKeystrokeDisplayEnabled = isKeystrokeDisplayEnabled
        settings.recordingMode = recordingMode.rawValue
        settings.webcamShape = webcamShape.rawValue
        settings.isCaptionEnabled = isCaptionEnabled
        settings.isCaptionOverlayVisible = isCaptionOverlayVisible
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        screenManager.onPreviewFrame = { [weak self] cgImage in
            Task { @MainActor in self?.previewImage = cgImage }
        }
        screenManager.onScreenFrame = { [weak self] buffer in
            self?.composer.appendScreenFrame(buffer)
        }
        // System audio from SCStream
        screenManager.onSystemAudioFrame = { [weak self] buffer in
            guard let self, self.isSystemAudioEnabled else { return }
            self.composer.appendAudioSample(buffer)
        }
        audioManager.onAudioSample = { [weak self] buffer in
            self?.composer.appendAudioSample(buffer)
            // Fork audio to caption service for real-time transcription
            if self?.isCaptionEnabled == true {
                self?.captionService.appendAudioBuffer(buffer)
            }
        }
        composer.getCameraFrame = { [weak self] in
            self?.cameraManager.latestPixelBuffer
        }
        cameraManager.onProcessedPreview = { [weak self] cgImage in
            Task { @MainActor in self?.webcamPreviewImage = cgImage }
        }

        // Click highlight events
        clickHighlightManager.onClickDetected = { [weak self] highlight in
            self?.composer.addClickHighlight(highlight)
        }

        // Keystroke events
        keystrokeManager.onKeystrokeDetected = { [weak self] keystroke in
            self?.composer.setCurrentKeystroke(keystroke)
        }

        // Caption events — feed into both UI and VideoComposer
        captionService.onCaptionUpdate = { [weak self] text in
            self?.composer.setCurrentCaption(text)
            Task { @MainActor in self?.currentCaptionText = text }
        }
    }

    // MARK: - Device Change Observers

    private func observeDeviceChanges() {
        let connectObs = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main
        ) { [weak self] notification in
            if let device = notification.object as? AVCaptureDevice {
                print("[Device] Connected: \(device.localizedName) (type: \(device.deviceType))")
            }
            Task { @MainActor in self?.refreshDevices() }
        }
        let disconnectObs = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main
        ) { [weak self] notification in
            if let device = notification.object as? AVCaptureDevice {
                print("[Device] Disconnected: \(device.localizedName)")
            }
            Task { @MainActor in self?.refreshDevices() }
        }
        deviceObservers = [connectObs, disconnectObs]
    }

    // MARK: - Device Enumeration

    func refreshDevices() {
        let videoTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external]
        let videoDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: videoTypes, mediaType: .video, position: .unspecified
        )
        availableCameras = videoDiscovery.devices
        print("[Cameras] Found \(availableCameras.count) device(s):")
        for cam in availableCameras {
            let t = cam.deviceType == .external ? "📱 External" : "💻 Built-in"
            print("  - \(cam.localizedName) [\(t)]")
        }
        if selectedCameraId.isEmpty, let first = availableCameras.first {
            selectedCameraId = first.uniqueID
        }

        let audioDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .external], mediaType: .audio, position: .unspecified
        )
        availableMics = audioDiscovery.devices
        if selectedMicId.isEmpty, let first = availableMics.first {
            selectedMicId = first.uniqueID
        }
    }

    var selectedCameraName: String {
        availableCameras.first(where: { $0.uniqueID == selectedCameraId })?.localizedName ?? "None"
    }
    var selectedMicName: String {
        availableMics.first(where: { $0.uniqueID == selectedMicId })?.localizedName ?? "None"
    }

    func selectCamera(_ id: String) {
        selectedCameraId = id
        saveSettings()
        if status.isRecording || status.isPaused {
            cameraManager.stopCapture()
            if let device = availableCameras.first(where: { $0.uniqueID == id }) {
                try? cameraManager.startCapture(device: device)
            }
        }
    }

    func selectMic(_ id: String) {
        selectedMicId = id
        saveSettings()
    }

    // MARK: - Recording with Countdown

    func startRecording() async {
        guard status == .idle else { return }

        saveSettings()

        // Countdown
        if isCountdownEnabled {
            for i in stride(from: settings.countdownDuration, to: 0, by: -1) {
                status = .countdown(i)
                countdownValue = i
                onCountdownStarted?(i)
                try? await Task.sleep(for: .seconds(1))
            }
            onCountdownEnded?()
        }

        status = .preparing

        do {
            let displays = try await screenManager.availableDisplays()
            guard let display = displays.first else {
                status = .error("No display found")
                return
            }

            let cropRect: CGRect? = (captureMode == .portion && selectedRegion.width > 20) ? selectedRegion : nil
            try await screenManager.startCapture(
                display: display,
                cropRect: cropRect,
                captureSystemAudio: isSystemAudioEnabled,
                qualityPreset: qualityPreset
            )

            // Start webcam if needed by recording mode
            let needsCamera = recordingMode != .screenOnly
            if needsCamera || isWebcamEnabled {
                let cam = availableCameras.first(where: { $0.uniqueID == selectedCameraId })
                try cameraManager.startCapture(device: cam)
            }

            let mic = availableMics.first(where: { $0.uniqueID == selectedMicId })
            try audioManager.startCapture(device: mic)

            try await Task.sleep(for: .milliseconds(300))

            let size = screenManager.captureSize
            resolutionText = "\(Int(size.width)) × \(Int(size.height))"
            let url = RecordingSettings.defaultOutputURL()
            try composer.startWriting(to: url, width: Int(size.width), height: Int(size.height))
            composer.webcamEnabled = isWebcamEnabled
            composer.webcamDiameter = webcamDiameter
            composer.clickHighlightEnabled = isClickHighlightEnabled
            composer.keystrokeDisplayEnabled = isKeystrokeDisplayEnabled
            composer.recordingMode = recordingMode
            composer.webcamShape = webcamShape
            composer.captionEnabled = isCaptionEnabled
            composer.captionStyle = captionStyle
            syncWebcamPosition()

            // Start click/keystroke managers if enabled
            if isClickHighlightEnabled {
                clickHighlightManager.start()
            }
            if isKeystrokeDisplayEnabled {
                keystrokeManager.start()
            }

            // Start caption service if enabled
            if isCaptionEnabled {
                print("[Captions] Caption enabled, checking speech permission...")
                await permissionManager.checkSpeechRecognition()
                if permissionManager.speechRecognitionAuthorized {
                    print("[Captions] Speech permission granted. Starting transcription...")
                    captionService.reset()
                    captionService.startTranscription()
                    // Sync caption state to VideoComposer
                    composer.captionEnabled = true
                    composer.captionStyle = captionStyle
                    if isCaptionOverlayVisible {
                        onCaptionOverlayChanged?(true)
                    }
                } else {
                    print("[Captions] Speech recognition permission denied. Go to System Settings > Privacy > Speech Recognition.")
                    composer.captionEnabled = false
                }
            } else {
                composer.captionEnabled = false
            }

            status = .recording
            recordingStartDate = Date()
            pauseAccumulator = 0
            startTimer()
            onRecordingStarted?()
        } catch {
            status = .error(error.localizedDescription)
            await cleanup()
        }
    }

    // MARK: - Pause / Resume

    func pauseRecording() {
        guard status == .recording else { return }
        status = .paused
        pauseStartDate = Date()
        composer.isPaused = true
        stopTimer()
        onPauseChanged?(true)
    }

    func resumeRecording() {
        guard status == .paused else { return }
        if let pauseStart = pauseStartDate {
            pauseAccumulator += Date().timeIntervalSince(pauseStart)
        }
        pauseStartDate = nil
        composer.isPaused = false
        status = .recording
        startTimer()
        onPauseChanged?(false)
    }

    func togglePause() {
        if status == .recording {
            pauseRecording()
        } else if status == .paused {
            resumeRecording()
        }
    }

    // MARK: - Stop

    func stopRecording() async {
        guard status.isActive else { return }
        status = .stopping
        stopTimer()

        // Stop click/keystroke managers
        clickHighlightManager.stop()
        keystrokeManager.stop()

        await screenManager.stopCapture()
        cameraManager.stopCapture()
        audioManager.stopCapture()
        webcamPreviewImage = nil

        // Stop captions and export SRT
        if isCaptionEnabled {
            captionService.stopTranscription()
            onCaptionOverlayChanged?(false)
            currentCaptionText = ""
        }

        if let url = await composer.finishWriting() {
            // Export SRT if captions were enabled and tier allows it
            if isCaptionEnabled && !captionService.captionSegments.isEmpty {
                if subscriptionManager.currentTier.canExportCaptions {
                    let srtURL = url.deletingPathExtension().appendingPathExtension("srt")
                    try? SRTExporter.export(segments: captionService.captionSegments, to: srtURL)
                }
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }

        onRecordingStopped?()

        status = .idle
        elapsedTime = 0
        recordingStartDate = nil
        pauseAccumulator = 0
    }

    func toggleWebcam() {
        isWebcamEnabled.toggle()
        composer.webcamEnabled = isWebcamEnabled
        saveSettings()
    }

    func updateWebcamPosition(_ point: CGPoint) {
        webcamPosition = point
        syncWebcamPosition()
        saveSettings()
    }

    func updateWebcamDiameter(_ d: CGFloat) {
        webcamDiameter = min(max(d, 80), 400)
        composer.webcamDiameter = webcamDiameter
        saveSettings()
    }

    func setBackground(_ bg: WebcamBackground) {
        selectedBackground = bg
        cameraManager.backgroundProcessor.mode = bg
        saveSettings()
    }

    func setCaptureMode(_ mode: CaptureMode) {
        captureMode = mode
        if mode == .portion {
            onRegionSelectRequested?()
        } else {
            selectedRegion = .zero
            onRegionBorderHide?()
        }
    }

    func setQualityPreset(_ preset: QualityPreset) {
        qualityPreset = preset
        saveSettings()
    }

    func toggleSystemAudio() {
        isSystemAudioEnabled.toggle()
        saveSettings()
    }

    func toggleCountdown() {
        isCountdownEnabled.toggle()
        saveSettings()
    }

    func toggleClickHighlight() {
        isClickHighlightEnabled.toggle()
        composer.clickHighlightEnabled = isClickHighlightEnabled
        saveSettings()
    }

    func toggleKeystrokeDisplay() {
        isKeystrokeDisplayEnabled.toggle()
        composer.keystrokeDisplayEnabled = isKeystrokeDisplayEnabled
        saveSettings()
    }

    func setWebcamShape(_ shape: WebcamShape) {
        webcamShape = shape
        composer.webcamShape = shape
        saveSettings()
    }

    func toggleCaptions() {
        isCaptionEnabled.toggle()
        saveSettings()
    }

    func toggleCaptionOverlay() {
        isCaptionOverlayVisible.toggle()
        onCaptionOverlayChanged?(isCaptionOverlayVisible)
        saveSettings()
    }

    func setCaptionPosition(_ position: CaptionStyle.CaptionPosition) {
        captionStyle.position = position
        composer.captionStyle = captionStyle
    }

    func setCaptionTextColor(_ color: CaptionStyle.CaptionColor) {
        captionStyle.textColor = color
        composer.captionStyle = captionStyle
    }

    func setCaptionFontSize(_ size: CGFloat) {
        captionStyle.fontSize = size
        composer.captionStyle = captionStyle
    }

    func setCaptionFontWeight(_ weight: CaptionStyle.FontWeight) {
        captionStyle.fontWeight = weight
        composer.captionStyle = captionStyle
    }

    func setCaptionBackgroundColor(_ color: CaptionStyle.CaptionColor) {
        captionStyle.backgroundColor = color
        composer.captionStyle = captionStyle
    }

    func setCaptionBackgroundOpacity(_ opacity: CGFloat) {
        captionStyle.backgroundOpacity = opacity
        composer.captionStyle = captionStyle
    }

    /// Switch recording mode at runtime — can be called while recording
    func setRecordingMode(_ mode: RecordingMode) {
        recordingMode = mode
        composer.recordingMode = mode

        // Auto-manage webcam based on mode
        switch mode {
        case .screenOnly:
            // No webcam needed — stop if running during recording
            if status.isActive {
                cameraManager.stopCapture()
            }
        case .screenAndWebcam:
            // Need webcam running
            if status.isActive, cameraManager.latestPixelBuffer == nil {
                let cam = availableCameras.first(where: { $0.uniqueID == selectedCameraId })
                try? cameraManager.startCapture(device: cam)
            }
        case .cameraOnly:
            // Need webcam running (it's the main source)
            if status.isActive, cameraManager.latestPixelBuffer == nil {
                let cam = availableCameras.first(where: { $0.uniqueID == selectedCameraId })
                try? cameraManager.startCapture(device: cam)
            }
        }

        saveSettings()
        onRecordingModeChanged?(mode)
    }

    // MARK: - Preview

    func startWebcamPreview() async {
        if isWebcamEnabled {
            let cam = availableCameras.first(where: { $0.uniqueID == selectedCameraId })
            try? cameraManager.startCapture(device: cam)
        }
    }

    func startPreview() async {
        await startWebcamPreview()
    }

    func stopPreview() async {
        cameraManager.stopCapture()
    }

    // MARK: - Private

    private func syncWebcamPosition() {
        composer.webcamNormalizedCenter = webcamPosition
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartDate else { return }
                self.elapsedTime = Date().timeIntervalSince(start) - self.pauseAccumulator

                // Check free tier recording limit
                let maxDuration = self.subscriptionManager.currentTier.maxRecordingDuration
                if maxDuration.isFinite {
                    self.freeTierTimeRemaining = max(0, maxDuration - self.elapsedTime)
                    if self.elapsedTime >= maxDuration {
                        await self.stopRecording()
                        self.onFreeTierLimitReached?()
                    }
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func cleanup() async {
        await screenManager.stopCapture()
        cameraManager.stopCapture()
        audioManager.stopCapture()
        clickHighlightManager.stop()
        keystrokeManager.stop()
    }

    func requestPermissions() async {
        await permissionManager.checkAll()
    }

    private func updateStorageInfo() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let vals = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = vals.volumeAvailableCapacityForImportantUsage {
            let gb = Double(bytes) / 1_000_000_000
            freeStorageText = String(format: "%.1f GB free", gb)
        }
    }
}
