

// ReviewRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/ReviewRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

// MARK: - Review Repository
@MainActor
final class ReviewRepository: RepositoryProtocol {
    typealias Model = Review
    
    // Singleton
    static let shared = ReviewRepository()
    
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    private let userRepository = UserRepository.shared
    private let cacheMaxAge: TimeInterval = 300 // 5 minutes
    
    // Active listeners
    private var reviewListeners: [String: ListenerRegistration] = [:]
    
    private init() {}
    
    // MARK: - Fetch Reviews with Pagination
    func fetch(limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [Review], lastDoc: DocumentSnapshot?) {
        var query = db.collection("reviews")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let reviews = snapshot.documents.compactMap { doc -> Review? in
            var review = try? doc.data(as: Review.self)
            review?.id = doc.documentID
            return review
        }
        
        return (reviews, snapshot.documents.last)
    }
    
    
    // MARK: - Fetch Single Review
    func fetchById(_ id: String) async throws -> Review? {
        let cacheKey = "review_\(id)"
        
        // Check cache first
        if !cache.isExpired(for: cacheKey, maxAge: cacheMaxAge),
           let cachedReview: Review = cache.retrieve(Review.self, for: cacheKey) {
            return cachedReview
        }
        
        // Fetch from Firestore
        let document = try await db.collection("reviews").document(id).getDocument()
        
        guard document.exists else { return nil }
        
        var review = try document.data(as: Review.self)
        review.id = document.documentID
        
        // Cache the review
        cache.store(review, for: cacheKey)
        
        return review
    }
    
    // MARK: - Fetch Reviews for User
    func fetchUserReviews(
        userId: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (items: [Review], lastDoc: DocumentSnapshot?) {
        let cacheKey = "reviews_user_\(userId)"
        
        // Check cache for first page
        if lastDocument == nil,
           !cache.isExpired(for: cacheKey, maxAge: cacheMaxAge),
           let cachedReviews: [Review] = cache.retrieve([Review].self, for: cacheKey) {
            return (cachedReviews, nil)
        }
        
        var query = db.collection("reviews")
            .whereField("reviewedUserId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let reviews = snapshot.documents.compactMap { doc -> Review? in
            var review = try? doc.data(as: Review.self)
            review?.id = doc.documentID
            return review
        }
        
        // Cache first page
        if lastDocument == nil && !reviews.isEmpty {
            cache.store(reviews, for: cacheKey)
        }
        
        return (reviews, snapshot.documents.last)
    }
    
    // MARK: - Fetch Reviews by Reviewer
    func fetchReviewsByReviewer(
        reviewerId: String,
        limit: Int = 20,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (items: [Review], lastDoc: DocumentSnapshot?) {
        var query = db.collection("reviews")
            .whereField("reviewerId", isEqualTo: reviewerId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let reviews = snapshot.documents.compactMap { doc -> Review? in
            var review = try? doc.data(as: Review.self)
            review?.id = doc.documentID
            return review
        }
        
        return (reviews, snapshot.documents.last)
    }
    
    // MARK: - Create Review
    func create(_ review: Review) async throws -> String {
        guard let reviewerId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Prevent self-reviews
        if reviewerId == review.reviewedUserId {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot review yourself"])
        }
        
        // Check for duplicate review
        let existingReviews = try await db.collection("reviews")
            .whereField("reviewerId", isEqualTo: reviewerId)
            .whereField("reviewedUserId", isEqualTo: review.reviewedUserId)
            .getDocuments()
        
        if existingReviews.documents.count >= 3 {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Maximum 3 reviews per user allowed"])
        }
        
        // Create review data dictionary (don't modify the input review)
        let reviewData: [String: Any] = [
            "reviewerId": reviewerId,
            "reviewedUserId": review.reviewedUserId,
            "reviewerName": review.reviewerName ?? "",
            "reviewerProfileImage": review.reviewerProfileImage ?? "",
            "rating": review.rating,
            "text": review.text,
            "mediaURLs": review.mediaURLs,  // Already exists in Review model
            "createdAt": Date(),
            "updatedAt": Date(),
            "isEdited": false,
            "helpfulVotes": [],
            "reviewNumber": existingReviews.documents.count + 1
        ]
        
        let docRef = try await db.collection("reviews").addDocument(data: reviewData)
        
        // Update user rating
        await userRepository.updateUserRating(userId: review.reviewedUserId)
        
        // Create notification
        await createReviewNotification(
            for: review.reviewedUserId,
            reviewId: docRef.documentID,
            type: .newReview,
            fromUserId: reviewerId
        )
        
        // Clear cache
        cache.remove(for: "reviews_user_\(review.reviewedUserId)")
        
        return docRef.documentID
    }
    
    // MARK: - Update Review
    func update(_ review: Review) async throws {
        guard let reviewId = review.id else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Review ID is required"])
        }
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify ownership
        let document = try await db.collection("reviews").document(reviewId).getDocument()
        guard let data = document.data(),
              data["reviewerId"] as? String == currentUserId else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to edit this review"])
        }
        
        // Update review
        let updates: [String: Any] = [
            "rating": review.rating,
            "text": review.text,
            "updatedAt": Date(),
            "isEdited": true
        ]
        
        try await db.collection("reviews").document(reviewId).updateData(updates)
        
        // Update user rating if rating changed
        if let reviewedUserId = data["reviewedUserId"] as? String {
            await userRepository.updateUserRating(userId: reviewedUserId)
            
            // Create notification
            await createReviewNotification(
                for: reviewedUserId,
                reviewId: reviewId,
                type: .reviewEdit,
                fromUserId: currentUserId
            )
        }
        
        // Clear cache
        cache.remove(for: "review_\(reviewId)")
        if let reviewedUserId = data["reviewedUserId"] as? String {
            cache.remove(for: "reviews_user_\(reviewedUserId)")
        }
    }
    
    // MARK: - Delete Review
    func delete(_ id: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Get review to verify ownership and get reviewedUserId
        let document = try await db.collection("reviews").document(id).getDocument()
        guard let data = document.data() else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Review not found"])
        }
        
        let reviewerId = data["reviewerId"] as? String ?? ""
        let reviewedUserId = data["reviewedUserId"] as? String ?? ""
        
        // Check if user can delete (own review or reviewed user can delete)
        guard currentUserId == reviewerId || currentUserId == reviewedUserId else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to delete this review"])
        }
        
        // Delete review
        try await db.collection("reviews").document(id).delete()
        
        // Update user rating
        await userRepository.updateUserRating(userId: reviewedUserId)
        
        // Clear cache
        cache.remove(for: "review_\(id)")
        cache.remove(for: "reviews_user_\(reviewedUserId)")
    }
    
    // MARK: - Reply to Review
    func replyToReview(_ reviewId: String, replyText: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Get review
        let document = try await db.collection("reviews").document(reviewId).getDocument()
        guard let data = document.data(),
              data["reviewedUserId"] as? String == currentUserId else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Can only reply to reviews about you"])
        }
        
        let reviewerId = data["reviewerId"] as? String ?? ""
        
        // Add reply
        let reply: [String: Any] = [
            "userId": currentUserId,
            "text": replyText,
            "repliedAt": Date()
        ]
        
        try await db.collection("reviews").document(reviewId).updateData([
            "reply": reply,
            "updatedAt": Date()
        ])
        
        // Create notification
        await createReviewNotification(
            for: reviewerId,
            reviewId: reviewId,
            type: .reviewReply,
            fromUserId: currentUserId
        )
        
        // Clear cache
        cache.remove(for: "review_\(reviewId)")
    }
    
    // MARK: - Vote Helpful
    func voteHelpful(_ reviewId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let reviewRef = db.collection("reviews").document(reviewId)
        
        // Get current review
        let document = try await reviewRef.getDocument()
        guard let data = document.data() else { return }
        
        let helpfulVotes = data["helpfulVotes"] as? [String] ?? []
        let reviewerId = data["reviewerId"] as? String ?? ""
        
        if helpfulVotes.contains(userId) {
            // Remove vote
            try await reviewRef.updateData([
                "helpfulVotes": FieldValue.arrayRemove([userId])
            ])
        } else {
            // Add vote
            try await reviewRef.updateData([
                "helpfulVotes": FieldValue.arrayUnion([userId])
            ])
            
            // Create notification only for new votes
            if userId != reviewerId {
                await createReviewNotification(
                    for: reviewerId,
                    reviewId: reviewId,
                    type: .helpfulVote,
                    fromUserId: userId
                )
            }
        }
        
        // Clear cache
        cache.remove(for: "review_\(reviewId)")
    }
    
    // MARK: - Get Review Stats
    func getReviewStats(for userId: String) async -> (average: Double, count: Int, breakdown: [Int: Int]) {
        do {
            let snapshot = try await db.collection("reviews")
                .whereField("reviewedUserId", isEqualTo: userId)
                .getDocuments()
            
            let reviews = snapshot.documents.compactMap { doc -> Review? in
                var review = try? doc.data(as: Review.self)
                review?.id = doc.documentID
                return review
            }
            
            guard !reviews.isEmpty else {
                return (0.0, 0, [:])
            }
            
            var breakdown: [Int: Int] = [:]
            for rating in 1...5 {
                let count = reviews.filter { $0.rating == rating }.count
                if count > 0 {
                    breakdown[rating] = count
                }
            }
            
            let totalRating = reviews.reduce(0) { $0 + $1.rating }
            let average = Double(totalRating) / Double(reviews.count)
            
            return (average, reviews.count, breakdown)
            
        } catch {
            print("Error getting review stats: \(error)")
            return (0.0, 0, [:])
        }
    }
    
    // MARK: - Real-time Listening
    
    func listenToUserReviews(userId: String, completion: @escaping ([Review]) -> Void) -> ListenerRegistration {
        // Remove existing listener
        reviewListeners[userId]?.remove()
        
        let listener = db.collection("reviews")
            .whereField("reviewedUserId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to reviews: \(error)")
                    completion([])
                    return
                }
                
                let reviews = snapshot?.documents.compactMap { doc -> Review? in
                    var review = try? doc.data(as: Review.self)
                    review?.id = doc.documentID
                    return review
                } ?? []
                
                completion(reviews)
            }
        
        reviewListeners[userId] = listener
        return listener
    }
    
    func stopListeningToUserReviews(userId: String) {
        reviewListeners[userId]?.remove()
        reviewListeners.removeValue(forKey: userId)
    }
    
    func removeAllListeners() {
        reviewListeners.values.forEach { $0.remove() }
        reviewListeners.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func createReviewNotification(
        for userId: String,
        reviewId: String,
        type: ReviewNotification.ReviewNotificationType,
        fromUserId: String
    ) async {
        // Get from user name
        guard let fromUser = try? await userRepository.fetchById(fromUserId) else { return }
        
        let message: String
        switch type {
        case .newReview:
            message = "\(fromUser.name) left you a review"
        case .reviewReply:
            message = "\(fromUser.name) replied to your review"
        case .reviewEdit:
            message = "\(fromUser.name) edited their review"
        case .helpfulVote:
            message = "\(fromUser.name) found your review helpful"
        }
        
        let notificationData: [String: Any] = [
            "userId": userId,
            "reviewId": reviewId,
            "type": type.rawValue,
            "fromUserId": fromUserId,
            "fromUserName": fromUser.name,
            "message": message,
            "isRead": false,
            "createdAt": Date()
        ]
        
        do {
            try await db.collection("reviewNotifications").addDocument(data: notificationData)
        } catch {
            print("Error creating review notification: \(error)")
        }
    }
    
    // 1. Create review with images
    func createReview(
        for userId: String,
        rating: Int,
        text: String,
        images: [UIImage] = []
    ) async throws -> Review {
        guard let reviewerId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Prevent self-reviews
        if reviewerId == userId {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot review yourself"])
        }
        
        // Check for existing reviews
        let existingReviews = try await db.collection("reviews")
            .whereField("reviewerId", isEqualTo: reviewerId)
            .whereField("reviewedUserId", isEqualTo: userId)
            .getDocuments()
        
        if existingReviews.documents.count >= 3 {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Maximum 3 reviews per user allowed"])
        }
        
        // Upload images
        var mediaURLs: [String] = []
        for (index, image) in images.enumerated() {
            let path = "reviews/\(reviewerId)/\(UUID().uuidString)_\(index).jpg"
            let url = try await FirebaseService.shared.uploadImage(image, path: path)
            mediaURLs.append(url)
        }
        
        // Get reviewer info
        let userDoc = try await db.collection("users").document(reviewerId).getDocument()
        let userData = try? userDoc.data(as: User.self)
        
        // Create review
        let review = Review(
            reviewerId: reviewerId,
            reviewedUserId: userId,
            reviewerName: userData?.name,
            reviewerProfileImage: userData?.profileImageURL,
            rating: rating,
            text: text,
            mediaURLs: mediaURLs,
            reviewNumber: existingReviews.documents.count + 1
        )
        
        let reviewId = try await create(review)
        
        var newReview = review
        newReview.id = reviewId
        
        return newReview
    }

    // 2. Update review (match FirebaseService signature)
    func updateReview(
        _ reviewId: String,
        rating: Int? = nil,
        text: String? = nil
    ) async throws -> Review? {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Get existing review
        let document = try await db.collection("reviews").document(reviewId).getDocument()
        guard let data = document.data(),
              data["reviewerId"] as? String == currentUserId else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        }
        
        // Build updates
        var updates: [String: Any] = [
            "updatedAt": Date(),
            "isEdited": true
        ]
        
        if let rating = rating {
            updates["rating"] = rating
        }
        
        if let text = text {
            updates["text"] = text
        }
        
        // Update document
        try await db.collection("reviews").document(reviewId).updateData(updates)
        
        // Get updated review
        let updatedDoc = try await db.collection("reviews").document(reviewId).getDocument()
        var updatedReview = try? updatedDoc.data(as: Review.self)
        updatedReview?.id = updatedDoc.documentID
        
        // Update user rating if rating changed
        if rating != nil, let reviewedUserId = data["reviewedUserId"] as? String {
            await userRepository.updateUserRating(userId: reviewedUserId)
            
            // Create notification
            await createReviewNotification(
                for: reviewedUserId,
                reviewId: reviewId,
                type: .reviewEdit,
                fromUserId: currentUserId
            )
        }
        
        // Clear cache
        cache.remove(for: "review_\(reviewId)")
        if let reviewedUserId = data["reviewedUserId"] as? String {
            cache.remove(for: "reviews_user_\(reviewedUserId)")
        }
        
        return updatedReview
    }

    // 3. Toggle helpful vote (return new state)
    func toggleHelpfulVote(
        for reviewId: String
    ) async throws -> (isVoted: Bool, count: Int) {
        guard let userId = Auth.auth().currentUser?.uid else {
            return (false, 0)
        }
        
        let reviewRef = db.collection("reviews").document(reviewId)
        let review = try await reviewRef.getDocument()
        
        guard let data = review.data() else {
            return (false, 0)
        }
        
        var helpfulVotes = data["helpfulVotes"] as? [String] ?? []
        let wasVoted = helpfulVotes.contains(userId)
        
        if wasVoted {
            helpfulVotes.removeAll { $0 == userId }
        } else {
            helpfulVotes.append(userId)
            
            // Create notification for helpful vote (only on adding, not removing)
            if let reviewerId = data["reviewerId"] as? String, reviewerId != userId {
                await createReviewNotification(
                    for: reviewerId,
                    reviewId: reviewId,
                    type: .helpfulVote,
                    fromUserId: userId
                )
            }
        }
        
        try await reviewRef.updateData([
            "helpfulVotes": helpfulVotes
        ])
        
        // Clear cache
        cache.remove(for: "review_\(reviewId)")
        
        return (!wasVoted, helpfulVotes.count)
    }

    // 4. Load review notifications
    func loadReviewNotifications() async -> [ReviewNotification] {
        guard let userId = Auth.auth().currentUser?.uid else {
            return []
        }
        
        do {
            let snapshot = try await db.collection("reviewNotifications")
                .whereField("userId", isEqualTo: userId)
                .whereField("isRead", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()
            
            return snapshot.documents.compactMap { doc in
                var notification = try? doc.data(as: ReviewNotification.self)
                notification?.id = doc.documentID
                return notification
            }
        } catch {
            print("Error loading review notifications: \(error)")
            return []
        }
    }

    // 5. Mark notification as read
    func markReviewNotificationAsRead(_ notificationId: String) async {
        do {
            try await db.collection("reviewNotifications").document(notificationId).updateData([
                "isRead": true
            ])
        } catch {
            print("Error marking notification as read: \(error)")
        }
    }

    // 6. Stop listening to user reviews
    func stopListeningToUserReviews(_ userId: String) {
        reviewListeners[userId]?.remove()
        reviewListeners.removeValue(forKey: userId)
    }

    
}
