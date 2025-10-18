// ContentView.swift - UPDATED FOR GUEST BROWSING
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
                
            case .authenticated, .unauthenticated:
                // CHANGED: Show MainTabView for BOTH authenticated and unauthenticated users
                // The MainTabView will handle showing guest views where needed
                MainTabView()
                    .transition(.opacity)
                
            case .authenticating:
                // Show loading during active authentication
                ProgressView("Authenticating...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            }
        }
        .animation(.easeInOut, value: authService.authState)
    }
}

#Preview {
    ContentView()
}
