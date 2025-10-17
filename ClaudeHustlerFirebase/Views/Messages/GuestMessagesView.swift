// GuestMessagesView.swift
// Path: ClaudeHustlerFirebase/Views/Messages/GuestMessagesView.swift
// Placeholder view shown in Messages tab when user is not logged in

import SwiftUI

struct GuestMessagesView: View {
    @State private var showingAuth = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                // Icon
                Image(systemName: "message.circle")
                    .font(.system(size: 80))
                    .foregroundColor(.gray)
                
                // Title
                Text("Sign Up to Message")
                    .font(.title2)
                    .fontWeight(.bold)
                
                // Description
                Text("Create an account to send messages and chat with service providers")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // Benefits
                VStack(alignment: .leading, spacing: 16) {
                    MessageBenefitRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Direct Messaging",
                        description: "Chat with service providers instantly"
                    )
                    
                    MessageBenefitRow(
                        icon: "photo.fill",
                        title: "Share Media",
                        description: "Send photos, videos, and files"
                    )
                    
                    MessageBenefitRow(
                        icon: "bell.fill",
                        title: "Get Notified",
                        description: "Never miss a message with notifications"
                    )
                }
                .padding(.horizontal, 30)
                
                // Sign Up Button
                Button(action: { showingAuth = true }) {
                    Text("Sign Up to Start Messaging")
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
            .navigationTitle("Messages")
            .sheet(isPresented: $showingAuth) {
                LoginView()
            }
        }
    }
}

// MARK: - Message Benefit Row
struct MessageBenefitRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    GuestMessagesView()
}
