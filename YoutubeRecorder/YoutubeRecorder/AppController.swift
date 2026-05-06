import SwiftUI
import AppKit
import Combine

/// Custom NSPanel that accepts key status so SwiftUI buttons/menus work
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate {

    let viewModel = RecordingViewModel()
    let authManager = AuthManager.shared
    var webcamPanel: KeyablePanel?
    private var countdownPanel: NSPanel?
    private var regionSelectPanel: NSPanel?
    private var regionBorderPanel: NSPanel?  // Persistent border around selected portion
    private var loginPanel: NSPanel?
    private var captionPanel: NSPanel?
    private var paywallPanel: NSPanel?
    private var captionStylePanel: NSPanel?

    // Remember webcam panel position when switching modes (only for Screen+Webcam size)
    private var savedWebcamFrame: NSRect?

    // Menu bar stop button
    private var statusItem: NSStatusItem?
    private var statusTimer: Timer?

    // Global hotkey monitors
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        createWebcamPanel()
        registerGlobalHotkeys()

        viewModel.onRecordingStarted = { [weak self] in
            self?.showMenuBarStopButton()
            // Show region border if portion mode
            if self?.viewModel.captureMode == .portion {
                self?.showRegionBorder()
            }
            // Ensure webcam panel is visible when mode requires it
            if let mode = self?.viewModel.recordingMode,
               mode == .screenAndWebcam || mode == .cameraOnly {
                self?.webcamPanel?.orderFront(nil)
            }
        }
        viewModel.onRecordingStopped = { [weak self] in
            self?.hideMenuBarStopButton()
            self?.webcamPanel?.orderOut(nil)
            self?.hideRegionBorder()
        }
        viewModel.onCountdownStarted = { [weak self] value in
            self?.showCountdownOverlay(value: value)
        }
        viewModel.onCountdownEnded = { [weak self] in
            self?.hideCountdownOverlay()
        }
        viewModel.onPauseChanged = { [weak self] isPaused in
            self?.updateMenuBarForPause(isPaused)
        }
        viewModel.onRecordingModeChanged = { [weak self] mode in
            self?.handleModeChange(mode)
        }
        viewModel.onRegionSelectRequested = { [weak self] in
            self?.showRegionSelector()
        }
        viewModel.onRegionBorderHide = { [weak self] in
            self?.hideRegionBorder()
        }
        viewModel.onCaptionOverlayChanged = { [weak self] visible in
            if visible { self?.showCaptionOverlay() }
            else { self?.hideCaptionOverlay() }
        }
        viewModel.onFreeTierLimitReached = { [weak self] in
            self?.showPaywallPanel()
        }
        viewModel.onCaptionStylePickerRequested = { [weak self] in
            self?.showCaptionStylePicker()
        }

        // Check auth state — show login if not authenticated
        Task {
            await authManager.refreshTokenIfNeeded()
            if !authManager.isAuthenticated {
                showLoginPanel()
            }
        }

        Task {
            await viewModel.requestPermissions()
            await viewModel.startWebcamPreview()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Global Hotkeys (work even when other apps are focused)

    private func registerGlobalHotkeys() {
        // Global monitor — fires when OTHER apps are active
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleHotkey(event)
            }
        }
        // Local monitor — fires when OUR app is active
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleHotkey(event)
            }
            return event
        }
    }

    private func handleHotkey(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌃⌘1 = Screen Only, ⌃⌘2 = Screen+Webcam, ⌃⌘3 = Camera Only
        if mods == [.command, .control] {
            switch event.keyCode {
            case 18: // 1
                viewModel.setRecordingMode(.screenOnly)
            case 19: // 2
                viewModel.setRecordingMode(.screenAndWebcam)
            case 20: // 3
                viewModel.setRecordingMode(.cameraOnly)
            default: break
            }
        }

        // ⇧⌘R = Start/Stop Recording
        if mods == [.command, .shift] {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "r":
                Task {
                    if viewModel.status.isActive {
                        await viewModel.stopRecording()
                    } else {
                        await viewModel.startRecording()
                    }
                }
            case "p":
                viewModel.togglePause()
            case "w":
                viewModel.toggleWebcam()
            default: break
            }
        }
    }

    // MARK: - Recording Mode Change

    private func handleModeChange(_ mode: RecordingMode) {
        guard let panel = webcamPanel else { return }

        switch mode {
        case .screenOnly:
            // Save current position before hiding (only if in overlay mode)
            if panel.isVisible && panel.frame.width <= 500 {
                savedWebcamFrame = panel.frame
            }
            panel.orderOut(nil)

        case .screenAndWebcam:
            // Restore to saved position — never reset to center
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            let size: CGFloat = 500
            if let saved = savedWebcamFrame {
                // Ensure saved frame has the correct panel size (might have been camera-only before)
                let restoredFrame = NSRect(
                    x: saved.midX - size / 2,
                    y: saved.midY - size / 2,
                    width: size,
                    height: size
                )
                panel.setFrame(restoredFrame, display: true, animate: true)
            } else {
                if let screen = NSScreen.main {
                    let newFrame = NSRect(
                        x: screen.frame.maxX - size - 20,
                        y: 80,
                        width: size,
                        height: size
                    )
                    panel.setFrame(newFrame, display: true, animate: true)
                }
            }
            panel.orderFront(nil)
            Task { await viewModel.startWebcamPreview() }

        case .cameraOnly:
            // Save current position before going full-screen
            if panel.isVisible && panel.frame.width <= 500 {
                savedWebcamFrame = panel.frame
            }
            panel.isMovableByWindowBackground = false
            // Use .normal level so macOS menu bar stays accessible above
            panel.level = .normal
            if let screen = NSScreen.main {
                panel.setFrame(screen.visibleFrame, display: true, animate: true)
            }
            panel.orderFront(nil)
            Task { await viewModel.startWebcamPreview() }
        }
    }

    // MARK: - Region Selector (QuickTime-style)

    private func showRegionSelector() {
        guard let screen = NSScreen.main else { return }

        let content = RegionSelectorView { [weak self] rect in
            guard let self else { return }
            self.viewModel.selectedRegion = rect
            self.regionSelectPanel?.orderOut(nil)
            self.regionSelectPanel = nil
            // Show persistent border immediately
            self.showRegionBorder()
        } onCancel: { [weak self] in
            self?.viewModel.captureMode = .fullScreen
            self?.regionSelectPanel?.orderOut(nil)
            self?.regionSelectPanel = nil
        }

        let hosting = NSHostingView(rootView: content)
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)
        panel.orderFront(nil)
        panel.makeKey()
        regionSelectPanel = panel
    }

    // MARK: - Persistent Region Border (visible during recording)

    private func showRegionBorder() {
        hideRegionBorder()  // Remove any existing

        let region = viewModel.selectedRegion
        guard region.width > 0, region.height > 0, let screen = NSScreen.main else { return }

        // Convert from pixel coords back to point coords
        let scale = screen.backingScaleFactor
        let pointRect = CGRect(
            x: region.origin.x / scale,
            y: region.origin.y / scale,
            width: region.width / scale,
            height: region.height / scale
        )

        // AppKit Y-flip: screen origin is bottom-left
        let flippedY = screen.frame.height - pointRect.origin.y - pointRect.height
        let borderInset: CGFloat = 4
        let panelFrame = NSRect(
            x: pointRect.origin.x - borderInset,
            y: flippedY - borderInset,
            width: pointRect.width + borderInset * 2,
            height: pointRect.height + borderInset * 2
        )

        // Use GeometryReader-based view so it adapts to resize
        let content = RegionBorderDynamicView()
        let hosting = NSHostingView(rootView: content)

        let panel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true  // Draggable!
        panel.sharingType = .none
        panel.minSize = NSSize(width: 100, height: 80)
        panel.contentView = hosting
        panel.setFrame(panelFrame, display: true)
        panel.orderFront(nil)
        regionBorderPanel = panel

        // Update selectedRegion when user drags or resizes the border panel
        let updateRegion: (Notification) -> Void = { [weak self] _ in
            guard let self, let p = self.regionBorderPanel, let scr = NSScreen.main else { return }
            let f = p.frame
            let s = scr.backingScaleFactor
            let bi: CGFloat = 4
            let px = (f.origin.x + bi) * s
            let py = (scr.frame.height - f.origin.y - f.height + bi) * s
            let pw = (f.width - bi * 2) * s
            let ph = (f.height - bi * 2) * s
            self.viewModel.selectedRegion = CGRect(x: px, y: py, width: pw, height: ph)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main,
            using: updateRegion
        )
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main,
            using: updateRegion
        )
    }

    private func hideRegionBorder() {
        regionBorderPanel?.orderOut(nil)
        regionBorderPanel = nil
    }

    // MARK: - Countdown Overlay

    private func showCountdownOverlay(value: Int) {
        let content = CountdownOverlayView(countdownValue: value)
        let hosting = NSHostingView(rootView: content)

        if let panel = countdownPanel {
            panel.contentView = hosting
            return
        }

        guard let screen = NSScreen.main else { return }
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)
        panel.orderFront(nil)
        countdownPanel = panel
    }

    private func hideCountdownOverlay() {
        countdownPanel?.orderOut(nil)
        countdownPanel = nil
    }

    // MARK: - Menu Bar Stop Button

    private func showMenuBarStopButton() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let button = item.button!

        let menu = NSMenu()
        let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopFromMenuBar), keyEquivalent: "")
        stopItem.target = self
        stopItem.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
        menu.addItem(stopItem)

        let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePauseFromMenuBar), keyEquivalent: "")
        pauseItem.target = self
        pauseItem.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: nil)
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let modeMenu = NSMenu()
        for mode in RecordingMode.allCases {
            let mi = NSMenuItem(title: mode.rawValue, action: #selector(switchModeFromMenuBar(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = mode.rawValue
            if viewModel.recordingMode == mode { mi.state = .on }
            modeMenu.addItem(mi)
        }
        let modeItem = NSMenuItem(title: "Recording Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(.separator())

        let showItem = NSMenuItem(title: "Show Controls", action: #selector(showControlPanel), keyEquivalent: "")
        showItem.target = self
        showItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        menu.addItem(showItem)

        let recentItem = NSMenuItem(title: "Recent Recordings", action: #selector(showRecentRecordings), keyEquivalent: "")
        recentItem.target = self
        recentItem.image = NSImage(systemSymbolName: "film.stack", accessibilityDescription: nil)
        menu.addItem(recentItem)

        item.menu = menu

        let config = NSImage.SymbolConfiguration(paletteColors: [.white, .systemRed])
        button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording")?.withSymbolConfiguration(config)
        button.title = " 00:00:00"
        button.imagePosition = .imageLeading
        button.toolTip = "Click for recording options"

        statusItem = item

        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let elapsed = self.viewModel.elapsedTime
                let hrs = Int(elapsed) / 3600
                let mins = (Int(elapsed) % 3600) / 60
                let secs = Int(elapsed) % 60
                self.statusItem?.button?.title = String(format: " %02d:%02d:%02d", hrs, mins, secs)

                if let menu = self.statusItem?.menu,
                   let pauseItem = menu.items.first(where: { $0.action == #selector(self.togglePauseFromMenuBar) }) {
                    pauseItem.title = self.viewModel.status.isPaused ? "Resume" : "Pause"
                    pauseItem.image = NSImage(systemSymbolName: self.viewModel.status.isPaused ? "play.fill" : "pause.fill", accessibilityDescription: nil)
                }

                if let menu = self.statusItem?.menu {
                    for item in menu.items {
                        if let modeMenu = item.submenu {
                            for mItem in modeMenu.items {
                                if let rawValue = mItem.representedObject as? String,
                                   let mode = RecordingMode(rawValue: rawValue) {
                                    mItem.state = (self.viewModel.recordingMode == mode) ? .on : .off
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func hideMenuBarStopButton() {
        statusTimer?.invalidate()
        statusTimer = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func updateMenuBarForPause(_ isPaused: Bool) {
        guard let button = statusItem?.button else { return }
        if isPaused {
            let config = NSImage.SymbolConfiguration(paletteColors: [.white, .systemOrange])
            button.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Paused")?.withSymbolConfiguration(config)
        } else {
            let config = NSImage.SymbolConfiguration(paletteColors: [.white, .systemRed])
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording")?.withSymbolConfiguration(config)
        }
    }

    @objc private func stopFromMenuBar() {
        Task { await viewModel.stopRecording() }
    }

    @objc private func togglePauseFromMenuBar() {
        viewModel.togglePause()
    }

    @objc private func showControlPanel() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func switchModeFromMenuBar(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = RecordingMode(rawValue: rawValue) else { return }
        viewModel.setRecordingMode(mode)
    }

    // MARK: - Main Menu Bar

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About YoutubeRecorder", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit YoutubeRecorder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let recMenu = NSMenu(title: "Recording")
        let startStop = NSMenuItem(title: "Start / Stop Recording", action: #selector(toggleRecording), keyEquivalent: "r")
        startStop.keyEquivalentModifierMask = [.command, .shift]
        startStop.target = self
        recMenu.addItem(startStop)

        let pauseResume = NSMenuItem(title: "Pause / Resume", action: #selector(togglePauseFromMenu), keyEquivalent: "p")
        pauseResume.keyEquivalentModifierMask = [.command, .shift]
        pauseResume.target = self
        recMenu.addItem(pauseResume)

        recMenu.addItem(.separator())

        let toggleCam = NSMenuItem(title: "Toggle Webcam", action: #selector(toggleWebcam), keyEquivalent: "w")
        toggleCam.keyEquivalentModifierMask = [.command, .shift]
        toggleCam.target = self
        recMenu.addItem(toggleCam)

        let toggleAudio = NSMenuItem(title: "Toggle System Audio", action: #selector(toggleSystemAudio), keyEquivalent: "a")
        toggleAudio.keyEquivalentModifierMask = [.command, .shift]
        toggleAudio.target = self
        recMenu.addItem(toggleAudio)

        recMenu.addItem(.separator())

        // Mode switching — ⌃⌘1/2/3 (shown in menu, actual hotkey via global monitor)
        let modeScreenOnly = NSMenuItem(title: "Screen Only", action: #selector(switchToScreenOnly), keyEquivalent: "1")
        modeScreenOnly.keyEquivalentModifierMask = [.command, .control]
        modeScreenOnly.target = self
        recMenu.addItem(modeScreenOnly)

        let modeScreenCam = NSMenuItem(title: "Screen + Webcam", action: #selector(switchToScreenAndWebcam), keyEquivalent: "2")
        modeScreenCam.keyEquivalentModifierMask = [.command, .control]
        modeScreenCam.target = self
        recMenu.addItem(modeScreenCam)

        let modeCamOnly = NSMenuItem(title: "Camera Only", action: #selector(switchToCameraOnly), keyEquivalent: "3")
        modeCamOnly.keyEquivalentModifierMask = [.command, .control]
        modeCamOnly.target = self
        recMenu.addItem(modeCamOnly)

        let recMenuItem = NSMenuItem()
        recMenuItem.submenu = recMenu
        mainMenu.addItem(recMenuItem)

        // Capture menu
        let capMenu = NSMenu(title: "Capture")
        let fullScreen = NSMenuItem(title: "Entire Screen", action: #selector(captureFullScreen), keyEquivalent: "")
        fullScreen.target = self
        capMenu.addItem(fullScreen)

        let portion = NSMenuItem(title: "Selected Portion…", action: #selector(captureSelectedPortion), keyEquivalent: "")
        portion.target = self
        capMenu.addItem(portion)

        let capMenuItem = NSMenuItem()
        capMenuItem.submenu = capMenu
        mainMenu.addItem(capMenuItem)

        let viewMenu = NSMenu(title: "View")
        let showCam = NSMenuItem(title: "Show Webcam", action: #selector(showWebcamPanel), keyEquivalent: "k")
        showCam.keyEquivalentModifierMask = [.command]
        showCam.target = self
        viewMenu.addItem(showCam)

        let showRecordings = NSMenuItem(title: "Recent Recordings", action: #selector(showRecentRecordings), keyEquivalent: "l")
        showRecordings.keyEquivalentModifierMask = [.command]
        showRecordings.target = self
        viewMenu.addItem(showRecordings)

        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu

        // Add Account menu
        addAccountMenu(to: mainMenu)
    }

    // MARK: - Account Menu

    private func addAccountMenu(to mainMenu: NSMenu) {
        let accountMenu = NSMenu(title: "Account")

        let signInItem = NSMenuItem(title: "Sign In…", action: #selector(showLoginFromMenu), keyEquivalent: "")
        signInItem.target = self
        accountMenu.addItem(signInItem)

        let signOutItem = NSMenuItem(title: "Sign Out", action: #selector(signOutFromMenu), keyEquivalent: "")
        signOutItem.target = self
        accountMenu.addItem(signOutItem)

        accountMenu.addItem(.separator())

        let upgradeItem = NSMenuItem(title: "Upgrade to Pro…", action: #selector(showPaywallFromMenu), keyEquivalent: "")
        upgradeItem.target = self
        upgradeItem.image = NSImage(systemSymbolName: "crown.fill", accessibilityDescription: nil)
        accountMenu.addItem(upgradeItem)

        let accountMenuItem = NSMenuItem()
        accountMenuItem.submenu = accountMenu
        mainMenu.addItem(accountMenuItem)
    }

    @objc private func showLoginFromMenu() { showLoginPanel() }
    @objc private func signOutFromMenu() {
        try? authManager.signOut()
    }
    @objc private func showPaywallFromMenu() { showPaywallPanel() }

    // MARK: - Menu Actions

    @objc private func toggleRecording() {
        Task {
            if viewModel.status.isActive {
                await viewModel.stopRecording()
            } else {
                await viewModel.startRecording()
            }
        }
    }

    @objc private func togglePauseFromMenu() { viewModel.togglePause() }
    @objc private func toggleWebcam() { viewModel.toggleWebcam() }
    @objc private func toggleSystemAudio() { viewModel.toggleSystemAudio() }
    @objc private func switchToScreenOnly() { viewModel.setRecordingMode(.screenOnly) }
    @objc private func switchToScreenAndWebcam() { viewModel.setRecordingMode(.screenAndWebcam) }
    @objc private func switchToCameraOnly() { viewModel.setRecordingMode(.cameraOnly) }

    @objc private func captureFullScreen() {
        viewModel.setCaptureMode(.fullScreen)
        hideRegionBorder()
    }

    @objc private func captureSelectedPortion() {
        viewModel.setCaptureMode(.portion)
    }

    @objc private func showWebcamPanel() {
        webcamPanel?.orderFront(nil)
    }

    @objc private func showRecentRecordings() {
        let content = RecordingsListView()
        let hosting = NSHostingView(rootView: content.preferredColorScheme(.dark))
        let size = NSSize(width: 520, height: 460)
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        panel.title = "Recent Recordings"
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()
        panel.orderFront(nil)
        panel.makeKey()
    }

    // MARK: - Webcam Panel

    private func createWebcamPanel() {
        let content = WebcamPanelView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: content)

        let isCameraOnly = viewModel.recordingMode == .cameraOnly
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelW: CGFloat = isCameraOnly ? screenFrame.width : 500
        let panelH: CGFloat = isCameraOnly ? screenFrame.height : 500

        hosting.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = !isCameraOnly
        panel.contentView = hosting
        panel.acceptsMouseMovedEvents = true
        panel.sharingType = .none  // Exclude from screen capture — prevents duplicate face

        if isCameraOnly {
            panel.setFrame(screenFrame, display: true)
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.maxX - panelW - 20, y: 80))
        }

        // Save initial position
        if !isCameraOnly {
            savedWebcamFrame = panel.frame
        }

        if viewModel.recordingMode != .screenOnly {
            panel.orderFront(nil)
        }
        webcamPanel = panel

        // Track position for video compositing — ONLY when in overlay mode (not camera-only)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, let p = self.webcamPanel, let scr = NSScreen.main else { return }
            // Save position for overlay mode only
            if p.frame.width <= 500 {
                self.savedWebcamFrame = p.frame
            }
            self.updateWebcamPositionFromPanel(p, screen: scr)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, let p = self.webcamPanel, let scr = NSScreen.main else { return }
            self.updateWebcamPositionFromPanel(p, screen: scr)
        }
    }

    private func updateWebcamPositionFromPanel(_ panel: NSPanel, screen: NSScreen) {
        let f = panel.frame
        let screenW = screen.frame.width
        let screenH = screen.frame.height
        let normalizedX = f.midX / screenW
        let normalizedY = 1.0 - (f.midY / screenH)
        viewModel.updateWebcamPosition(CGPoint(x: normalizedX, y: normalizedY))
    }

    // MARK: - Login Panel

    private func showLoginPanel() {
        if let existing = loginPanel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let content = LoginView {
            self.loginPanel?.orderOut(nil)
            self.loginPanel = nil
        }
        let hosting = NSHostingView(rootView: content.preferredColorScheme(.dark))
        let size = NSSize(width: 380, height: 520)
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        panel.title = "Sign In"
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()
        panel.orderFront(nil)
        panel.makeKey()
        loginPanel = panel
    }

    // MARK: - Caption Overlay Panel

    private func showCaptionOverlay() {
        guard captionPanel == nil, let screen = NSScreen.main else { return }

        let content = CaptionOverlayView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: content)

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)
        panel.orderFront(nil)
        captionPanel = panel
    }

    private func hideCaptionOverlay() {
        captionPanel?.orderOut(nil)
        captionPanel = nil
    }

    // MARK: - Paywall Panel

    func showPaywallPanel() {
        if let existing = paywallPanel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let content = PaywallView {
            self.paywallPanel?.orderOut(nil)
            self.paywallPanel = nil
        }
        let hosting = NSHostingView(rootView: content.preferredColorScheme(.dark))
        let size = NSSize(width: 420, height: 620)
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        panel.title = "Upgrade to Pro"
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()
        panel.orderFront(nil)
        panel.makeKey()
        paywallPanel = panel
    }

    // MARK: - Caption Style Picker Panel

    func showCaptionStylePicker() {
        if let existing = captionStylePanel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let content = CaptionStylePickerView(viewModel: viewModel) {
            self.captionStylePanel?.orderOut(nil)
            self.captionStylePanel = nil
        }
        let hosting = NSHostingView(rootView: content.preferredColorScheme(.dark))
        let size = NSSize(width: 420, height: 640)
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        panel.title = "Caption Style"
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()
        panel.orderFront(nil)
        panel.makeKey()
        captionStylePanel = panel
    }
}

// MARK: - Region Border View (dynamic — adapts to resize)

struct RegionBorderDynamicView: View {
    @State private var dashPhase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Marching-ants border
                RoundedRectangle(cornerRadius: 4)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 4], dashPhase: dashPhase))
                    .foregroundStyle(.white.opacity(0.8))

                RoundedRectangle(cornerRadius: 4)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 4], dashPhase: dashPhase + 6))
                    .foregroundStyle(Color.accentColor.opacity(0.6))

                // Corner + edge handles for visual resize affordance
                ForEach(handlePositions(w: w, h: h), id: \.0) { handle in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: handle.3, height: handle.4)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .position(x: handle.1, y: handle.2)
                }

                // Dimension label
                VStack {
                    Spacer()
                    let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                    Text("\(Int(w * scale)) × \(Int(h * scale))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .offset(y: 18)
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                dashPhase = 12
            }
        }
    }

    /// Corner handles + midpoint handles
    private func handlePositions(w: CGFloat, h: CGFloat) -> [(String, CGFloat, CGFloat, CGFloat, CGFloat)] {
        [
            // Corners (square)
            ("tl", 0, 0, 8, 8),
            ("tr", w, 0, 8, 8),
            ("bl", 0, h, 8, 8),
            ("br", w, h, 8, 8),
            // Midpoints (rectangular)
            ("t",  w/2, 0,   12, 6),
            ("b",  w/2, h,   12, 6),
            ("l",  0,   h/2, 6, 12),
            ("r",  w,   h/2, 6, 12),
        ]
    }
}

// MARK: - Region Selector View (QuickTime-style drag to select area)

struct RegionSelectorView: View {
    var onSelect: (CGRect) -> Void
    var onCancel: () -> Void

    @State private var startPoint: CGPoint = .zero
    @State private var currentPoint: CGPoint = .zero
    @State private var isDragging = false

    private var selectionRect: CGRect {
        let x = min(startPoint.x, currentPoint.x)
        let y = min(startPoint.y, currentPoint.y)
        let w = abs(currentPoint.x - startPoint.x)
        let h = abs(currentPoint.y - startPoint.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed overlay with cut-out
                Canvas { context, size in
                    // Fill entire screen with dim
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.4)))

                    if isDragging {
                        // Cut out the selected region
                        context.blendMode = .clear
                        context.fill(Path(selectionRect), with: .color(.white))
                    }
                }
                .ignoresSafeArea()

                // Selection border
                if isDragging {
                    // White border around selection
                    Rectangle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .shadow(color: .white.opacity(0.3), radius: 4)

                    // Corner handles
                    ForEach(["tl", "tr", "bl", "br"], id: \.self) { corner in
                        let pos = cornerPosition(corner)
                        Circle()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .position(x: pos.x, y: pos.y)
                    }

                    // Dimension label
                    let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                    Text("\(Int(selectionRect.width * scale)) × \(Int(selectionRect.height * scale))")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .position(x: selectionRect.midX, y: selectionRect.maxY + 24)
                }

                // Instructions
                if !isDragging {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.dashed")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Drag to select recording area")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white)
                        Text("Press Escape to cancel • Release to confirm")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if !isDragging {
                            startPoint = value.startLocation
                            isDragging = true
                        }
                        currentPoint = value.location
                    }
                    .onEnded { _ in
                        let rect = selectionRect
                        guard rect.width > 20 && rect.height > 20 else {
                            onCancel()
                            return
                        }
                        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                        let screenRect = CGRect(
                            x: rect.origin.x * scale,
                            y: rect.origin.y * scale,
                            width: rect.width * scale,
                            height: rect.height * scale
                        )
                        onSelect(screenRect)
                    }
            )
            .onExitCommand {
                onCancel()
            }
        }
    }

    private func cornerPosition(_ corner: String) -> CGPoint {
        let r = selectionRect
        switch corner {
        case "tl": return CGPoint(x: r.minX, y: r.minY)
        case "tr": return CGPoint(x: r.maxX, y: r.minY)
        case "bl": return CGPoint(x: r.minX, y: r.maxY)
        case "br": return CGPoint(x: r.maxX, y: r.maxY)
        default: return .zero
        }
    }
}
