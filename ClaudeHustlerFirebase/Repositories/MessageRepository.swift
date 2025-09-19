

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
        var query = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
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
    
    // MARK: - Protocol Conformance Create (required by RepositoryProtocol)
    func create(_ item: Message) async throws -> String {
        // Use the conversationId from the message itself
        let conversationId = item.conversationId
        
        // Call the existing create method
        return try await create(item, in: conversationId)
    }
    
    // MARK: - Create Message with ConversationId
    func create(_ message: Message, in conversationId: String) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Create message data dictionary
        let messageData: [String: Any] = [
            "senderId": userId,
            "conversationId": conversationId,
            "text": message.text,
            "timestamp": Date(),
            "isRead": false,
            "contextType": message.contextType?.rawValue ?? "",
            "contextId": message.contextId ?? ""
        ]
        
        let docRef = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .addDocument(data: messageData)
        
        // Update conversation's last message
        try await updateConversationLastMessage(conversationId, message: message.text)
        
        // Clear cache
        cache.remove(for: "messages_\(conversationId)")
        
        return docRef.documentID
    }
    
    // MARK: - Update Message (Edit)
    func update(_ message: Message) async throws {
        guard let messageId = message.id else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Message ID is required"])
        }
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Find the conversation that contains this message
        let conversationId = message.conversationId
        
        // Verify ownership
        let document = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .getDocument()
        
        guard let data = document.data(),
              data["senderId"] as? String == currentUserId else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to edit this message"])
        }
        
        // Update message
        try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData([
                "text": message.text,
                "isEdited": true,
                "editedAt": Date()
            ])
        
        // Clear cache
        cache.remove(for: "messages_\(conversationId)")
    }
    
    // MARK: - Delete Message
    func delete(_ id: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Find which conversation contains this message
        // This is a simplified approach - in production, you might want to store conversationId with the message
        let conversationsSnapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .getDocuments()
        
        for conversationDoc in conversationsSnapshot.documents {
            let messageDoc = try await conversationDoc.reference
                .collection("messages")
                .document(id)
                .getDocument()
            
            if messageDoc.exists,
               let data = messageDoc.data(),
               data["senderId"] as? String == currentUserId {
                // Soft delete (mark as deleted but keep record)
                try await conversationDoc.reference
                    .collection("messages")
                    .document(id)
                    .updateData([
                        "isDeleted": true,
                        "text": "This message was deleted",
                        "deletedAt": Date()
                    ])
                
                // Clear cache
                cache.remove(for: "messages_\(conversationDoc.documentID)")
                return
            }
        }
        
        throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Message not found or unauthorized"])
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
        let conversationData: [String: Any] = [
            "participantIds": [currentUserId, recipientId],
            "participantNames": [:],
            "participantImages": [:],
            "lastMessage": "",
            "lastMessageTimestamp": Date(),
            "lastMessageSenderId": "",
            "unreadCounts": [currentUserId: 0, recipientId: 0],
            "lastReadTimestamps": [:],
            "createdAt": Date(),
            "updatedAt": Date(),
            "blockedUsers": []
        ]
        
        let docRef = try await db.collection("conversations").addDocument(data: conversationData)
        
        // Load participant details
        await updateConversationParticipantInfo(conversationId: docRef.documentID)
        
        return docRef.documentID
    }
    
    func markMessagesAsRead(conversationId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let batch = db.batch()
        
        // Update all unread messages in this conversation
        let unreadMessages = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .whereField("isRead", isEqualTo: false)
            .whereField("senderId", isNotEqualTo: userId)
            .getDocuments()
        
        for doc in unreadMessages.documents {
            batch.updateData(["isRead": true], forDocument: doc.reference)
        }
        
        // Update conversation unread count
        let conversationRef = db.collection("conversations").document(conversationId)
        batch.updateData([
            "unreadCounts.\(userId)": 0,
            "lastReadTimestamps.\(userId)": Date()
        ], forDocument: conversationRef)
        
        try await batch.commit()
        
        // Clear cache
        cache.remove(for: "conversations_page_1")
    }
    
    // MARK: - Private Helper Methods
    
    private func updateConversationLastMessage(_ conversationId: String, message: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("conversations").document(conversationId).updateData([
            "lastMessage": message,
            "lastMessageTimestamp": Date(),
            "lastMessageSenderId": userId,
            "updatedAt": Date()
        ])
    }
    
    private func updateConversationParticipantInfo(conversationId: String) async {
        do {
            let conversation = try await db.collection("conversations").document(conversationId).getDocument()
            guard let participantIds = conversation.data()?["participantIds"] as? [String] else { return }
            
            var participantNames: [String: String] = [:]
            var participantImages: [String: String] = [:]
            
            for participantId in participantIds {
                let userDoc = try await db.collection("users").document(participantId).getDocument()
                if let userData = userDoc.data() {
                    participantNames[participantId] = userData["name"] as? String ?? "Unknown"
                    if let imageURL = userData["profileImageURL"] as? String {
                        participantImages[participantId] = imageURL
                    }
                }
            }
            
            try await db.collection("conversations").document(conversationId).updateData([
                "participantNames": participantNames,
                "participantImages": participantImages
            ])
        } catch {
            print("Error updating participant info: \(error)")
        }
    }
    
    // MARK: - Real-time Listening
    
    func listenToConversation(_ conversationId: String, completion: @escaping ([Message]) -> Void) -> ListenerRegistration {
        // Remove existing listener
        messageListeners[conversationId]?.remove()
        
        let listener = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
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
        
        messageListeners[conversationId] = listener
        return listener
    }
    
    func stopListeningToConversation(_ conversationId: String) {
        messageListeners[conversationId]?.remove()
        messageListeners.removeValue(forKey: conversationId)
    }
    
    func removeAllListeners() {
        conversationListeners.values.forEach { $0.remove() }
        conversationListeners.removeAll()
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
    }
}
