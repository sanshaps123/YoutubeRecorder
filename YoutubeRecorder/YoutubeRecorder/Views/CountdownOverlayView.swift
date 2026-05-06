import SwiftUI

/// Full-screen countdown overlay (3 → 2 → 1 → GO) before recording starts
struct CountdownOverlayView: View {
    let countdownValue: Int

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Countdown number
            VStack(spacing: 16) {
                Text(countdownValue > 0 ? "\(countdownValue)" : "GO")
                    .font(.system(size: 160, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 5)
                    .scaleEffect(1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: countdownValue)

                Text(countdownValue > 0 ? "Recording starts in..." : "Recording!")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Circular progress ring
            Circle()
                .trim(from: 0, to: CGFloat(countdownValue) / 3.0)
                .stroke(
                    LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 260, height: 260)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: countdownValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
