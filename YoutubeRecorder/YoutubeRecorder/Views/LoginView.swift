import SwiftUI
import GoogleSignInSwift

/// Login / Sign-Up view displayed in an NSPanel.
/// Dark-themed to match the existing YoutubeRecorder aesthetic.
struct LoginView: View {
    @State private var viewModel = AuthViewModel()
    var onAuthenticated: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                    .shadow(color: .red.opacity(0.4), radius: 8)

                Text("YoutubeRecorder")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text(viewModel.isSignUpMode ? "Create your account" : "Sign in to continue")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            // Form
            VStack(spacing: 14) {
                // Email
                VStack(alignment: .leading, spacing: 4) {
                    Text("Email")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("you@example.com", text: $viewModel.email)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )
                        .textContentType(.emailAddress)
                }

                // Password
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    SecureField("At least 6 characters", text: $viewModel.password)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )
                        .textContentType(.password)
                }

                // Confirm Password (sign-up only)
                if viewModel.isSignUpMode {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confirm Password")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        SecureField("Re-enter password", text: $viewModel.confirmPassword)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                            .textContentType(.newPassword)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Validation hint
                if let hint = viewModel.validationHint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Error message
                if let error = viewModel.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(error)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.red.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 28)

            // Submit button
            VStack(spacing: 12) {
                Button {
                    Task { await viewModel.submit() }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(.circular)
                        }
                        Text(viewModel.isSignUpMode ? "Create Account" : "Sign In")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(viewModel.canSubmit ? .blue : .blue.opacity(0.3))
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSubmit)

                // Divider
                HStack {
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                    Text("or")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                }

                // Google Sign-In button
                Button {
                    Task { await viewModel.googleSignIn() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 14))
                        Text("Continue with Google")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Spacer()

            // Continue as Guest
            Button {
                viewModel.guestSignIn()
            } label: {
                Text("Continue as Guest")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)

            // Toggle sign-in / sign-up
            HStack(spacing: 4) {
                Text(viewModel.isSignUpMode ? "Already have an account?" : "Don't have an account?")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleMode()
                    }
                } label: {
                    Text(viewModel.isSignUpMode ? "Sign In" : "Sign Up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 20)
        }
        .frame(width: 380, height: viewModel.isSignUpMode ? 580 : 520)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.isAuthenticated) { _, isAuth in
            if isAuth {
                onAuthenticated?()
            }
        }
    }
}
