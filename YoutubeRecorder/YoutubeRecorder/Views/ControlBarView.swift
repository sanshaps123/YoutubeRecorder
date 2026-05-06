import SwiftUI

struct ControlBarView: View {
    @Bindable var viewModel: RecordingViewModel

    var body: some View {
        HStack(spacing: 20) {
            // Recording timer
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
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(minWidth: 120)

            Spacer()

            // Pause / Resume (during active recording)
            if viewModel.status.isActive {
                Button {
                    viewModel.togglePause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 44, height: 44)
                        Image(systemName: viewModel.status.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(viewModel.status.isPaused ? .orange : .white)
                    }
                }
                .buttonStyle(.plain)
            }

            // Record / Stop button
            Button {
                Task {
                    if viewModel.status.isActive {
                        await viewModel.stopRecording()
                    } else if viewModel.status == .idle {
                        await viewModel.startRecording()
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)

                    if viewModel.status.isActive {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.red)
                            .frame(width: 20, height: 20)
                    } else {
                        Circle()
                            .fill(.red)
                            .frame(width: 28, height: 28)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.status == .preparing || viewModel.status == .stopping)

            Spacer()

            // Webcam toggle
            Button {
                viewModel.toggleWebcam()
            } label: {
                Image(systemName: viewModel.isWebcamEnabled ? "video.fill" : "video.slash.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(viewModel.isWebcamEnabled ? .white : .gray)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Status indicator
            statusBadge
                .frame(minWidth: 80)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch viewModel.status {
        case .idle:
            Label("Ready", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .countdown(let n):
            Label("\(n)…", systemImage: "timer")
                .font(.caption.bold())
                .foregroundStyle(.orange)
        case .preparing:
            Label("Starting…", systemImage: "gear")
                .font(.caption)
                .foregroundStyle(.orange)
        case .recording:
            Label("REC", systemImage: "record.circle")
                .font(.caption.bold())
                .foregroundStyle(.red)
        case .paused:
            Label("PAUSED", systemImage: "pause.circle")
                .font(.caption.bold())
                .foregroundStyle(.orange)
        case .stopping:
            Label("Saving…", systemImage: "square.and.arrow.down")
                .font(.caption)
                .foregroundStyle(.yellow)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }
}

// MARK: - Pulse Animation
struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
