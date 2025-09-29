// NotificationsView.swift
// Path: ClaudeHustlerFirebase/Views/Notifications/NotificationsView.swift

import SwiftUI
import FirebaseFirestore

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    @State private var showingDeleteAlert = false
    @State private var notificationToDelete: AppNotification?
    @Environment(\.dismiss) var dismiss
    
    // FILTER TO SHOW ONLY BELL NOTIFICATIONS (THIS IS THE KEY CHANGE)
    private var filteredNotifications: [AppNotification] {
        viewModel.getBellNotifications()
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading {
                    ProgressView("Loading notifications...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredNotifications.isEmpty {  // USE FILTERED
                    emptyStateView
                } else {
                    notificationsList
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !filteredNotifications.isEmpty {  // USE FILTERED
                        Menu {
                            Button(action: {
                                Task {
                                    await viewModel.markAllAsRead()
                                }
                            }) {
                                Label("Mark All as Read", systemImage: "checkmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .alert("Delete Notification", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
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
        .refreshable {
            await viewModel.refresh()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Notifications")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("When someone interacts with your content, you'll see it here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
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
        .listStyle(PlainListStyle())
    }
    
    // Group notifications by date - NOW USES FILTERED NOTIFICATIONS
    private func groupedNotifications() -> [(Date, [AppNotification])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredNotifications) { notification in
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
        dismiss()
        
        // Handle navigation based on action type
        // This would typically be handled by a navigation coordinator
        // For now, we'll dismiss and let the parent handle navigation
    }
}

// MARK: - Notification Row
struct NotificationRow: View {
    let notification: AppNotification
    let onTap: () -> Void
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // User Avatar
                UserAvatar(
                    imageURL: notification.fromUserProfileImage,
                    userName: notification.fromUserName,
                    size: 44
                )
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Main text with name highlighted
                    Text(attributedNotificationText)
                        .font(.subheadline)
                        .lineLimit(2)
                        .foregroundColor(notification.isRead ? .secondary : .primary)
                    
                    // Time
                    Text(timeAgo(from: notification.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Type icon
                Image(systemName: notification.type.icon)
                    .font(.caption)
                    .foregroundColor(iconColor)
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(notification.isRead ? Color.clear : Color.blue.opacity(0.05))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var attributedNotificationText: AttributedString {
        var text = AttributedString(notification.fromUserName)
        text.font = .subheadline.weight(.semibold)
        
        var bodyText = AttributedString(" " + notificationBodyText)
        bodyText.font = .subheadline
        
        return text + bodyText
    }
    
    private var notificationBodyText: String {
        switch notification.type {
        case .newReview:
            return "left you a review"
        case .reviewReply:
            return "replied to your review"
        case .reviewEdit:
            return "edited their review"
        case .helpfulVote:
            return "found your review helpful"
        case .reelLike:
            return "liked your reel"
        case .commentLike:
            return "liked your comment"
        case .newMessage, .messageRequest:
            // These won't appear here because they're filtered out
            return ""
        }
    }
    
    private var iconColor: Color {
        switch notification.type {
        case .newReview, .reviewReply, .reviewEdit:
            return .yellow
        case .helpfulVote:
            return .green
        case .reelLike:
            return .red
        case .commentLike:
            return .blue
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

// MARK: - Preview
struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsView()
    }
}
