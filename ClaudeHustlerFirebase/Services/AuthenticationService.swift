

// AuthenticationService.swift
// Path: ClaudeHustlerFirebase/Services/AuthenticationService.swift

import Foundation
import FirebaseAuth
import SwiftUI

// MARK: - Authentication State
enum AuthState: Equatable {
    case unknown
    case authenticated(userId: String)
    case unauthenticated
    case authenticating
    
    // Implement Equatable conformance
    static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown):
            return true
        case (.authenticated(let lhsUserId), .authenticated(let rhsUserId)):
            return lhsUserId == rhsUserId
        case (.unauthenticated, .unauthenticated):
            return true
        case (.authenticating, .authenticating):
            return true
        default:
            return false
        }
    }
}

// MARK: - Authentication Errors
enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword(reasons: [String])
    case invalidName(reason: String)
    case userNotFound
    case wrongPassword
    case emailAlreadyInUse
    case networkError
    case tooManyRequests
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address"
        case .weakPassword(let reasons):
            return reasons.joined(separator: "\n")
        case .invalidName(let reason):
            return reason
        case .userNotFound:
            return "No account found with this email address"
        case .wrongPassword:
            return "Incorrect password"
        case .emailAlreadyInUse:
            return "An account with this email already exists"
        case .networkError:
            return "Network connection error. Please try again"
        case .tooManyRequests:
            return "Too many attempts. Please wait a moment and try again"
        case .unknownError(let message):
            return message
        }
    }
}

// MARK: - Authentication Service
@MainActor
class AuthenticationService: ObservableObject {
    @Published var authState: AuthState = .unknown
    @Published var error: AuthError?
    @Published var isLoading = false
    
    private let firebase = FirebaseService.shared
    private var authListener: AuthStateDidChangeListenerHandle?
    
    // Singleton pattern
    static let shared = AuthenticationService()
    
    private init() {
        setupAuthListener()
    }
    
    deinit {
        if let listener = authListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    // MARK: - Setup
    private func setupAuthListener() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let userId = user?.uid {
                    self?.authState = .authenticated(userId: userId)
                } else {
                    self?.authState = .unauthenticated
                }
            }
        }
    }
    
    // MARK: - Sign In
    func signIn(email: String, password: String) async {
        // Reset error state
        error = nil
        
        // Check rate limiting
        guard SecurityService.rateLimiter.shouldAllowRequest(for: "signin_\(email)", limit: 5, window: 300) else {
            error = .tooManyRequests
            return
        }
        
        // Validate email
        guard SecurityService.validateEmail(email) else {
            error = .invalidEmail
            return
        }
        
        // Basic password check (just ensure it's not empty for sign in)
        guard !password.isEmpty else {
            error = .wrongPassword
            return
        }
        
        isLoading = true
        authState = .authenticating
        
        do {
            try await firebase.signIn(email: email, password: password)
            SecurityService.rateLimiter.resetLimit(for: "signin_\(email)")
        } catch {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Sign Up
    func signUp(email: String, password: String, name: String) async {
        // Reset error state
        error = nil
        
        // Check rate limiting
        guard SecurityService.rateLimiter.shouldAllowRequest(for: "signup_\(email)", limit: 3, window: 600) else {
            error = .tooManyRequests
            return
        }
        
        // Validate email
        guard SecurityService.validateEmail(email) else {
            error = .invalidEmail
            return
        }
        
        // Validate password
        let passwordValidation = SecurityService.validatePassword(password)
        guard passwordValidation.isValid else {
            error = .weakPassword(reasons: passwordValidation.errors)
            return
        }
        
        // Validate and sanitize name
        let nameValidation = SecurityService.validateName(name)
        guard nameValidation.isValid else {
            error = .invalidName(reason: nameValidation.error ?? "Invalid name")
            return
        }
        
        isLoading = true
        authState = .authenticating
        
        do {
            let sanitizedName = SecurityService.sanitizeInput(name)
            try await firebase.signUp(email: email, password: password, name: sanitizedName)
            SecurityService.rateLimiter.resetLimit(for: "signup_\(email)")
        } catch {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Sign Out
    func signOut() throws {
        // Clean up all Firebase listeners - calling method if it exists
        if firebase.responds(to: #selector(FirebaseService.removeAllListeners)) {
            firebase.performSelector(onMainThread: #selector(FirebaseService.removeAllListeners), with: nil, waitUntilDone: true)
        }
        
        // Clean up Firebase cached data
        firebase.cleanupOnSignOut()
        
        // Sign out from Firebase Auth - FIXED: Using firebase.signOut()
        try firebase.signOut()
        
        print("✅ User signed out and all listeners cleaned")
    }
    
    // MARK: - Password Reset
    func resetPassword(email: String) async {
        error = nil
        
        // Check rate limiting
        guard SecurityService.rateLimiter.shouldAllowRequest(for: "reset_\(email)", limit: 3, window: 3600) else {
            error = .tooManyRequests
            return
        }
        
        // Validate email
        guard SecurityService.validateEmail(email) else {
            error = .invalidEmail
            return
        }
        
        isLoading = true
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            // Success - password reset email sent
        } catch {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Error Handling
    private func handleAuthError(_ error: Error) {
        if let authError = error as NSError? {
            switch authError.code {
            case AuthErrorCode.invalidEmail.rawValue:
                self.error = .invalidEmail
            case AuthErrorCode.userNotFound.rawValue:
                self.error = .userNotFound
            case AuthErrorCode.wrongPassword.rawValue:
                self.error = .wrongPassword
            case AuthErrorCode.emailAlreadyInUse.rawValue:
                self.error = .emailAlreadyInUse
            case AuthErrorCode.networkError.rawValue:
                self.error = .networkError
            case AuthErrorCode.tooManyRequests.rawValue:
                self.error = .tooManyRequests
            default:
                self.error = .unknownError(authError.localizedDescription)
            }
        } else {
            self.error = .unknownError(error.localizedDescription)
        }
    }
}
