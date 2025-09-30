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
    
    // MARK: - Handle Notification Tap
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
                return .openReview(reviewId, notification.fromUserId)
            }
            
        case .reelLike, .commentLike:
            if let reelId = notification.data?["reelId"] {
                return .openReel(reelId)
            }
        }
        
        return nil
    }
    
    // MARK: - Update App Badge
    private func updateAppBadge() async {
        // This would update the app icon badge count
        // Requires AppDelegate setup with UNUserNotificationCenter
        #if !targetEnvironment(simulator)
        UNUserNotificationCenter.current().setBadgeCount(bellNotificationCount)
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
}
