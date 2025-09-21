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
    
    @StateObject private var firebase = FirebaseService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var messages: [Message] = []
    @State private var messageText = ""
    @State private var isLoadingMessages = false
    @State private var showingBlockConfirmation = false
    @State private var showingClearConfirmation = false
    @State private var showingReportSheet = false
    @State private var reportMessageId: String?
    @State private var messagesListener: ListenerRegistration?
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
        NavigationView {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom Navigation Bar
                    customNavigationBar
                    
                    // Messages List
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                // DEBUG: Simple test to see if ForEach works
                                if messages.isEmpty {
                                    Text("No messages to display")
                                        .foregroundColor(.gray)
                                        .padding()
                                } else {
                                    ForEach(messages) { message in
                                        MessageBubbleView(
                                            message: message,
                                            isFromCurrentUser: message.senderId == firebase.currentUser?.id
                                        )
                                        .id(message.id)
                                    }
                                }
                                
                                Color.clear
                                    .frame(height: 1)
                                    .id(bottomAnchor)
                            }
                            .padding()
                        }
                        .onChange(of: messages.count) { oldCount, newCount in
                            print("DEBUG - messages.count changed from \(oldCount) to \(newCount)")
                            // Add delay to ensure views have rendered
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    scrollProxy.scrollTo(bottomAnchor, anchor: .bottom)
                                }
                            }
                        }
                        .onAppear {
                            // Initial scroll to bottom when view appears
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                scrollProxy.scrollTo(bottomAnchor, anchor: .bottom)
                            }
                        }
                    }
                    
                    // Message Composer
                    messageComposer
                }
            }
            .navigationBarHidden(true)
            .task {
                await setupChat()
            }
            .onDisappear {
                messagesListener?.remove()
                messagesListener = nil  // IMPORTANT: Set to nil to release the reference
            }
        }
    }
    
    // MARK: - Custom Navigation Bar
    
    @ViewBuilder
    private var customNavigationBar: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: {
                dismiss()
            }) {
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
                print("DEBUG - Participants: \(conversation.participantIds)")
            } else if let recipientId = recipientId {
                print("DEBUG - Creating/finding conversation with recipient: \(recipientId)")
                print("DEBUG - Current user: \(firebase.currentUser?.id ?? "nil")")
                currentConversationId = try await firebase.findOrCreateConversation(with: recipientId)
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
            
            // Load messages - this should work even if marking as read fails
            if let conversationId = currentConversationId {
                messages = await firebase.loadMessages(for: conversationId)
                
                // Trigger scroll to bottom after messages load
                if !messages.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.scrollToBottom = true
                    }
                }
                
                // Try to mark messages as read, but don't fail if permissions denied
                do {
                    try await firebase.markMessagesAsRead(in: conversationId)
                } catch {
                    print("Could not mark messages as read (non-critical): \(error)")
                }
                
                // Start listening for new messages
                messagesListener = firebase.listenToMessages(in: conversationId) { newMessages in
                    DispatchQueue.main.async {
                        self.messages = newMessages
                    }
                }
            }
        } catch {
            print("Error setting up chat: \(error)")
            // Still try to load messages even if setup partially fails
            if let conversationId = currentConversationId {
                messages = await firebase.loadMessages(for: conversationId)
                
                // Trigger scroll even in error case
                if !messages.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.scrollToBottom = true
                    }
                }
                
                // Start listening anyway
                messagesListener = firebase.listenToMessages(in: conversationId) { newMessages in
                    DispatchQueue.main.async {
                        self.messages = newMessages
                    }
                }
            }
        }
        
        isLoadingMessages = false
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !text.isEmpty else { return }
        guard let recipientId = otherUserId else { return }
        
        Task {
            do {
                // Include context only if coming from content view
                let shouldIncludeContext = isFromContentView && contextType != nil
                
                try await firebase.sendMessage(
                    to: recipientId,
                    text: text,
                    contextType: shouldIncludeContext ? contextType : nil,
                    contextId: shouldIncludeContext ? contextId : nil,
                    contextData: shouldIncludeContext ? contextData : nil
                )
                
                messageText = ""
                
                // Clear context after first message if from content view
                if isFromContentView {
                    isFromContentView = false
                }
            } catch {
                print("Error sending message: \(error)")
            }
        }
    }
    
    private func blockUser() async {
        guard let conversationId = currentConversationId,
              let userId = otherUserId else { return }
        
        do {
            try await firebase.blockUser(userId, in: conversationId)
            dismiss()
        } catch {
            print("Error blocking user: \(error)")
        }
    }
    
    private func clearChat() async {
        guard let conversationId = currentConversationId else { return }
        
        do {
            try await firebase.clearConversation(conversationId)
            messages = []
        } catch {
            print("Error clearing chat: \(error)")
        }
    }
    
    private func contextTypeString(_ type: Message.MessageContextType) -> String {
        switch type {
        case .post: return "Post"
        case .reel: return "Reel"
        case .status: return "Status"
        }
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: Message
    let isFromCurrentUser: Bool
    
    var body: some View {
        HStack {
            if isFromCurrentUser { Spacer() }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Content preview if exists
                if message.contextType != nil {
                    ContentPreviewCard(message: message)
                }
                
                // Message bubble
                Text(message.text)
                    .font(.body)
                    .foregroundColor(isFromCurrentUser ? .white : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isFromCurrentUser ? Color.blue : Color(.systemGray5))
                    .cornerRadius(18)
                
                // Timestamp and read receipt
                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    // Only show read receipts for messages from current user
                    if isFromCurrentUser {
                        if message.isRead {
                            // Double checkmark for read
                            HStack(spacing: -3) {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        } else if message.isDelivered {
                            // Single checkmark for delivered
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            // Clock for sending
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: isFromCurrentUser ? .trailing : .leading)
            
            if !isFromCurrentUser { Spacer() }
        }
        .padding(.horizontal)
    }
}
// MARK: - Report Message View

struct ReportMessageView: View {
    let messageId: String?
    let conversationId: String
    let reportedUserId: String
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var selectedReason: MessageReport.ReportReason = .spam
    @State private var additionalDetails = ""
    @State private var isSubmitting = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Reason for Report") {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(MessageReport.ReportReason.allCases, id: \.self) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                }
                
                Section("Additional Details (Optional)") {
                    TextEditor(text: $additionalDetails)
                        .frame(minHeight: 100)
                }
                
                Section {
                    Button(action: submitReport) {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Submit Report")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.red)
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("Report Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func submitReport() {
        isSubmitting = true
        
        Task {
            do {
                // Temporarily disabled during migration
                // TODO: Implement in MessageRepository
                print("Report submission temporarily disabled")
                print("Would report: messageId: \(messageId ?? "none"), reason: \(selectedReason)")
                
                // Simulate successful submission
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                
                dismiss()
            } catch {
                print("Error submitting report: \(error)")
                isSubmitting = false
            }
        }
    }
}
