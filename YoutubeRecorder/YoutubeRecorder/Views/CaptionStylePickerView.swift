import SwiftUI

/// A dedicated panel for configuring caption/subtitle appearance before recording.
/// Shows a live preview of how subtitles will appear in the final recorded video.
struct CaptionStylePickerView: View {
    @Bindable var viewModel: RecordingViewModel
    var onDismiss: (() -> Void)?

    @State private var previewText = "Hello, welcome to this recording"
    @State private var animatedText = ""
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Caption Style", systemImage: "captions.bubble.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(red: 0.08, green: 0.09, blue: 0.11))

            Divider().background(Color.white.opacity(0.1))

            // Live Preview Area
            ZStack {
                // Simulated video background
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.14, blue: 0.18),
                        Color(red: 0.08, green: 0.1, blue: 0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Grid pattern to simulate screen content
                VStack(spacing: 20) {
                    ForEach(0..<4) { _ in
                        HStack(spacing: 16) {
                            ForEach(0..<3) { _ in
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white.opacity(0.04))
                                    .frame(height: 30)
                            }
                        }
                    }
                }
                .padding(30)

                // Caption preview at configured position
                VStack {
                    if viewModel.captionStyle.position == .top {
                        captionPreview
                            .padding(.top, 20)
                        Spacer()
                    } else if viewModel.captionStyle.position == .center {
                        Spacer()
                        captionPreview
                        Spacer()
                    } else {
                        Spacer()
                        captionPreview
                            .padding(.bottom, 20)
                    }
                }

                // "PREVIEW" badge
                VStack {
                    HStack {
                        Text("PREVIEW")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.white.opacity(0.08)))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(16)

            Divider().background(Color.white.opacity(0.1))

            // Settings
            ScrollView {
                VStack(spacing: 16) {
                    // Position
                    settingSection("Position") {
                        HStack(spacing: 8) {
                            ForEach(CaptionStyle.CaptionPosition.allCases) { pos in
                                positionButton(pos)
                            }
                        }
                    }

                    // Text Color
                    settingSection("Text Color") {
                        HStack(spacing: 8) {
                            ForEach(CaptionStyle.CaptionColor.allCases) { color in
                                colorButton(color, isSelected: viewModel.captionStyle.textColor == color) {
                                    viewModel.setCaptionTextColor(color)
                                }
                            }
                        }
                    }

                    // Background Color
                    settingSection("Background") {
                        HStack(spacing: 8) {
                            ForEach(CaptionStyle.CaptionColor.allCases) { color in
                                colorButton(color, isSelected: viewModel.captionStyle.backgroundColor == color) {
                                    viewModel.setCaptionBackgroundColor(color)
                                }
                            }
                        }
                    }

                    // Font Weight
                    settingSection("Font Weight") {
                        HStack(spacing: 8) {
                            ForEach(CaptionStyle.FontWeight.allCases) { weight in
                                weightButton(weight)
                            }
                        }
                    }

                    // Font Size
                    settingSection("Font Size") {
                        HStack(spacing: 12) {
                            Text("\(Int(viewModel.captionStyle.fontSize))pt")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 40)

                            Slider(
                                value: Binding(
                                    get: { viewModel.captionStyle.fontSize },
                                    set: { viewModel.setCaptionFontSize($0) }
                                ),
                                in: 18...56,
                                step: 2
                            )
                            .tint(.blue)
                        }
                    }

                    // Background Opacity
                    settingSection("Background Opacity") {
                        HStack(spacing: 12) {
                            Text("\(Int(viewModel.captionStyle.backgroundOpacity * 100))%")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 40)

                            Slider(
                                value: Binding(
                                    get: { viewModel.captionStyle.backgroundOpacity },
                                    set: { viewModel.setCaptionBackgroundOpacity($0) }
                                ),
                                in: 0...1,
                                step: 0.05
                            )
                            .tint(.blue)
                        }
                    }

                    // Sample text
                    settingSection("Preview Text") {
                        TextField("Type sample text...", text: $previewText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white.opacity(0.06))
                            )
                    }
                }
                .padding(16)
            }

            Divider().background(Color.white.opacity(0.1))

            // Footer
            HStack {
                Button("Reset to Default") {
                    viewModel.captionStyle = .default
                    viewModel.setCaptionPosition(.bottom)
                    viewModel.setCaptionTextColor(.white)
                    viewModel.setCaptionFontWeight(.bold)
                    viewModel.setCaptionBackgroundColor(.black)
                    viewModel.setCaptionFontSize(32)
                    viewModel.setCaptionBackgroundOpacity(0.75)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onDismiss?()
                } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.blue)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 640)
        .background(Color(red: 0.06, green: 0.07, blue: 0.09))
        .preferredColorScheme(.dark)
        .onAppear {
            startWordAnimation()
        }
    }

    // MARK: - Caption Preview (YouTube-style)

    @ViewBuilder
    private var captionPreview: some View {
        let style = viewModel.captionStyle

        Text(animatedText.isEmpty ? previewText : animatedText)
            .font(.system(
                size: style.fontSize * 0.55, // Scale down for the preview box
                weight: nsWeight(style.fontWeight)
            ))
            .foregroundStyle(Color(nsColor: style.textColor.nsColor))
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: style.backgroundColor.nsColor)
                        .opacity(style.backgroundOpacity))
            )
            .padding(.horizontal, 30)
            .animation(.easeInOut(duration: 0.15), value: animatedText)
    }

    // MARK: - Word-by-Word Animation (simulates YouTube live captions)

    private func startWordAnimation() {
        guard !isAnimating else { return }
        isAnimating = true

        let words = previewText.split(separator: " ").map(String.init)
        animatedText = ""

        Task {
            for word in words {
                try? await Task.sleep(for: .milliseconds(280))
                await MainActor.run {
                    if animatedText.isEmpty {
                        animatedText = word
                    } else {
                        animatedText += " " + word
                    }
                }
            }

            // Hold for 2 seconds, then restart
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                isAnimating = false
                animatedText = ""
                startWordAnimation()
            }
        }
    }

    // MARK: - Subviews

    private func settingSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func positionButton(_ pos: CaptionStyle.CaptionPosition) -> some View {
        let isSelected = viewModel.captionStyle.position == pos
        return Button {
            viewModel.setCaptionPosition(pos)
        } label: {
            VStack(spacing: 4) {
                // Mini position indicator
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.1))
                    .frame(width: 36, height: 24)
                    .overlay {
                        VStack(spacing: 0) {
                            if pos == .top {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(isSelected ? .blue : .white.opacity(0.3))
                                    .frame(width: 20, height: 4)
                                    .padding(.top, 3)
                                Spacer()
                            } else if pos == .center {
                                Spacer()
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(isSelected ? .blue : .white.opacity(0.3))
                                    .frame(width: 20, height: 4)
                                Spacer()
                            } else {
                                Spacer()
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(isSelected ? .blue : .white.opacity(0.3))
                                    .frame(width: 20, height: 4)
                                    .padding(.bottom, 3)
                            }
                        }
                    }
                Text(pos.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? .blue.opacity(0.15) : .white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? .blue.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func colorButton(_ color: CaptionStyle.CaptionColor, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(isSelected ? .blue : .white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                )
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(color == .white || color == .yellow ? .black : .white)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(color.rawValue)
    }

    private func weightButton(_ weight: CaptionStyle.FontWeight) -> some View {
        let isSelected = viewModel.captionStyle.fontWeight == weight
        return Button {
            viewModel.setCaptionFontWeight(weight)
        } label: {
            Text(weight.rawValue)
                .font(.system(size: 11, weight: nsWeight(weight)))
                .foregroundStyle(isSelected ? .blue : .white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? .blue.opacity(0.15) : .white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? .blue.opacity(0.5) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func nsWeight(_ weight: CaptionStyle.FontWeight) -> Font.Weight {
        switch weight {
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        case .bold:     return .bold
        }
    }
}
