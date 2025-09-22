// ChatView.swift
// Path: ClaudeHustlerFirebase/Views/Messages/ChatView.swift

import SwiftUI
import FirebaseFirestore

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
    @State private var scrollToBottom = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var otherUser: User?
    @State private var currentConversationId: String?
    @State private var isFromContentView = false
    
    // Navigation context for returning from content
    @State private var navigatingToContent = false
    @State private var selectedContentMessage: Message?
    
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
                                    isCurrentUser: message.senderId == firebase.currentUser?.id
                                ) {
                                    // Context tap action
                                    if let contextType = message.contextType,
                                       let contextId = message.contextId {
                                        navigateToContent(type: contextType, id: contextId)
                                    }
                                }
                                .id(message.id)
                            }
                            
                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchor)
                        }
                        .padding()
                    }
                    .background(Color(.systemGray6))
                    .onChange(of: messages.count) { _ in
                        withAnimation {
                            scrollProxy.scrollTo(bottomAnchor, anchor: .bottom)
                        }
                    }
                    .onChange(of: scrollToBottom) { shouldScroll in
                        if shouldScroll {
                            withAnimation {
                                scrollProxy.scrollTo(bottomAnchor, anchor: .bottom)
                            }
                            scrollToBottom = false
                        }
                    }
                }
                
                // Message Composer
                messageComposer
            }
            .navigationBarHidden(true)
            .task {
                await setupChat()
            }
            .onDisappear {
                viewModel.stopListeningToMessages()
            }
        }
    }
    
    // MARK: - Custom Navigation Bar
    
    @ViewBuilder
    private var customNavigationBar: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    if isFromContentView {
                        Text("Back")
                            .font(.subheadline)
                    }
                }
                .foregroundColor(.blue)
            }
            
            // User info
            if let otherUser = otherUser {
                NavigationLink(destination: EnhancedProfileView(userId: otherUser.id ?? "")) {
                    HStack(spacing: 10) {
                        // Profile image
                        if let imageURL = otherUser.profileImageURL {
                            AsyncImage(url: URL(string: imageURL)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                            } placeholder: {
                                profileImagePlaceholder
                            }
                        } else {
                            profileImagePlaceholder
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(otherUser.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Tap for profile")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text(chatTitle)
                    .font(.headline)
            }
            
            Spacer()
            
            // More options
            Menu {
                Button(action: { showingClearConfirmation = true }) {
                    Label("Clear Chat", systemImage: "trash")
                }
                
                Divider()
                
                Button(action: { showingBlockConfirmation = true }) {
                    Label("Block User", systemImage: "hand.raised.fill")
                }
                
                Button(action: {
                    reportMessageId = nil
                    showingReportSheet = true
                }) {
                    Label("Report Conversation", systemImage: "flag.fill")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 2)
    }
    
    private var profileImagePlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 36, height: 36)
            .overlay(
                Text(String(otherUser?.name.first ?? "U"))
                    .font(.subheadline)
                    .foregroundColor(.white)
            )
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
                print("DEBUG - Using existing conversation: \(conversation.id ?? "nil")")
            } else if let recipientId = recipientId {
                print("DEBUG - Creating/finding conversation with recipient: \(recipientId)")
                currentConversationId = try await viewModel.findOrCreateConversation(with: recipientId)
                print("DEBUG - Got conversation ID: \(currentConversationId ?? "nil")")
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
            
            // Load messages through viewModel
            if let conversationId = currentConversationId {
                await viewModel.loadMessages(for: conversationId)
                messages = viewModel.messages
                
                // Trigger scroll to bottom after messages load
                if !messages.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.scrollToBottom = true
                    }
                }
                
                // Mark messages as read
                try await viewModel.markMessagesAsRead(in: conversationId)
                
                // Start listening for new messages
                viewModel.listenToMessages(in: conversationId) { newMessages in
                    DispatchQueue.main.async {
                        self.messages = newMessages
                    }
                }
            }
        } catch {
            print("Error setting up chat: \(error)")
        }
        
        isLoadingMessages = false
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let recipientId = otherUserId else { return }
        
        Task {
            do {
                // Include context only if coming from content view
                let shouldIncludeContext = isFromContentView && contextType != nil
                
                try await viewModel.sendMessage(
                    to: recipientId,
                    text: text,
                    contextType: shouldIncludeContext ? contextType : nil,
                    contextId: shouldIncludeContext ? contextId : nil,
                    contextData: shouldIncludeContext ? contextData : nil
                )
                
                messageText = ""
                
                // Reload messages
                if let conversationId = currentConversationId {
                    await viewModel.loadMessages(for: conversationId)
                    messages = viewModel.messages
                }
                
                // Scroll to bottom
                scrollToBottom = true
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
    
    private func navigateToContent(type: Message.MessageContextType, id: String) {
        // Handle navigation to content based on type
        selectedContentMessage = messages.first { $0.contextId == id }
        navigatingToContent = true
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
                    Button(action: {
                        onContextTap?()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: contextIcon)
                                .font(.caption)
                            
                            if let title = message.contextTitle {
                                Text(title)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                        .padding(8)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Message bubble
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isCurrentUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(isCurrentUser ? .white : .primary)
                    .cornerRadius(16)
                
                // Timestamp
                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: isCurrentUser ? .trailing : .leading)
            
            if !isCurrentUser {
                Spacer()
            }
        }
    }
    
    private var contextIcon: String {
        switch message.contextType {
        case .post: return "doc.text"
        case .reel: return "play.rectangle"
        case .status: return "circle.dotted"
        case .none: return ""
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}
