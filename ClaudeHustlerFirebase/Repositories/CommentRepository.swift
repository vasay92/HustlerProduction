// CommentRepository.swift (Updated with notifications)
// Path: ClaudeHustlerFirebase/Repositories/CommentRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class CommentRepository {
    // Singleton
    static let shared = CommentRepository()
    
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    private let notificationRepository = NotificationRepository.shared
    
    // Listener storage
    private var commentListeners: [String: ListenerRegistration] = [:]
    
    private init() {}
    
    // MARK: - Create Comment
    
    func postComment(on reelId: String, text: String, parentCommentId: String? = nil) async throws -> Comment {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "CommentRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Get current user info
        let userDoc = try await db.collection("users").document(userId).getDocument()
        let userData = try? userDoc.data(as: User.self)
        
        let comment = Comment(
            reelId: reelId,
            userId: userId,
            userName: userData?.name ?? "User",
            userProfileImage: userData?.profileImageURL,
            text: text,
            parentCommentId: parentCommentId
        )
        
        let docRef = try await db.collection("comments").addDocument(from: comment)
        
        // If this is a reply, update parent comment and create notification
        if let parentId = parentCommentId {
            // Get parent comment to find its owner
            let parentDoc = try await db.collection("comments").document(parentId).getDocument()
            if let parentData = parentDoc.data(),
               let parentUserId = parentData["userId"] as? String {
                
                // Update parent comment's reply count
                try await db.collection("comments").document(parentId).updateData([
                    "replyCount": FieldValue.increment(Int64(1))
                ])
                
                // CREATE NOTIFICATION for parent comment owner
                await notificationRepository.createReelNotification(
                    for: parentUserId,
                    reelId: reelId,
                    type: .commentReply,
                    fromUserId: userId
                )
            }
        }
        
        // Update reel's comment count
        try await db.collection("reels").document(reelId).updateData([
            "comments": FieldValue.increment(Int64(1))
        ])
        
        var newComment = comment
        newComment.id = docRef.documentID
        
        return newComment
    }
    
    // MARK: - Delete Comment
    
    func deleteComment(_ commentId: String, reelId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let commentDoc = try await db.collection("comments").document(commentId).getDocument()
        guard let commentData = commentDoc.data() else { return }
        
        let commentUserId = commentData["userId"] as? String ?? ""
        
        // Get reel owner
        let reelDoc = try await db.collection("reels").document(reelId).getDocument()
        let reelOwnerId = reelDoc.data()?["userId"] as? String ?? ""
        
        // Check permission
        guard userId == commentUserId || userId == reelOwnerId else {
            throw NSError(domain: "CommentRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        }
        
        // Soft delete
        try await db.collection("comments").document(commentId).updateData([
            "isDeleted": true,
            "deletedAt": Date()
        ])
        
        // Update counts
        if let parentId = commentData["parentCommentId"] as? String {
            try await db.collection("comments").document(parentId).updateData([
                "replyCount": FieldValue.increment(Int64(-1))
            ])
        }
        
        try await db.collection("reels").document(reelId).updateData([
            "comments": FieldValue.increment(Int64(-1))
        ])
    }
    
    // MARK: - Like/Unlike Comment WITH NOTIFICATIONS
    
    func likeComment(_ commentId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Get comment to find owner and reel
        let commentDoc = try await db.collection("comments").document(commentId).getDocument()
        guard let commentData = commentDoc.data(),
              let commentOwnerId = commentData["userId"] as? String,
              let reelId = commentData["reelId"] as? String else { return }
        
        // Add like
        try await db.collection("comments").document(commentId).updateData([
            "likes": FieldValue.arrayUnion([userId])
        ])
        
        // CREATE NOTIFICATION for comment owner
        await notificationRepository.createReelNotification(
            for: commentOwnerId,
            reelId: reelId,
            type: .commentLike,
            fromUserId: userId
        )
    }
    
    func unlikeComment(_ commentId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("comments").document(commentId).updateData([
            "likes": FieldValue.arrayRemove([userId])
        ])
    }
    
    // MARK: - Fetch Comments
    
    func fetchComments(for reelId: String, limit: Int = 100) async throws -> [Comment] {
        let snapshot = try await db.collection("comments")
            .whereField("reelId", isEqualTo: reelId)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "timestamp", descending: false)
            .limit(to: limit)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            var comment = try? doc.data(as: Comment.self)
            comment?.id = doc.documentID
            return comment
        }
    }
    
    func fetchReplies(for commentId: String) async throws -> [Comment] {
        let snapshot = try await db.collection("comments")
            .whereField("parentCommentId", isEqualTo: commentId)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "timestamp", descending: false)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            var comment = try? doc.data(as: Comment.self)
            comment?.id = doc.documentID
            return comment
        }
    }
    
    // MARK: - Real-time Listening
    
    func listenToComments(for reelId: String, completion: @escaping ([Comment]) -> Void) -> ListenerRegistration {
        // Remove existing listener
        commentListeners[reelId]?.remove()
        
        let listener = db.collection("comments")
            .whereField("reelId", isEqualTo: reelId)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to comments: \(error)")
                    completion([])
                    return
                }
                
                let comments = snapshot?.documents.compactMap { doc -> Comment? in
                    var comment = try? doc.data(as: Comment.self)
                    comment?.id = doc.documentID
                    return comment
                } ?? []
                
                completion(comments)
            }
        
        commentListeners[reelId] = listener
        return listener
    }
    
    func stopListeningToComments(_ reelId: String) {
        commentListeners[reelId]?.remove()
        commentListeners.removeValue(forKey: reelId)
    }
    
    // Cleanup all listeners
    func removeAllListeners() {
        commentListeners.values.forEach { $0.remove() }
        commentListeners.removeAll()
    }
    
    // MARK: - Protocol Compliance Methods (for CommentsView compatibility)
    
    func create(_ comment: Comment) async throws {
        _ = try await postComment(
            on: comment.reelId,
            text: comment.text,
            parentCommentId: comment.parentCommentId
        )
    }
    
    func delete(_ commentId: String) async throws {
        // Get the reelId for the existing deleteComment method
        let commentDoc = try await db.collection("comments").document(commentId).getDocument()
        guard let commentData = commentDoc.data(),
              let reelId = commentData["reelId"] as? String else {
            throw NSError(domain: "CommentRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Comment or reelId not found"])
        }
        
        try await deleteComment(commentId, reelId: reelId)
    }
}
