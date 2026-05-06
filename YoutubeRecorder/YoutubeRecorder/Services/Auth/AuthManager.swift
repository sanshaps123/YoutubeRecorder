import Foundation
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
import AppKit

/// Singleton authentication manager wrapping Firebase Auth.
/// Supports Email/Password, Google Sign-In, and a dev bypass mode on macOS.
@Observable @MainActor
final class AuthManager {

    static let shared = AuthManager()

    // MARK: - Published State

    var currentUser: User?
    var isLoading = false
    var errorMessage: String?

    /// Dev bypass — when true, the user is "authenticated" without Firebase.
    /// Set to false once your Firebase project is fully configured.
    private(set) var isDevBypass = false

    /// True if user is authenticated (either via Firebase or dev bypass).
    var isAuthenticated: Bool {
        isDevBypass || currentUser != nil
    }

    // MARK: - Private

    nonisolated(unsafe) private var authStateHandle: AuthStateDidChangeListenerHandle?

    private init() {
        // Use default Keychain access group — required for macOS without Keychain Sharing entitlement
        do {
            try Auth.auth().useUserAccessGroup(nil)
        } catch {
            print("[Auth] Keychain access group setup failed: \(error.localizedDescription)")
        }
        addAuthStateListener()
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Auth State Listener

    /// Listens for Firebase auth state changes (login, logout, token refresh).
    /// Firebase persists sessions via Keychain automatically.
    private func addAuthStateListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
            }
        }
    }

    // MARK: - Dev Bypass (Guest Mode)

    /// Sign in as a local guest — bypasses Firebase entirely.
    /// All features work; auth-gated UI simply sees isAuthenticated = true.
    func signInAsGuest() {
        isDevBypass = true
        currentUser = nil
        errorMessage = nil
        print("[Auth] Signed in as guest (dev bypass).")
    }

    // MARK: - Email / Password

    /// Sign in with email and password.
    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            currentUser = result.user
        } catch {
            errorMessage = Self.friendlyError(error)
            throw error
        }
    }

    /// Create a new account with email and password.
    func signUp(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            currentUser = result.user
        } catch {
            errorMessage = Self.friendlyError(error)
            throw error
        }
    }

    // MARK: - Google Sign-In

    /// Initiate Google Sign-In using the system browser.
    func signInWithGoogle() async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Configure GIDSignIn with the Firebase client ID
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                throw AuthError.missingToken
            }
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

            // Get the presenting window for the Google Sign-In flow
            guard let window = NSApp.keyWindow ?? NSApp.windows.first else {
                throw AuthError.noWindow
            }

            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
            let user = result.user

            guard let idToken = user.idToken?.tokenString else {
                throw AuthError.missingToken
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )

            let authResult = try await Auth.auth().signIn(with: credential)
            currentUser = authResult.user
        } catch {
            if (error as NSError).code == GIDSignInError.canceled.rawValue {
                // User cancelled — not an error
                return
            }
            errorMessage = Self.friendlyError(error)
            throw error
        }
    }

    // MARK: - Sign Out

    func signOut() throws {
        if isDevBypass {
            isDevBypass = false
            currentUser = nil
            errorMessage = nil
            print("[Auth] Guest signed out.")
            return
        }

        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            currentUser = nil
            errorMessage = nil
        } catch {
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
            throw error
        }
    }

    // MARK: - Token Refresh

    /// Silently refresh the Firebase ID token if user is already signed in.
    /// Called on app launch to ensure the session is still valid.
    func refreshTokenIfNeeded() async {
        // No refresh needed for guest mode
        if isDevBypass { return }

        guard let user = Auth.auth().currentUser else { return }
        do {
            _ = try await user.getIDTokenResult(forcingRefresh: false)
            self.currentUser = user
        } catch {
            print("[Auth] Token refresh failed: \(error.localizedDescription)")
            // Session expired — user will need to re-authenticate
            try? signOut()
        }
    }

    // MARK: - User Info Helpers

    var userEmail: String {
        if isDevBypass { return "guest@youtuberecorder.local" }
        return currentUser?.email ?? "Unknown"
    }

    var userDisplayName: String {
        if isDevBypass { return "Guest User" }
        return currentUser?.displayName ?? currentUser?.email ?? "User"
    }

    // MARK: - Error Helpers

    enum AuthError: LocalizedError {
        case noWindow
        case missingToken

        var errorDescription: String? {
            switch self {
            case .noWindow:     return "No window available for Google Sign-In."
            case .missingToken: return "Failed to obtain Google ID token."
            }
        }
    }

    /// Maps Firebase/Google errors to user-friendly messages.
    private static func friendlyError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case AuthErrorCode.wrongPassword.rawValue:
            return "Incorrect password. Please try again."
        case AuthErrorCode.invalidEmail.rawValue:
            return "Invalid email address format."
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return "An account with this email already exists."
        case AuthErrorCode.weakPassword.rawValue:
            return "Password must be at least 6 characters."
        case AuthErrorCode.userNotFound.rawValue:
            return "No account found with this email."
        case AuthErrorCode.networkError.rawValue:
            return "Network error. Check your connection."
        case AuthErrorCode.tooManyRequests.rawValue:
            return "Too many attempts. Please wait and try again."
        default:
            return error.localizedDescription
        }
    }
}
