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
        print("DEBUG - MessagesViewModel init - currentUserId: \(self.currentUserId ?? "nil")")
    }
    
    deinit {
        cleanupListeners()
    }
    
    // MARK: - Conversation Management
    
    func loadConversations() async {
        isLoading = true
        error = nil
        
        do {
            let (fetchedConversations, _) = try await repository.fetch(limit: 50, lastDocument: nil)
            
            await MainActor.run {
                self.conversations = fetchedConversations
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
            print("Error loading conversations: \(error)")
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
        let conversationId = try await repository.findOrCreateConversation(with: recipientId)
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessagesViewModel", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Get current user info
        let currentUser = firebase.currentUser
        
        // Create the message
        let message = Message(
            senderId: currentUserId,
            senderName: currentUser?.name ?? "Unknown",
            senderProfileImage: currentUser?.profileImageURL,
            conversationId: conversationId,
            text: text,
            contextType: contextType,
            contextId: contextId,
            contextTitle: contextData?.title,
            contextImage: contextData?.image,
            contextUserId: contextData?.userId
        )
        
        // Send through repository
        try await repository.sendMessage(message)
    }
    
    func loadMessages(for conversationId: String) async {
        do {
            let fetchedMessages = try await repository.fetchMessages(for: conversationId, limit: 100)
            
            await MainActor.run {
                self.messages = fetchedMessages
            }
        } catch {
            print("Error loading messages: \(error)")
            self.messages = []
        }
    }
    
    func markMessagesAsRead(in conversationId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        try await repository.markMessagesAsRead(conversationId: conversationId, userId: currentUserId)
    }
    
    func deleteMessage(_ messageId: String) async throws {
        guard let message = messages.first(where: { $0.id == messageId }) else { return }
        try await repository.deleteMessage(messageId, in: message.conversationId)
        messages.removeAll { $0.id == messageId }
    }
    
    // MARK: - Real-time Listeners
    
    func listenToConversations() {
        guard let userId = currentUserId else { return }
        
        conversationListener = repository.listenToConversations(userId: userId) { [weak self] conversations in
            DispatchQueue.main.async {
                self?.conversations = conversations
            }
        }
    }
    
    func listenToMessages(in conversationId: String, completion: @escaping ([Message]) -> Void) {
        messagesListener?.remove() // Remove any existing listener
        
        messagesListener = repository.listenToMessages(conversationId: conversationId) { [weak self] messages in
            DispatchQueue.main.async {
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
    
    private func cleanupListeners() {
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
