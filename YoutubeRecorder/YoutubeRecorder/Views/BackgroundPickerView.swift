import SwiftUI

struct BackgroundPickerView: View {
    @Bindable var viewModel: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Virtual Background")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button { viewModel.showBackgroundPicker = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(WebcamBackground.allCases) { bg in
                    backgroundTile(bg)
                }
            }
        }
        .padding(56)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
        .frame(width: 340)
    }

    private func backgroundTile(_ bg: WebcamBackground) -> some View {
        let isSelected = viewModel.selectedBackground == bg
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.setBackground(bg)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if bg == .none {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.gray.opacity(0.2))
                            .overlay(
                                Image(systemName: "nosign")
                                    .foregroundStyle(.secondary)
                            )
                    } else if bg == .blur {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.linearGradient(
                                colors: [.gray.opacity(0.5), .gray.opacity(0.3)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(
                                Image(systemName: "camera.filters")
                                    .foregroundStyle(.white.opacity(0.8))
                            )
                    } else {
                        let (c0, c1) = bg.previewColors
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.linearGradient(
                                colors: [Color(c0), Color(c1)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .frame(height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                )

                Text(bg.rawValue)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
