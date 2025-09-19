

// ReelRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/ReelRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

// MARK: - Reel Repository
@MainActor
final class ReelRepository: RepositoryProtocol {
    typealias Model = Reel
    
    // Singleton
    static let shared = ReelRepository()
    
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    private let storage = FirebaseService.shared
    private let cacheMaxAge: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    // MARK: - Fetch with Pagination
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
        
        let lastDoc = snapshot.documents.last
        
        // Cache first page
        if lastDocument == nil && !reels.isEmpty {
            cache.store(reels, for: "reels_page_1")
        }
        
        return (reels, lastDoc)
    }
    
    // MARK: - Fetch Single Reel
    func fetchById(_ id: String) async throws -> Reel? {
        let cacheKey = "reel_\(id)"
        
        // Check cache first
        if !cache.isExpired(for: cacheKey, maxAge: cacheMaxAge),
           let cachedReel: Reel = cache.retrieve(Reel.self, for: cacheKey) {
            return cachedReel
        }
        
        // Fetch from Firestore
        let document = try await db.collection("reels").document(id).getDocument()
        
        guard document.exists else { return nil }
        
        var reel = try document.data(as: Reel.self)
        reel.id = document.documentID
        
        // Update view count
        try await incrementViewCount(for: id)
        
        // Cache the reel
        cache.store(reel, for: cacheKey)
        
        return reel
    }
    
    // MARK: - Fetch by Category
    func fetchByCategory(_ category: ServiceCategory, limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [Reel], lastDoc: DocumentSnapshot?) {
        var query = db.collection("reels")
            .whereField("category", isEqualTo: category.rawValue)
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
    
    // MARK: - Fetch User's Reels
    func fetchUserReels(_ userId: String, limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [Reel], lastDoc: DocumentSnapshot?) {
        var query = db.collection("reels")
            .whereField("userId", isEqualTo: userId)
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
    
    // MARK: - Fetch Trending Reels
    func fetchTrending(limit: Int = 20) async throws -> [Reel] {
        // Get reels from last 7 days with most engagement
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        let snapshot = try await db.collection("reels")
            .whereField("createdAt", isGreaterThan: sevenDaysAgo)
            .order(by: "createdAt", descending: false)
            .limit(to: 100)
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
        
        return Array(reels.prefix(limit))
    }
    
    // MARK: - Create Reel
    func create(_ reel: Reel) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReelRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        var reelData = reel
        reelData.userId = userId
        reelData.createdAt = Date()
        reelData.likes = []
        reelData.comments = 0
        reelData.shares = 0
        reelData.views = 0
        
        let docRef = try await db.collection("reels").addDocument(from: reelData)
        
        // Clear cache
        cache.remove(for: "reels_page_1")
        
        return docRef.documentID
    }
    
    // MARK: - Update Reel
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
        
        // Update only allowed fields
        let updates: [String: Any] = [
            "title": reel.title,
            "description": reel.description,
            "hashtags": reel.hashtags,
            "updatedAt": Date()
        ]
        
        try await db.collection("reels").document(reelId).updateData(updates)
        
        // Update cache
        cache.store(reel, for: "reel_\(reelId)")
        cache.remove(for: "reels_page_1")
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
        
        // Delete reel
        try await db.collection("reels").document(id).delete()
        
        // Delete associated comments
        let comments = try await db.collection("comments")
            .whereField("reelId", isEqualTo: id)
            .getDocuments()
        
        for comment in comments.documents {
            try await comment.reference.delete()
        }
        
        // Delete associated likes
        let likes = try await db.collection("reelLikes")
            .whereField("reelId", isEqualTo: id)
            .getDocuments()
        
        for like in likes.documents {
            try await like.reference.delete()
        }
        
        // Clear cache
        cache.remove(for: "reel_\(id)")
        cache.remove(for: "reels_page_1")
    }
    
    // MARK: - Engagement Methods
    
    func likeReel(_ reelId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReelRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
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
    
    private func incrementViewCount(for reelId: String) async throws {
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
}
