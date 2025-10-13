// NotificationsViewModel.swift
// Path: ClaudeHustlerFirebase/ViewModels/NotificationsViewModel.swift

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0
    @Published var isLoading = false
    @Published var error: Error?
    
    private let repository = NotificationRepository.shared
    private var notificationListener: ListenerRegistration?
    static weak var shared: NotificationsViewModel?
    
    init() {
        Self.shared = self
        Task {
            await loadNotifications()
            startListening()
        }
    }
    
    // MARK: - Filtered Counts
    var bellNotificationCount: Int {
        notifications.filter { notification in
            !notification.isRead && notification.type.isBellNotification
        }.count
    }
    
    var messageNotificationCount: Int {
        notifications.filter { notification in
            !notification.isRead && (notification.type == .newMessage || notification.type == .messageRequest)
        }.count
    }
    
    // MARK: - Filtered Notifications
    func getBellNotifications() -> [AppNotification] {
        notifications.filter { $0.type.isBellNotification }
    }
    
    func getMessageNotifications() -> [AppNotification] {
        notifications.filter {
            $0.type == .newMessage || $0.type == .messageRequest
        }
    }
    
    // MARK: - Load Notifications
    func loadNotifications() async {
        isLoading = true
        error = nil
        
        do {
            let fetchedNotifications = try await repository.fetchNotifications(limit: 100)
            
            await MainActor.run {
                self.notifications = fetchedNotifications
                self.unreadCount = fetchedNotifications.filter { !$0.isRead }.count
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
            print("Error loading notifications: \(error)")
        }
    }
    
    // MARK: - Real-time Updates
    func startListening() {
        notificationListener?.remove()
        
        notificationListener = repository.listenToNotifications { [weak self] notifications in
            Task { @MainActor in
                self?.notifications = notifications
                self?.unreadCount = notifications.filter { !$0.isRead }.count
                
                print("🔔 NotificationsViewModel updated:")
                print("   Total: \(notifications.count)")
                print("   Bell count: \(self?.bellNotificationCount ?? 0)")
                print("   Message count: \(self?.messageNotificationCount ?? 0)")
                
                // Update app badge
                await self?.updateAppBadge()
            }
        }
    }
    
    func stopListening() {
        notificationListener?.remove()
        notificationListener = nil
    }
    
    // MARK: - Mark as Read
    func markAsRead(_ notification: AppNotification) async {
        guard let notificationId = notification.id else { return }
        
        do {
            try await repository.markAsRead(notificationId)
            
            // Update local state
            if let index = notifications.firstIndex(where: { $0.id == notificationId }) {
                notifications[index].isRead = true
                unreadCount = notifications.filter { !$0.isRead }.count
            }
        } catch {
            print("Error marking notification as read: \(error)")
        }
    }
    
    func markAllAsRead() async {
        do {
            try await repository.markAllAsRead()
            
            // Update local state
            for index in notifications.indices {
                notifications[index].isRead = true
            }
            unreadCount = 0
        } catch {
            print("Error marking all notifications as read: \(error)")
        }
    }
    
    // MARK: - Delete Notifications
    func deleteNotification(_ notification: AppNotification) async {
        guard let notificationId = notification.id else { return }
        
        do {
            try await repository.deleteNotification(notificationId)
            
            // Update local state
            notifications.removeAll { $0.id == notificationId }
            unreadCount = notifications.filter { !$0.isRead }.count
        } catch {
            print("Error deleting notification: \(error)")
        }
    }
    
    // NotificationsViewModel.swift - FIXED SECTION
    // Replace the handleNotificationTap method's review handling section with this:

        // MARK: - Handle Notification Tap (FIXED)
        func handleNotificationTap(_ notification: AppNotification) async -> NotificationAction? {
            // Mark as read
            await markAsRead(notification)
            
            // Determine navigation action based on type
            switch notification.type {
            case .newMessage, .messageRequest:
                if let conversationId = notification.data?["conversationId"] {
                    return .openConversation(conversationId)
                }
                
            case .newReview, .reviewReply, .reviewEdit, .helpfulVote:
                if let reviewId = notification.data?["reviewId"] {
                    // FIXED: Navigate to the correct profile
                    // For review notifications, we need to navigate to the profile that HAS the review
                    
                    let targetUserId: String
                    
                    if notification.type == .newReview {
                        // For new reviews: The notification recipient (YOU) received a review on YOUR profile
                        // So navigate to YOUR profile to see the review someone left for you
                        targetUserId = notification.userId  // The person receiving the notification
                    } else if notification.type == .reviewReply || notification.type == .reviewEdit {
                        // For replies/edits: The review exists on the profile being reviewed
                        // Check if we stored the profile owner's ID in the notification data
                        if let profileUserId = notification.data?["profileUserId"] as? String {
                            targetUserId = profileUserId
                        } else {
                            // Fallback: assume it's on the notification recipient's profile
                            targetUserId = notification.userId
                        }
                    } else if notification.type == .helpfulVote {
                        // For helpful votes: The person who wrote the review gets notified
                        // The review exists on some profile (not necessarily theirs)
                        // We need to store and retrieve which profile has this review
                        if let profileUserId = notification.data?["profileUserId"] as? String {
                            targetUserId = profileUserId
                        } else {
                            // Fallback: check if it's the recipient's own profile
                            targetUserId = notification.userId
                        }
                    } else {
                        // Default fallback
                        targetUserId = notification.userId
                    }
                    
                    return .openReview(reviewId, targetUserId)
                }
                
            case .reelLike:
                if let reelId = notification.data?["reelId"] {
                    return .openReel(reelId)
                }
                
            case .reelComment, .commentLike, .commentReply:
                if let reelId = notification.data?["reelId"],
                   let commentId = notification.data?["commentId"] {
                    return .openReelComment(reelId, commentId)
                } else if let reelId = notification.data?["reelId"] {
                    // Fallback if no comment ID
                    return .openReel(reelId)
                }
            }
            
            return nil
        }

    // IMPORTANT: Also update the notification creation to include profileUserId
    // When creating review-related notifications, make sure to add:
    // "profileUserId": profileOwnerId  // The ID of the user whose profile has the review
    
    // MARK: - Update App Badge
    private func updateAppBadge() async {
        // This would update the app icon badge count
        // Requires AppDelegate setup with UNUserNotificationCenter
        #if !targetEnvironment(simulator)
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(bellNotificationCount)
        }
        #endif
    }
    
    // MARK: - Refresh
    func refresh() async {
        await loadNotifications()
    }
    
    // MARK: - Clean Up
    func cleanup() {
        stopListening()
    }
    
    deinit {
        // Use Task.detached for cleanup
        let listenerToClean = notificationListener
        Task.detached {
            listenerToClean?.remove()
        }
    }
}

// MARK: - Notification Action
enum NotificationAction {
    case openConversation(String)
    case openReview(String, String) // reviewId, userId
    case openProfile(String)
    case openReel(String)
    case openReelComment(String, String) // reelId, commentId
}
