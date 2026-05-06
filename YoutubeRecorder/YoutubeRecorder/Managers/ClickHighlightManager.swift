import Cocoa
import CoreGraphics

/// Monitors global mouse clicks and generates highlight events for the video composer.
/// Requires Accessibility permission (System Settings → Privacy → Accessibility).
final class ClickHighlightManager: @unchecked Sendable {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let tapQueue = DispatchQueue(label: "com.youtuberecorder.clickhighlight", qos: .userInteractive)
    private let lock = NSLock()
    private var _isRunning = false

    var onClickDetected: ((ClickHighlight) -> Void)?

    var isRunning: Bool {
        lock.withLock { _isRunning }
    }

    func start() {
        guard !isRunning else { return }

        tapQueue.async { [weak self] in
            guard let self else { return }

            let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
                                       | (1 << CGEventType.rightMouseDown.rawValue)

            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                    guard let refcon else { return Unmanaged.passRetained(event) }
                    let manager = Unmanaged<ClickHighlightManager>.fromOpaque(refcon).takeUnretainedValue()
                    manager.handleEvent(event)
                    return Unmanaged.passRetained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                print("[ClickHighlight] ⚠️ Failed to create event tap — check Accessibility permissions")
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

    private func handleEvent(_ event: CGEvent) {
        let location = event.location
        guard let screen = NSScreen.main else { return }

        // Normalize to 0-1 range
        let normalized = CGPoint(
            x: location.x / screen.frame.width,
            y: location.y / screen.frame.height  // Already in screen coords (top-left origin)
        )

        let highlight = ClickHighlight(
            position: normalized,
            timestamp: CACurrentMediaTime()
        )

        onClickDetected?(highlight)
    }

    deinit {
        stop()
    }
}
