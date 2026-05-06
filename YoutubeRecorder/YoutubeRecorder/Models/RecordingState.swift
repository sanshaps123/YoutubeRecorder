import Foundation

enum RecordingStatus: Equatable {
    case idle
    case countdown(Int)  // 3, 2, 1
    case preparing
    case recording
    case paused
    case stopping
    case error(String)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var isActive: Bool {
        switch self {
        case .recording, .paused: return true
        default: return false
        }
    }
}

enum CaptureMode: String, Equatable {
    case fullScreen
    case portion
}

/// The 3 recording modes — switchable at runtime during recording
enum RecordingMode: String, CaseIterable, Identifiable, Equatable {
    case screenOnly = "Screen Only"
    case screenAndWebcam = "Screen + Webcam"
    case cameraOnly = "Camera Only"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .screenOnly:       return "rectangle.inset.filled"
        case .screenAndWebcam:  return "rectangle.inset.filled.and.person.filled"
        case .cameraOnly:       return "person.crop.rectangle.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .screenOnly:       return "Screen"
        case .screenAndWebcam:  return "Screen+Cam"
        case .cameraOnly:       return "Camera"
        }
    }
}

/// Webcam overlay shape options
enum WebcamShape: String, CaseIterable, Identifiable, Equatable {
    case circle = "Circle"
    case roundedRect = "Rounded Rect"
    case rectangle = "Rectangle"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .circle:      return "circle.fill"
        case .roundedRect: return "app.fill"
        case .rectangle:   return "rectangle.fill"
        }
    }

    /// Corner radius multiplier relative to webcam size
    var cornerRadiusFraction: CGFloat {
        switch self {
        case .circle:      return 0.5   // Full circle
        case .roundedRect: return 0.15  // Rounded corners
        case .rectangle:   return 0.03  // Nearly square
        }
    }
}

enum QualityPreset: String, CaseIterable, Identifiable {
    case original = "Native"
    case hd1080 = "1080p"
    case hd4k = "4K"

    var id: String { rawValue }

    /// Returns (width, height) for the preset, or nil for native resolution
    func resolution(displayWidth: Int, displayHeight: Int) -> (Int, Int)? {
        switch self {
        case .original: return nil
        case .hd1080:   return (1920, 1080)
        case .hd4k:     return (3840, 2160)
        }
    }
}

struct RecordingSettings {
    var frameRate: Int = 30
    var webcamEnabled: Bool = true
    var webcamDiameter: CGFloat = 200

    static func defaultOutputURL() -> URL {
        let dir = SettingsStore.shared.saveDirectory
        let dirURL = URL(fileURLWithPath: dir)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "Recording_\(formatter.string(from: Date())).mov"
        return dirURL.appendingPathComponent(name)
    }
}
