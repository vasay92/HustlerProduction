// UserRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/UserRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - User Repository
class UserRepository: ObservableObject {
    static let shared = UserRepository()
    private let db = Firestore.firestore()
    private let cache = CacheService.shared  // FIXED: Use CacheService instead of CacheManager
    
    private init() {}
    
    // MARK: - Fetch Users
    
    func fetch(limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [User], lastDoc: DocumentSnapshot?) {
        var query: Query = db.collection("users")
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
    
    // MARK: - Fetch User by ID
    func fetchById(_ id: String) async throws -> User? {
        // Check cache first
        if let cachedUser: User = cache.retrieve(User.self, for: "user_\(id)") {
            if !cache.isExpired(for: "user_\(id)", maxAge: 300) { // 5 minutes
                return cachedUser
            }
        }
        
        let document = try await db.collection("users").document(id).getDocument()
        
        guard document.exists else { return nil }
        
        var user = try document.data(as: User.self)
        user.id = document.documentID
        
        // Cache the user
        cache.store(user, for: "user_\(id)")
        
        return user
    }
    
    // MARK: - Create User
    func create(_ user: User) async throws -> String {
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
            "bio": user.bio,
            "location": user.location,
            "isServiceProvider": user.isServiceProvider,
            "profileImageURL": user.profileImageURL ?? "",
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
    
    // MARK: - COMPLETE PROFILE IMAGE UPDATE METHOD
    func updateProfileImage(_ imageURL: String, for userId: String) async throws {
        guard userId == Auth.auth().currentUser?.uid else {
            throw NSError(domain: "UserRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Can only update own profile image"])
        }
        
        let batch = db.batch()
        var updateCount = 0
        let maxBatchSize = 450
        
        // 1. Update user profile
        let userRef = db.collection("users").document(userId)
        batch.updateData([
            "profileImageURL": imageURL,
            "updatedAt": Date()
        ], forDocument: userRef)
        updateCount += 1
        
        // 2. Update posts - IMAGE ONLY
        let posts = try await db.collection("posts")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        for post in posts.documents {
            if updateCount >= maxBatchSize { break }
            batch.updateData([
                "userProfileImage": imageURL
            ], forDocument: post.reference)
            updateCount += 1
        }
        
        // 3. Update reels - IMAGE ONLY
        let reels = try await db.collection("reels")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        for reel in reels.documents {
            if updateCount >= maxBatchSize { break }
            batch.updateData([
                "userProfileImage": imageURL
            ], forDocument: reel.reference)
            updateCount += 1
        }
        
        // 4. Update comments - IMAGE ONLY
        let comments = try await db.collection("comments")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        for comment in comments.documents {
            if updateCount >= maxBatchSize { break }
            batch.updateData([
                "userProfileImage": imageURL
            ], forDocument: comment.reference)
            updateCount += 1
        }
        
        // 5. Update statuses - IMAGE ONLY
        let statuses = try await db.collection("statuses")
            .whereField("userId", isEqualTo: userId)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        
        for status in statuses.documents {
            if updateCount >= maxBatchSize { break }
            batch.updateData([
                "userProfileImage": imageURL
            ], forDocument: status.reference)
            updateCount += 1
        }
        
        // 6. Update reviews - IMAGE ONLY
        let reviews = try await db.collection("reviews")
            .whereField("reviewerId", isEqualTo: userId)
            .getDocuments()
        
        for review in reviews.documents {
            if updateCount >= maxBatchSize { break }
            batch.updateData([
                "reviewerProfileImage": imageURL
            ], forDocument: review.reference)
            updateCount += 1
        }
        
        // 7. Update conversations - IMAGE ONLY
        let conversations = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .getDocuments()
        
        for conversation in conversations.documents {
            if updateCount >= maxBatchSize { break }
            batch.updateData([
                "participantImages.\(userId)": imageURL
            ], forDocument: conversation.reference)
            updateCount += 1
        }
        
        // 8. Update messages - IMAGE ONLY (if field exists)
        let messages = try await db.collection("messages")
            .whereField("senderId", isEqualTo: userId)
            .limit(to: 50)
            .order(by: "timestamp", descending: true)
            .getDocuments()
        
        for message in messages.documents {
            if updateCount >= maxBatchSize { break }
            if message.data()["senderProfileImage"] != nil {
                batch.updateData([
                    "senderProfileImage": imageURL
                ], forDocument: message.reference)
                updateCount += 1
            }
        }
        
        // 9. Update reel likes - IMAGE ONLY (if field exists)
        let reelLikes = try await db.collection("reelLikes")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        for like in reelLikes.documents {
            if updateCount >= maxBatchSize { break }
            if like.data()["userProfileImage"] != nil {
                batch.updateData([
                    "userProfileImage": imageURL
                ], forDocument: like.reference)
                updateCount += 1
            }
        }
        
        // Commit all updates
        try await batch.commit()
        
        // Clear all caches
        cache.clearAll()
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
    
    // MARK: - Update User Rating
    func updateUserRating(userId: String) async {
        do {
            // Fetch all reviews for this user
            let reviews = try await db.collection("reviews")
                .whereField("reviewedUserId", isEqualTo: userId)
                .getDocuments()
            
            guard !reviews.documents.isEmpty else {
                // No reviews, reset rating
                try await db.collection("users").document(userId).updateData([
                    "rating": 0.0,
                    "reviewCount": 0,
                    "lastRatingUpdate": Date()
                ])
                return
            }
            
            // Calculate average rating and breakdown
            var totalRating = 0
            var ratingBreakdown: [String: Int] = [:]
            
            for doc in reviews.documents {
                if let rating = doc.data()["rating"] as? Int {
                    totalRating += rating
                    let key = String(rating)
                    ratingBreakdown[key, default: 0] += 1
                }
            }
            
            let averageRating = Double(totalRating) / Double(reviews.documents.count)
            
            // Update user document
            try await db.collection("users").document(userId).updateData([
                "rating": averageRating,
                "reviewCount": reviews.documents.count,
                "ratingBreakdown": ratingBreakdown,
                "lastRatingUpdate": Date()
            ])
            
            // Clear cache
            cache.remove(for: "user_\(userId)")
            
        } catch {
            print("Error updating user rating: \(error)")
        }
    }
    
    // MARK: - Search Users
    func searchUsers(query: String, limit: Int = 20) async throws -> [User] {
        guard !query.isEmpty else { return [] }
        
        // Removed unused variable that was causing warning
        // Search by name (simple prefix search)
        let snapshot = try await db.collection("users")
            .order(by: "name")
            .start(at: [query])
            .end(at: [query + "\u{f8ff}"])
            .limit(to: limit)
            .getDocuments()
        
        let users = snapshot.documents.compactMap { doc -> User? in
            var user = try? doc.data(as: User.self)
            user?.id = doc.documentID
            return user
        }
        
        return users
    }
    
    // MARK: - Check Username Availability
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let snapshot = try await db.collection("users")
            .whereField("username", isEqualTo: username.lowercased())
            .limit(to: 1)
            .getDocuments()
        
        return snapshot.documents.isEmpty
    }
}

// MARK: - Array Extension for Chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
