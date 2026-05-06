import SwiftUI
import StoreKit

/// Premium paywall screen — shows feature comparison, subscription options, and purchase flow.
/// Opened in an NSPanel from AppController.
struct PaywallView: View {
    @State private var viewModel = SubscriptionViewModel()
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: .purple.opacity(0.4), radius: 12)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }

                Text("Upgrade to Pro")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Text("Unlock unlimited recordings, caption export, and more.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Feature comparison
            VStack(spacing: 0) {
                featureRow("Recording Duration", free: "5 minutes", pro: "Unlimited", proHighlight: true)
                featureRow("Caption Export (.srt)", free: "—", pro: "✓", proHighlight: true)
                featureRow("4K Recording", free: "—", pro: "✓", proHighlight: true)
                featureRow("Virtual Backgrounds", free: "✓", pro: "✓", proHighlight: false)
                featureRow("System Audio Capture", free: "✓", pro: "✓", proHighlight: false)
                featureRow("Webcam Overlay", free: "✓", pro: "✓", proHighlight: false)
                featureRow("Priority Support", free: "—", pro: "✓", proHighlight: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.04))
            )
            .padding(.horizontal, 20)

            Spacer().frame(height: 20)

            // Subscription cards
            if viewModel.isPro {
                // Already subscribed
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're a Pro member!")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("All features are unlocked.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.green.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.green.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 10) {
                    // Monthly
                    if let monthly = viewModel.monthlyProduct {
                        subscriptionCard(
                            product: monthly,
                            label: "Monthly",
                            sublabel: "\(monthly.displayPrice)/month",
                            badge: nil
                        )
                    }

                    // Yearly
                    if let yearly = viewModel.yearlyProduct {
                        let badge = viewModel.yearlySavingsPercent.map { "Save \($0)%" }
                        subscriptionCard(
                            product: yearly,
                            label: "Yearly",
                            sublabel: "\(yearly.displayPrice)/year",
                            badge: badge
                        )
                    }

                    if viewModel.products.isEmpty && !viewModel.isLoading {
                        Text("Subscription products not available.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding(.horizontal, 20)
            }

            // Error message
            if let error = viewModel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.red)
                .padding(.top, 8)
                .padding(.horizontal, 20)
            }

            Spacer()

            // Footer
            VStack(spacing: 8) {
                if !viewModel.isPro {
                    Button("Restore Purchases") {
                        Task { await viewModel.restore() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                    .disabled(viewModel.isLoading)
                }

                HStack(spacing: 16) {
                    Link("Terms of Use", destination: URL(string: "https://example.com/terms")!)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)
        }
        .frame(width: 420, height: 620)
        .background(Color(red: 0.06, green: 0.07, blue: 0.09))
        .preferredColorScheme(.dark)
        .task {
            if viewModel.products.isEmpty {
                await viewModel.loadProducts()
            }
        }
        .alert("Welcome to Pro!", isPresented: $viewModel.showSuccessAlert) {
            Button("Continue") {
                onDismiss?()
            }
        } message: {
            Text("You now have access to unlimited recordings, caption export, and all Pro features.")
        }
    }

    // MARK: - Feature Row

    private func featureRow(_ feature: String, free: String, pro: String, proHighlight: Bool) -> some View {
        HStack {
            Text(feature)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(free)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .center)

            Text(pro)
                .font(.system(size: 12, weight: proHighlight ? .semibold : .regular))
                .foregroundStyle(proHighlight ? .cyan : .secondary)
                .frame(width: 80, alignment: .center)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    // MARK: - Subscription Card

    private func subscriptionCard(product: Product, label: String, sublabel: String, badge: String?) -> some View {
        Button {
            Task { await viewModel.purchase(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.purple, .blue],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                        }
                    }
                    Text(sublabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.isPurchasing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .progressViewStyle(.circular)
                } else {
                    Text("Subscribe")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isPurchasing || viewModel.isLoading)
    }
}
