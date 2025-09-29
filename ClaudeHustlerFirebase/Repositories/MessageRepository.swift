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
        guard let userId = FirebaseService.shared.currentUser?.id else {
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
    
    func fetchConversationMessages(
        conversationId: String,
        limit: Int = 50,
        lastDocument: DocumentSnapshot? = nil
    ) async throws -> (items: [Message], lastDoc: DocumentSnapshot?) {
        // Use top-level messages collection, not subcollection
        var query = db.collection("messages")  // NOT conversations/id/messages
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
        }.reversed()
        
        return (Array(messages), snapshot.documents.last)
    }
    
    // MARK: - Protocol Conformance Create (required by RepositoryProtocol)
    func create(_ item: Message) async throws -> String {
        // Message already has everything we need
        let conversationId = item.conversationId
        return try await create(item, in: conversationId)
    }

    // MARK: - Create Message with ConversationId
    // In MessageRepository.swift, update the create method's messageData:

    func create(_ message: Message, in conversationId: String) async throws -> String {
        let messageData: [String: Any] = [
            "senderId": message.senderId,
            "senderName": message.senderName,
            "senderProfileImage": message.senderProfileImage ?? "",
            "conversationId": conversationId,
            "text": message.text,
            "timestamp": Date(),
            "isRead": false,
            "isDeleted": false,
            "isDelivered": false,
            "contextType": message.contextType?.rawValue ?? "",
            "contextId": message.contextId ?? "",
            "contextTitle": message.contextTitle ?? "",     // ADD THIS
            "contextImage": message.contextImage ?? "",     // ADD THIS
            "contextUserId": message.contextUserId ?? ""    // ADD THIS
        ]
        
        print("DEBUG - Creating message with context: \(message.contextTitle ?? "no title")")
        
        // Rest of the method stays the same...
        let docRef = try await db.collection("messages")
            .addDocument(data: messageData)
        
        try await updateConversationLastMessage(conversationId, message: message.text, senderId: message.senderId)
        cache.remove(for: "messages_\(conversationId)")
        
        return docRef.documentID
    }

    // Helper method for updating conversation
    private func updateConversationLastMessage(_ conversationId: String, message: String, senderId: String) async throws {
        try await db.collection("conversations").document(conversationId).updateData([
            "lastMessage": message,
            "lastMessageTimestamp": Date(),
            "lastMessageSenderId": senderId,
            "updatedAt": Date()
        ])
    }
    
    // MARK: - Update Message (Edit)
    func update(_ message: Message) async throws {
        guard let messageId = message.id else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Message ID is required"])
        }
        
        guard let currentUserId = FirebaseService.shared.currentUser?.id else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Find the conversation that contains this message
        let conversationId = message.conversationId
        
        // Verify ownership - using top-level messages collection
        let document = try await db.collection("messages")
            .document(messageId)
            .getDocument()
        
        guard let data = document.data(),
              data["senderId"] as? String == currentUserId else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to edit this message"])
        }
        
        // Update message in top-level collection
        try await db.collection("messages")
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
        guard let currentUserId = FirebaseService.shared.currentUser?.id else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Get the message from top-level collection
        let messageDoc = try await db.collection("messages").document(id).getDocument()
        
        guard messageDoc.exists,
              let data = messageDoc.data(),
              data["senderId"] as? String == currentUserId else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Message not found or unauthorized"])
        }
        
        // Soft delete (mark as deleted but keep record)
        try await db.collection("messages")
            .document(id)
            .updateData([
                "isDeleted": true,
                "text": "This message was deleted",
                "deletedAt": Date()
            ])
        
        // Clear cache
        if let conversationId = data["conversationId"] as? String {
            cache.remove(for: "messages_\(conversationId)")
        }
    }
    
    // MARK: - Conversation Management
    
    func fetchConversations(limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [Conversation], lastDoc: DocumentSnapshot?) {
        guard let userId = FirebaseService.shared.currentUser?.id else {
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
        guard let currentUserId = FirebaseService.shared.currentUser?.id else {
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
    
    // MARK: - Private Helper Methods
    
    private func updateConversationParticipantInfo(conversationId: String) async {
        do {
            let conversation = try await db.collection("conversations").document(conversationId).getDocument()
            guard let participantIds = conversation.data()?["participantIds"] as? [String] else {
                print("❌ No participant IDs found for conversation: \(conversationId)")
                return
            }
            
            var participantNames: [String: String] = [:]
            var participantImages: [String: String] = [:]
            
            for participantId in participantIds {
                let userDoc = try await db.collection("users").document(participantId).getDocument()
                if let userData = userDoc.data() {
                    // Get name
                    participantNames[participantId] = userData["name"] as? String ?? "Unknown"
                    
                    // Get profile image URL - check different possible field names
                    if let imageURL = userData["profileImageURL"] as? String, !imageURL.isEmpty {
                        participantImages[participantId] = imageURL
                        print("✅ Found profile image for \(participantId): \(imageURL)")
                    } else if let imageURL = userData["profileImage"] as? String, !imageURL.isEmpty {
                        participantImages[participantId] = imageURL
                        print("✅ Found profile image (alt field) for \(participantId): \(imageURL)")
                    } else {
                        print("⚠️ No profile image for user \(participantId)")
                    }
                }
            }
            
            // Update the conversation with participant info
            try await db.collection("conversations").document(conversationId).updateData([
                "participantNames": participantNames,
                "participantImages": participantImages
            ])
            
            print("✅ Updated conversation \(conversationId) with participant info")
        } catch {
            print("❌ Error updating participant info for conversation \(conversationId): \(error)")
        }
    }
    
    // MARK: - Real-time Listening
    
    func listenToConversation(_ conversationId: String, completion: @escaping ([Message]) -> Void) -> ListenerRegistration {
        // Remove existing listener
        messageListeners[conversationId]?.remove()
        
        // Use TOP-LEVEL messages collection with filter
        let listener = db.collection("messages")  // NOT conversations/id/messages
            .whereField("conversationId", isEqualTo: conversationId)
            .whereField("isDeleted", isEqualTo: false)
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
    
    // MARK: - Additional Methods for Complete Migration

    func loadMessages(for conversationId: String, limit: Int = 50) async -> [Message] {
        do {
            let result = try await fetchConversationMessages(
                conversationId: conversationId,
                limit: limit
            )
            return result.items
        } catch {
            print("Error loading messages: \(error)")
            return []
        }
    }

    func sendMessage(
        to recipientId: String,
        text: String,
        contextType: Message.MessageContextType? = nil,
        contextId: String? = nil,
        contextData: (title: String, image: String?, userId: String)? = nil  // ADD THIS PARAMETER
    ) async throws {
        guard let currentUserId = FirebaseService.shared.currentUser?.id else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Find or create conversation
        let conversationId = try await findOrCreateConversation(with: recipientId)
        
        // Get current user info
        let userDoc = try await db.collection("users").document(currentUserId).getDocument()
        let userData = try? userDoc.data(as: User.self)
        
        // Create message
        let message = Message(
            senderId: currentUserId,
            senderName: userData?.name ?? "Unknown",
            senderProfileImage: userData?.profileImageURL,
            conversationId: conversationId,
            text: text,
            contextType: contextType,
            contextId: contextId,
            contextTitle: contextData?.title,  // ADD THIS
            contextImage: contextData?.image,  // ADD THIS
            contextUserId: contextData?.userId  // ADD THIS
        )
        
        _ = try await create(message, in: conversationId)
    }
    
    // Add these methods to MessageRepository.swift:

    // MARK: - Block/Unblock Users
    func blockUser(_ userId: String, in conversationId: String) async throws {
        guard let currentUserId = FirebaseService.shared.currentUser?.id else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        try await db.collection("conversations").document(conversationId).updateData([
            "blockedUsers": FieldValue.arrayUnion([userId])
        ])
        
        cache.remove(for: "conversation_\(conversationId)")
    }

    func unblockUser(_ userId: String, in conversationId: String) async throws {
        guard let currentUserId = FirebaseService.shared.currentUser?.id else {
            throw NSError(domain: "MessageRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        try await db.collection("conversations").document(conversationId).updateData([
            "blockedUsers": FieldValue.arrayRemove([userId])
        ])
        
        cache.remove(for: "conversation_\(conversationId)")
    }

    // MARK: - Delete Conversation
    func deleteConversation(_ conversationId: String) async throws {
        // Delete all messages in the conversation
        let messages = try await db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .getDocuments()
        
        let batch = db.batch()
        
        for doc in messages.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Delete the conversation document
        batch.deleteDocument(db.collection("conversations").document(conversationId))
        
        try await batch.commit()
        
        // Clear cache
        cache.remove(for: "conversation_\(conversationId)")
        cache.remove(for: "messages_\(conversationId)")
    }
    // Add this method for loading conversations (currently missing the proper implementation)
    func loadConversations() async -> [Conversation] {
        do {
            let result = try await fetchConversations(limit: 50)
            
            // Ensure participant info is up to date for all conversations
            await refreshAllConversationsParticipantInfo()
            
            // Fetch again to get updated data
            let updatedResult = try await fetchConversations(limit: 50)
            return updatedResult.items
        } catch {
            print("Error loading conversations: \(error)")
            return []
        }
    }

    // Add the complete listenToMessages implementation (move from FirebaseService)
    func listenToMessages(in conversationId: String, completion: @escaping ([Message]) -> Void) -> ListenerRegistration {
        // Remove any existing listener for this conversation
        messageListeners[conversationId]?.remove()
        
        let listener = db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to messages: \(error)")
                    return
                }
                
                print("DEBUG - Listener received \(snapshot?.documents.count ?? 0) documents")
                
                let messages: [Message] = snapshot?.documents.compactMap { doc in
                    let data = doc.data()
                    
                    // Filter out deleted messages
                    if let isDeleted = data["isDeleted"] as? Bool, isDeleted {
                        return nil
                    }
                    
                    // Manual message creation to avoid decoding issues
                    guard let senderId = data["senderId"] as? String,
                          let text = data["text"] as? String,
                          let conversationId = data["conversationId"] as? String else {
                        return nil
                    }
                    
                    var message = Message(
                        senderId: senderId,
                        senderName: data["senderName"] as? String ?? "Unknown",
                        senderProfileImage: data["senderProfileImage"] as? String,
                        conversationId: conversationId,
                        text: text
                    )
                    
                    // Set all optional fields
                    message.id = doc.documentID
                    
                    if let timestamp = data["timestamp"] as? Timestamp {
                        message.timestamp = timestamp.dateValue()
                    }
                    
                    message.isDelivered = data["isDelivered"] as? Bool ?? false
                    message.isRead = data["isRead"] as? Bool ?? false
                    
                    if let deliveredAt = data["deliveredAt"] as? Timestamp {
                        message.deliveredAt = deliveredAt.dateValue()
                    }
                    
                    if let readAt = data["readAt"] as? Timestamp {
                        message.readAt = readAt.dateValue()
                    }
                    
                    // Handle context fields
                    if let contextType = data["contextType"] as? String, !contextType.isEmpty {
                        message.contextType = Message.MessageContextType(rawValue: contextType)
                    }
                    
                    if let contextId = data["contextId"] as? String, !contextId.isEmpty {
                        message.contextId = contextId
                    }
                    
                    message.contextTitle = data["contextTitle"] as? String
                    message.contextImage = data["contextImage"] as? String
                    message.contextUserId = data["contextUserId"] as? String
                    
                    message.isEdited = data["isEdited"] as? Bool ?? false
                    if let editedAt = data["editedAt"] as? Timestamp {
                        message.editedAt = editedAt.dateValue()
                    }
                    
                    return message
                } ?? []
                
                print("DEBUG - Listener triggered with \(messages.count) messages")
                completion(messages)
            }
        
        messageListeners[conversationId] = listener
        return listener
    }

    // Add the complete markMessagesAsRead implementation (move from FirebaseService)
    func markMessagesAsRead(conversationId: String) async throws {
        guard let currentUserId = FirebaseService.shared.currentUser?.id else { return }
        
        // Get all unread messages in this conversation for current user
        let unreadMessages = try await db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .whereField("senderId", isNotEqualTo: currentUserId)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()
        
        // Batch update all unread messages
        let batch = db.batch()
        
        for document in unreadMessages.documents {
            batch.updateData([
                "isRead": true,
                "readAt": Date()
            ], forDocument: document.reference)
        }
        
        // Also mark messages sent by current user as delivered if not already
        let sentMessages = try await db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .whereField("senderId", isEqualTo: currentUserId)
            .whereField("isDelivered", isEqualTo: false)
            .getDocuments()
        
        for document in sentMessages.documents {
            batch.updateData([
                "isDelivered": true,
                "deliveredAt": Date()
            ], forDocument: document.reference)
        }
        
        // Commit all updates
        if !unreadMessages.documents.isEmpty || !sentMessages.documents.isEmpty {
            try await batch.commit()
        }
        
        // Update conversation unread count
        do {
            try await db.collection("conversations")
                .document(conversationId)
                .updateData([
                    "unreadCounts.\(currentUserId)": 0,
                    "lastReadTimestamps.\(currentUserId)": Date()
                ])
        } catch {
            print("Could not update conversation: \(error)")
        }
        
        // Clear cache
        cache.remove(for: "messages_\(conversationId)")
    }
    
    func refreshAllConversationsParticipantInfo() async {
        guard let userId = FirebaseService.shared.currentUser?.id else { return }
        
        do {
            // Get all conversations for the current user
            let snapshot = try await db.collection("conversations")
                .whereField("participantIds", arrayContains: userId)
                .getDocuments()
            
            // Update participant info for each conversation
            for doc in snapshot.documents {
                await updateConversationParticipantInfo(conversationId: doc.documentID)
            }
            
            print("✅ Updated participant info for \(snapshot.documents.count) conversations")
        } catch {
            print("❌ Error refreshing conversation participant info: \(error)")
        }
    }
}
