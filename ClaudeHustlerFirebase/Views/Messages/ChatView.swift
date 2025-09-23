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
    
    // Navigation states - Updated with all three types
    @State private var postToShow: ServicePost? = nil
    @State private var reelToShow: Reel? = nil
    @State private var statusToShow: Status? = nil
   
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
                
                // Messages List with improved scroll behavior
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(messages) { message in
                                MessageRow(
                                    message: message,
                                    isCurrentUser: message.senderId == firebase.currentUser?.id,
                                    onContextTap: {
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
                    .onChange(of: messages.count) { oldCount, newCount in
                        // Scroll to bottom when messages count changes
                        if newCount > oldCount {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    scrollProxy.scrollTo(bottomAnchor, anchor: .bottom)
                                }
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
            .confirmationDialog("Clear Chat?", isPresented: $showingClearConfirmation) {
                Button("Clear All Messages", role: .destructive) {
                    Task {
                        await clearChat()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all messages in this conversation. This action cannot be undone.")
            }
        }
        .fullScreenCover(item: $postToShow) { post in
            PostDetailView(post: post)
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
        .fullScreenCover(item: $statusToShow) { status in
            StatusViewerView(status: status)
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
    
    private func clearChat() async {
        guard let conversationId = currentConversationId else { return }
        
        do {
            // Clear messages from Firebase
            let messagesQuery = try await Firestore.firestore()
                .collection("messages")
                .whereField("conversationId", isEqualTo: conversationId)
                .getDocuments()
            
            let batch = Firestore.firestore().batch()
            
            for doc in messagesQuery.documents {
                batch.deleteDocument(doc.reference)
            }
            
            try await batch.commit()
            
            // Clear local messages
            messages = []
            
            // Update conversation's last message
            try await Firestore.firestore()
                .collection("conversations")
                .document(conversationId)
                .updateData([
                    "lastMessage": "",
                    "lastMessageTimestamp": Date(),
                    "lastMessageSenderId": ""
                ])
            
        } catch {
            print("Error clearing chat: \(error)")
        }
    }
    
    private func contextTypeString(_ type: Message.MessageContextType) -> String {
        switch type {
        case .post: return "post"
        case .reel: return "reel"
        case .status: return "status"
        }
    }
    
    private func navigateToContent(type: Message.MessageContextType, id: String) {
        Task {
            do {
                switch type {
                case .post:
                    print("DEBUG: Attempting to fetch post with ID: \(id)")
                    
                    guard let fetchedPost = try await PostRepository.shared.fetchById(id) else {
                        print("ERROR: Post not found with ID: \(id)")
                        
                        await MainActor.run {
                            showContentUnavailableAlert(type: "Post")
                        }
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
                        
                        await MainActor.run {
                            showContentUnavailableAlert(type: "Reel")
                        }
                        return
                    }
                    
                    print("DEBUG: Successfully fetched reel: \(fetchedReel.title)")
                    
                    await MainActor.run {
                        self.reelToShow = fetchedReel
                        print("DEBUG: reelToShow set, modal should open")
                    }
                    
                case .status:
                    print("DEBUG: Attempting to fetch status with ID: \(id)")
                    
                    guard let fetchedStatus = try await StatusRepository.shared.fetchById(id) else {
                        print("ERROR: Status not found with ID: \(id)")
                        
                        await MainActor.run {
                            showContentUnavailableAlert(type: "Status")
                        }
                        return
                    }
                    
                    print("DEBUG: Successfully fetched status from user: \(fetchedStatus.userName ?? "Unknown")")
                    
                    await MainActor.run {
                        self.statusToShow = fetchedStatus
                        print("DEBUG: statusToShow set, modal should open")
                    }
                }
            } catch {
                print("ERROR: Failed to load content - \(error)")
                
                await MainActor.run {
                    showContentErrorAlert()
                }
            }
        }
    }
    
    private func showContentUnavailableAlert(type: String) {
        let alert = UIAlertController(
            title: "\(type) Unavailable",
            message: "This \(type.lowercased()) has been deleted or is no longer available.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func showContentErrorAlert() {
        let alert = UIAlertController(
            title: "Error",
            message: "Unable to load content. Please try again later.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
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
                    ContentPreviewCard(
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
