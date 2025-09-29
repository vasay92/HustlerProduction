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
        .padding(.horizontal)
        .padding(.top, -20)  // ← NEGATIVE padding to pull it up closer to the title
        .padding(.bottom, 8)  // Small bottom padding for spacing from list
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
        
        Task { @MainActor in
            // CHANGE FROM: let conversations = await FirebaseService.shared.loadConversations()
            // TO:
            await viewModel.loadConversations()
            let conversations = viewModel.conversations
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
        let imageURL = conversation.otherParticipantImage(currentUserId: userId)
        
        // Debug logging
        if imageURL == nil || imageURL?.isEmpty == true {
            print("⚠️ No image URL for \(otherParticipantName) in conversation \(conversation.id ?? "unknown")")
        }
        
        return imageURL
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
            // Avatar - Now using UserAvatar with initials fallback!
            UserAvatar(
                imageURL: otherParticipantImage,
                userName: otherParticipantName,
                size: 56
            )
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(otherParticipantName)
                        .font(.headline)
                        .fontWeight(hasUnread ? .semibold : .regular)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Time
                    Text(conversation.lastMessageTimestamp.timeAgo())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    // Last message preview
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
                    
                    // Unread badge
                    if hasUnread {
                        Text("\(unreadCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(hasUnread ? Color.blue.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Date Extension for Time Ago
extension Date {
    func timeAgo() -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.year, .month, .weekOfYear, .day, .hour, .minute], from: self, to: now)
        
        if let years = components.year, years > 0 {
            return "\(years)y"
        } else if let months = components.month, months > 0 {
            return "\(months)mo"
        } else if let weeks = components.weekOfYear, weeks > 0 {
            return "\(weeks)w"
        } else if let days = components.day, days > 0 {
            if days == 1 {
                return "Yesterday"
            } else {
                return "\(days)d"
            }
        } else if let hours = components.hour, hours > 0 {
            return "\(hours)h"
        } else if let minutes = components.minute, minutes > 0 {
            return "\(minutes)m"
        } else {
            return "Now"
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

