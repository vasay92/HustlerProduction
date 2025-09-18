import SwiftUI
import Firebase
import SDWebImageSwiftUI

@main
struct ClaudeHustlerFirebaseApp: App {
    
    init() {
        FirebaseApp.configure()
        
        // Configure image cache
        SDWebImageManager.shared.cacheSerializer = SDImageCacheSerializer.default
        
        // Set memory cache to 50MB
        SDImageCache.shared.config.maxMemoryCost = 50 * 1024 * 1024
        
        // Set disk cache to 200MB
        SDImageCache.shared.config.maxDiskSize = 200 * 1024 * 1024
        
        // Cache images for 1 week
        SDImageCache.shared.config.maxDiskAge = 7 * 24 * 60 * 60
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
