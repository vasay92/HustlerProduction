

// MessageRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/MessageRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Message Repository
@MainActor
final class MessageRepository: RepositoryProtocol {
    typealias Model = Message
    
    // Singleton
    static let shared = MessageRepository()
    
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    private let cacheMaxAge: TimeInterval = 60 // 1 minute for messages
    
    // Active listeners
    private var conversationListeners: [String: ListenerRegistration] = [:]
    private var messageListeners: [String: ListenerRegistration] = [:]
    
    private init() {}
    
    // MARK: - Fetch Messages with Pagination
    func fetch(limit: Int = 50, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [Message], lastDoc: DocumentSnapshot?) {
        // This fetches all messages for current user (not typically used)
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        var query = db.collection("messages")
            .whereField("senderId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let messages = snapshot.documents.compactMap { doc -> Message? in
            var message = try? doc.data(as: Message.self)
            message?.id = doc.documentID
            return message
        }
        
        return (messages, snapshot.documents.last)
    }
    
    // MARK: - Fetch Single Message
    func fetchById(_ id: String) async throws -> Message? {
        let document = try await db.collection("messages").document(id).getDocument()
        
        guard document.exists else { return nil }
        
        var message = try document.data(as: Message.self)
        message.id = document.documentID
        
        return message
    }
    
    // MARK: - Fetch Messages for Conversation
    func fetchConversationMessages(
        conversationId: String,
        limit: Int = 50,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (items: [Message], lastDoc: DocumentSnapshot?) {
        var query = db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let messages = snapshot.documents.compactMap { doc -> Message? in
            var message = try? doc.data(as: Message.self)
            message?.id = doc.documentID
            return message
        }.reversed() // Reverse to show oldest first
        
        return (Array(messages), snapshot.documents.last)
    }
    
    // MARK: - Create Message (Send)
    func create(_ message: Message) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        var messageData = message
        messageData.senderId = userId
        messageData.timestamp = Date()
        messageData.isDelivered = false
        messageData.isRead = false
        
        // Start a batch write
        let batch = db.batch()
        
        // Add the message
        let messageRef = db.collection("messages").document()
        try batch.setData(from: messageData, forDocument: messageRef)
        
        // Update conversation
        let conversationRef = db.collection("conversations").document(message.conversationId)
        batch.updateData([
            "lastMessage": message.text,
            "lastMessageTimestamp": Date(),
            "lastMessageSenderId": userId,
            "updatedAt": Date()
        ], forDocument: conversationRef)
        
        // Increment unread count for recipient
        let conversationDoc = try await conversationRef.getDocument()
        if let data = conversationDoc.data(),
           let participantIds = data["participantIds"] as? [String] {
            let recipientId = participantIds.first { $0 != userId } ?? ""
            batch.updateData([
                "unreadCounts.\(recipientId)": FieldValue.increment(Int64(1))
            ], forDocument: conversationRef)
        }
        
        // Commit the batch
        try await batch.commit()
        
        // Clear conversation cache
        cache.remove(for: "conversation_\(message.conversationId)")
        
        return messageRef.documentID
    }
    
    // MARK: - Update Message (Edit)
    func update(_ message: Message) async throws {
        guard let messageId = message.id else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Message ID is required"])
        }
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify ownership
        let document = try await db.collection("messages").document(messageId).getDocument()
        guard let data = document.data(),
              data["senderId"] as? String == currentUserId else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to edit this message"])
        }
        
        // Update message
        try await db.collection("messages").document(messageId).updateData([
            "text": message.text,
            "isEdited": true,
            "editedAt": Date()
        ])
        
        // Clear cache
        cache.remove(for: "conversation_\(message.conversationId)")
    }
    
    // MARK: - Delete Message
    func delete(_ id: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Get message to verify ownership and get conversationId
        let document = try await db.collection("messages").document(id).getDocument()
        guard let data = document.data(),
              data["senderId"] as? String == currentUserId,
              let conversationId = data["conversationId"] as? String else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to delete this message"])
        }
        
        // Soft delete (mark as deleted but keep record)
        try await db.collection("messages").document(id).updateData([
            "isDeleted": true,
            "text": "This message was deleted",
            "deletedAt": Date()
        ])
        
        // Clear cache
        cache.remove(for: "conversation_\(conversationId)")
    }
    
    // MARK: - Conversation Management
    
    func fetchConversations(limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [Conversation], lastDoc: DocumentSnapshot?) {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        var query = db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .order(by: "lastMessageTimestamp", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let conversations = snapshot.documents.compactMap { doc -> Conversation? in
            var conversation = try? doc.data(as: Conversation.self)
            conversation?.id = doc.documentID
            return conversation
        }
        
        // Cache first page
        if lastDocument == nil && !conversations.isEmpty {
            cache.store(conversations, for: "conversations_page_1")
        }
        
        return (conversations, snapshot.documents.last)
    }
    
    func findOrCreateConversation(with recipientId: String) async throws -> String {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Check if conversation already exists
        let existingConversation = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .getDocuments()
        
        for doc in existingConversation.documents {
            if let participantIds = doc.data()["participantIds"] as? [String],
               participantIds.contains(recipientId) && participantIds.count == 2 {
                return doc.documentID
            }
        }
        
        // Create new conversation
        let conversationData = Conversation(
            participantIds: [currentUserId, recipientId],
            participantNames: [:],
            participantImages: [:],
            lastMessage: nil,
            lastMessageTimestamp: Date(),
            lastMessageSenderId: nil,
            unreadCounts: [currentUserId: 0, recipientId: 0],
            lastReadTimestamps: [:],
            createdAt: Date(),
            updatedAt: Date(),
            blockedUsers: []
        )
        
        let docRef = try await db.collection("conversations").addDocument(from: conversationData)
        
        // Load participant details
        await updateConversationParticipantInfo(conversationId: docRef.documentID)
        
        return docRef.documentID
    }
    
    func markMessagesAsRead(conversationId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let batch = db.batch()
        
        // Update all unread messages in this conversation
        let unreadMessages = try await db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .whereField("senderId", isNotEqualTo: userId)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()
        
        for message in unreadMessages.documents {
            batch.updateData([
                "isRead": true,
                "readAt": Date()
            ], forDocument: message.reference)
        }
        
        // Reset unread count in conversation
        let conversationRef = db.collection("conversations").document(conversationId)
        batch.updateData([
            "unreadCounts.\(userId)": 0,
            "lastReadTimestamps.\(userId)": Date()
        ], forDocument: conversationRef)
        
        try await batch.commit()
        
        // Clear cache
        cache.remove(for: "conversation_\(conversationId)")
    }
    
    func blockUserInConversation(_ userId: String, conversationId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("conversations").document(conversationId).updateData([
            "blockedUsers": FieldValue.arrayUnion([userId])
        ])
        
        cache.remove(for: "conversation_\(conversationId)")
    }
    
    func unblockUserInConversation(_ userId: String, conversationId: String) async throws {
        try await db.collection("conversations").document(conversationId).updateData([
            "blockedUsers": FieldValue.arrayRemove([userId])
        ])
        
        cache.remove(for: "conversation_\(conversationId)")
    }
    
    // MARK: - Real-time Listeners
    
    func listenToConversation(_ conversationId: String, completion: @escaping ([Message]) -> Void) -> ListenerRegistration {
        // Remove existing listener
        conversationListeners[conversationId]?.remove()
        
        let listener = db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to messages: \(error)")
                    completion([])
                    return
                }
                
                let messages = snapshot?.documents.compactMap { doc -> Message? in
                    var message = try? doc.data(as: Message.self)
                    message?.id = doc.documentID
                    return message
                } ?? []
                
                completion(messages)
            }
        
        conversationListeners[conversationId] = listener
        return listener
    }
    
    func stopListeningToConversation(_ conversationId: String) {
        conversationListeners[conversationId]?.remove()
        conversationListeners.removeValue(forKey: conversationId)
    }
    
    func removeAllListeners() {
        conversationListeners.values.forEach { $0.remove() }
        conversationListeners.removeAll()
        
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func updateConversationParticipantInfo(conversationId: String) async {
        do {
            let conversation = try await db.collection("conversations").document(conversationId).getDocument()
            guard let data = conversation.data(),
                  let participantIds = data["participantIds"] as? [String] else { return }
            
            var participantNames: [String: String] = [:]
            var participantImages: [String: String] = [:]
            
            for userId in participantIds {
                let userDoc = try await db.collection("users").document(userId).getDocument()
                if let userData = userDoc.data() {
                    participantNames[userId] = userData["name"] as? String ?? "Unknown"
                    participantImages[userId] = userData["profileImageURL"] as? String
                }
            }
            
            try await db.collection("conversations").document(conversationId).updateData([
                "participantNames": participantNames,
                "participantImages": participantImages
            ])
        } catch {
            print("Error updating conversation info: \(error)")
        }
    }
}
