// GuestProfileView.swift
// Path: ClaudeHustlerFirebase/Views/Profile/GuestProfileView.swift
// Placeholder view shown in Profile tab when user is not logged in

import SwiftUI

struct GuestProfileView: View {
    @State private var showingAuth = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                // Icon
                Image(systemName: "person.circle")
                    .font(.system(size: 80))
                    .foregroundColor(.gray)
                
                // Title
                Text("Create Your Profile")
                    .font(.title2)
                    .fontWeight(.bold)
                
                // Description
                Text("Sign up to create your profile, post services, and connect with others")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // Features Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    FeatureCard(icon: "briefcase.fill", title: "Post Services", color: .blue)
                    FeatureCard(icon: "star.fill", title: "Get Reviews", color: .orange)
                    FeatureCard(icon: "photo.fill", title: "Share Work", color: .green)
                    FeatureCard(icon: "person.2.fill", title: "Build Network", color: .purple)
                }
                .padding(.horizontal, 30)
                
                // Sign Up Button
                Button(action: { showingAuth = true }) {
                    Text("Sign Up")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 30)
                
                // Sign In Link
                Button(action: { showingAuth = true }) {
                    Text("Already have an account? Sign In")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                Spacer()
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showingAuth) {
                LoginView()
            }
        }
    }
}

// MARK: - Feature Card
struct FeatureCard: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    GuestProfileView()
}
