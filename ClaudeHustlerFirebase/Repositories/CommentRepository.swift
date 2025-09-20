// CommentRepository.swift
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
        
        // Update parent comment's reply count if this is a reply
        if let parentId = parentCommentId {
            try await db.collection("comments").document(parentId).updateData([
                "replyCount": FieldValue.increment(Int64(1))
            ])
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
    
    // MARK: - Like/Unlike Comment
    
    func likeComment(_ commentId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("comments").document(commentId).updateData([
            "likes": FieldValue.arrayUnion([userId])
        ])
    }
    
    func unlikeComment(_ commentId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("comments").document(commentId).updateData([
            "likes": FieldValue.arrayRemove([userId])
        ])
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
}
