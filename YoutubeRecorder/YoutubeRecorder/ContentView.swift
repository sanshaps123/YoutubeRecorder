import SwiftUI
import AVFoundation

struct ContentView: View {
    @State var viewModel = RecordingViewModel()

    var body: some View {
        Group {
            if viewModel.permissionManager.allGranted {
                mainRecordingUI
            } else {
                PermissionsView(permissionManager: viewModel.permissionManager)
            }
        }
        .task {
            await viewModel.requestPermissions()
            // Start screen preview immediately
            if viewModel.permissionManager.allGranted {
                await viewModel.startPreview()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Main Recording UI (Kinetic Recorder style)

    private var mainRecordingUI: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.09).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider().background(Color.white.opacity(0.1))

                ZStack {
                    // Live screen preview
                    previewArea

                    // Left info panel
                    VStack {
                        infoPanel
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)

                    // Center status badge
                    VStack {
                        statusBadge
                            .padding(.top, 40)
                        Spacer()
                    }

                    // Countdown overlay
                    if case .countdown(let value) = viewModel.status {
                        CountdownOverlayView(countdownValue: value)
                            .transition(.opacity)
                    }

                    // Webcam overlay (bottom-right)
                    GeometryReader { geo in
                        WebcamOverlayView(viewModel: viewModel, containerSize: geo.size)
                    }
                }

                Divider().background(Color.white.opacity(0.1))
                bottomBar
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text("YoutubeRecorder")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)

            statusPill
                .padding(.leading, 8)

            Spacer()

            // System audio toggle
            Button { viewModel.toggleSystemAudio() } label: {
                Image(systemName: viewModel.isSystemAudioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(viewModel.isSystemAudioEnabled ? .purple : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help(viewModel.isSystemAudioEnabled ? "System audio ON" : "System audio OFF")

            // Mic toggle
            Button { } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)

            // Camera toggle
            Button { viewModel.toggleWebcam() } label: {
                Image(systemName: viewModel.isWebcamEnabled ? "video.fill" : "video.slash.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(viewModel.isWebcamEnabled ? .white.opacity(0.7) : .red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)

            // Settings
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
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .idle: return .green
        case .countdown: return .orange
        case .preparing: return .orange
        case .recording: return .red
        case .paused: return .yellow
        case .stopping: return .yellow
        case .error: return .red
        }
    }

    private var statusText: String {
        switch viewModel.status {
        case .idle: return "READY"
        case .countdown(let n): return "STARTING IN \(n)"
        case .preparing: return "PREPARING"
        case .recording: return "RECORDING"
        case .paused: return "PAUSED"
        case .stopping: return "SAVING"
        case .error(let m): return "ERROR: \(m)"
        }
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        Group {
            if let cgImage = viewModel.previewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(8)
            } else {
                Color.black.opacity(0.3)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading preview…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    )
                    .padding(8)
            }
        }
    }

    // MARK: - Left Info Panel

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            infoRow(label: "RESOLUTION", value: viewModel.resolutionText)
            infoRow(label: "FRAME RATE", value: "30 FPS")
            infoRow(label: "FORMAT", value: "H.264 / MOV")
            infoRow(label: "QUALITY", value: viewModel.qualityPreset.rawValue)
            if !viewModel.freeStorageText.isEmpty {
                infoRow(label: "STORAGE", value: viewModel.freeStorageText)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .frame(width: 170)
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.red.opacity(0.9))
                .tracking(1)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Center Status Badge

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusBadgeDotColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusBadgeDotColor.opacity(0.6), radius: 4)
                .modifier(PulseModifier())

            Text(statusBadgeText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
    }

    private var statusBadgeDotColor: Color {
        switch viewModel.status {
        case .recording: return .red
        case .paused: return .orange
        default: return .orange
        }
    }

    private var statusBadgeText: String {
        switch viewModel.status {
        case .recording: return "Recording…"
        case .paused: return "Paused"
        case .countdown(let n): return "Starting in \(n)…"
        default: return "System standing by for capture…"
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            // Timer
            VStack(alignment: .leading, spacing: 2) {
                Text("ELAPSED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1)
                Text(RecordingTimeFormatter.format(viewModel.elapsedTime))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(minWidth: 140, alignment: .leading)

            Spacer()

            // Source dropdown
            dropdownSection(icon: "rectangle.dashed", label: "SOURCE", items: ["Entire Screen", "Selected Portion"]) { item in
                viewModel.setCaptureMode(item == "Entire Screen" ? .fullScreen : .portion)
            } currentValue: {
                viewModel.captureMode == .fullScreen ? "Entire Screen" : "Selected Portion"
            }

            Spacer().frame(width: 16)

            // Camera dropdown (includes iPhone via Continuity Camera)
            cameraDropdown

            Spacer().frame(width: 16)

            // Audio dropdown
            audioDropdown

            Spacer()

            // Pause button (during active recording)
            if viewModel.status.isActive {
                Button {
                    viewModel.togglePause()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.status.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(viewModel.status.isPaused ? "RESUME" : "PAUSE")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(viewModel.status.isPaused ? .orange : .white.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }

            // Record / Stop button
            recordButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
    }

    // MARK: - Dropdowns

    private func dropdownSection(icon: String, label: String, items: [String],
                                  action: @escaping (String) -> Void,
                                  currentValue: () -> String) -> some View {
        Menu {
            ForEach(items, id: \.self) { item in
                Button(item) { action(item) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text(label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(1)
                }
                HStack(spacing: 4) {
                    Text(currentValue())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .menuStyle(.borderlessButton)
    }

    private var cameraDropdown: some View {
        Menu {
            ForEach(viewModel.availableCameras, id: \.uniqueID) { cam in
                Button {
                    viewModel.selectCamera(cam.uniqueID)
                } label: {
                    HStack {
                        // iPhone cameras show as external devices via Continuity Camera
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
            Button("Refresh Devices") { viewModel.refreshDevices() }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("CAMERA")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(1)
                }
                HStack(spacing: 4) {
                    Text(viewModel.selectedCameraName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .menuStyle(.borderlessButton)
    }

    private var audioDropdown: some View {
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
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.blue)
                    Text("AUDIO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(1)
                }
                HStack(spacing: 4) {
                    Text(viewModel.selectedMicName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            Task {
                if viewModel.status.isActive {
                    await viewModel.stopRecording()
                } else {
                    await viewModel.startRecording()
                }
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.status.isActive {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
                        .frame(width: 14, height: 14)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                }
                Text(viewModel.status.isActive ? "STOP" : "START RECORDING")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(viewModel.status.isActive
                          ? Color.gray.opacity(0.6)
                          : Color.red)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.status == .preparing || viewModel.status == .stopping)
    }
}
