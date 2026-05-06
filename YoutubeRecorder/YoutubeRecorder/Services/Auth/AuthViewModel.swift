import Foundation

/// ViewModel for the login/signup flow.
/// Wraps AuthManager and provides form state + validation for the UI.
@Observable @MainActor
final class AuthViewModel {

    // MARK: - Form State

    var email = ""
    var password = ""
    var confirmPassword = ""
    var isSignUpMode = false
    var isLoading = false
    var errorMessage: String?
    var showSuccessMessage = false

    // MARK: - Dependencies

    private let authManager = AuthManager.shared

    var isAuthenticated: Bool { authManager.isAuthenticated }
    var userEmail: String { authManager.userEmail }

    // MARK: - Validation

    private var isEmailValid: Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    private var isPasswordValid: Bool {
        password.count >= 6
    }

    private var doPasswordsMatch: Bool {
        !isSignUpMode || password == confirmPassword
    }

    var canSubmit: Bool {
        isEmailValid && isPasswordValid && doPasswordsMatch && !isLoading
    }

    /// Returns a validation hint for the current form state.
    var validationHint: String? {
        if !email.isEmpty && !isEmailValid {
            return "Enter a valid email address"
        }
        if !password.isEmpty && !isPasswordValid {
            return "Password must be at least 6 characters"
        }
        if isSignUpMode && !confirmPassword.isEmpty && !doPasswordsMatch {
            return "Passwords don't match"
        }
        return nil
    }

    // MARK: - Actions

    /// Submit the form — sign in or sign up based on current mode.
    func submit() async {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil

        do {
            if isSignUpMode {
                try await authManager.signUp(email: email, password: password)
            } else {
                try await authManager.signIn(email: email, password: password)
            }
            showSuccessMessage = true
            clearForm()
        } catch {
            errorMessage = authManager.errorMessage ?? error.localizedDescription
        }

        isLoading = false
    }

    /// Initiate Google Sign-In.
    func googleSignIn() async {
        isLoading = true
        errorMessage = nil

        do {
            try await authManager.signInWithGoogle()
            showSuccessMessage = true
            clearForm()
        } catch {
            errorMessage = authManager.errorMessage ?? error.localizedDescription
        }

        isLoading = false
    }

    /// Sign out the current user.
    func logout() {
        do {
            try authManager.signOut()
            clearForm()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle between sign-in and sign-up modes.
    func toggleMode() {
        isSignUpMode.toggle()
        errorMessage = nil
        confirmPassword = ""
    }

    /// Sign in as a guest — bypasses Firebase, all features available.
    func guestSignIn() {
        authManager.signInAsGuest()
        showSuccessMessage = true
        clearForm()
    }

    // MARK: - Private

    private func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
        errorMessage = nil
    }
}
