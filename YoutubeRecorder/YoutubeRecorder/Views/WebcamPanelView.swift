import SwiftUI

/// Floating webcam panel — adapts between circular/shaped overlay and full-frame camera preview
struct WebcamPanelView: View {
    @Bindable var viewModel: RecordingViewModel
    @State private var isHovering = false

    private var diameter: CGFloat { viewModel.webcamDiameter }
    private var isCameraOnly: Bool { viewModel.recordingMode == .cameraOnly }

    var body: some View {
        VStack(spacing: 0) {
            if isCameraOnly {
                cameraOnlyView
            } else {
                webcamOverlayView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.2)) { isHovering = h }
        }
        .animation(.easeInOut(duration: 0.3), value: isCameraOnly)
    }

    // MARK: - Camera Only (full-screen preview)

    private var cameraOnlyView: some View {
        GeometryReader { geo in
            ZStack {
                if let cgImage = viewModel.webcamPreviewImage {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.black
                        .overlay(ProgressView().scaleEffect(1.2))
                }

                // Top bar overlay
                VStack {
                    HStack {
                        modeBadge(text: "CAMERA ONLY", color: .orange)
                        Spacer()
                        if viewModel.status.isRecording {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 10, height: 10)
                                    .shadow(color: .red.opacity(0.8), radius: 4)
                                    .modifier(PulseModifier())
                                Text(RecordingTimeFormatter.format(viewModel.elapsedTime))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.5)))
                        } else if viewModel.status.isPaused {
                            HStack(spacing: 6) {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                                Text("PAUSED")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.5)))
                        }
                    }
                    .padding(16)
                    Spacer()
                }

                // Bottom bar (on hover)
                if isHovering {
                    VStack {
                        Spacer()
                        // Mode switcher + controls
                        HStack(spacing: 12) {
                            Button { viewModel.showBackgroundPicker.toggle() } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo.fill")
                                        .font(.system(size: 12))
                                    Text("Background")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(.ultraThinMaterial))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            // Mode switcher
                            HStack(spacing: 2) {
                                ForEach(RecordingMode.allCases) { mode in
                                    Button {
                                        viewModel.setRecordingMode(mode)
                                    } label: {
                                        Image(systemName: mode.icon)
                                            .font(.system(size: 12))
                                            .foregroundStyle(viewModel.recordingMode == mode ? .white : .white.opacity(0.4))
                                            .frame(width: 32, height: 28)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(viewModel.recordingMode == mode
                                                          ? Color.accentColor.opacity(0.5)
                                                          : Color.clear)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(4)
                            .background(Capsule().fill(.black.opacity(0.5)))

                            Spacer()

                            Text(viewModel.selectedCameraName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(.black.opacity(0.4)))
                        }
                        .padding(16)
                    }
                    .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Webcam Overlay (Screen + Webcam mode) — shape-adaptive

    private var webcamOverlayView: some View {
        VStack(spacing: 10) {
            ZStack {
                if viewModel.isWebcamEnabled {
                    if let cgImage = viewModel.webcamPreviewImage {
                        Image(decorative: cgImage, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: diameter, height: diameter)
                            .clipShape(RoundedRectangle(cornerRadius: shapeCornerRadius))
                    } else {
                        RoundedRectangle(cornerRadius: shapeCornerRadius)
                            .fill(.black.opacity(0.4))
                            .frame(width: diameter, height: diameter)
                            .overlay(ProgressView().scaleEffect(0.8))
                    }

                    // Border
                    RoundedRectangle(cornerRadius: shapeCornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.7), .white.opacity(0.2)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: diameter, height: diameter)



                    // Background picker
                    Button { viewModel.showBackgroundPicker.toggle() } label: {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: -(diameter / 2 - 14), y: -(diameter / 2 - 14))
                    .opacity(isHovering ? 1 : 0)
                }
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)

            // Controls on hover
            if isHovering && viewModel.isWebcamEnabled {
                VStack(spacing: 6) {
                    shapePicker
                    sizeControls
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Background picker popover
            if viewModel.showBackgroundPicker {
                BackgroundPickerView(viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }

    /// Corner radius from the current webcam shape
    private var shapeCornerRadius: CGFloat {
        diameter * viewModel.webcamShape.cornerRadiusFraction
    }

    // MARK: - Helpers

    private func modeBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.8)))
    }

    /// Shape picker — circle / rounded rect / rectangle
    private var shapePicker: some View {
        HStack(spacing: 4) {
            ForEach(WebcamShape.allCases) { shape in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.setWebcamShape(shape)
                    }
                } label: {
                    Image(systemName: shape.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(viewModel.webcamShape == shape ? .white : .white.opacity(0.4))
                        .frame(width: 30, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewModel.webcamShape == shape
                                      ? Color.accentColor.opacity(0.5)
                                      : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
        )
    }

    private var sizeControls: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.updateWebcamDiameter(diameter - 30)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { Double(viewModel.webcamDiameter) },
                    set: { viewModel.updateWebcamDiameter(CGFloat($0)) }
                ),
                in: 80...400, step: 10
            )
            .frame(width: 100)
            .tint(.white.opacity(0.6))

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.updateWebcamDiameter(diameter + 30)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            .buttonStyle(.plain)

            Text("\(Int(diameter))")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
        )
    }
}
