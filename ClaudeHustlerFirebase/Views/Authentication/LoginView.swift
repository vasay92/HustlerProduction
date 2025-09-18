// LoginView.swift
// Path: ClaudeHustlerFirebase/Views/Authentication/LoginView.swift

import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var name = ""
    @State private var isSignUp = false
    @State private var showingPasswordReset = false
    @State private var showingErrorAlert = false
    
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Logo
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .padding(.top, 40)
                    
                    Text("Hustler")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    // Input fields
                    VStack(spacing: 15) {
                        // Name field (only for sign up)
                        if isSignUp {
                            TextField("Full Name", text: $name)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.words)
                                .disabled(authService.isLoading)
                        }
                        
                        TextField("Email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .disabled(authService.isLoading)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.init(rawValue: ""))
                            .disabled(authService.isLoading)
                        
                        // Confirm password (only for sign up)
                        if isSignUp {
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .textContentType(.init(rawValue: ""))
                                .disabled(authService.isLoading)
                            
                            // Password requirements hint
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Password must contain:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("• At least 8 characters")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("• Upper & lowercase letters")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("• At least one number")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("• At least one special character")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Error message
                    if let error = authService.error {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Sign In/Up Button
                    Button(action: { performAuth() }) {
                        if authService.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text(isSignUp ? "Sign Up" : "Sign In")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(authService.isLoading ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(authService.isLoading || !isFormValid)
                    .padding(.horizontal)
                    
                    // Additional options
                    VStack(spacing: 10) {
                        // Toggle between Sign In/Up
                        Button(action: {
                            withAnimation {
                                isSignUp.toggle()
                                authService.error = nil
                            }
                        }) {
                            Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                                .foregroundColor(.blue)
                        }
                        .disabled(authService.isLoading)
                        
                        // Forgot password (only for sign in)
                        if !isSignUp {
                            Button(action: { showingPasswordReset = true }) {
                                Text("Forgot Password?")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .disabled(authService.isLoading)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .alert("Reset Password", isPresented: $showingPasswordReset) {
                TextField("Email", text: $email)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                Button("Send Reset Email") {
                    Task {
                        await authService.resetPassword(email: email)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter your email address and we'll send you a password reset link.")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var isFormValid: Bool {
        if isSignUp {
            return !name.isEmpty &&
                   !email.isEmpty &&
                   !password.isEmpty &&
                   password == confirmPassword
        } else {
            return !email.isEmpty && !password.isEmpty
        }
    }
    
    private func performAuth() {
        Task {
            if isSignUp {
                if password != confirmPassword {
                    authService.error = AuthError.weakPassword(reasons: ["Passwords do not match"])
                    return
                }
                await authService.signUp(email: email, password: password, name: name)
            } else {
                await authService.signIn(email: email, password: password)
            }
        }
    }
}

#Preview {
    LoginView()
}
