// ChatView.swift
// Path: ClaudeHustlerFirebase/Views/Messages/ChatView.swift

import SwiftUI
import FirebaseFirestore
import FirebaseStorage

struct ChatView: View {
    let conversation: Conversation?
    let recipientId: String?
    let contextType: Message.MessageContextType?
    let contextId: String?
    let contextData: (title: String, image: String?, userId: String)?
    
    @StateObject private var viewModel = MessagesViewModel()
    @StateObject private var firebase = FirebaseService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var messages: [Message] = []
    @State private var messageText = ""
    @State private var isLoadingMessages = false
    @State private var showingBlockConfirmation = false
    @State private var showingClearConfirmation = false
    @State private var showingReportSheet = false
    @State private var reportMessageId: String?
    @State private var keyboardHeight: CGFloat = 0
    @State private var otherUser: User?
    @State private var currentConversationId: String?
    @State private var isFromContentView = false
    
    // Navigation states
    @State private var showingPost = false
    @State private var showingReel = false
    @State private var postToShow: ServicePost? = nil
    @State private var reelToShow: Reel? = nil
   
    // Real-time listener
    @State private var messageListener: ListenerRegistration?
    
    // For scroll view
    @Namespace private var bottomAnchor
    
    init(conversation: Conversation) {
        self.conversation = conversation
        self.recipientId = nil
        self.contextType = nil
        self.contextId = nil
        self.contextData = nil
    }
    
    init(recipientId: String,
         contextType: Message.MessageContextType? = nil,
         contextId: String? = nil,
         contextData: (title: String, image: String?, userId: String)? = nil,
         isFromContentView: Bool = false) {
        self.conversation = nil
        self.recipientId = recipientId
        self.contextType = contextType
        self.contextId = contextId
        self.contextData = contextData
        self._isFromContentView = State(initialValue: isFromContentView)
    }
    
    private var chatTitle: String {
        if let conversation = conversation {
            return conversation.otherParticipantName(currentUserId: firebase.currentUser?.id ?? "") ?? "Chat"
        } else if let otherUser = otherUser {
            return otherUser.name
        }
        return "Chat"
    }
    
    private var otherUserId: String? {
        if let conversation = conversation {
            return conversation.otherParticipantId(currentUserId: firebase.currentUser?.id ?? "")
        }
        return recipientId
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom Navigation Bar
                customNavigationBar
                
                // Messages List
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(messages) { message in
                                MessageRow(
                                    message: message,
                                    isCurrentUser: message.senderId == firebase.currentUser?.id,
                                    onContextTap: {
                                        // This should handle BOTH posts and reels
                                        if let contextType = message.contextType,
                                           let contextId = message.contextId {
                                            navigateToContent(type: contextType, id: contextId)
                                        }
                                    }
                                )
                                .id(message.id)
                            }
                            
                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchor)
                        }
                        .padding()
                    }
                    .background(Color(.systemGray6))
                    .onAppear {
                        // Initial scroll to bottom
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                scrollProxy.scrollTo(bottomAnchor, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: messages.count) { oldCount, newCount in
                        // Scroll to bottom when new messages arrive
                        if newCount > oldCount {
                            withAnimation(.easeOut(duration: 0.3)) {
                                scrollProxy.scrollTo(bottomAnchor, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Message Composer
                messageComposer
            }
            .navigationBarHidden(true)
            .onAppear {
                Task {
                    await setupChat()
                    startListeningForMessages()
                }
            }
            .onDisappear {
                stopListeningForMessages()
            }
        }
        .fullScreenCover(item: $postToShow) { post in
            PostDetailView(post: post)  // Use the real PostDetailView
        }

        .fullScreenCover(item: $reelToShow) { reel in
            ZStack(alignment: .topLeading) {
                // The full reel view
                FullScreenReelView(
                    reel: reel,
                    isCurrentReel: true,
                    onDismiss: {
                        reelToShow = nil
                    }
                )
                
                // Add a back button overlay
                VStack {
                    HStack {
                        Button(action: {
                            reelToShow = nil
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                Text("Back")
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(20)
                        }
                        .padding()
                        
                        Spacer()
                    }
                    
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var customNavigationBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
            
            // User info
            HStack(spacing: 10) {
                // Use ProfileImageView from CachedAsyncImage.swift
                ProfileImageView(imageURL: otherUser?.profileImageURL, size: 36)
                
                Text(chatTitle)
                    .font(.headline)
            }
            
            Spacer()
            
            Menu {
                Button(action: { showingBlockConfirmation = true }) {
                    Label("Block User", systemImage: "hand.raised")
                }
                
                Button(action: { showingClearConfirmation = true }) {
                    Label("Clear Chat", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
    
    // MARK: - Message Composer
    
    @ViewBuilder
    private var messageComposer: some View {
        VStack(spacing: 0) {
            // Context indicator if replying to content
            if let contextType = contextType,
               let contextData = contextData,
               isFromContentView {
                HStack {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Text("Sharing \(contextTypeString(contextType))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(contextData.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }
            
            // Input field
            HStack(spacing: 12) {
                // Text field
                HStack {
                    TextField("Message...", text: $messageText, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .lineLimit(1...5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(Color(.systemGray6))
                .cornerRadius(20)
                
                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                        .foregroundColor(messageText.isEmpty ? .gray : .white)
                        .frame(width: 36, height: 36)
                        .background(messageText.isEmpty ? Color(.systemGray4) : Color.blue)
                        .clipShape(Circle())
                }
                .disabled(messageText.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }
    
    // MARK: - Helper Functions
    
    private func setupChat() async {
        isLoadingMessages = true
        
        do {
            // Get or create conversation
            if let conversation = conversation {
                currentConversationId = conversation.id
            } else if let recipientId = recipientId {
                currentConversationId = try await viewModel.findOrCreateConversation(with: recipientId)
            }
            
            // Load other user info
            if let otherUserId = otherUserId {
                let document = try await Firestore.firestore()
                    .collection("users")
                    .document(otherUserId)
                    .getDocument()
                otherUser = try? document.data(as: User.self)
                otherUser?.id = otherUserId
            }
            
            // Initial load of messages
            if let conversationId = currentConversationId {
                await viewModel.loadMessages(for: conversationId)
                messages = viewModel.messages
                
                // Mark messages as read
                try await viewModel.markMessagesAsRead(in: conversationId)
            }
        } catch {
            print("Error setting up chat: \(error)")
        }
        
        isLoadingMessages = false
    }
    
    private func startListeningForMessages() {
        guard let conversationId = currentConversationId else { return }
        
        // Set up real-time listener
        messageListener = firebase.listenToMessages(in: conversationId) { newMessages in
            DispatchQueue.main.async {
                self.messages = newMessages
                
                // Mark new messages as read
                Task {
                    try? await self.viewModel.markMessagesAsRead(in: conversationId)
                }
            }
        }
    }
    
    private func stopListeningForMessages() {
        messageListener?.remove()
        messageListener = nil
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let recipientId = otherUserId else { return }
        
        messageText = ""  // Clear immediately for better UX
        
        Task {
            do {
                // Include context only if coming from content view
                let shouldIncludeContext = isFromContentView && contextType != nil
                
                // Send message with context if needed
                try await firebase.sendMessage(
                    to: recipientId,
                    text: text,
                    contextType: shouldIncludeContext ? contextType : nil,
                    contextId: shouldIncludeContext ? contextId : nil,
                    contextData: shouldIncludeContext ? contextData : nil
                )
                
                // Clear context after first message
                if isFromContentView {
                    isFromContentView = false
                }
                
            } catch {
                print("Error sending message: \(error)")
            }
        }
    }
    
    private func contextTypeString(_ type: Message.MessageContextType) -> String {
        switch type {
        case .post: return "post"
        case .reel: return "reel"
        case .status: return "status"
        }
    }
    
    // In ChatView.swift, update the navigateToContent function:

    private func navigateToContent(type: Message.MessageContextType, id: String) {
        Task {
            do {
                switch type {
                case .post:
                    print("DEBUG: Attempting to fetch post with ID: \(id)")
                    
                    guard let fetchedPost = try await PostRepository.shared.fetchById(id) else {
                        print("ERROR: Post not found with ID: \(id)")
                        return
                    }
                    
                    print("DEBUG: Successfully fetched post: \(fetchedPost.title)")
                    
                    await MainActor.run {
                        self.postToShow = fetchedPost
                        print("DEBUG: postToShow set, modal should open")
                    }
                    
                case .reel:
                    print("DEBUG: Attempting to fetch reel with ID: \(id)")
                    
                    guard let fetchedReel = try await ReelRepository.shared.fetchById(id) else {
                        print("ERROR: Reel not found with ID: \(id)")
                        return
                    }
                    
                    print("DEBUG: Successfully fetched reel: \(fetchedReel.title)")
                    
                    await MainActor.run {
                        self.reelToShow = fetchedReel
                        print("DEBUG: reelToShow set, modal should open")
                    }
                    
                case .status:
                    print("DEBUG: Status navigation not implemented")
                    break
                }
            } catch {
                print("ERROR: Failed to load content - \(error)")
            }
        }
    }
}

// MARK: - Message Row Component
struct MessageRow: View {
    let message: Message
    let isCurrentUser: Bool
    var onContextTap: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                // Context card if present
                if message.contextType != nil {
                    ContextPreviewCard(
                        message: message,
                        isCurrentUser: isCurrentUser,
                        onTap: onContextTap
                    )
                }
                
                // Message bubble
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isCurrentUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(isCurrentUser ? .white : .primary)
                    .cornerRadius(16)
                
                // Timestamp and read status
                HStack(spacing: 4) {
                    Text(timeString)
                        .font(.caption2)
                    
                    if isCurrentUser {
                        Image(systemName: statusIcon)
                            .font(.caption2)
                            .foregroundColor(statusColor)
                    }
                }
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: isCurrentUser ? .trailing : .leading)
            
            if !isCurrentUser {
                Spacer()
            }
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
    
    private var statusIcon: String {
        if message.isRead {
            return "checkmark.circle.fill"
        } else if message.isDelivered {
            return "checkmark.circle"
        } else {
            return "clock"
        }
    }
    
    private var statusColor: Color {
        if message.isRead {
            return .blue
        } else {
            return .secondary
        }
    }
}

// MARK: - Context Preview Card
struct ContextPreviewCard: View {
    let message: Message
    let isCurrentUser: Bool
    var onTap: (() -> Void)?
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 8) {
                // Thumbnail image if available
                if let imageURL = message.contextImage {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipped()
                            .cornerRadius(8)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: contextIcon)
                                    .foregroundColor(.gray)
                            )
                    }
                } else {
                    // Icon placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: contextIcon)
                                .foregroundColor(.gray)
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(contextTypeLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(message.contextTitle ?? "")
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundColor(isCurrentUser ? .white : .primary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(isCurrentUser ? Color.blue.opacity(0.8) : Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var contextIcon: String {
        switch message.contextType {
        case .post: return "doc.text"
        case .reel: return "play.rectangle"
        case .status: return "circle.dotted"
        case .none: return "link"
        }
    }
    
    private var contextTypeLabel: String {
        switch message.contextType {
        case .post: return "Post"
        case .reel: return "Reel"
        case .status: return "Story"
        case .none: return ""
        }
    }
}

// MARK: - Reel Detail View (Simplified)
struct ReelDetailView: View {
    let reel: Reel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Reel content
                AsyncImage(url: URL(string: reel.thumbnailURL ?? reel.videoURL)) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(height: 400)
                        .overlay(
                            ProgressView()
                        )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(reel.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(reel.description)
                        .font(.body)
                    
                    if !reel.hashtags.isEmpty {
                        Text(reel.hashtags.map { "#\($0)" }.joined(separator: " "))
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    HStack {
                        Label("\(reel.likes.count)", systemImage: "heart.fill")
                            .foregroundColor(.red)
                        
                        Label("\(reel.comments)", systemImage: "bubble.left.fill")
                            .foregroundColor(.blue)
                        
                        Label("\(reel.views)", systemImage: "eye.fill")
                            .foregroundColor(.gray)
                    }
                    .font(.caption)
                    .padding(.top)
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle("Reel")
        .navigationBarTitleDisplayMode(.inline)
    }
}
