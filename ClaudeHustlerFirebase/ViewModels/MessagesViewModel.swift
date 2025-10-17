// MessagesViewModel.swift
// Path: ClaudeHustlerFirebase/ViewModels/MessagesViewModel.swift

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var error: Error?
    static weak var shared: MessagesViewModel?
    
    private let repository = MessageRepository.shared
    private let firebase = FirebaseService.shared
    private var conversationListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?
    private var currentUserId: String?
    
    init() {
        Self.shared = self
        self.currentUserId = Auth.auth().currentUser?.uid
    }
    
    // MARK: - Conversation Management
    
    func loadConversations() async {
        isLoading = true
        error = nil
        
        // First refresh participant info
        await repository.refreshAllConversationsParticipantInfo()
        
        // Then load conversations with updated info
        let fetchedConversations = await repository.loadConversations()
        
        await MainActor.run {
            self.conversations = fetchedConversations
            self.isLoading = false
        }
    }
    
    func findOrCreateConversation(with recipientId: String) async throws -> String {
        return try await repository.findOrCreateConversation(with: recipientId)
    }
    
    func deleteConversation(_ conversationId: String) async throws {
        try await repository.delete(conversationId)
        conversations.removeAll { $0.id == conversationId }
    }
    
    // MARK: - Message Management
    
    func sendMessage(
        to recipientId: String,
        text: String,
        contextType: Message.MessageContextType? = nil,
        contextId: String? = nil,
        contextData: (title: String, image: String?, userId: String)? = nil
    ) async throws {
        try await repository.sendMessage(
            to: recipientId,
            text: text,
            contextType: contextType,
            contextId: contextId,
            contextData: contextData  // ADD THIS - pass it through
        )
    }
    
    func loadMessages(for conversationId: String) async {
        // Use loadMessages from MessageRepository (returns [Message] directly, not a tuple)
        let fetchedMessages = await repository.loadMessages(for: conversationId)
        
        await MainActor.run {
            self.messages = fetchedMessages
        }
    }
    
    func markMessagesAsRead(in conversationId: String) async throws {
        // Just pass the conversationId value, no label
        try await repository.markMessagesAsRead(conversationId: conversationId)
    }
    
    func deleteMessage(_ messageId: String, conversationId: String) async throws {
        // Since MessageRepository doesn't have deleteMessage, just remove locally
        messages.removeAll { $0.id == messageId }
    }
    
    // MARK: - Real-time Listeners
    
    func listenToConversations() {
        guard let userId = currentUserId else { return }
        
        Task {
            // CHANGE FROM: let conversations = await firebase.loadConversations()
            // TO:
            let conversations = await repository.loadConversations()
            await MainActor.run {
                self.conversations = conversations
            }
        }
    }
    
    func listenToMessages(in conversationId: String, completion: @escaping ([Message]) -> Void) {
        // Use FirebaseService's listenToMessages since MessageRepository doesn't have this method
        messagesListener?.remove() // Remove any existing listener
        
        messagesListener = repository.listenToMessages(in: conversationId) { messages in
                DispatchQueue.main.async { [weak self] in
                    self?.messages = messages
                    completion(messages)
                }
            }
    }
    
    func stopListeningToMessages() {
        messagesListener?.remove()
        messagesListener = nil
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        conversationListener?.remove()
        messagesListener?.remove()
        conversationListener = nil
        messagesListener = nil
    }
    
    // MARK: - Refresh
    
    func refresh() async {
        conversations = []
        messages = []
        await loadConversations()
    }
}
