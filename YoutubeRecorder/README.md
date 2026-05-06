# YoutubeRecorder — macOS Screen Recording App

> **A production-ready macOS screen recorder for content creators.** Records your screen with a circular webcam overlay (with virtual backgrounds), system audio capture, click highlights, keystroke display, countdown timer, pause/resume — and saves to `.mov`. Transparent UI — only the webcam circle and a compact control bar are visible. Stop/pause button appears in the macOS menu bar during recording, just like QuickTime Player.

---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [File Map](#file-map)
- [Data Flow](#data-flow)
- [Key APIs Used](#key-apis-used)
- [UI Components](#ui-components)
- [Recording Pipeline](#recording-pipeline)
- [Virtual Background System](#virtual-background-system)
- [Click Highlights](#click-highlights)
- [Keystroke Display](#keystroke-display)
- [iPhone Camera (Continuity Camera)](#iphone-camera-continuity-camera)
- [Permissions](#permissions)
- [Configuration](#configuration)
- [Settings Persistence](#settings-persistence)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Known Behaviors](#known-behaviors)
- [Future Enhancement Areas](#future-enhancement-areas)

---

## Features

| Feature | Implementation |
|---------|---------------|
| Screen recording | ScreenCaptureKit (`SCStream`) |
| System audio capture | `SCStream` audio output (`.capturesAudio`) |
| Microphone recording | AVFoundation `AVCaptureAudioDataOutput` |
| Webcam overlay | AVFoundation + floating `NSPanel` |
| Circular webcam | Core Image radial gradient masking |
| Virtual backgrounds | Vision `VNGeneratePersonSegmentationRequest` |
| Background blur | Core Image Gaussian blur |
| Gradient backgrounds | Sunset, Ocean, Forest, Night Sky, Studio |
| Draggable webcam | `NSPanel.isMovableByWindowBackground` |
| Resizable webcam | Slider + ±buttons (80–400px) |
| iPhone camera | macOS Continuity Camera (WiFi, same Apple ID) |
| Countdown timer | 3-2-1-GO overlay before recording |
| Pause/Resume | Continuous file with PTS offset |
| Click highlights | Expanding yellow rings on mouse clicks via `CGEvent` tap |
| Keystroke display | Modifier+key badge in video via `CGEvent` tap |
| Quality presets | Native, 1080p, 4K |
| Recent recordings | List with thumbnails, duration, size, actions |
| Settings persistence | All preferences saved via `UserDefaults` |
| Menu bar stop button | `NSStatusItem` with live timer + dropdown menu |
| Keyboard shortcuts | ⇧⌘R (record), ⇧⌘P (pause), ⇧⌘W (webcam), ⇧⌘A (sys audio) |

---

## Architecture

```
YoutubeRecorderApp (@main)
├── AppController (NSApplicationDelegate)
│   ├── Creates webcam floating NSPanel
│   ├── Creates countdown overlay NSPanel  
│   ├── Manages macOS menu bar + keyboard shortcuts
│   ├── Shows/hides NSStatusItem (stop/pause button) during recording
│   ├── Opens RecordingsListView panel
│   └── Holds shared RecordingViewModel
│
├── Window Scene (SwiftUI)
│   └── ControlPanelView (timer, pickers, toggles, settings, pause, record)
│
└── RecordingViewModel (@Observable, @MainActor)
    ├── ScreenCaptureManager (SCStream — screen + system audio)
    ├── CameraManager (AVCaptureSession + BackgroundProcessor)
    ├── AudioManager (AVCaptureAudioDataOutput — mic)
    ├── VideoComposer (AVAssetWriter + CIImage compositing)
    │   ├── Webcam overlay (circular mask)
    │   ├── Click highlight rings (CIRadialGradient)
    │   └── Keystroke badge (CoreText → CIImage)
    ├── ClickHighlightManager (CGEvent tap — mouse)
    ├── KeystrokeManager (CGEvent tap — keyboard)
    ├── PermissionManager
    └── SettingsStore (UserDefaults persistence)
```

**Pattern**: MVVM. The `RecordingViewModel` is the single source of truth. Both the SwiftUI Window (control bar) and the AppController (webcam panel, menu bar) share the same ViewModel instance.

---

## File Map

### Entry Point
| File | Lines | Purpose |
|------|-------|---------|
| `YoutubeRecorderApp.swift` | 17 | `@main` App struct. Uses `@NSApplicationDelegateAdaptor(AppController.self)`. Single `Window` scene for control bar. |
| `AppController.swift` | 350 | `NSApplicationDelegate`. Creates webcam `NSPanel`, countdown overlay, macOS menu bar, `NSStatusItem` stop/pause button, recent recordings panel. |

### Models
| File | Lines | Purpose |
|------|-------|---------|
| `RecordingState.swift` | 65 | `RecordingStatus` enum (idle/countdown/preparing/recording/paused/stopping/error), `CaptureMode`, `QualityPreset` enum (Native/1080p/4K), `RecordingSettings`. |

### ViewModel
| File | Lines | Purpose |
|------|-------|---------|
| `RecordingViewModel.swift` | 459 | **Central orchestrator.** Recording lifecycle, countdown, pause/resume, device enumeration, click/keystroke manager lifecycle, settings load/save, callbacks to AppController. |

### Managers (Business Logic)
| File | Lines | Purpose |
|------|-------|---------|
| `ScreenCaptureManager.swift` | 149 | `SCStream` wrapper. Supports full-screen/portion capture, system audio capture, quality presets. Excludes app's own windows. |
| `CameraManager.swift` | 110 | `AVCaptureSession` wrapper. Accepts Mac webcam or iPhone Continuity Camera. Routes frames through `BackgroundProcessor`. |
| `AudioManager.swift` | 63 | Microphone capture via `AVCaptureAudioDataOutput`. |
| `VideoComposer.swift` | 510 | **Real-time compositor.** AVAssetWriter + Core Image. Merges screen + circular webcam + click highlights + keystroke badges. Pause/resume with PTS offset. |
| `BackgroundProcessor.swift` | 163 | Vision person segmentation → blur/gradient virtual backgrounds. |
| `ClickHighlightManager.swift` | 94 | `CGEvent.tapCreate()` for global mouse click monitoring. Generates `ClickHighlight` events with normalized position + timestamp. |
| `KeystrokeManager.swift` | 191 | `CGEvent.tapCreate()` for global keystroke monitoring. Maps virtual key codes to symbols (⌘C, ⇧⌘S, etc.). Only fires for modifier-based shortcuts. |

### Views (UI)
| File | Lines | Purpose |
|------|-------|---------|
| `ControlPanelView.swift` | 271 | **Floating control bar.** Timer, camera/audio/system-audio pickers, webcam/settings toggles, click highlight/keystroke/countdown toggles, quality presets, pause button, record/stop button. |
| `WebcamPanelView.swift` | 134 | **Floating webcam circle.** Shows processed camera feed, recording indicator, background picker, size controls. |
| `CountdownOverlayView.swift` | 42 | **Full-screen countdown.** 3→2→1→GO with animated progress ring. |
| `RecordingsListView.swift` | 258 | **Recent recordings.** List with thumbnails, duration, file size, date. Open/Reveal/Delete actions. |
| `BackgroundPickerView.swift` | 83 | Grid of virtual background options with color previews. |
| `ControlBarView.swift` | 121 | Contains `PulseModifier` (used by other views). |
| `WebcamOverlayView.swift` | 188 | Webcam overlay for window-based UI (ContentView). |
| `ContentView.swift` | 433 | Alternative full-window UI (inactive). |
| `PermissionsView.swift` | 68 | Permission request screen (inactive). |

### Utilities
| File | Lines | Purpose |
|------|-------|---------|
| `SettingsStore.swift` | 120 | `UserDefaults` persistence for camera, mic, webcam size/position/background, system audio, countdown, quality, click highlights, keystroke display, save directory. |
| `PermissionManager.swift` | 69 | Checks camera/mic on launch. Screen recording checked lazily on first record. |
| `TimeFormatter.swift` | 10 | Formats `TimeInterval` to `HH:MM:SS`. |

---

## Data Flow

### Recording Start (with Countdown)
```
User clicks RECORD
  → RecordingViewModel.startRecording()
    → If countdown enabled:
      → status = .countdown(3) → onCountdownStarted(3) → AppController shows overlay
      → sleep 1s → .countdown(2) → .countdown(1) → onCountdownEnded → hide overlay
    → status = .preparing
    → ScreenCaptureManager.startCapture(display, cropRect?, systemAudio?, quality?)
    → CameraManager.startCapture(device)
    → AudioManager.startCapture(device)
    → VideoComposer.startWriting(url, width, height)
    → ClickHighlightManager.start() (if enabled)
    → KeystrokeManager.start() (if enabled)
    → status = .recording → onRecordingStarted → AppController shows menu bar button
```

### Every Screen Frame
```
SCStream → ScreenCaptureManager
  → If paused: skip frame, record pauseStartTime
  → If resumed: compute totalPauseOffset, adjust PTS
  → onScreenFrame → VideoComposer.appendScreenFrame()
    → Webcam compositing (if enabled): circular mask + position
    → Click highlights (if enabled): render expanding yellow rings
    → Keystroke display (if enabled): render modifier+key badge
    → AVAssetWriterInputPixelBufferAdaptor.append(adjusted PTS)
```

### Pause/Resume
```
User clicks PAUSE
  → ViewModel.pauseRecording()
    → status = .paused
    → composer.isPaused = true → frames skipped, pauseStartTime recorded
    → Timer stopped → elapsed time frozen
    → onPauseChanged(true) → menu bar shows ⏸ orange icon

User clicks RESUME
  → ViewModel.resumeRecording()
    → pauseAccumulator += duration of pause
    → composer.isPaused = false → totalPauseOffset updated on next frame
    → status = .recording → timer restarts
    → onPauseChanged(false) → menu bar shows 🔴 red icon
```

### Recording Stop
```
User clicks STOP (menu bar / control bar / ⇧⌘R)
  → RecordingViewModel.stopRecording()
    → ClickHighlightManager.stop()
    → KeystrokeManager.stop()
    → ScreenCaptureManager.stopCapture()
    → CameraManager.stopCapture()
    → AudioManager.stopCapture()
    → VideoComposer.finishWriting() → .mov URL
    → NSWorkspace.activateFileViewerSelecting([url])
    → onRecordingStopped → hide menu bar button + webcam panel
    → status = .idle
```

---

## Key APIs Used

| API | Usage |
|-----|-------|
| `ScreenCaptureKit` | `SCStream` (screen + system audio), `SCStreamConfiguration`, `SCContentFilter` |
| `AVFoundation` | `AVCaptureSession`, `AVCaptureDevice`, `AVAssetWriter`, `AVAssetWriterInput` |
| `Vision` | `VNGeneratePersonSegmentationRequest` (person mask for virtual backgrounds) |
| `Core Image` | `CIBlendWithMask`, `CIRadialGradient`, `CILinearGradient`, `CIGaussianBlur` |
| `CoreText` | `CTFontCreateWithName`, `CTLineDraw` (keystroke badge rendering) |
| `CoreGraphics` | `CGEvent.tapCreate` (global click + keystroke monitoring) |
| `AppKit` | `NSPanel`, `NSStatusItem`, `NSMenu`, `NSHostingView` |
| `SwiftUI` | `Window` scene, `@Observable`, `@Bindable`, `Menu`, `Toggle`, `Slider` |

---

## UI Components

### 1. Control Bar (SwiftUI Window — bottom of screen)
```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ 00:00:00 │ 📹 Camera ▾ │ 🎤 Mic ▾ │ 🔊 │ 👤 │ ⚙️ │ ⏸ PAUSE │ ● RECORD │
└──────────────────────────────────────────────────────────────────────────────────┘
```
- Settings gear contains: virtual background, capture mode, quality, click highlights, keystroke display, countdown toggle, keyboard shortcuts

### 2. Webcam Circle (floating NSPanel)
```
     ┌──📷──┐
    (  FACE  )  ← Draggable, resizable, virtual background
     └──────┘
```

### 3. Menu Bar Status (NSStatusItem — during recording)
```
                                    [🔴 ⏹ 00:01:23]  ← click for dropdown
                                     ├─ Stop Recording
                                     ├─ Pause / Resume
                                     ├─ Show Controls
                                     └─ Recent Recordings
```

### 4. Countdown Overlay (NSPanel — before recording)
```
          ┌─────────────────┐
          │                 │
          │       3         │
          │  Recording...   │
          │   ◠◡◠◡◠◡       │  ← progress ring
          └─────────────────┘
```

### 5. Recent Recordings (NSPanel)
```
┌─ Recent Recordings ─────────────────────┐
│ 🎬 Recording_2026-04-25  3:42  145 MB  │
│ 🎬 Recording_2026-04-24  1:15   52 MB  │
│ 🎬 Recording_2026-04-23  0:30   21 MB  │
│         [📂] [▶] [🗑]                   │
└─────────────────────────────────────────┘
```

---

## Click Highlights

When enabled, every mouse click creates an expanding yellow ring in the recorded video:

```
CGEvent.tapCreate(.listenOnly, leftMouseDown | rightMouseDown)
  → normalize position to 0-1 screen coords
  → ClickHighlight(position, timestamp, duration: 0.6s)
  → VideoComposer.addClickHighlight()
  → On each frame: render CIRadialGradient ring
    → radius: 20px → 60px (expanding)
    → color: yellow → orange → transparent (fading)
    → Composited over screen frame via CIImage
```

**Requires Accessibility permission.**

---

## Keystroke Display

When enabled, modifier keyboard shortcuts appear as a badge in the recorded video:

```
CGEvent.tapCreate(.listenOnly, keyDown)
  → Filter: only when ⌘, ⌃, or ⌥ modifier is held
  → Map virtual key code → readable name (A-Z, F1-F12, ↩, ⌫, etc.)
  → Format: "⌘C", "⇧⌘S", "⌃⌥⌦"
  → KeystrokeDisplay(text, timestamp, duration: 2.0s)
  → VideoComposer renders pill badge at bottom-center:
    → Dark semi-transparent background (rounded rect)
    → White text rendered via CoreText
    → Fades out via alpha after 2 seconds
```

**Requires Accessibility permission.**

---

## Virtual Background System

```
Raw Camera Frame → VNGeneratePersonSegmentationRequest (.balanced)
  → Person Mask → scale to match frame
  → Background: .blur → Gaussian(18) | .sunset/.ocean/etc → CILinearGradient
  → CIBlendWithMask(person, background, mask)
  → Output CVPixelBuffer
```

**Backgrounds**: None, Blur, Sunset, Ocean, Forest, Night Sky, Studio

---

## iPhone Camera (Continuity Camera)

macOS 13+ can use iPhone cameras as `AVCaptureDevice` (type: `.external`).

**Requirements**: Same Apple ID, WiFi+Bluetooth ON, iPhone unlocked & nearby, Handoff enabled.

**Auto-detection**: `AVCaptureDeviceWasConnected` observer auto-refreshes the camera list when an iPhone connects.

---

## Permissions

| Permission | When Checked | Method |
|------------|-------------|--------|
| Camera | On app launch | `AVCaptureDevice.requestAccess(for: .video)` |
| Microphone | On app launch | `AVCaptureDevice.requestAccess(for: .audio)` |
| Screen Recording | On first Record click | `SCShareableContent` triggers native macOS prompt |
| Accessibility | When click highlights / keystroke display enabled | `CGEvent.tapCreate` — fails silently if denied |

---

## Configuration

### Build Settings
- `ENABLE_APP_SANDBOX = NO`
- `MACOSX_DEPLOYMENT_TARGET = 14.0`
- Camera + Microphone usage descriptions in Info.plist
- Code Signing: "Sign to Run Locally"

### Recording Output
- **Format**: H.264 / AAC in `.mov`
- **Frame Rate**: 30 FPS
- **Bitrate**: `width × height × 6`
- **Audio**: 44.1kHz stereo, 128kbps AAC
- **System Audio**: 48kHz stereo (via SCStream)
- **Save Location**: `~/Desktop/Recording_*.mov` (configurable)

---

## Settings Persistence

All preferences persist across launches via `SettingsStore` (UserDefaults):

| Setting | Default |
|---------|---------|
| Selected camera | First available |
| Selected mic | First available |
| Webcam diameter | 180px |
| Webcam position | (0.82, 0.82) |
| Virtual background | None |
| Webcam enabled | true |
| System audio | false |
| Countdown timer | true (3 seconds) |
| Quality preset | Native |
| Click highlights | false |
| Keystroke display | false |
| Save directory | Desktop |

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⇧⌘R | Start / Stop Recording |
| ⇧⌘P | Pause / Resume |
| ⇧⌘W | Toggle Webcam |
| ⇧⌘A | Toggle System Audio |
| ⌘K | Show Webcam Panel |
| ⌘L | Recent Recordings |
| ⌘Q | Quit |

---

## Known Behaviors

1. **First run**: macOS prompts for Camera, Microphone, and Screen Recording permissions
2. **After rebuild**: Screen Recording permission may need re-granting (`tccutil reset ScreenCapture`)
3. **Click/keystroke features**: Require Accessibility permission — added manually via System Settings
4. **Webcam hidden on stop**: The webcam panel hides when recording stops. Re-show via ⌘K
5. **Pause**: Video file is continuous — paused segments are omitted, no gap in playback
6. **Settings persist**: All preferences saved automatically on every change

---

## Future Enhancement Areas

| Area | What to Add | Where to Modify |
|------|-------------|-----------------|
| Custom background images | Load user photos as backgrounds | `BackgroundProcessor` + `WebcamBackground` |
| Webcam shapes | Square, rounded-rect, pill | `VideoComposer.compositeFrames()` mask |
| Annotations/Drawing | Draw on screen during recording | New overlay `NSPanel` |
| Auto-zoom on clicks | Smooth zoom like Screen Studio | `VideoComposer` + `ClickHighlightManager` |
| Video preview/trim | Trim before saving | New `PreviewWindow` + `AVPlayer` |
| Export formats | MP4, WebM, GIF | `AVAssetExportSession` post-processing |
| Multi-monitor | Select which display | `ScreenCaptureManager.availableDisplays()` picker |
| Click sounds | Audio feedback on clicks | Mix click sound into audio track |
| Cursor smoothing | Smooth mouse movement in video | `VideoComposer` frame interpolation |
| Hotkey screenshot | Capture still during recording | `ScreenCaptureManager` + save CGImage |
| App notarization | Distribute outside App Store | Code signing + notarization workflow |
