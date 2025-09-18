

// ContentView.swift
// Path: ClaudeHustlerFirebase/Views/ContentView.swift

import SwiftUI

struct ContentView: View {
    @StateObject private var firebase = FirebaseService.shared
    @StateObject private var authService = AuthenticationService.shared
    
    var body: some View {
        Group {
            switch authService.authState {
            case .unknown:
                // Loading state
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                
            case .authenticated:
                MainTabView()
                    .transition(.opacity)
                
            case .unauthenticated, .authenticating:
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: authService.authState)
    }
}

#Preview {
    ContentView()
}
