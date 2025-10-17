// AuthenticationPromptView.swift
// Path: ClaudeHustlerFirebase/Views/Authentication/AuthenticationPromptView.swift
// A reusable prompt that appears when non-registered users try to interact

import SwiftUI

struct AuthenticationPromptView: View {
    @Environment(\.dismiss) var dismiss
    let action: String  // The action they were trying to perform
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                // Logo
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                
                // Title
                Text("Sign Up to \(action)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                // Benefits
                VStack(alignment: .leading, spacing: 12) {
                    Text("Join Hustler to:")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    BenefitRow(icon: "briefcase.fill", text: "Post and find services")
                    BenefitRow(icon: "person.2.fill", text: "Connect with service providers")
                    BenefitRow(icon: "heart.fill", text: "Save your favorite posts")
                    BenefitRow(icon: "message.fill", text: "Send messages and chat")
                    BenefitRow(icon: "star.fill", text: "Leave and read reviews")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Action Buttons
                VStack(spacing: 12) {
                    NavigationLink(destination: LoginView()) {
                        Text("Sign Up")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    NavigationLink(destination: LoginView()) {
                        Text("Sign In")
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                // Continue Browsing
                Button(action: { dismiss() }) {
                    Text("Continue Browsing")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 20)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
}

// MARK: - Benefit Row
struct BenefitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

#Preview {
    AuthenticationPromptView(action: "Like Posts")
}
