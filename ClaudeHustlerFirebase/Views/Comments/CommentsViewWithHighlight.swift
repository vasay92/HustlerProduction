// CommentsViewWithHighlight.swift
// Path: ClaudeHustlerFirebase/Views/Comments/CommentsViewWithHighlight.swift

import SwiftUI
import FirebaseFirestore

struct CommentsViewWithHighlight: View {
    let reelId: String
    let reelOwnerId: String
    let highlightCommentId: String?
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var comments: [Comment] = []
    @State private var commentText = ""
    @State private var isLoading = false
    @State private var replyingTo: Comment?
    @State private var showDeleteConfirmation = false
    @State private var commentToDelete: Comment?
    @State private var listener: ListenerRegistration?
    
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
                
                // Comments List with ScrollViewReader
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
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(comments.filter { $0.parentCommentId == nil }) { comment in
                                    CommentCellWithHighlight(
                                        comment: comment,
                                        reelOwnerId: reelOwnerId,
                                        isHighlighted: comment.id == highlightCommentId,
                                        onReply: { replyingTo = comment },
                                        onDelete: {
                                            commentToDelete = comment
                                            showDeleteConfirmation = true
                                        },
                                        highlightCommentId: highlightCommentId
                                    )
                                    .id(comment.id)
                                }
                            }
                            .padding()
                            .onAppear {
                                // Scroll to highlighted comment after delay
                                if let highlightId = highlightCommentId {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo(highlightId, anchor: .center)
                                        }
                                    }
                                }
                            }
                        }
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
                _ = try await CommentRepository.shared.postComment(
                    on: reelId,
                    text: trimmedText,
                    parentCommentId: replyingTo?.id
                )
                
                await MainActor.run {
                    commentText = ""
                    replyingTo = nil
                }
            } catch {
                print("Error posting comment: \(error)")
            }
        }
    }
    
    private func deleteComment(_ comment: Comment) async {
        guard let commentId = comment.id else { return }
        
        do {
            try await CommentRepository.shared.deleteComment(commentId, reelId: reelId)
        } catch {
            print("Error deleting comment: \(error)")
        }
    }
}

// MARK: - Comment Cell with Highlight
struct CommentCellWithHighlight: View {
    let comment: Comment
    let reelOwnerId: String
    let isHighlighted: Bool
    let onReply: () -> Void
    let onDelete: () -> Void
    let highlightCommentId: String?
    
    @StateObject private var firebase = FirebaseService.shared
    @State private var isLiked = false
    @State private var replies: [Comment] = []
    @State private var showReplies = false
    @State private var highlightAnimation = false
    
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
                        
                        Button(action: { toggleLike() }) {
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
                            onReply()
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
            }
            
            // Replies
            if showReplies {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(replies) { reply in
                        ReplyCellWithHighlight(
                            comment: reply,
                            reelOwnerId: reelOwnerId,
                            isHighlighted: reply.id == highlightCommentId,
                            onReply: onReply,
                            onDelete: onDelete
                        )
                        .padding(.leading, 40)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHighlighted && highlightAnimation ? Color.blue.opacity(0.2) : Color.clear)
                .animation(.easeInOut(duration: 0.5), value: highlightAnimation)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHighlighted && highlightAnimation ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
                .animation(.easeInOut(duration: 0.5), value: highlightAnimation)
        )
        .onAppear {
            isLiked = comment.likes.contains(firebase.currentUser?.id ?? "")
            if isHighlighted {
                // Trigger highlight animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    highlightAnimation = true
                    // Fade out after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 1)) {
                            highlightAnimation = false
                        }
                    }
                }
            }
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
                print("Error toggling like: \(error)")
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
                print("Error loading replies: \(error)")
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Reply Cell with Highlight
struct ReplyCellWithHighlight: View {
    let comment: Comment
    let reelOwnerId: String
    let isHighlighted: Bool
    let onReply: () -> Void
    let onDelete: () -> Void
    
    @StateObject private var firebase = FirebaseService.shared
    @State private var highlightAnimation = false
    
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
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted && highlightAnimation ? Color.blue.opacity(0.2) : Color.clear)
                .animation(.easeInOut(duration: 0.5), value: highlightAnimation)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHighlighted && highlightAnimation ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1.5)
                .animation(.easeInOut(duration: 0.5), value: highlightAnimation)
        )
        .onAppear {
            if isHighlighted {
                // Trigger highlight animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    highlightAnimation = true
                    // Fade out after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 1)) {
                            highlightAnimation = false
                        }
                    }
                }
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
