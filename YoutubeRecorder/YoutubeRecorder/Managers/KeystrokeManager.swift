import Cocoa
import CoreGraphics
import Carbon.HIToolbox

/// Monitors global keyboard events and formats them for display in the video.
/// Requires Accessibility permission (System Settings → Privacy → Accessibility).
final class KeystrokeManager: @unchecked Sendable {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let tapQueue = DispatchQueue(label: "com.youtuberecorder.keystroke", qos: .userInteractive)
    private let lock = NSLock()
    private var _isRunning = false

    var onKeystrokeDetected: ((KeystrokeDisplay) -> Void)?

    var isRunning: Bool {
        lock.withLock { _isRunning }
    }

    func start() {
        guard !isRunning else { return }

        tapQueue.async { [weak self] in
            guard let self else { return }

            let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                                       | (1 << CGEventType.flagsChanged.rawValue)

            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                    guard let refcon else { return Unmanaged.passRetained(event) }
                    let manager = Unmanaged<KeystrokeManager>.fromOpaque(refcon).takeUnretainedValue()
                    if type == .keyDown {
                        manager.handleKeyDown(event)
                    }
                    return Unmanaged.passRetained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                print("[KeystrokeManager] ⚠️ Failed to create event tap — check Accessibility permissions")
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

            self.eventTap = tap
            self.runLoopSource = source
            self.lock.withLock { self._isRunning = true }

            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
    }

    func stop() {
        guard isRunning else { return }
        lock.withLock { _isRunning = false }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleKeyDown(_ event: CGEvent) {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Only show when modifier keys are pressed (⌘, ⌃, ⌥, or ⇧ with another modifier)
        let hasCommand = flags.contains(.maskCommand)
        let hasControl = flags.contains(.maskControl)
        let hasOption = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)

        // Require at least one modifier (not just shift alone)
        guard hasCommand || hasControl || hasOption else { return }

        var parts: [String] = []
        if hasControl { parts.append("⌃") }
        if hasOption  { parts.append("⌥") }
        if hasShift   { parts.append("⇧") }
        if hasCommand { parts.append("⌘") }

        let keyName = Self.keyName(for: Int(keyCode))
        parts.append(keyName)

        let text = parts.joined()

        let keystroke = KeystrokeDisplay(
            text: text,
            timestamp: CACurrentMediaTime()
        )

        onKeystrokeDetected?(keystroke)
    }

    /// Maps virtual key codes to readable key names
    private static func keyName(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "?"
        }
    }

    deinit {
        stop()
    }
}
