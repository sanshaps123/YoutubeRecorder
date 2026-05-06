import Foundation

/// Persists user preferences across app launches using UserDefaults
@Observable @MainActor
final class SettingsStore {

    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Key {
        static let selectedCameraId = "selectedCameraId"
        static let selectedMicId = "selectedMicId"
        static let webcamDiameter = "webcamDiameter"
        static let webcamPositionX = "webcamPositionX"
        static let webcamPositionY = "webcamPositionY"
        static let webcamBackground = "webcamBackground"
        static let isWebcamEnabled = "isWebcamEnabled"
        static let isSystemAudioEnabled = "isSystemAudioEnabled"
        static let isCountdownEnabled = "isCountdownEnabled"
        static let countdownDuration = "countdownDuration"
        static let qualityPreset = "qualityPreset"
        static let captureMode = "captureMode"
        static let isClickHighlightEnabled = "isClickHighlightEnabled"
        static let isKeystrokeDisplayEnabled = "isKeystrokeDisplayEnabled"
        static let saveDirectory = "saveDirectory"
        static let recordingMode = "recordingMode"
        static let webcamShape = "webcamShape"
        static let isCaptionEnabled = "isCaptionEnabled"
        static let isCaptionOverlayVisible = "isCaptionOverlayVisible"
    }

    // MARK: - Properties

    var selectedCameraId: String {
        get { defaults.string(forKey: Key.selectedCameraId) ?? "" }
        set { defaults.set(newValue, forKey: Key.selectedCameraId) }
    }

    var selectedMicId: String {
        get { defaults.string(forKey: Key.selectedMicId) ?? "" }
        set { defaults.set(newValue, forKey: Key.selectedMicId) }
    }

    var webcamDiameter: CGFloat {
        get {
            let val = defaults.double(forKey: Key.webcamDiameter)
            return val > 0 ? val : 180
        }
        set { defaults.set(Double(newValue), forKey: Key.webcamDiameter) }
    }

    var webcamPositionX: CGFloat {
        get {
            let val = defaults.double(forKey: Key.webcamPositionX)
            return val > 0 ? val : 0.82
        }
        set { defaults.set(Double(newValue), forKey: Key.webcamPositionX) }
    }

    var webcamPositionY: CGFloat {
        get {
            let val = defaults.double(forKey: Key.webcamPositionY)
            return val > 0 ? val : 0.82
        }
        set { defaults.set(Double(newValue), forKey: Key.webcamPositionY) }
    }

    var webcamBackground: String {
        get { defaults.string(forKey: Key.webcamBackground) ?? "None" }
        set { defaults.set(newValue, forKey: Key.webcamBackground) }
    }

    var isWebcamEnabled: Bool {
        get { defaults.object(forKey: Key.isWebcamEnabled) == nil ? true : defaults.bool(forKey: Key.isWebcamEnabled) }
        set { defaults.set(newValue, forKey: Key.isWebcamEnabled) }
    }

    var isSystemAudioEnabled: Bool {
        get { defaults.bool(forKey: Key.isSystemAudioEnabled) }
        set { defaults.set(newValue, forKey: Key.isSystemAudioEnabled) }
    }

    var isCountdownEnabled: Bool {
        get { defaults.object(forKey: Key.isCountdownEnabled) == nil ? true : defaults.bool(forKey: Key.isCountdownEnabled) }
        set { defaults.set(newValue, forKey: Key.isCountdownEnabled) }
    }

    var countdownDuration: Int {
        get {
            let val = defaults.integer(forKey: Key.countdownDuration)
            return val > 0 ? val : 3
        }
        set { defaults.set(newValue, forKey: Key.countdownDuration) }
    }

    var qualityPreset: String {
        get { defaults.string(forKey: Key.qualityPreset) ?? "original" }
        set { defaults.set(newValue, forKey: Key.qualityPreset) }
    }

    var isClickHighlightEnabled: Bool {
        get { defaults.bool(forKey: Key.isClickHighlightEnabled) }
        set { defaults.set(newValue, forKey: Key.isClickHighlightEnabled) }
    }

    var isKeystrokeDisplayEnabled: Bool {
        get { defaults.bool(forKey: Key.isKeystrokeDisplayEnabled) }
        set { defaults.set(newValue, forKey: Key.isKeystrokeDisplayEnabled) }
    }

    var saveDirectory: String {
        get {
            if let dir = defaults.string(forKey: Key.saveDirectory), !dir.isEmpty { return dir }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.path
        }
        set { defaults.set(newValue, forKey: Key.saveDirectory) }
    }

    var recordingMode: String {
        get { defaults.string(forKey: Key.recordingMode) ?? RecordingMode.screenAndWebcam.rawValue }
        set { defaults.set(newValue, forKey: Key.recordingMode) }
    }

    var webcamShape: String {
        get { defaults.string(forKey: Key.webcamShape) ?? WebcamShape.circle.rawValue }
        set { defaults.set(newValue, forKey: Key.webcamShape) }
    }

    var isCaptionEnabled: Bool {
        get { defaults.bool(forKey: Key.isCaptionEnabled) }
        set { defaults.set(newValue, forKey: Key.isCaptionEnabled) }
    }

    var isCaptionOverlayVisible: Bool {
        get { defaults.bool(forKey: Key.isCaptionOverlayVisible) }
        set { defaults.set(newValue, forKey: Key.isCaptionOverlayVisible) }
    }
}
