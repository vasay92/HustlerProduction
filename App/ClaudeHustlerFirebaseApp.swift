import SwiftUI
import FirebaseCore
import SDWebImageSwiftUI

@main
struct ClaudeHustlerFirebaseApp: App {
    init() {
        FirebaseApp.configure()
        
        // Configure image cache (corrected version)
        SDImageCache.shared.config.maxMemoryCost = 50 * 1024 * 1024  // 50MB memory
        SDImageCache.shared.config.maxDiskSize = 200 * 1024 * 1024   // 200MB disk
        SDImageCache.shared.config.maxDiskAge = 7 * 24 * 60 * 60      // 1 week
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
