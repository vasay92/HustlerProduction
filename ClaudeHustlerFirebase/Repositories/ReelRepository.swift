// ReelRepository.swift (FIXED VERSION)
// Path: ClaudeHustlerFirebase/Repositories/ReelRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ReelRepository: RepositoryProtocol {
    typealias Model = Reel
    
    // Singleton
    static let shared = ReelRepository()
    
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    private let notificationRepository = NotificationRepository.shared
    
    private init() {}
    
    // MARK: - Fetch Methods
    
    func fetch(limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [Reel], lastDoc: DocumentSnapshot?) {
        var query = db.collection("reels")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let reels = snapshot.documents.compactMap { doc -> Reel? in
            var reel = try? doc.data(as: Reel.self)
            reel?.id = doc.documentID
            return reel
        }
        
        return (reels, snapshot.documents.last)
    }
    
    func fetchById(_ id: String) async throws -> Reel? {
        // Check cache first - FIXED: Added type parameter
        if let cached: Reel = cache.retrieve(Reel.self, for: "reel_\(id)") {
            return cached
        }
        
        let document = try await db.collection("reels").document(id).getDocument()
        
        guard document.exists else { return nil }
        
        var reel = try document.data(as: Reel.self)
        reel.id = document.documentID
        
        // Cache the result
        cache.store(reel, for: "reel_\(id)")
        
        return reel
    }
    
    // MARK: - User Reels
    func fetchUserReels(_ userId: String, limit: Int = 20) async throws -> (items: [Reel], lastDoc: DocumentSnapshot?) {
        let snapshot = try await db.collection("reels")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let reels = snapshot.documents.compactMap { doc -> Reel? in
            var reel = try? doc.data(as: Reel.self)
            reel?.id = doc.documentID
            return reel
        }
        
        return (reels, snapshot.documents.last)
    }
    
    // MARK: - Trending Reels
    func fetchTrending(limit: Int = 10) async throws -> [Reel] {
        // Check cache first - FIXED: Added type parameter
        if let cached: [Reel] = cache.retrieve([Reel].self, for: "trending_reels") {
            return cached
        }
        
        // Fetch reels from the last 7 days
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        let snapshot = try await db.collection("reels")
            .whereField("createdAt", isGreaterThan: sevenDaysAgo)
            .getDocuments()
        
        var reels = snapshot.documents.compactMap { doc -> Reel? in
            var reel = try? doc.data(as: Reel.self)
            reel?.id = doc.documentID
            return reel
        }
        
        // Sort by engagement (likes + comments + shares)
        reels.sort { reel1, reel2 in
            let engagement1 = reel1.likes.count + reel1.comments + reel1.shares
            let engagement2 = reel2.likes.count + reel2.comments + reel2.shares
            return engagement1 > engagement2
        }
        
        let trending = Array(reels.prefix(limit))
        
        // Cache for 5 minutes - FIXED: Removed expiration parameter
        // Note: If you need expiration, implement it differently or update CacheService
        cache.store(trending, for: "trending_reels")
        
        return trending
    }
    
    // MARK: - Create Reel (FIXED)
    func create(_ reel: Reel) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReelRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Create reel data dictionary with CORRECT field names
        let reelData: [String: Any] = [
            "userId": userId,
            "userName": reel.userName ?? "",
            "userProfileImage": reel.userProfileImage ?? "",
            "videoURL": reel.videoURL,
            "thumbnailURL": reel.thumbnailURL ?? "",
            "title": reel.title,
            "description": reel.description,
            "tags": reel.tags,  //  FIXED: Using "tags" instead of "hashtags"
            "createdAt": Date(),
            "likes": [],
            "comments": 0,
            "shares": 0,
            "views": 0,
            "isPromoted": false
        ]
        
        let docRef = try await db.collection("reels").addDocument(data: reelData)
        
        // Clear cache
        cache.remove(for: "reels_page_1")
        cache.remove(for: "trending_reels")
        
        // Update tag analytics if you have TagRepository
        if !reel.tags.isEmpty {
            await TagRepository.shared.updateTagAnalytics(reel.tags, type: "reel")
        }
        
        return docRef.documentID
    }


    
    // MARK: - Update Reel (FIXED)
    func update(_ reel: Reel) async throws {
        guard let reelId = reel.id else {
            throw NSError(domain: "ReelRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Reel ID is required"])
        }
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReelRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify ownership
        let document = try await db.collection("reels").document(reelId).getDocument()
        guard let data = document.data(),
              data["userId"] as? String == currentUserId else {
            throw NSError(domain: "ReelRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to update this reel"])
        }
        
        // Update only allowed fields with CORRECT field names
        let updates: [String: Any] = [
            "title": reel.title,
            "description": reel.description,
            "tags": reel.tags,  //  FIXED: Using "tags" instead of "hashtags"
            "updatedAt": Date()
        ]
        
        try await db.collection("reels").document(reelId).updateData(updates)
        
        // Update cache
        cache.store(reel, for: "reel_\(reelId)")
        cache.remove(for: "reels_page_1")
        
        // Update tag analytics if you have TagRepository
        if !reel.tags.isEmpty {
            await TagRepository.shared.updateTagAnalytics(reel.tags, type: "reel")
        }
    }
    
    // MARK: - Delete Reel
    func delete(_ id: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReelRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify ownership
        let document = try await db.collection("reels").document(id).getDocument()
        guard let data = document.data(),
              data["userId"] as? String == currentUserId else {
            throw NSError(domain: "ReelRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to delete this reel"])
        }
        
        // Delete the reel
        try await db.collection("reels").document(id).delete()
        
        // Clear cache
        cache.remove(for: "reel_\(id)")
        cache.remove(for: "reels_page_1")
        cache.remove(for: "trending_reels")
    }
    
    // MARK: - Engagement Methods WITH NOTIFICATIONS
    
    // In ReelRepository.swift, replace the commented notification section with:

    func likeReel(_ reelId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReelRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Get reel to find owner
        let reelDoc = try await db.collection("reels").document(reelId).getDocument()
        guard let reelData = reelDoc.data(),
              let reelOwnerId = reelData["userId"] as? String else { return }
        
        let batch = db.batch()
        
        // Add to likes array
        let reelRef = db.collection("reels").document(reelId)
        batch.updateData([
            "likes": FieldValue.arrayUnion([userId])
        ], forDocument: reelRef)
        
        // Add to reelLikes collection for tracking
        let likeId = "\(userId)_\(reelId)"
        let likeRef = db.collection("reelLikes").document(likeId)
        let likeData: [String: Any] = [
            "reelId": reelId,
            "userId": userId,
            "likedAt": Date()
        ]
        batch.setData(likeData, forDocument: likeRef)
        
        try await batch.commit()
        
        // CREATE NOTIFICATION for reel owner - FIXED
        if userId != reelOwnerId {
            await notificationRepository.createReelNotification(
                for: reelOwnerId,
                reelId: reelId,
                type: .reelLike,
                fromUserId: userId
            )
        }
        
        // Clear cache for this reel
        cache.remove(for: "reel_\(reelId)")
    }
    
    func unlikeReel(_ reelId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReelRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let batch = db.batch()
        
        // Remove from likes array
        let reelRef = db.collection("reels").document(reelId)
        batch.updateData([
            "likes": FieldValue.arrayRemove([userId])
        ], forDocument: reelRef)
        
        // Remove from reelLikes collection
        let likeId = "\(userId)_\(reelId)"
        let likeRef = db.collection("reelLikes").document(likeId)
        batch.deleteDocument(likeRef)
        
        try await batch.commit()
        
        // Clear cache for this reel
        cache.remove(for: "reel_\(reelId)")
    }
    
    func incrementShareCount(for reelId: String) async throws {
        try await db.collection("reels").document(reelId).updateData([
            "shares": FieldValue.increment(Int64(1))
        ])
        
        cache.remove(for: "reel_\(reelId)")
    }
    
    func incrementViewCount(for reelId: String) async throws {
        try await db.collection("reels").document(reelId).updateData([
            "views": FieldValue.increment(Int64(1))
        ])
    }
    
    // MARK: - Search
    func search(query: String, limit: Int = 20) async throws -> [Reel] {
        // Note: For proper text search, consider using Algolia or ElasticSearch
        // This is a basic implementation
        
        let snapshot = try await db.collection("reels")
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()
        
        let reels = snapshot.documents.compactMap { doc -> Reel? in
            var reel = try? doc.data(as: Reel.self)
            reel?.id = doc.documentID
            return reel
        }.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query) ||
            $0.hashtags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        
        return Array(reels.prefix(limit))
    }
    
    // Add to ReelRepository.swift

    // MARK: - Search Reels
    func searchReels(query: String, limit: Int = 50) async throws -> [Reel] {
        let searchLower = query.lowercased()
        
        // First, try to get reels with matching tags
        let tagQuery = db.collection("reels")
            .whereField("tags", arrayContains: searchLower)
            .limit(to: limit)
        
        let tagSnapshot = try await tagQuery.getDocuments()
        
        var reels = tagSnapshot.documents.compactMap { doc -> Reel? in
            var reel = try? doc.data(as: Reel.self)
            reel?.id = doc.documentID
            return reel
        }
        
        // If not enough results, search in all reels
        if reels.count < 10 {
            let allReelsSnapshot = try await db.collection("reels")
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()
            
            let additionalReels = allReelsSnapshot.documents.compactMap { doc -> Reel? in
                var reel = try? doc.data(as: Reel.self)
                reel?.id = doc.documentID
                
                // Check if title or description contains search query
                if let reel = reel {
                    let matches = reel.title.lowercased().contains(searchLower) ||
                                 reel.description.lowercased().contains(searchLower) ||
                                 reel.tags.contains { $0.lowercased().contains(searchLower) }
                    
                    return matches && !reels.contains(where: { $0.id == reel.id }) ? reel : nil
                }
                
                return nil
            }
            
            reels.append(contentsOf: additionalReels)
        }
        
        return Array(reels.prefix(limit))
    }
}
