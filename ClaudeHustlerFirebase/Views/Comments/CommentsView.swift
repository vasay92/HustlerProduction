// CommentsView.swift
// Path: ClaudeHustlerFirebase/Views/Comments/CommentsView.swift

import SwiftUI
import FirebaseFirestore

struct CommentsView: View {
    let reelId: String
    let reelOwnerId: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var comments: [Comment] = []
    @State private var commentText = ""
    @State private var isLoading = false
    @State private var replyingTo: Comment?
    @State private var showDeleteConfirmation = false
    @State private var commentToDelete: Comment?
    @State private var listener: ListenerRegistration?
    // ADD THESE:
    @State private var showingAuthPrompt = false
    @State private var authPromptAction = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Comments")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button("Done") {
                        dismiss()
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .overlay(
                    Divider(),
                    alignment: .bottom
                )
                
                // Comments List
                if isLoading && comments.isEmpty {
                    Spacer()
                    ProgressView("Loading comments...")
                    Spacer()
                } else if comments.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No comments yet")
                            .foregroundColor(.secondary)
                        Text("Be the first to comment!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(comments.filter { $0.parentCommentId == nil }) { comment in
                                CommentCell(
                                    comment: comment,
                                    reelOwnerId: reelOwnerId,
                                    onReply: { replyingTo = comment },
                                    onDelete: {
                                        commentToDelete = comment
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
                
                // Reply indicator
                if let replyingTo = replyingTo {
                    HStack {
                        Text("Replying to \(replyingTo.userName ?? "User")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Cancel") {
                            self.replyingTo = nil
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                }
                
                // Input Section
                HStack(spacing: 12) {
                    UserAvatar(
                        imageURL: firebase.currentUser?.profileImageURL,
                        userName: firebase.currentUser?.name,
                        size: 32
                    )
                    
                    HStack {
                        TextField(
                            replyingTo != nil ? "Add a reply..." : "Add a comment...",
                            text: $commentText
                        )
                        .textFieldStyle(PlainTextFieldStyle())
                        
                        if !commentText.isEmpty {
                            Button(action: postComment) {
                                Image(systemName: "paperplane.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationBarHidden(true)
            .confirmationDialog(
                "Delete Comment?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let comment = commentToDelete {
                        Task {
                            await deleteComment(comment)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                startListeningToComments()
            }
            .onDisappear {
                listener?.remove()
                CommentRepository.shared.stopListeningToComments(reelId)
            }
        }
    }
    
    private func startListeningToComments() {
        isLoading = true
        
        // Use CommentRepository's listener instead of direct Firestore
        listener = CommentRepository.shared.listenToComments(for: reelId) { fetchedComments in
            self.comments = fetchedComments
            self.isLoading = false
        }
    }
    
    private func postComment() {
        let trimmedText = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        Task {
            do {
                // Use the existing postComment method from CommentRepository
                _ = try await CommentRepository.shared.postComment(
                    on: reelId,
                    text: trimmedText,
                    parentCommentId: replyingTo?.id
                )
                
                // Clear the input fields
                await MainActor.run {
                    commentText = ""
                    replyingTo = nil
                }
                
                // Note: The CommentRepository.postComment method already handles:
                // - Updating the comment count on the reel
                // - Updating the reply count on parent comments
                
            } catch {
                
            }
        }
    }
    
    private func deleteComment(_ comment: Comment) async {
        guard let commentId = comment.id else { return }
        
        do {
            // Use the existing deleteComment method from CommentRepository
            try await CommentRepository.shared.deleteComment(commentId, reelId: reelId)
            
            // Note: The CommentRepository.deleteComment method already handles:
            // - Checking permissions (owner or reel owner can delete)
            // - Updating the comment count on the reel
            // - Updating the reply count on parent comments
            // - Soft deleting the comment
            
        } catch {
           
        }
    }
}

// MARK: - Comment Cell

struct CommentCell: View {
    let comment: Comment
    let reelOwnerId: String
    let onReply: () -> Void
    let onDelete: () -> Void
    
    @StateObject private var firebase = FirebaseService.shared
    @State private var isLiked = false
    @State private var replies: [Comment] = []
    @State private var showReplies = false
    @State private var showingAuthPrompt = false
    @State private var authPromptAction = ""
    var canDelete: Bool {
        comment.userId == firebase.currentUser?.id || reelOwnerId == firebase.currentUser?.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // Profile image with navigation
                NavigationLink(destination: EnhancedProfileView(userId: comment.userId)) {
                    UserAvatar(
                        imageURL: comment.userProfileImage,
                        userName: comment.userName,
                        size: 32
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                VStack(alignment: .leading, spacing: 4) {
                    // Username and comment
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.userName ?? "User")
                            .font(.footnote)
                            .fontWeight(.semibold)
                        
                        Text(comment.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Actions
                    HStack(spacing: 16) {
                        Text(timeAgo(from: comment.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            if firebase.isAuthenticated {
                                toggleLike()
                            } else {
                                authPromptAction = "Like Comments"
                                showingAuthPrompt = true
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.caption)
                                if comment.likes.count > 0 {
                                    Text("\(comment.likes.count)")
                                        .font(.caption2)
                                }
                            }
                            .foregroundColor(isLiked ? .red : .secondary)
                        }
                        
                        Button("Reply") {
                            if firebase.isAuthenticated {
                                onReply()
                            } else {
                                authPromptAction = "Reply to Comments"
                                showingAuthPrompt = true
                            }
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        
                        if canDelete {
                            Button("Delete") {
                                onDelete()
                            }
                            .font(.caption2)
                            .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
            }
            
            // Show replies button
            if comment.replyCount > 0 {
                Button(action: {
                    showReplies.toggle()
                    if showReplies && replies.isEmpty {
                        loadReplies()
                    }
                }) {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 2, height: 12)
                            .offset(x: 16)
                        
                        Text(showReplies ? "Hide replies" : "View \(comment.replyCount) replies")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                // Replies
                if showReplies {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(replies) { reply in
                            ReplyCell(
                                comment: reply,
                                reelOwnerId: reelOwnerId,
                                onReply: onReply,
                                onDelete: onDelete
                            )
                            .padding(.leading, 40)
                        }
                    }
                }
            }
        }
        .onAppear {
            isLiked = comment.likes.contains(firebase.currentUser?.id ?? "")
        }
        .sheet(isPresented: $showingAuthPrompt) {
            AuthenticationPromptView(action: authPromptAction)
        }
    }
    
    private func toggleLike() {
        guard let commentId = comment.id else { return }
        
        Task {
            do {
                if isLiked {
                    try await CommentRepository.shared.unlikeComment(commentId)
                } else {
                    try await CommentRepository.shared.likeComment(commentId)
                }
                
                await MainActor.run {
                    isLiked.toggle()
                }
            } catch {
                
            }
        }
    }
    
    private func loadReplies() {
        guard let commentId = comment.id else { return }
        
        Task {
            do {
                let snapshot = try await Firestore.firestore()
                    .collection("comments")
                    .whereField("parentCommentId", isEqualTo: commentId)
                    .order(by: "timestamp", descending: false)
                    .getDocuments()
                
                let loadedReplies = snapshot.documents.compactMap { doc in
                    var reply = try? doc.data(as: Comment.self)
                    reply?.id = doc.documentID
                    return reply
                }
                
                await MainActor.run {
                    self.replies = loadedReplies
                }
            } catch {
                
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
        
}

// MARK: - Reply Cell

struct ReplyCell: View {
    let comment: Comment
    let reelOwnerId: String
    let onReply: () -> Void
    let onDelete: () -> Void
    
    @StateObject private var firebase = FirebaseService.shared
    
    var canDelete: Bool {
        comment.userId == firebase.currentUser?.id || reelOwnerId == firebase.currentUser?.id
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Profile image
            NavigationLink(destination: EnhancedProfileView(userId: comment.userId)) {
                UserAvatar(
                    imageURL: comment.userProfileImage,
                    userName: comment.userName,
                    size: 24
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(comment.userName ?? "User")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Text("• \(timeAgo(from: comment.timestamp))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text(comment.text)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                
                if canDelete {
                    Button("Delete") {
                        onDelete()
                    }
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(.top, 2)
                }
            }
            
            Spacer()
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
