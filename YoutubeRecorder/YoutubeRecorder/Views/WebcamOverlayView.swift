import SwiftUI

struct WebcamOverlayView: View {
    @Bindable var viewModel: RecordingViewModel
    let containerSize: CGSize

    @State private var dragOffset: CGSize = .zero
    @State private var currentPosition: CGPoint?
    @State private var baseScale: CGFloat = 1.0
    @State private var isHovering = false

    private var diameter: CGFloat { viewModel.webcamDiameter }

    var body: some View {
        if viewModel.isWebcamEnabled {
            let pos = currentPositionValue

            ZStack {
                // Webcam circle
                webcamCircle

                // Floating controls (visible on hover)
                if isHovering {
                    sizeControls
                        .offset(y: diameter / 2 + 28)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 4)
            .position(x: pos.x + dragOffset.width, y: pos.y + dragOffset.height)
            .gesture(dragGesture)
            .gesture(magnifyGesture)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) { isHovering = hovering }
            }
            .animation(.interactiveSpring(response: 0.3), value: dragOffset)

            // Background picker popover
            if viewModel.showBackgroundPicker {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        BackgroundPickerView(viewModel: viewModel)
                            .padding(.trailing, 20)
                            .padding(.bottom, diameter + 70)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
            }
        }
    }

    // MARK: - Webcam Circle

    private var webcamCircle: some View {
        ZStack {
            if let cgImage = viewModel.webcamPreviewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(.black.opacity(0.5))
                    .frame(width: diameter, height: diameter)
                    .overlay(ProgressView().scaleEffect(0.7))
            }

            Circle()
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.2)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 3
                )
                .frame(width: diameter, height: diameter)

            // Background picker toggle (top-right)
            Button { viewModel.showBackgroundPicker.toggle() } label: {
                Image(systemName: "photo.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: diameter / 2 - 14, y: -(diameter / 2 - 14))
        }
    }

    // MARK: - Size Controls

    private var sizeControls: some View {
        HStack(spacing: 8) {
            // Reduce button
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

            // Size slider
            Slider(
                value: Binding(
                    get: { Double(viewModel.webcamDiameter) },
                    set: { viewModel.updateWebcamDiameter(CGFloat($0)) }
                ),
                in: 80...400,
                step: 10
            )
            .frame(width: 100)
            .tint(.white.opacity(0.6))

            // Enlarge button
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

            // Size label
            Text("\(Int(diameter))px")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        )
    }

    // MARK: - Position

    private var currentPositionValue: CGPoint {
        currentPosition ?? CGPoint(
            x: containerSize.width - diameter / 2 - 24,
            y: containerSize.height - diameter / 2 - 60
        )
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in dragOffset = v.translation }
            .onEnded { v in
                let newPos = CGPoint(x: currentPositionValue.x + v.translation.width,
                                    y: currentPositionValue.y + v.translation.height)
                let clamped = CGPoint(
                    x: min(max(newPos.x, diameter / 2), containerSize.width - diameter / 2),
                    y: min(max(newPos.y, diameter / 2 + 30), containerSize.height - diameter / 2 - 30)
                )
                currentPosition = clamped
                dragOffset = .zero
                viewModel.updateWebcamPosition(CGPoint(
                    x: clamped.x / containerSize.width,
                    y: clamped.y / containerSize.height
                ))
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                viewModel.updateWebcamDiameter(baseScale * diameter * v.magnification)
            }
            .onEnded { _ in baseScale = 1.0 }
    }
}
