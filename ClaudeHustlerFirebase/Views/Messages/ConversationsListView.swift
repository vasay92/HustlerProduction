// ConversationsListView.swift
// Path: ClaudeHustlerFirebase/Views/Messages/ConversationsListView.swift

import SwiftUI
import FirebaseFirestore

struct ConversationsListView: View {
    @StateObject private var viewModel = MessagesViewModel()
    @State private var searchText = ""
    @State private var selectedConversation: Conversation?
    @State private var showingNewMessage = false
    @State private var conversationToDelete: Conversation?
    @State private var showingDeleteAlert = false
    @Environment(\.dismiss) var dismiss
    
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
                // Custom Navigation Bar with Back Button
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.title3)
                                .fontWeight(.medium)
                            Text("Back")
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Text("Messages")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button(action: { showingNewMessage = true }) {
                        Image(systemName: "square.and.pencil")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                
                // Search Bar (only show if there are conversations)
                if !viewModel.conversations.isEmpty {
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
                    .padding(.horizontal)
                    .padding(.top, 8)      // ADDED - space from nav bar
                    .padding(.bottom, 10)
                }
                
                // Content
                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Loading conversations...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Spacer()
                } else if viewModel.conversations.isEmpty {
                    emptyStateView
                } else {
                    // Conversations List with Swipe Actions
                    List {
                        ForEach(filteredConversations) { conversation in
                            ConversationRow(conversation: conversation)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedConversation = conversation
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        conversationToDelete = conversation
                                        showingDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button(action: {
                                        // Mark as read functionality
                                    }) {
                                        Label("Mark as Read", systemImage: "envelope.open")
                                    }
                                    
                                    Button(role: .destructive, action: {
                                        conversationToDelete = conversation
                                        showingDeleteAlert = true
                                    }) {
                                        Label("Delete Conversation", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(PlainListStyle())
                    .refreshable {
                        await viewModel.refresh()
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadConversations()
        }
        .fullScreenCover(item: $selectedConversation) { conversation in
            ChatView(conversation: conversation)
        }
        .sheet(isPresented: $showingNewMessage) {
            // NewMessageView() // You'll need to create this
            Text("New Message View")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingNewMessage = false
                        }
                    }
                }
        }
        .alert("Delete Conversation?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let conversation = conversationToDelete {
                    Task {
                        await deleteConversation(conversation)
                    }
                }
            }
        } message: {
            Text("This will permanently delete this conversation and all messages. This cannot be undone.")
        }
    }
    
    // Empty State View
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
    
    // Delete Conversation Function
    private func deleteConversation(_ conversation: Conversation) async {
        guard let conversationId = conversation.id else { return }
        
        do {
            try await MessageRepository.shared.deleteConversation(conversationId)
            await viewModel.loadConversations()
        } catch {
            print("Error deleting conversation: \(error)")
        }
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
    
    // In ConversationRow, replace the unreadCount and hasUnread computed properties:

    private var unreadCount: Int {
        guard let userId = currentUserId else { return 0 }
        let count = conversation.unreadCounts[userId] ?? 0  // ADD THIS LINE
        print("DEBUG: Conversation \(conversation.id ?? "unknown") - unreadCount for user \(userId): \(count)")
        return count
    }

    private var hasUnread: Bool {
        let result = unreadCount > 0  // ADD THIS LINE
        print("DEBUG: hasUnread = \(result) for conversation \(conversation.id ?? "unknown")")
        return result
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            UserAvatar(
                imageURL: otherParticipantImage,
                userName: otherParticipantName,
                size: 50
            )
            
            // Conversation Info
            VStack(alignment: .leading, spacing: 4) {
                // Name and Time
                HStack {
                    Text(otherParticipantName)
                        .font(.subheadline)
                        .fontWeight(hasUnread ? .semibold : .medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(formatTimestamp(conversation.lastMessageTimestamp))
                        .font(.caption)
                        .foregroundColor(hasUnread ? .primary : .secondary)  // ADDED - darker when unread
                }
                
                // Last Message
                HStack {
                    Text(conversation.lastMessage ?? "No messages yet")
                        .font(.caption)
                        .fontWeight(hasUnread ? .semibold : .regular)  // CHANGED - bold when unread
                        .foregroundColor(hasUnread ? .primary : .secondary)  // CHANGED - darker when unread
                        .lineLimit(2)
                    
                    Spacer()
                    
                    // Unread Badge
                    if hasUnread {
                        Text("\(unreadCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(hasUnread ? Color.blue.opacity(0.05) : Color(.systemBackground))
        )
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}
