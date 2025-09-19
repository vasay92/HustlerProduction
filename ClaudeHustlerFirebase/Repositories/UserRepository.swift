

// UserRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/UserRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

// MARK: - User Repository
@MainActor
final class UserRepository: RepositoryProtocol {
    typealias Model = User
    
    // Singleton
    static let shared = UserRepository()
    
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    private let cacheMaxAge: TimeInterval = 600 // 10 minutes for user profiles
    
    private init() {}
    
    // MARK: - Fetch Users with Pagination (for user lists)
    func fetch(limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [User], lastDoc: DocumentSnapshot?) {
        var query = db.collection("users")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let users = snapshot.documents.compactMap { doc -> User? in
            var user = try? doc.data(as: User.self)
            user?.id = doc.documentID
            return user
        }
        
        return (users, snapshot.documents.last)
    }
    
    // MARK: - Fetch Single User
    func fetchById(_ id: String) async throws -> User? {
        let cacheKey = "user_\(id)"
        
        // Check cache first
        if !cache.isExpired(for: cacheKey, maxAge: cacheMaxAge),
           let cachedUser: User = cache.retrieve(User.self, for: cacheKey) {
            return cachedUser
        }
        
        // Fetch from Firestore
        let document = try await db.collection("users").document(id).getDocument()
        
        guard document.exists else { return nil }
        
        var user = try document.data(as: User.self)
        user.id = document.documentID
        
        // Cache the user
        cache.store(user, for: cacheKey)
        
        return user
    }
    
    // MARK: - Create User
    func create(_ user: User) async throws -> String {
        // Create user data dictionary
        let userData: [String: Any] = [
            "email": user.email,
            "name": user.name,
            "profileImageURL": user.profileImageURL ?? "",
            "bio": user.bio,
            "isServiceProvider": user.isServiceProvider,
            "location": user.location,
            "rating": user.rating,
            "reviewCount": user.reviewCount,
            "following": user.following,
            "followers": user.followers,
            "createdAt": Date(),
            "lastActive": Date()
        ]
        
        let docRef = try await db.collection("users").addDocument(data: userData)
        
        // Clear cache
        cache.remove(for: "all_users")
        
        return docRef.documentID
    }
    
    // MARK: - Update User Profile
    func update(_ user: User) async throws {
        guard let userId = user.id ?? Auth.auth().currentUser?.uid else {
            throw NSError(domain: "UserRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "User ID is required"])
        }
        
        guard userId == Auth.auth().currentUser?.uid else {
            throw NSError(domain: "UserRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Can only update own profile"])
        }
        
        // Prepare update data (only updatable fields)
        let updates: [String: Any] = [
            "name": user.name,
            "bio": user.bio ?? "",
            "location": user.location ?? "",
            "isServiceProvider": user.isServiceProvider,
//            "skills": user.skills ?? [],
//            "availability": user.availability ?? "",
            "updatedAt": Date()
        ]
        
        try await db.collection("users").document(userId).updateData(updates)
        
        // Update cache
        cache.store(user, for: "user_\(userId)")
    }
    
    // MARK: - Delete User (Soft Delete)
    func delete(_ id: String) async throws {
        guard id == Auth.auth().currentUser?.uid else {
            throw NSError(domain: "UserRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Can only delete own account"])
        }
        
        // Soft delete - mark as deleted but keep data
        try await db.collection("users").document(id).updateData([
            "isDeleted": true,
            "deletedAt": Date()
        ])
        
        // Clear cache
        cache.remove(for: "user_\(id)")
    }
    
    // MARK: - Update Profile Image
    func updateProfileImage(_ imageURL: String, for userId: String) async throws {
        guard userId == Auth.auth().currentUser?.uid else {
            throw NSError(domain: "UserRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Can only update own profile image"])
        }
        
        let batch = db.batch()
        
        // Update user profile
        let userRef = db.collection("users").document(userId)
        batch.updateData([
            "profileImageURL": imageURL,
            "updatedAt": Date()
        ], forDocument: userRef)
        
        // Update all user's posts
        let posts = try await db.collection("posts")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        for post in posts.documents {
            batch.updateData([
                "userProfileImage": imageURL
            ], forDocument: post.reference)
        }
        
        // Update all user's reels
        let reels = try await db.collection("reels")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        for reel in reels.documents {
            batch.updateData([
                "userProfileImage": imageURL
            ], forDocument: reel.reference)
        }
        
        // Commit batch
        try await batch.commit()
        
        // Clear cache
        cache.remove(for: "user_\(userId)")
    }
    
    // MARK: - Follow/Unfollow Operations
    
    func followUser(_ targetUserId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "UserRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        guard currentUserId != targetUserId else {
            throw NSError(domain: "UserRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot follow yourself"])
        }
        
        let batch = db.batch()
        
        // Add to current user's following
        let currentUserRef = db.collection("users").document(currentUserId)
        batch.updateData([
            "following": FieldValue.arrayUnion([targetUserId])
        ], forDocument: currentUserRef)
        
        // Add to target user's followers
        let targetUserRef = db.collection("users").document(targetUserId)
        batch.updateData([
            "followers": FieldValue.arrayUnion([currentUserId])
        ], forDocument: targetUserRef)
        
        // Create follow activity (optional)
        let activityRef = db.collection("activities").document()
        let activityData: [String: Any] = [
            "type": "follow",
            "fromUserId": currentUserId,
            "toUserId": targetUserId,
            "timestamp": Date()
        ]
        batch.setData(activityData, forDocument: activityRef)
        
        try await batch.commit()
        
        // Clear cache
        cache.remove(for: "user_\(currentUserId)")
        cache.remove(for: "user_\(targetUserId)")
    }
    
    func unfollowUser(_ targetUserId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "UserRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let batch = db.batch()
        
        // Remove from current user's following
        let currentUserRef = db.collection("users").document(currentUserId)
        batch.updateData([
            "following": FieldValue.arrayRemove([targetUserId])
        ], forDocument: currentUserRef)
        
        // Remove from target user's followers
        let targetUserRef = db.collection("users").document(targetUserId)
        batch.updateData([
            "followers": FieldValue.arrayRemove([currentUserId])
        ], forDocument: targetUserRef)
        
        try await batch.commit()
        
        // Clear cache
        cache.remove(for: "user_\(currentUserId)")
        cache.remove(for: "user_\(targetUserId)")
    }
    
    // MARK: - Fetch Followers/Following
    
    func fetchFollowers(for userId: String, limit: Int = 50) async throws -> [User] {
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let followerIds = userDoc.data()?["followers"] as? [String] else {
            return []
        }
        
        guard !followerIds.isEmpty else { return [] }
        
        // Fetch in batches (Firestore 'in' query limit is 10)
        var allFollowers: [User] = []
        for batch in followerIds.chunked(into: 10) {
            let snapshot = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments()
            
            let users = snapshot.documents.compactMap { doc -> User? in
                var user = try? doc.data(as: User.self)
                user?.id = doc.documentID
                return user
            }
            allFollowers.append(contentsOf: users)
        }
        
        return Array(allFollowers.prefix(limit))
    }
    
    func fetchFollowing(for userId: String, limit: Int = 50) async throws -> [User] {
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let followingIds = userDoc.data()?["following"] as? [String] else {
            return []
        }
        
        guard !followingIds.isEmpty else { return [] }
        
        // Fetch in batches
        var allFollowing: [User] = []
        for batch in followingIds.chunked(into: 10) {
            let snapshot = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments()
            
            let users = snapshot.documents.compactMap { doc -> User? in
                var user = try? doc.data(as: User.self)
                user?.id = doc.documentID
                return user
            }
            allFollowing.append(contentsOf: users)
        }
        
        return Array(allFollowing.prefix(limit))
    }
    
    // MARK: - Search Users
    
    func searchUsers(query: String, limit: Int = 20) async throws -> [User] {
        // Note: For better search, use Algolia or ElasticSearch
        // This is a basic implementation
        
        let snapshot = try await db.collection("users")
            .order(by: "name")
            .limit(to: 100)
            .getDocuments()
        
        let users = snapshot.documents.compactMap { doc -> User? in
            var user = try? doc.data(as: User.self)
            user?.id = doc.documentID
            return user
        }.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.bio.localizedCaseInsensitiveContains(query) ||
            $0.location.localizedCaseInsensitiveContains(query)
        }
        
        return Array(users.prefix(limit))
    }
    
    // MARK: - Service Providers
    
    func fetchServiceProviders(category: ServiceCategory? = nil, limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [User], lastDoc: DocumentSnapshot?) {
        var query = db.collection("users")
            .whereField("isServiceProvider", isEqualTo: true)
            .order(by: "rating", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        var users = snapshot.documents.compactMap { doc -> User? in
            var user = try? doc.data(as: User.self)
            user?.id = doc.documentID
            return user
        }
        
        // Filter by skills if category provided
        if let category = category {
            users = users.filter { user in
      //          user.skills?.contains(category.displayName) ?? false
            }
        }
        
        return (users, snapshot.documents.last)
    }
    
    // MARK: - Update User Rating
    
    func updateUserRating(userId: String) async {
        do {
            // Get all reviews for this user
            let reviewsSnapshot = try await db.collection("reviews")
                .whereField("reviewedUserId", isEqualTo: userId)
                .getDocuments()
            
            guard !reviewsSnapshot.documents.isEmpty else { return }
            
            // Calculate average rating
            var totalRating = 0
            var reviewCount = 0
            
            for doc in reviewsSnapshot.documents {
                if let rating = doc.data()["rating"] as? Int {
                    totalRating += rating
                    reviewCount += 1
                }
            }
            
            let averageRating = reviewCount > 0 ? Double(totalRating) / Double(reviewCount) : 0.0
            
            // Update user document
            try await db.collection("users").document(userId).updateData([
                "rating": averageRating,
                "reviewCount": reviewCount,
                "updatedAt": Date()
            ])
            
            // Clear cache
            cache.remove(for: "user_\(userId)")
            
        } catch {
            print("Error updating user rating: \(error)")
        }
    }
}

// MARK: - Helper Extension for Array Chunking
private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
