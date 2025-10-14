// NotificationsView.swift
// Path: ClaudeHustlerFirebase/Views/Notifications/NotificationsView.swift

import SwiftUI
import FirebaseFirestore

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    @State private var showingDeleteAlert = false
    @State private var notificationToDelete: AppNotification?
    @State private var selectedReelId: String?
    @State private var selectedCommentId: String?
    @State private var showingReel = false
    @State private var showingReelWithComment = false
    @State private var selectedConversationId: String?
    @State private var showingConversation = false
    @State private var selectedUserId: String?
    @State private var showingProfile = false
    @State private var selectedReviewId: String?  // ADDED
    @State private var selectedReviewUserId: String?  // ADDED
    @State private var showingReview = false  // ADDED
    @Environment(\.dismiss) var dismiss
    
    // Filter to show only bell notifications
    private var filteredNotifications: [AppNotification] {
        viewModel.getBellNotifications()
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading {
                    ProgressView("Loading notifications...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredNotifications.isEmpty {
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
                    if !filteredNotifications.isEmpty {
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
        .fullScreenCover(isPresented: $showingReel) {
            if let reelId = selectedReelId {
                ReelFullScreenPresenter(reelId: reelId)
            }
        }
        .fullScreenCover(isPresented: $showingReelWithComment) {
            if let reelId = selectedReelId {
                ReelWithCommentPresenter(
                    reelId: reelId,
                    commentId: selectedCommentId
                )
            }
        }
        .fullScreenCover(isPresented: $showingConversation) {
            if let conversationId = selectedConversationId {
                NavigationView {
                    if let conversation = loadConversation(conversationId) {
                        ChatView(conversation: conversation)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingProfile) {
            if let userId = selectedUserId {
                NavigationView {
                    UserProfileView(userId: userId)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Close") {
                                    showingProfile = false
                                }
                            }
                        }
                }
            }
        }
        .fullScreenCover(isPresented: $showingReview) {  // ADDED
            if let userId = selectedReviewUserId {
                NavigationView {
                    EnhancedProfileView(
                        userId: userId,
                        highlightReviewId: selectedReviewId  // Pass the review ID to highlight
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") {
                                showingReview = false
                            }
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
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                notificationToDelete = notification
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
    }
    
    private func groupedNotifications() -> [(Date, [AppNotification])] {
        let grouped = Dictionary(grouping: filteredNotifications) { notification in
            Calendar.current.startOfDay(for: notification.createdAt)
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
    
    // UPDATED handleNavigation
    private func handleNavigation(_ action: NotificationAction) {
        switch action {
        case .openReel(let reelId):
            selectedReelId = reelId
            selectedCommentId = nil
            showingReel = true
            
        case .openReelComment(let reelId, let commentId):
            selectedReelId = reelId
            selectedCommentId = commentId
            showingReelWithComment = true
            
        case .openConversation(let conversationId):
            selectedConversationId = conversationId
            showingConversation = true
            
        case .openReview(let reviewId, let userId):  // UPDATED
            selectedReviewId = reviewId
            selectedReviewUserId = userId
            showingReview = true
            
        case .openProfile(let userId):
            selectedUserId = userId
            showingProfile = true
        }
    }
    
    private func loadConversation(_ conversationId: String) -> Conversation? {
        // This would need to be async in reality, but for now return nil
        // You'd implement proper conversation loading here
        return nil
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
                
                // Thumbnail for reel notifications
                if notification.type == .reelLike ||
                   notification.type == .reelComment ||
                   notification.type == .commentLike ||
                   notification.type == .commentReply {
                    if let thumbnailURL = notification.data?["targetImage"],
                       !thumbnailURL.isEmpty {
                        AsyncImage(url: URL(string: thumbnailURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Image(systemName: "play.rectangle.fill")
                                        .foregroundColor(.gray)
                                )
                        }
                    }
                } else {
                    // Type icon for non-reel notifications
                    Image(systemName: notification.type.icon)
                        .font(.caption)
                        .foregroundColor(iconColor)
                        .frame(width: 30, height: 30)
                        .background(iconColor.opacity(0.1))
                        .clipShape(Circle())
                }
                
                // Unread indicator
                if !notification.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
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
            if let reelTitle = notification.data?["targetTitle"], !reelTitle.isEmpty {
                return "liked your reel: \(reelTitle)"
            }
            return "liked your reel"
        case .reelComment:
            return "commented on your reel"
        case .commentLike:
            return "liked your comment"
        case .commentReply:
            return "replied to your comment"
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
        case .reelComment, .commentLike, .commentReply:
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

// MARK: - ReelFullScreenPresenter
struct ReelFullScreenPresenter: View {
    let reelId: String
    @StateObject private var viewModel = ReelsViewModel()
    @State private var reel: Reel?
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Group {
            if let reel = reel {
                // Use the same viewer as the main app
                VerticalReelScrollView(
                    reels: [reel],
                    initialIndex: 0,
                    viewModel: viewModel
                )
            } else if isLoading {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            } else {
                // Error state
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack {
                        Text("Could not load reel")
                            .foregroundColor(.white)
                        Button("Close") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                    }
                }
            }
        }
        .task {
            do {
                reel = try await ReelRepository.shared.fetchById(reelId)
                isLoading = false
            } catch {
                print("Error loading reel: \(error)")
                isLoading = false
            }
        }
    }
}

// MARK: - ReelWithCommentPresenter
struct ReelWithCommentPresenter: View {
    let reelId: String
    let commentId: String?
    
    @State private var reel: Reel?
    @State private var isLoading = true
    @State private var showComments = false
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = ReelsViewModel()
    
    var body: some View {
        Group {
            if let reel = reel {
                VerticalReelScrollView(
                    reels: [reel],
                    initialIndex: 0,
                    viewModel: viewModel
                )
                .onAppear {
                    // Auto-open comments after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showComments = true
                    }
                }
                .sheet(isPresented: $showComments) {
                    CommentsViewWithHighlight(
                        reelId: reelId,
                        reelOwnerId: reel.userId,
                        highlightCommentId: commentId
                    )
                }
            } else if isLoading {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack {
                        Text("Could not load reel")
                            .foregroundColor(.white)
                        Button("Close") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                    }
                }
            }
        }
        .task {
            do {
                reel = try await ReelRepository.shared.fetchById(reelId)
                isLoading = false
            } catch {
                print("Error loading reel: \(error)")
                isLoading = false
            }
        }
    }
}
