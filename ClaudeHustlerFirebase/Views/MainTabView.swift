// MainTabView.swift - UPDATED WITH GUEST BROWSING
// Path: ClaudeHustlerFirebase/Views/MainTabView.swift

import SwiftUI
import PhotosUI

// MARK: - Enums
enum CameraMode {
    case status, reel
}

enum ActiveSheet: Identifiable {
    case serviceForm
    case camera(mode: CameraMode)
    
    var id: String {
        switch self {
        case .serviceForm:
            return "serviceForm"
        case .camera(let mode):
            return "camera_\(mode == .status ? "status" : "reel")"
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @StateObject private var firebase = FirebaseService.shared
    @State private var selectedTab = 0
    @State private var showingPostOptions = false
    @State private var previousTab = 0
    @State private var activeSheet: ActiveSheet?
    @State private var pendingSheet: ActiveSheet?
    @StateObject private var notificationsViewModel = NotificationsViewModel()
    @State private var showingAuthPrompt = false
    @State private var authPromptAction = ""
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Home Tab
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            // Services Tab
            ServicesView()
                .tabItem {
                    Label("Services", systemImage: "briefcase.fill")
                }
                .tag(1)
            
            // Post Tab (Middle) - This doesn't show a view, just triggers the sheet
            Color.clear
                .tabItem {
                    Label("Post", systemImage: "plus.square.fill")
                }
                .tag(2)
            
            // Reels Tab
            ReelsView()
                .tabItem {
                    Label("Reels", systemImage: "play.rectangle.fill")
                }
                .tag(3)
            
            // Profile Tab - UPDATED: Show GuestProfileView if not logged in
            NavigationView {
                if firebase.isAuthenticated {
                    ProfileView()
                } else {
                    GuestProfileView()
                }
            }
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
            .tag(4)
        }
        .accentColor(.blue)
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 2 {
                // UPDATED: Check authentication before showing create options
                if !firebase.isAuthenticated {
                    authPromptAction = "Create Content"
                    showingAuthPrompt = true
                    selectedTab = previousTab
                } else {
                    // Post tab was selected - show options and revert to previous tab
                    showingPostOptions = true
                    selectedTab = previousTab
                }
            } else {
                // Normal tab selection - store as previous tab
                previousTab = newValue
            }
        }
        .sheet(isPresented: $showingPostOptions, onDismiss: {
            // When sheet dismisses, show the pending sheet if any
            if let pending = pendingSheet {
                activeSheet = pending
                pendingSheet = nil
            }
        }) {
            PostOptionsSheet(pendingSheet: $pendingSheet)
        }
        .fullScreenCover(item: $activeSheet) { sheet in
            switch sheet {
            case .serviceForm:
                ServiceFormView()
            case .camera(let mode):
                CameraView(mode: mode)
            }
        }
        // ADDED: Auth prompt sheet
        .sheet(isPresented: $showingAuthPrompt) {
            AuthenticationPromptView(action: authPromptAction)
        }
    }
}

// MARK: - Post Options Sheet
struct PostOptionsSheet: View {
    @Binding var pendingSheet: ActiveSheet?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Handle bar
                Capsule()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                
                Text("Create")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.vertical, 20)
                
                VStack(spacing: 16) {
                    // Services Option
                    PostOptionButton(
                        icon: "briefcase.fill",
                        title: "Services",
                        subtitle: "Offer or request a service",
                        color: .blue,
                        action: {
                            pendingSheet = .serviceForm
                            dismiss()
                        }
                    )
                    
                    // Status Option
                    PostOptionButton(
                        icon: "circle.dashed",
                        title: "Status",
                        subtitle: "Share what you're working on (24hr)",
                        color: .orange,
                        action: {
                            pendingSheet = .camera(mode: .status)
                            dismiss()
                        }
                    )
                    
                    // Reel Option
                    PostOptionButton(
                        icon: "play.rectangle.fill",
                        title: "Reel",
                        subtitle: "Create a video showcasing your skills",
                        color: .purple,
                        action: {
                            pendingSheet = .camera(mode: .reel)
                            dismiss()
                        }
                    )
                }
                .padding()
                
                Spacer()
                
                // Cancel Button
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Post Option Button
struct PostOptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}
