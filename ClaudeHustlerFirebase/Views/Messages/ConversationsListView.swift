// ConversationsListView.swift
// Path: ClaudeHustlerFirebase/Views/Messages/ConversationsListView.swift

import SwiftUI
import FirebaseFirestore

struct ConversationsListView: View {
    @StateObject private var viewModel = MessagesViewModel()
    @State private var searchText = ""
    @State private var selectedConversation: Conversation?
    @State private var showingNewMessage = false
    @State private var conversationsListener: ListenerRegistration?
    
    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return viewModel.conversations
        }
        
        guard let currentUserId = FirebaseService.shared.currentUser?.id else {
            return viewModel.conversations
        }
        
        return viewModel.conversations.filter { conversation in
            let otherName = conversation.otherParticipantName(currentUserId: currentUserId) ?? ""
            return otherName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar (only show if there are conversations)
                if !viewModel.conversations.isEmpty {
                    searchBar
                }
                
                // Content
                if viewModel.isLoading {
                    // Loading state
                    Spacer()
                    ProgressView("Loading conversations...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Spacer()
                } else if viewModel.conversations.isEmpty {
                    // Empty state
                    emptyStateView
                } else {
                    // Conversations List
                    conversationsList
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewMessage = true }) {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .task {
            await viewModel.loadConversations()
            startListeningToConversations()
        }
        .onDisappear {
            stopListeningToConversations()
        }
        .fullScreenCover(item: $selectedConversation) { conversation in
            ChatView(conversation: conversation)
        }
        .sheet(isPresented: $showingNewMessage) {
            NewMessageView()
        }
    }
    
    // MARK: - View Components
    
    private var searchBar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("Search conversations", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .padding()
    }
    
    private var conversationsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredConversations) { conversation in
                    ConversationRow(conversation: conversation)
                        .onTapGesture {
                            selectedConversation = conversation
                        }
                    
                    Divider()
                        .padding(.leading, 76)
                }
            }
        }
        .refreshable {
            await viewModel.loadConversations()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "message")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Messages Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Start a conversation to connect with others")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: { showingNewMessage = true }) {
                Label("New Message", systemImage: "square.and.pencil")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Real-time Listeners
    
    private func startListeningToConversations() {
        guard let userId = FirebaseService.shared.currentUser?.id else { return }
        
        conversationsListener = FirebaseService.shared.listenToConversations { [weak viewModel] conversations in
            Task { @MainActor in
                viewModel?.conversations = conversations
            }
        }
    }
    
    private func stopListeningToConversations() {
        conversationsListener?.remove()
        conversationsListener = nil
    }
}

// MARK: - Conversation Row
struct ConversationRow: View {
    let conversation: Conversation
    @StateObject private var firebase = FirebaseService.shared
    
    private var currentUserId: String? {
        firebase.currentUser?.id
    }
    
    private var otherParticipantName: String {
        guard let userId = currentUserId else { return "Unknown" }
        return conversation.otherParticipantName(currentUserId: userId) ?? "Unknown"
    }
    
    private var otherParticipantImage: String? {
        guard let userId = currentUserId else { return nil }
        return conversation.otherParticipantImage(currentUserId: userId)
    }
    
    private var unreadCount: Int {
        guard let userId = currentUserId else { return 0 }
        return conversation.unreadCounts[userId] ?? 0
    }
    
    private var hasUnread: Bool {
        unreadCount > 0
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ProfileImageView(imageURL: otherParticipantImage, size: 56)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(otherParticipantName)
                        .font(.headline)
                        .fontWeight(hasUnread ? .semibold : .regular)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let timestamp = conversation.lastMessageTimestamp {
                        Text(timestamp.timeAgo())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    if let lastMessage = conversation.lastMessage {
                        Text(lastMessage)
                            .font(.subheadline)
                            .foregroundColor(hasUnread ? .primary : .secondary)
                            .lineLimit(2)
                    } else {
                        Text("Start a conversation")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    
                    Spacer()
                    
                    if hasUnread {
                        Text("\(unreadCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - Profile Image View Helper
struct ProfileImageView: View {
    let imageURL: String?
    let size: CGFloat
    
    var body: some View {
        if let urlString = imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        ProgressView()
                    )
            }
        } else {
            Image(systemName: "person.circle.fill")
                .font(.system(size: size))
                .foregroundColor(.gray)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Date Extension for Time Ago
extension Date {
    func timeAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let now = Date()
        let timeInterval = now.timeIntervalSince(self)
        
        switch timeInterval {
        case 0..<60:
            return "now"
        case 60..<3600:
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m"
        case 3600..<86400:
            let hours = Int(timeInterval / 3600)
            return "\(hours)h"
        case 86400..<604800:
            let days = Int(timeInterval / 86400)
            return "\(days)d"
        default:
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            return dateFormatter.string(from: self)
        }
    }
}

// MARK: - New Message View (Placeholder)
// Note: This is a placeholder - you should already have this view in your project
struct NewMessageView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var searchText = ""
    @State private var selectedUser: User?
    
    var body: some View {
        NavigationView {
            VStack {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search users...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
                
                // Users list would go here
                ScrollView {
                    Text("User search functionality to be implemented")
                        .foregroundColor(.secondary)
                        .padding()
                }
                
                Spacer()
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Chat View (Placeholder)
// Note: You should already have this view - this is just to make the file compile
struct ChatView: View {
    let conversation: Conversation
    @Environment(\.dismiss) var dismiss
    
    init(conversation: Conversation) {
        self.conversation = conversation
    }
    
    // Alternative initializer for creating new conversations
    init(recipientId: String, contextType: Message.MessageContextType? = nil,
         contextId: String? = nil,
         contextData: (title: String, image: String, userId: String)? = nil,
         isFromContentView: Bool = false) {
        // Create a temporary conversation
        self.conversation = Conversation(
            participantIds: [FirebaseService.shared.currentUser?.id ?? "", recipientId],
            participantNames: [:],
            participantImages: [:]
        )
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Messages would be displayed here
                ScrollView {
                    Text("Chat messages will appear here")
                        .foregroundColor(.secondary)
                        .padding()
                }
                
                // Message input bar would go here
                HStack {
                    TextField("Type a message...", text: .constant(""))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: {}) {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .padding()
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        dismiss()
                    }
                }
            }
        }
    }
}
