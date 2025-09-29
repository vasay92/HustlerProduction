// NotificationRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/NotificationRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Unified Notification Model
struct AppNotification: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String // Who receives the notification
    let type: NotificationType
    let fromUserId: String
    let fromUserName: String
    var fromUserProfileImage: String?
    let title: String
    let body: String
    let data: [String: String]? // Additional data for navigation
    var isRead: Bool = false
    let createdAt: Date = Date()
    
    enum NotificationType: String, Codable {
        // Review notifications
        case newReview = "new_review"
        case reviewReply = "review_reply"
        case reviewEdit = "review_edit"
        case helpfulVote = "helpful_vote"
        
        // ADD THESE NEW TYPES:
        case reelLike = "reel_like"
        case commentLike = "comment_like"
            
        // Message notifications
        case newMessage = "new_message"
        case messageRequest = "message_request"
        
        var icon: String {
            switch self {
            case .newReview, .reviewReply, .reviewEdit:
                return "star.fill"
            case .helpfulVote:
                return "hand.thumbsup.fill"
            case .newMessage, .messageRequest:
                return "message.fill"
            case .reelLike:              // ← ADD THIS
                return "heart.fill"
            case .commentLike:           // ← ADD THIS
                return "bubble.left.fill"
            }
        }
        // ADD THIS: Categorize notifications
            var isBellNotification: Bool {
                switch self {
                case .newReview, .helpfulVote, .reelLike, .commentLike:
                    return true
                case .reviewReply, .reviewEdit, .newMessage, .messageRequest:
                    return false
                }
            }
    }
}

// MARK: - Notification Repository
@MainActor
final class NotificationRepository {
    static let shared = NotificationRepository()
    
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    private var notificationListener: ListenerRegistration?
    
    private init() {}
    
    // MARK: - Create Message Notification
    func createMessageNotification(
        for userId: String,
        fromUserId: String,
        conversationId: String,
        messageText: String,
        isNewConversation: Bool = false
    ) async {
        // Don't notify yourself
        guard userId != fromUserId else { return }
        
        // Get sender info
        guard let fromUser = try? await UserRepository.shared.fetchById(fromUserId) else { return }
        
        // Check user's notification settings
        let recipientUser = try? await UserRepository.shared.fetchById(userId)
        if let settings = recipientUser?.notificationSettings {
            if isNewConversation && !settings.messageRequests { return }
            if !isNewConversation && !settings.newMessages { return }
        }
        
        let notification = AppNotification(
            userId: userId,
            type: isNewConversation ? .messageRequest : .newMessage,
            fromUserId: fromUserId,
            fromUserName: fromUser.name,
            fromUserProfileImage: fromUser.profileImageURL,
            title: isNewConversation ? "New Message Request" : "New Message",
            body: "\(fromUser.name): \(String(messageText.prefix(100)))",
            data: [
                "conversationId": conversationId,
                "senderId": fromUserId
            ],
            isRead: false
        )
        
        do {
            try await createNotification(notification)
            
            // Send push notification if user has FCM token
            if let fcmToken = recipientUser?.fcmToken {
                await sendPushNotification(
                    to: fcmToken,
                    title: notification.title,
                    body: notification.body,
                    data: notification.data ?? [:]
                )
            }
        } catch {
            print("Error creating message notification: \(error)")
        }
    }
    
    // MARK: - Create Review Notification
    func createReviewNotification(
        for userId: String,
        reviewId: String,
        type: AppNotification.NotificationType,
        fromUserId: String,
        reviewText: String? = nil
    ) async {
        // Don't notify yourself
        guard userId != fromUserId else { return }
        
        // Get sender info
        guard let fromUser = try? await UserRepository.shared.fetchById(fromUserId) else { return }
        
        // Check user's notification settings
        let recipientUser = try? await UserRepository.shared.fetchById(userId)
        if let settings = recipientUser?.notificationSettings {
            switch type {
            case .newReview:
                if !settings.newReviews { return }
            case .reviewReply:
                if !settings.reviewReplies { return }
            case .reviewEdit:
                if !settings.reviewEdits { return }
            case .helpfulVote:
                if !settings.helpfulVotes { return }
            default:
                break
            }
        }
        
        let title: String
        let body: String
        
        switch type {
        case .newReview:
            title = "New Review"
            body = "\(fromUser.name) left you a review"
        case .reviewReply:
            title = "Review Reply"
            body = "\(fromUser.name) replied to your review"
        case .reviewEdit:
            title = "Review Updated"
            body = "\(fromUser.name) edited their review"
        case .helpfulVote:
            title = "Review Appreciated"
            body = "\(fromUser.name) found your review helpful"
        default:
            title = "Notification"
            body = "You have a new notification"
        }
        
        let notification = AppNotification(
            userId: userId,
            type: type,
            fromUserId: fromUserId,
            fromUserName: fromUser.name,
            fromUserProfileImage: fromUser.profileImageURL,
            title: title,
            body: body,
            data: ["reviewId": reviewId],
            isRead: false
        )
        
        do {
            try await createNotification(notification)
            
            // Send push notification if user has FCM token
            if let fcmToken = recipientUser?.fcmToken {
                await sendPushNotification(
                    to: fcmToken,
                    title: notification.title,
                    body: notification.body,
                    data: notification.data ?? [:]
                )
            }
        } catch {
            print("Error creating review notification: \(error)")
        }
    }
    
    // MARK: - Create Reel Notification
    func createReelNotification(
        for userId: String,
        reelId: String,
        type: AppNotification.NotificationType,
        fromUserId: String
    ) async {
        // Don't notify yourself
        guard userId != fromUserId else { return }
        
        // Get sender info
        guard let fromUser = try? await UserRepository.shared.fetchById(fromUserId) else { return }
        
        // Check user's notification settings
        let recipientUser = try? await UserRepository.shared.fetchById(userId)
        if let settings = recipientUser?.notificationSettings {
            switch type {
            case .reelLike:
                if !(settings.reelLikes ?? true) { return }
            case .commentLike:
                if !(settings.commentLikes ?? true) { return }
            default:
                break
            }
        }
        
        let title: String
        let body: String
        
        switch type {
        case .reelLike:
            title = "Reel Liked"
            body = "\(fromUser.name) liked your reel"
        case .commentLike:
            title = "Comment Liked"
            body = "\(fromUser.name) liked your comment"
        default:
            return
        }
        
        let notification = AppNotification(
            userId: userId,
            type: type,
            fromUserId: fromUserId,
            fromUserName: fromUser.name,
            fromUserProfileImage: fromUser.profileImageURL,
            title: title,
            body: body,
            data: ["reelId": reelId],
            isRead: false
        )
        
        do {
            try await createNotification(notification)
            
            // Send push notification if user has FCM token
            if let fcmToken = recipientUser?.fcmToken {
                await sendPushNotification(
                    to: fcmToken,
                    title: notification.title,
                    body: notification.body,
                    data: notification.data ?? [:]
                )
            }
        } catch {
            print("Error creating reel notification: \(error)")
        }
    }
    
    // MARK: - Core Notification Operations
    private func createNotification(_ notification: AppNotification) async throws {
        let data: [String: Any] = [
            "userId": notification.userId,
            "type": notification.type.rawValue,
            "fromUserId": notification.fromUserId,
            "fromUserName": notification.fromUserName,
            "fromUserProfileImage": notification.fromUserProfileImage ?? "",
            "title": notification.title,
            "body": notification.body,
            "data": notification.data ?? [:],
            "isRead": false,
            "createdAt": Date()
        ]
        
        try await db.collection("notifications").addDocument(data: data)
    }
    
    // MARK: - Fetch Notifications
    func fetchNotifications(
        for userId: String? = nil,
        limit: Int = 50,
        unreadOnly: Bool = false
    ) async throws -> [AppNotification] {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        guard let targetUserId = targetUserId else {
            throw NSError(domain: "NotificationRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No user ID provided"])
        }
        
        var query = db.collection("notifications")
            .whereField("userId", isEqualTo: targetUserId)
        
        if unreadOnly {
            query = query.whereField("isRead", isEqualTo: false)
        }
        
        query = query.order(by: "createdAt", descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        
        return snapshot.documents.compactMap { doc in
            var notification = try? doc.data(as: AppNotification.self)
            notification?.id = doc.documentID
            return notification
        }
    }
    
    // MARK: - Mark Notifications as Read
    func markAsRead(_ notificationId: String) async throws {
        try await db.collection("notifications").document(notificationId).updateData([
            "isRead": true
        ])
    }
    
    func markAllAsRead(for userId: String? = nil) async throws {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        guard let targetUserId = targetUserId else { return }
        
        let unreadNotifications = try await db.collection("notifications")
            .whereField("userId", isEqualTo: targetUserId)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()
        
        let batch = db.batch()
        
        for doc in unreadNotifications.documents {
            batch.updateData(["isRead": true], forDocument: doc.reference)
        }
        
        if !unreadNotifications.documents.isEmpty {
            try await batch.commit()
        }
    }
    
    // MARK: - Delete Notifications
    func deleteNotification(_ notificationId: String) async throws {
        try await db.collection("notifications").document(notificationId).delete()
    }
    
    func deleteOldNotifications(olderThan days: Int = 30) async throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        let oldNotifications = try await db.collection("notifications")
            .whereField("createdAt", isLessThan: cutoffDate)
            .getDocuments()
        
        let batch = db.batch()
        
        for doc in oldNotifications.documents {
            batch.deleteDocument(doc.reference)
        }
        
        if !oldNotifications.documents.isEmpty {
            try await batch.commit()
        }
    }
    
    // MARK: - Real-time Listening
    func listenToNotifications(
        for userId: String? = nil,
        completion: @escaping ([AppNotification]) -> Void
    ) -> ListenerRegistration {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        guard let targetUserId = targetUserId else {
            completion([])
            return db.collection("notifications").limit(to: 1).addSnapshotListener { _, _ in }
        }
        
        // Remove existing listener
        notificationListener?.remove()
        
        let listener = db.collection("notifications")
            .whereField("userId", isEqualTo: targetUserId)
            .whereField("isRead", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to notifications: \(error)")
                    completion([])
                    return
                }
                
                let notifications = snapshot?.documents.compactMap { doc -> AppNotification? in
                    var notification = try? doc.data(as: AppNotification.self)
                    notification?.id = doc.documentID
                    return notification
                } ?? []
                
                completion(notifications)
            }
        
        notificationListener = listener
        return listener
    }
    
    func stopListening() {
        notificationListener?.remove()
        notificationListener = nil
    }
    
    // MARK: - Push Notifications (FCM)
    private func sendPushNotification(
        to token: String,
        title: String,
        body: String,
        data: [String: String]
    ) async {
        // This would integrate with your FCM backend service
        // For now, we'll just log it
        print("📱 Would send push notification:")
        print("  To: \(token)")
        print("  Title: \(title)")
        print("  Body: \(body)")
        print("  Data: \(data)")
        
        // In production, you would call your backend API or Cloud Function here
        // Example:
        // await FirebaseCloudMessaging.send(to: token, notification: ...)
    }
    
    // MARK: - Badge Count
    func getUnreadCount(for userId: String? = nil) async -> Int {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        guard let targetUserId = targetUserId else { return 0 }
        
        do {
            let snapshot = try await db.collection("notifications")
                .whereField("userId", isEqualTo: targetUserId)
                .whereField("isRead", isEqualTo: false)
                .count
                .getAggregation(source: .server)
            
            return Int(truncating: snapshot.count ?? 0)
        } catch {
            print("Error getting unread count: \(error)")
            return 0
        }
    }
}
