import SwiftUI

/// Live caption overlay displayed in a floating NSPanel during recording.
/// Observes the RecordingViewModel directly so captions update in real-time.
struct CaptionOverlayView: View {
    var viewModel: RecordingViewModel

    @State private var displayedText: String = ""
    @State private var opacity: Double = 0

    var body: some View {
        VStack {
            Spacer()

            if !displayedText.isEmpty {
                Text(displayedText)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.black.opacity(0.75))
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                    )
                    .padding(.horizontal, 60)
                    .padding(.bottom, 60)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .opacity(opacity)
                    .animation(.easeInOut(duration: 0.2), value: displayedText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.currentCaptionText) { _, newValue in
            if !newValue.isEmpty {
                displayedText = newValue
                withAnimation(.easeIn(duration: 0.15)) {
                    opacity = 1.0
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0.0
                }
                // Clear text after fade-out
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if viewModel.currentCaptionText.isEmpty {
                        displayedText = ""
                    }
                }
            }
        }
        .onAppear {
            displayedText = viewModel.currentCaptionText
            if !displayedText.isEmpty {
                opacity = 1.0
            }
        }
    }
}
