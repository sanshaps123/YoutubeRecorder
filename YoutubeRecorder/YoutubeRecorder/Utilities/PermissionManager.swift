import AVFoundation
import ScreenCaptureKit
import Speech

@Observable
final class PermissionManager {
    var cameraAuthorized = false
    var microphoneAuthorized = false
    var screenRecordingAuthorized = true  // Assume true — checked lazily when recording starts
    var speechRecognitionAuthorized = false

    /// For UI purposes: camera + mic are required upfront. Screen recording is checked only when needed.
    var allGranted: Bool {
        cameraAuthorized && microphoneAuthorized
    }

    func checkAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.checkCamera() }
            group.addTask { await self.checkMicrophone() }
        }
        // Do NOT check screen recording here — it triggers a modal prompt every launch
    }

    @MainActor
    func checkCamera() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraAuthorized = true
        case .notDetermined:
            cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraAuthorized = false
        }
    }

    @MainActor
    func checkMicrophone() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneAuthorized = true
        case .notDetermined:
            microphoneAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            microphoneAuthorized = false
        }
    }

    /// Check speech recognition permission — required for live captions.
    @MainActor
    func checkSpeechRecognition() async {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            speechRecognitionAuthorized = true
        case .notDetermined:
            speechRecognitionAuthorized = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            speechRecognitionAuthorized = false
        }
    }

    /// Check screen recording permission — only call this when the user clicks Record.
    /// Returns true if permission is granted, false otherwise.
    @MainActor
    func checkScreenRecordingOnDemand() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            screenRecordingAuthorized = !content.displays.isEmpty
            return screenRecordingAuthorized
        } catch {
            screenRecordingAuthorized = false
            openSystemPreferences()
            return false
        }
    }

    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

