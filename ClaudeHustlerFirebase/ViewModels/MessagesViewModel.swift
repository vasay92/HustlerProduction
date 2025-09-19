// MessagesViewModel.swift
// Path: ClaudeHustlerFirebase/ViewModels/MessagesViewModel.swift

import SwiftUI
import FirebaseFirestore

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var messages: [Message] = []
    @Published var isLoading = false
    
    private let repository = MessageRepository.shared
    private var conversationListener: ListenerRegistration?
    
    func loadConversations() async {
        isLoading = true
        do {
            let result = try await repository.fetchConversations(limit: 20)
            conversations = result.items
        } catch {
            print("Error loading conversations: \(error)")
        }
        isLoading = false
    }
    
    func sendMessage(text: String, conversationId: String) async {
        let message = Message(
            senderId: FirebaseService.shared.currentUser?.id ?? "",
            senderName: FirebaseService.shared.currentUser?.name ?? "",
            conversationId: conversationId,
            text: text
        )
        
        do {
            _ = try await repository.create(message)
        } catch {
            print("Error sending message: \(error)")
        }
    }
    
    deinit {
        repository.removeAllListeners()
    }
}
