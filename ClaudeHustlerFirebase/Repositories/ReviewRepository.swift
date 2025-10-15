// ReviewRepository.swift - PROPERLY FIXED VERSION (Unlimited Reviews)
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
    private let notificationRepository = NotificationRepository.shared
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
        
        if !cache.isExpired(for: cacheKey, maxAge: cacheMaxAge),
           let cachedReview: Review = cache.retrieve(Review.self, for: cacheKey) {
            return cachedReview
        }
        
        let document = try await db.collection("reviews").document(id).getDocument()
        guard document.exists else { return nil }
        
        var review = try document.data(as: Review.self)
        review.id = document.documentID
        
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
        
        if lastDocument == nil {
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
        
        if reviewerId == review.reviewedUserId {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot review yourself"])
        }
        
        let reviewData: [String: Any] = [
            "reviewerId": reviewerId,
            "reviewedUserId": review.reviewedUserId,
            "reviewerName": review.reviewerName ?? "",
            "reviewerProfileImage": review.reviewerProfileImage ?? "",
            "rating": review.rating,
            "text": review.text,
            "mediaURLs": review.mediaURLs,
            "createdAt": Date(),
            "updatedAt": Date(),
            "isEdited": false,
            "helpfulVotes": []
        ]
        
        let docRef = try await db.collection("reviews").addDocument(data: reviewData)
        
        await notificationRepository.createReviewNotification(
            for: review.reviewedUserId,
            reviewId: docRef.documentID,
            type: .newReview,
            fromUserId: reviewerId,
            profileUserId: review.reviewedUserId,  // ADDED - The review is on this person's profile
            reviewText: review.text
        )
        
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
        
        let document = try await db.collection("reviews").document(reviewId).getDocument()
        guard let data = document.data(),
              data["reviewerId"] as? String == currentUserId else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to edit this review"])
        }
        
        let updates: [String: Any] = [
            "rating": review.rating,
            "text": review.text,
            "updatedAt": Date(),
            "isEdited": true
        ]
        
        try await db.collection("reviews").document(reviewId).updateData(updates)
        
        if let reviewedUserId = data["reviewedUserId"] as? String {
            await userRepository.updateUserRating(userId: reviewedUserId)
            await notificationRepository.createReviewNotification(
                for: reviewedUserId,
                reviewId: reviewId,
                type: .reviewEdit,
                fromUserId: currentUserId,
                profileUserId: reviewedUserId,  // ADDED - The review is on this person's profile
                reviewText: review.text
            )
            cache.remove(for: "reviews_user_\(reviewedUserId)")
        }
        
        cache.remove(for: "review_\(reviewId)")
    }
    
    // MARK: - Delete Review
    func delete(_ id: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let document = try await db.collection("reviews").document(id).getDocument()
        guard let data = document.data() else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Review not found"])
        }
        
        let reviewerId = data["reviewerId"] as? String ?? ""
        let reviewedUserId = data["reviewedUserId"] as? String ?? ""
        
        guard currentUserId == reviewerId || currentUserId == reviewedUserId else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to delete this review"])
        }
        
        try await db.collection("reviews").document(id).delete()
        await userRepository.updateUserRating(userId: reviewedUserId)
        
        cache.remove(for: "review_\(id)")
        cache.remove(for: "reviews_user_\(reviewedUserId)")
    }
    
    // MARK: - Reply to Review
    func replyToReview(_ reviewId: String, replyText: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let document = try await db.collection("reviews").document(reviewId).getDocument()
        guard let data = document.data(),
              data["reviewedUserId"] as? String == currentUserId else {
            throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Can only reply to reviews about you"])
        }
        
        let reviewerId = data["reviewerId"] as? String ?? ""
        
        let reply: [String: Any] = [
            "userId": currentUserId,
            "text": replyText,
            "repliedAt": Date()
        ]
        
        try await db.collection("reviews").document(reviewId).updateData([
            "reply": reply,
            "updatedAt": Date()
        ])
        
        await notificationRepository.createReviewNotification(
            for: reviewerId,
            reviewId: reviewId,
            type: .reviewReply,
            fromUserId: currentUserId,
            profileUserId: currentUserId,  // ADDED - The review is on the replier's profile
            reviewText: replyText
        )
        
        cache.remove(for: "review_\(reviewId)")
    }
    
    // MARK: - Helpful Votes
    func voteHelpful(_ reviewId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let reviewRef = db.collection("reviews").document(reviewId)
        let document = try await reviewRef.getDocument()
        guard let data = document.data() else { return }
        
        let helpfulVotes = data["helpfulVotes"] as? [String] ?? []
        let reviewerId = data["reviewerId"] as? String ?? ""
        
        if helpfulVotes.contains(userId) {
            try await reviewRef.updateData([
                "helpfulVotes": FieldValue.arrayRemove([userId])
            ])
        } else {
            try await reviewRef.updateData([
                "helpfulVotes": FieldValue.arrayUnion([userId])
            ])
            
            if userId != reviewerId {
                // ADDED: Get the reviewedUserId (whose profile has this review)
                let reviewedUserId = data["reviewedUserId"] as? String ?? ""
                
                await notificationRepository.createReviewNotification(
                    for: reviewerId,
                    reviewId: reviewId,
                    type: .helpfulVote,
                    fromUserId: userId,
                    profileUserId: reviewedUserId  // ADDED - The profile that has the review
                )
            }
        }
        
        cache.remove(for: "review_\(reviewId)")
    }
    
    func toggleHelpfulVote(for reviewId: String) async throws -> (isVoted: Bool, count: Int) {
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
            if let reviewerId = data["reviewerId"] as? String, reviewerId != userId {
                // ADDED: Get the reviewedUserId (whose profile has this review)
                let reviewedUserId = data["reviewedUserId"] as? String ?? ""
                
                await notificationRepository.createReviewNotification(
                    for: reviewerId,
                    reviewId: reviewId,
                    type: .helpfulVote,
                    fromUserId: userId,
                    profileUserId: reviewedUserId  // ADDED - The profile that has the review
                )
            }
        }
        
        try await reviewRef.updateData(["helpfulVotes": helpfulVotes])
        cache.remove(for: "review_\(reviewId)")
        
        return (!wasVoted, helpfulVotes.count)
    }
    
    // MARK: - Stats
    func getReviewStats(for userId: String) async -> (average: Double, count: Int, breakdown: [Int: Int]) {
        do {
            let snapshot = try await db.collection("reviews")
                .whereField("reviewedUserId", isEqualTo: userId)
                .getDocuments()
            
            let reviews = snapshot.documents.compactMap { try? $0.data(as: Review.self) }
            guard !reviews.isEmpty else { return (0.0, 0, [:]) }
            
            var breakdown: [Int: Int] = [:]
            for rating in 1...5 {
                let count = reviews.filter { $0.rating == rating }.count
                if count > 0 { breakdown[rating] = count }
            }
            
            let totalRating = reviews.reduce(0) { $0 + $1.rating }
            let average = Double(totalRating) / Double(reviews.count)
            return (average, reviews.count, breakdown)
        } catch {
            
            return (0.0, 0, [:])
        }
    }
    
    // MARK: - Create with Images
    // MARK: - Create with Images (FIXED WITH LOGGING)
       func createReview(for userId: String, rating: Int, text: String, images: [UIImage] = []) async throws -> Review {
           
           
           guard let reviewerId = Auth.auth().currentUser?.uid else {
               throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
           }
           
           if reviewerId == userId {
               throw NSError(domain: "ReviewRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot review yourself"])
           }
           
           var mediaURLs: [String] = []
           
           // Upload images if provided
           if !images.isEmpty {
               
               for (index, image) in images.enumerated() {
                   
                   
                   let path = "reviews/\(reviewerId)/\(UUID().uuidString)_\(index).jpg"
                   
                   
                   do {
                       let url = try await FirebaseService.shared.uploadImage(image, path: path)
                       mediaURLs.append(url)
                       
                   } catch {
                       
                       throw error
                   }
               }
               
           }
           
           // Get reviewer info
           let userDoc = try await db.collection("users").document(reviewerId).getDocument()
           let userData = try? userDoc.data(as: User.self)
           
           // Create review object
           let review = Review(
               reviewerId: reviewerId,
               reviewedUserId: userId,
               reviewerName: userData?.name,
               reviewerProfileImage: userData?.profileImageURL,
               rating: rating,
               text: text,
               mediaURLs: mediaURLs  // This should now contain the uploaded URLs
           )
           
           
           
           let reviewId = try await create(review)
           var newReview = review
           newReview.id = reviewId
           
           
           
           return newReview
       }
    
    // MARK: - Real-time Listeners
    func listenToUserReviews(userId: String, completion: @escaping ([Review]) -> Void) -> ListenerRegistration {
        reviewListeners[userId]?.remove()
        
        let listener = db.collection("reviews")
            .whereField("reviewedUserId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    
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
    
    // MARK: - Deprecated
    func markReviewNotificationAsRead(_ notificationId: String) async {
        do {
            try await notificationRepository.markAsRead(notificationId)
        } catch {
            
        }
    }
    
    // MARK: - Cleanup
    deinit {
        let listenersToClean = reviewListeners
        Task.detached {
            listenersToClean.values.forEach { $0.remove() }
        }
    }
}
