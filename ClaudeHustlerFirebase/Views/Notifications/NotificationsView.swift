// NotificationsView.swift
// Path: ClaudeHustlerFirebase/Views/Notifications/NotificationsView.swift

import SwiftUI

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    @State private var showingDeleteAlert = false
    @State private var notificationToDelete: AppNotification?
    
    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.notifications.isEmpty && !viewModel.isLoading {
                    EmptyNotificationsView()
                } else {
                    notificationsList
                }
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.notifications.isEmpty {
                        Menu {
                            Button(action: {
                                Task {
                                    await viewModel.markAllAsRead()
                                }
                            }) {
                                Label("Mark All as Read", systemImage: "checkmark.circle")
                            }
                            
                            Button(role: .destructive, action: {
                                Task {
                                    await clearOldNotifications()
                                }
                            }) {
                                Label("Clear Old Notifications", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.loadNotifications()
            }
        }
        .alert("Delete Notification", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let notification = notificationToDelete {
                    Task {
                        await viewModel.deleteNotification(notification)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this notification?")
        }
    }
    
    private var notificationsList: some View {
        List {
            ForEach(groupedNotifications(), id: \.0) { date, notifications in
                Section(header: Text(sectionHeader(for: date))) {
                    ForEach(notifications) { notification in
                        NotificationRow(
                            notification: notification,
                            onTap: {
                                Task {
                                    if let action = await viewModel.handleNotificationTap(notification) {
                                        handleNavigation(action)
                                    }
                                }
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                notificationToDelete = notification
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if !notification.isRead {
                                Button {
                                    Task {
                                        await viewModel.markAsRead(notification)
                                    }
                                } label: {
                                    Label("Mark as Read", systemImage: "checkmark.circle")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    private func groupedNotifications() -> [(Date, [AppNotification])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: viewModel.notifications) { notification in
            calendar.startOfDay(for: notification.createdAt)
        }
        return grouped.sorted { $0.key > $1.key }
    }
    
    private func sectionHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    private func handleNavigation(_ action: NotificationAction) {
        switch action {
        case .openConversation(let conversationId):
            // Navigate to ChatView with conversationId
            print("Navigate to conversation: \(conversationId)")
            
        case .openReview(let reviewId, let userId):
            // Navigate to user profile with review highlighted
            print("Navigate to review: \(reviewId) for user: \(userId)")
            
        case .openProfile(let userId):
            // Navigate to user profile
            print("Navigate to profile: \(userId)")
        }
    }
    
    private func clearOldNotifications() async {
        do {
            try await NotificationRepository.shared.deleteOldNotifications(olderThan: 30)
            await viewModel.loadNotifications()
        } catch {
            print("Error clearing old notifications: \(error)")
        }
    }
}

// MARK: - Notification Row
struct NotificationRow: View {
    let notification: AppNotification
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Profile Image
                if let imageURL = notification.fromUserProfileImage {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                }
                
                // Notification Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(.headline)
                        .foregroundColor(notification.isRead ? .secondary : .primary)
                        .lineLimit(1)
                    
                    Text(notification.body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    Text(timeAgo(from: notification.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Type Icon
                Image(systemName: notification.type.icon)
                    .foregroundColor(iconColor(for: notification.type))
                    .font(.system(size: 20))
                
                // Unread Indicator
                if !notification.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconColor(for type: AppNotification.NotificationType) -> Color {
        switch type {
        case .newReview, .reviewReply, .reviewEdit:
            return .yellow
        case .helpfulVote:
            return .green
        case .newMessage, .messageRequest:
            return .blue
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Empty State View
struct EmptyNotificationsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Notifications")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("When you receive notifications about messages or reviews, they'll appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NotificationsView()
}
