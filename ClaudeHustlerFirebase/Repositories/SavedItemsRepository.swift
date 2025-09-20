// SavedItemsRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/SavedItemsRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class SavedItemsRepository {
    // Singleton
    static let shared = SavedItemsRepository()
    
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    
    private init() {}
    
    // MARK: - Save/Unsave Items
    
    func saveItem(itemId: String, type: SavedItem.SavedItemType) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "SavedItemsRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let savedItem = SavedItem(
            userId: userId,
            itemId: itemId,
            itemType: type
        )
        
        // Use composite ID to prevent duplicates
        let docId = "\(userId)_\(itemId)"
        try await db.collection("savedItems").document(docId).setData(from: savedItem)
        
        // Clear cache
        cache.remove(for: "saved_\(type.rawValue)_\(userId)")
    }
    
    func unsaveItem(itemId: String, type: SavedItem.SavedItemType) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let docId = "\(userId)_\(itemId)"
        try await db.collection("savedItems").document(docId).delete()
        
        // Clear cache
        cache.remove(for: "saved_\(type.rawValue)_\(userId)")
    }
    
    func isItemSaved(itemId: String, type: SavedItem.SavedItemType) async -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else { return false }
        
        let docId = "\(userId)_\(itemId)"
        
        do {
            let doc = try await db.collection("savedItems").document(docId).getDocument()
            return doc.exists
        } catch {
            print("Error checking saved status: \(error)")
            return false
        }
    }
    
    func toggleSave(itemId: String, type: SavedItem.SavedItemType) async throws -> Bool {
        let isSaved = await isItemSaved(itemId: itemId, type: type)
        
        if isSaved {
            try await unsaveItem(itemId: itemId, type: type)
            return false
        } else {
            try await saveItem(itemId: itemId, type: type)
            return true
        }
    }
    
    // MARK: - Fetch Saved Items
    
    func fetchSavedReels() async throws -> [Reel] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        
        // Check cache first...
        
        let savedItems = try await db.collection("savedItems")
            .whereField("userId", isEqualTo: userId)
            .whereField("itemType", isEqualTo: SavedItem.SavedItemType.reel.rawValue)
            .order(by: "savedAt", descending: true)
            .getDocuments()
        
        var reels: [Reel] = []
        var seenIds = Set<String>() // Track unique IDs
        
        for item in savedItems.documents {
            let data = item.data()
            if let itemId = data["itemId"] as? String,
               !seenIds.contains(itemId) { // Check for duplicates
                seenIds.insert(itemId)
                
                let reelDoc = try await db.collection("reels").document(itemId).getDocument()
                if var reel = try? reelDoc.data(as: Reel.self) {
                    reel.id = reelDoc.documentID
                    reels.append(reel)
                }
            }
        }
        
        // Cache results
        cache.store(reels, for: "saved_reels_\(userId)")
        
        return reels
    }
    
    func fetchSavedPosts() async throws -> [ServicePost] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        
        // Check cache
        if let cached: [ServicePost] = cache.retrieve([ServicePost].self, for: "saved_posts_\(userId)"),
           !cache.isExpired(for: "saved_posts_\(userId)", maxAge: 600) {
            return cached
        }
        
        let savedItems = try await db.collection("savedItems")
            .whereField("userId", isEqualTo: userId)
            .whereField("itemType", isEqualTo: SavedItem.SavedItemType.post.rawValue)
            .order(by: "savedAt", descending: true)
            .getDocuments()
        
        var posts: [ServicePost] = []
        
        for item in savedItems.documents {
            let data = item.data()
            if let itemId = data["itemId"] as? String {
                let postDoc = try await db.collection("posts").document(itemId).getDocument()
                if var post = try? postDoc.data(as: ServicePost.self) {
                    post.id = postDoc.documentID
                    posts.append(post)
                }
            }
        }
        
        // Cache results
        cache.store(posts, for: "saved_posts_\(userId)")
        
        return posts
    }
}
