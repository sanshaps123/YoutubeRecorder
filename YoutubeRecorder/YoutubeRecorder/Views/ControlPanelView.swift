import SwiftUI
import AVFoundation

/// Compact floating control bar at the bottom of the screen
struct ControlPanelView: View {
    @Bindable var viewModel: RecordingViewModel

    var body: some View {
        HStack(spacing: 14) {
            // Recording indicator + timer
            HStack(spacing: 8) {
                if viewModel.status.isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .shadow(color: .red.opacity(0.8), radius: 4)
                        .modifier(PulseModifier())
                } else if viewModel.status.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Text(RecordingTimeFormatter.format(viewModel.elapsedTime))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(minWidth: 110, alignment: .leading)

            divider

            // Recording Mode Switcher (Screen | Screen+Cam | Camera)
            HStack(spacing: 2) {
                ForEach(RecordingMode.allCases) { mode in
                    Button {
                        viewModel.setRecordingMode(mode)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 10))
                            Text(mode.shortLabel)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewModel.recordingMode == mode
                                      ? Color.accentColor.opacity(0.7)
                                      : Color.white.opacity(0.06))
                        )
                        .foregroundStyle(viewModel.recordingMode == mode ? .white : .white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            divider
            // Camera picker
            Menu {
                ForEach(viewModel.availableCameras, id: \.uniqueID) { cam in
                    Button {
                        viewModel.selectCamera(cam.uniqueID)
                    } label: {
                        HStack {
                            if cam.deviceType == .external {
                                Image(systemName: "iphone")
                            }
                            Text(cam.localizedName)
                            if cam.uniqueID == viewModel.selectedCameraId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("Refresh") { viewModel.refreshDevices() }
            } label: {
                compactLabel(icon: "video.fill", color: .green, text: viewModel.selectedCameraName)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 130)

            divider

            // Audio picker
            Menu {
                ForEach(viewModel.availableMics, id: \.uniqueID) { mic in
                    Button {
                        viewModel.selectMic(mic.uniqueID)
                    } label: {
                        HStack {
                            Text(mic.localizedName)
                            if mic.uniqueID == viewModel.selectedMicId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                compactLabel(icon: "mic.fill", color: .blue, text: viewModel.selectedMicName)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 130)

            divider

            // System audio toggle
            Button { viewModel.toggleSystemAudio() } label: {
                Image(systemName: viewModel.isSystemAudioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(viewModel.isSystemAudioEnabled ? .purple : .gray)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help(viewModel.isSystemAudioEnabled ? "System audio ON" : "System audio OFF")

            // Webcam toggle
            Button { viewModel.toggleWebcam() } label: {
                Image(systemName: viewModel.isWebcamEnabled ? "person.crop.circle.fill" : "person.crop.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(viewModel.isWebcamEnabled ? .green : .gray)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help(viewModel.isWebcamEnabled ? "Hide webcam" : "Show webcam")

            // Settings menu
            Menu {
                Menu("Virtual Background") {
                    ForEach(WebcamBackground.allCases) { bg in
                        Button {
                            viewModel.setBackground(bg)
                        } label: {
                            HStack {
                                Image(systemName: bg.icon)
                                Text(bg.rawValue)
                                if viewModel.selectedBackground == bg {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Menu("Capture Mode") {
                    Button {
                        viewModel.setCaptureMode(.fullScreen)
                    } label: {
                        HStack {
                            Text("Entire Screen")
                            if viewModel.captureMode == .fullScreen {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(viewModel.status.isActive)
                    Button {
                        viewModel.setCaptureMode(.portion)
                    } label: {
                        HStack {
                            Text("Selected Portion")
                            if viewModel.captureMode == .portion {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(viewModel.status.isActive)
                }

                Menu("Quality") {
                    ForEach(QualityPreset.allCases) { preset in
                        Button {
                            viewModel.setQualityPreset(preset)
                        } label: {
                            HStack {
                                Text(preset.rawValue)
                                if viewModel.qualityPreset == preset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

               /* Toggle("Click Highlights", isOn: Binding(
                    get: { viewModel.isClickHighlightEnabled },
                    set: { _ in viewModel.toggleClickHighlight() }
                ))

                Toggle("Keystroke Display", isOn: Binding(
                    get: { viewModel.isKeystrokeDisplayEnabled },
                    set: { _ in viewModel.toggleKeystrokeDisplay() }
                ))*/

                Toggle("Countdown Timer", isOn: Binding(
                    get: { viewModel.isCountdownEnabled },
                    set: { _ in viewModel.toggleCountdown() }
                ))

                Menu("Webcam Shape") {
                    ForEach(WebcamShape.allCases) { shape in
                        Button {
                            viewModel.setWebcamShape(shape)
                        } label: {
                            HStack {
                                Image(systemName: shape.icon)
                                Text(shape.rawValue)
                                if viewModel.webcamShape == shape {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                Toggle("Live Captions", isOn: Binding(
                    get: { viewModel.isCaptionEnabled },
                    set: { _ in viewModel.toggleCaptions() }
                ))

                if viewModel.isCaptionEnabled {
                    Toggle("Caption Overlay", isOn: Binding(
                        get: { viewModel.isCaptionOverlayVisible },
                        set: { _ in viewModel.toggleCaptionOverlay() }
                    ))

                    Button("Customize Caption Style…") {
                        viewModel.onCaptionStylePickerRequested?()
                    }
                }

                Divider()

                Text("⇧⌘R  Start/Stop Recording")
                Text("⇧⌘P  Pause/Resume")
                Text("⇧⌘W  Toggle Webcam")
                Text("⌃⌘1  Screen Only")
                Text("⌃⌘2  Screen + Webcam")
                Text("⌃⌘3  Camera Only")
                Text("⌘L     Recent Recordings")
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)

            // Free tier time remaining indicator
            if SubscriptionManager.shared.currentTier == .free && viewModel.status.isActive {
                Text(RecordingTimeFormatter.format(viewModel.freeTierTimeRemaining))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.orange)
                    .help("Free tier: \(SubscriptionManager.shared.currentTier.recordingLimitText) limit")
            }

            divider

            // Pause / Resume (only during active recording)
            if viewModel.status.isActive {
                Button {
                    viewModel.togglePause()
                } label: {
                    Image(systemName: viewModel.status.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(viewModel.status.isPaused ? .orange : .white.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .help(viewModel.status.isPaused ? "Resume" : "Pause")
            }

            // Record / Stop
            Button {
                Task {
                    if viewModel.status.isActive {
                        await viewModel.stopRecording()
                    } else {
                        await viewModel.startRecording()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.status.isActive {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white)
                            .frame(width: 12, height: 12)
                    } else {
                        Circle().fill(.white).frame(width: 10, height: 10)
                    }
                    Text(viewModel.status.isActive ? "STOP" : "RECORD")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(viewModel.status.isActive ? .gray.opacity(0.5) : .red)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.status == .preparing || viewModel.status == .stopping)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minWidth: 750)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 28)
    }

    private func compactLabel(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}
