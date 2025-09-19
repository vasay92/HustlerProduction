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
    
    private let repository = MessageRepository.shared
    private let firebase = FirebaseService.shared
    private var conversationListener: ListenerRegistration?
    private var currentUserId: String?
    
    init() {
        self.currentUserId = Auth.auth().currentUser?.uid
    }
    
    func loadConversations() async {
        isLoading = true
        do {
            let result = try await repository.fetchConversations(limit: 20)
            conversations = result.items
        } catch {
            self.error = error
            print("Error loading conversations: \(error)")
        }
        isLoading = false
    }
    
    func loadMessages(for conversationId: String) async {
        isLoading = true
        do {
            let result = try await repository.fetchConversationMessages(
                conversationId: conversationId,
                limit: 50
            )
            messages = result.items.reversed() // Show in chronological order
        } catch {
            self.error = error
            print("Error loading messages: \(error)")
        }
        isLoading = false
    }
    
    func sendMessage(text: String, conversationId: String) async {
        guard let userId = currentUserId,
              let userName = firebase.currentUser?.name else { return }
        
        let message = Message(
            senderId: userId,
            senderName: userName,
            senderProfileImage: firebase.currentUser?.profileImageURL,
            conversationId: conversationId,
            text: text
        )
        
        do {
            _ = try await repository.create(message)
            // Message will appear via listener
        } catch {
            self.error = error
            print("Error sending message: \(error)")
        }
    }
    
    func markMessagesAsRead(conversationId: String) async {
        do {
            try await repository.markMessagesAsRead(conversationId: conversationId)
        } catch {
            print("Error marking messages as read: \(error)")
        }
    }
    
    func deleteMessage(_ messageId: String) async {
        
            print("Error deleting message: \(error)")

    }
    
    deinit {
        Task { @MainActor in
                repository.removeAllListeners()
            }
    }
}
