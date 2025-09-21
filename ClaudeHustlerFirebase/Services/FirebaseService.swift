// FirebaseService.swift
// Path: ClaudeHustlerFirebase/Services/FirebaseService.swift

import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit
import SDWebImage

typealias AppUser = User  // Your custom User model
typealias AuthUser = FirebaseAuth.User  // Firebase Auth User

@MainActor
class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    let db = Firestore.firestore()
    let auth = Auth.auth()
    let storage = Storage.storage(url: "gs://hustlernew-968dd.firebasestorage.app")
    
//    private let reelRepository = ReelRepository.shared
//    private let messageRepository = MessageRepository.shared
//    private let userRepository = UserRepository.shared
//    private let reviewRepository = ReviewRepository.shared
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var posts: [ServicePost] = []
    @Published var offers: [ServicePost] = []
    @Published var requests: [ServicePost] = []
    @Published var statuses: [Status] = []
    @Published var reels: [Reel] = []
    @Published var isLoading = false
    
    // Listener properties for cleanup
    private var conversationsListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?
    
    private init() {
        setupAuthListener()
    }
    
    private func setupAuthListener() {
        auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                print("Auth state changed - User UID: \(user?.uid ?? "nil")")
                self?.isAuthenticated = user != nil
                if let userId = user?.uid {
                    print("Loading user with ID: \(userId)")
                    await self?.loadUser(userId: userId)
                    print("After loadUser - currentUser ID: \(self?.currentUser?.id ?? "nil")")
                } else {
                    self?.currentUser = nil
                }
            }
        }
    }
    
    // MARK: - Authentication
    
    func signIn(email: String, password: String) async throws {
        try await auth.signIn(withEmail: email, password: password)
    }
    
    func signUp(email: String, password: String, name: String) async throws {
        let result = try await auth.createUser(withEmail: email, password: password)
        
        let userData: [String: Any] = [
            "email": email,
            "name": name,
            "bio": "",
            "isServiceProvider": false,
            "location": "",
            "rating": 0.0,
            "reviewCount": 0,
            "following": [],
            "followers": [],
            "createdAt": Date()
        ]
        
        try await db.collection("users").document(result.user.uid).setData(userData)
    }
    
    func cleanupOnSignOut() {
        // Remove all listeners
        conversationsListener?.remove()
        messagesListener?.remove()
        
        // Clear cached data
        currentUser = nil
        posts = []
        offers = []
        requests = []
        statuses = []
        reels = []
        
        // Clear any additional cached data
        isLoading = false
    }
    
    func signOut() throws {
        cleanupOnSignOut()
        try auth.signOut()
    }
    
    // MARK: - User Management
    
    private func loadUser(userId: String) async {
        print("loadUser called with userId: \(userId)")
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            print("Document exists: \(document.exists)")
            
            if document.exists {
                let data = document.data() ?? [:]
                print("Document data keys: \(data.keys)")
                
                do {
                    currentUser = try document.data(as: User.self)
                    print("Successfully decoded user: \(currentUser?.id ?? "nil")")
                } catch {
                    print("Failed to decode user: \(error)")
                    
                    currentUser = User(
                        id: userId,
                        email: data["email"] as? String ?? "",
                        name: data["name"] as? String ?? "User",
                        profileImageURL: data["profileImageURL"] as? String,
                        bio: data["bio"] as? String ?? "",
                        isServiceProvider: data["isServiceProvider"] as? Bool ?? false,
                        location: data["location"] as? String ?? "",
                        rating: data["rating"] as? Double ?? 0.0,
                        reviewCount: data["reviewCount"] as? Int ?? 0,
                        following: data["following"] as? [String] ?? [],
                        followers: data["followers"] as? [String] ?? []
                    )
                    print("Manually created user: \(currentUser?.id ?? "nil")")
                }
            }
        } catch {
            print("Error in loadUser: \(error)")
        }
    }
    
    
    // MARK: - Reels
    
    func loadReels() async {
        do {
            let (reels, _) = try await ReelRepository.shared.fetch(limit: 50)
            self.reels = reels
        } catch {
            print("Error loading reels: \(error)")
            self.reels = []
        }
    }
    
    func createReel(
        videoURL: String,
        thumbnailImage: UIImage?,
        title: String,
        description: String,
        category: ServiceCategory?,
        hashtags: [String] = []
    ) async throws -> String {
        guard let userId = currentUser?.id,
              let userName = currentUser?.name else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        var thumbnailURL = ""
        if let thumbnail = thumbnailImage {
            thumbnailURL = try await uploadImage(thumbnail, path: "reels/\(userId)/thumbnails/\(UUID().uuidString).jpg")
        }
        
        let reel = Reel(
            userId: userId,
            userName: userName,
            userProfileImage: currentUser?.profileImageURL,
            videoURL: videoURL,
            thumbnailURL: thumbnailURL.isEmpty ? nil : thumbnailURL,
            title: title,
            description: description,
            category: category,
            hashtags: hashtags
        )
        
        let reelId = try await ReelRepository.shared.create(reel)
        
        // Refresh reels in view model if needed
        await ReelsViewModel.shared?.loadInitialReels()
        
        return reelId
    }
    
    func createImageReel(
        image: UIImage,
        title: String,
        description: String,
        category: ServiceCategory? = nil
    ) async throws -> String {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let imageURL = try await uploadImage(image, path: "reels/\(userId)/\(UUID().uuidString).jpg")
        
        return try await createReel(
            videoURL: imageURL,
            thumbnailImage: image,
            title: title,
            description: description,
            category: category
        )
    }

    
    // MARK: - Status Interactions
    
    func viewStatus(_ statusId: String) async {
        guard let userId = currentUser?.id else { return }
        
        do {
            let statusRef = db.collection("statuses").document(statusId)
            try await statusRef.updateData([
                "viewedBy": FieldValue.arrayUnion([userId])
            ])
        } catch {
            print("Error marking status as viewed: \(error)")
        }
    }
    
    // MARK: - Image Upload
    
    func uploadImage(_ image: UIImage, path: String) async throws -> String {
        
        
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "ImageError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])
        }
        
        // Create a fresh reference each time
        let storageRef = Storage.storage().reference().child(path)
        
        
        
        // Use metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        do {
            // Upload the data
            let uploadTask = try await storageRef.putDataAsync(imageData, metadata: metadata)
            
            
            // Get the download URL
            let downloadURL = try await storageRef.downloadURL()
            
            
            return downloadURL.absoluteString
        } catch {
            
            throw error
        }
    }
    // MARK: - Following System
    
    // In FirebaseService.swift, replace the existing methods:
    func followUser(_ targetUserId: String) async throws {
        guard let currentUserId = currentUser?.id else { return }
        
        try await UserRepository.shared.followUser(targetUserId)
        
        // Reload current user and statuses
        await loadUser(userId: currentUserId)
        
        // Use StatusRepository for loading statuses
        if let user = currentUser {
            var userIds = user.following
            userIds.append(currentUserId)
            statuses = try await StatusRepository.shared.fetchStatusesFromFollowing(userIds: userIds)
        }
    }

    func unfollowUser(_ targetUserId: String) async throws {
        guard let currentUserId = currentUser?.id else { return }
        
        try await UserRepository.shared.unfollowUser(targetUserId)
        
        // Reload current user and statuses
        await loadUser(userId: currentUserId)
        
        // Use StatusRepository for loading statuses
        if let user = currentUser {
            var userIds = user.following
            userIds.append(currentUserId)
            statuses = try await StatusRepository.shared.fetchStatusesFromFollowing(userIds: userIds)
        }
    }
    
    
    // MARK: - Cache Management

    func clearImageCache() {
        SDImageCache.shared.clearMemory()
        SDImageCache.shared.clearDisk {
            print("Image cache cleared")
        }
    }
}

// MARK: - Profile Updates Extension
extension FirebaseService {
    
    func refreshCurrentUser() async {
        guard let userId = currentUser?.id else { return }
        await loadUser(userId: userId)
    }
    
    func updateUserProfile(
        name: String? = nil,
        bio: String? = nil,
        location: String? = nil,
        profileImageURL: String? = nil,
        isServiceProvider: Bool? = nil
    ) async throws {
        guard var user = currentUser else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Update the user object with new values
        if let name = name { user.name = name }
        if let bio = bio { user.bio = bio }
        if let location = location { user.location = location }
        if let profileImageURL = profileImageURL { user.profileImageURL = profileImageURL }
        if let isServiceProvider = isServiceProvider { user.isServiceProvider = isServiceProvider }
        
        // Use UserRepository to update
        try await UserRepository.shared.update(user)
        
        // Reload current user
        if let userId = user.id {
            await loadUser(userId: userId)
        }
    }
    
    func isFollowing(userId: String) -> Bool {
        return currentUser?.following.contains(userId) ?? false
    }
    
    func getFollowerCount(for userId: String) async -> Int {
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            if let user = try? document.data(as: User.self) {
                return user.followers.count
            }
        } catch {
            print("Error getting follower count: \(error)")
        }
        return 0
    }
    
    func getFollowingCount(for userId: String) async -> Int {
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            if let user = try? document.data(as: User.self) {
                return user.following.count
            }
        } catch {
            print("Error getting following count: \(error)")
        }
        return 0
    }
    
    func updateLastActive() async {
        guard let userId = currentUser?.id else { return }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "lastActive": Date()
            ])
        } catch {
            print("Error updating last active: \(error)")
        }
    }
}

// MARK: - Portfolio Management Extension
extension FirebaseService {
    
    
    // Fixed createPortfolioCard method for FirebaseService.swift
    // Replace the existing method around line 577 with this version

    func createPortfolioCard(title: String, coverImage: UIImage?, mediaImages: [UIImage], description: String?) async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        print("Creating portfolio for user: \(userId)")
        
        // Upload media images
        var mediaURLs: [String] = []
        for (index, image) in mediaImages.enumerated() {
            let path = "portfolio/\(userId)/\(UUID().uuidString)_\(index).jpg"
            let url = try await uploadImage(image, path: path)
            mediaURLs.append(url)
            print("Uploaded image \(index + 1)/\(mediaImages.count)")
        }
        
        // Upload cover image
        var coverURL: String?
        if let cover = coverImage {
            let path = "portfolio/\(userId)/covers/\(UUID().uuidString).jpg"
            coverURL = try await uploadImage(cover, path: path)
            print("Uploaded cover image")
        } else if !mediaURLs.isEmpty {
            coverURL = mediaURLs.first
        }
        
        // Get existing cards count for display order using PortfolioRepository
        let existingCards = try await PortfolioRepository.shared.fetchPortfolioCards(for: userId)
        
        // Create the portfolio card using PortfolioRepository
        let newCard = PortfolioCard(
            userId: userId,
            title: title,
            coverImageURL: coverURL ?? "",
            mediaURLs: mediaURLs,
            description: description ?? "",
            displayOrder: existingCards.count
        )
        
        let cardId = try await PortfolioRepository.shared.createPortfolioCard(newCard)
        print("Portfolio saved with ID: \(cardId)")
    }
}




// MARK: - Enhanced Reels & Comments Extension
extension FirebaseService {
    
    // Listener storage
    private static var reelListeners: [String: ListenerRegistration] = [:]
    private static var likesListeners: [String: ListenerRegistration] = [:]
    
    // MARK: - Real-time Reel Listening
    
    
    
    
    // MARK: - Enhanced Likes Management
    
    
    
    // MARK: - Update Reel Caption (remove placeholders)
    
    func updateReelCaption(_ reelId: String, title: String, description: String) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Get the reel to update
        guard var reel = try await ReelRepository.shared.fetchById(reelId) else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Reel not found"])
        }
        
        // Verify ownership
        guard reel.userId == currentUserId else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to edit this reel"])
        }
        
        // Update the reel
        reel.title = title
        reel.description = description
        
        try await ReelRepository.shared.update(reel)
    }
    
    // MARK: - Cleanup
    
    func stopListeningToLikes(_ reelId: String) {
        Self.likesListeners[reelId]?.remove()
        Self.likesListeners.removeValue(forKey: reelId)
    }
}

// MARK: - Followers/Following Lists Extension
extension FirebaseService {
    
    // Update getFollowers/getFollowing in FirebaseService:
    func getFollowers(for userId: String) async -> [User] {
        do {
            return try await UserRepository.shared.fetchFollowers(for: userId)
        } catch {
            return []
        }
    }

    func getFollowing(for userId: String) async -> [User] {
        do {
            return try await UserRepository.shared.fetchFollowing(for: userId)
        } catch {
            print("Error getting following: \(error)")
            return []
        }
    }
}

// MARK: - Messaging Extension for FirebaseService
extension FirebaseService {
    
    // MARK: - Conversation Management
    
    /// Find or create a conversation between two users
    func findOrCreateConversation(with otherUserId: String) async throws -> String {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "MessagingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Check if conversation already exists
        let participantIds = [currentUserId, otherUserId].sorted()
        
        let existingConversations = try await db.collection("conversations")
            .whereField("participantIds", isEqualTo: participantIds)
            .getDocuments()
        
        if let existingConversation = existingConversations.documents.first {
            return existingConversation.documentID
        }
        
        // Create new conversation
        let otherUser = try await getUserInfo(userId: otherUserId)
        
        let conversationData: [String: Any] = [
            "participantIds": participantIds,
            "participantNames": [
                currentUserId: currentUser?.name ?? "Unknown",
                otherUserId: otherUser?.name ?? "Unknown"
            ],
            "participantImages": [
                currentUserId: currentUser?.profileImageURL ?? "",
                otherUserId: otherUser?.profileImageURL ?? ""
            ],
            "unreadCounts": [
                currentUserId: 0,
                otherUserId: 0
            ],
            "createdAt": Date(),
            "updatedAt": Date(),
            "blockedUsers": []
        ]
        
        let newConversation = try await db.collection("conversations").addDocument(data: conversationData)
        return newConversation.documentID
    }
    
    /// Load all conversations for current user
    func loadConversations() async -> [Conversation] {
        guard let userId = currentUser?.id else { return [] }
        
        do {
            let snapshot = try await db.collection("conversations")
                .whereField("participantIds", arrayContains: userId)
                .order(by: "lastMessageTimestamp", descending: true)
                .getDocuments()
            
            let conversations = snapshot.documents.compactMap { doc in
                if var conversation = try? doc.data(as: Conversation.self) {
                    conversation.id = doc.documentID
                    return conversation
                }
                return nil
            }
            
            // Filter out conversations where user is blocked
            return conversations.filter { !$0.isBlocked(by: userId) }
        } catch {
            print("Error loading conversations: \(error)")
            return []
        }
    }
    
    // MARK: - Message Management
    
    /// Send a message with optional context
    func sendMessage(
        to recipientId: String,
        text: String,
        contextType: Message.MessageContextType? = nil,
        contextId: String? = nil,
        contextData: (title: String, image: String?, userId: String)? = nil
    ) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "MessagingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Debug logging
        if let contextType = contextType, let contextId = contextId {
            print("📤 Sending message with context - Type: \(contextType.rawValue), ID: \(contextId)")
        }
        
        // Find or create conversation
        let conversationId = try await findOrCreateConversation(with: recipientId)
        
        // Create message data
        var messageData: [String: Any] = [
            "senderId": currentUserId,
            "senderName": currentUser?.name ?? "Unknown",
            "conversationId": conversationId,
            "text": text,
            "timestamp": Date(),
            "isDelivered": false,
            "isRead": false,
            "isEdited": false,
            "isDeleted": false
        ]
        
        if let profileImage = currentUser?.profileImageURL {
            messageData["senderProfileImage"] = profileImage
        }
        
        // Add context if provided
        if let contextType = contextType,
           let contextId = contextId,
           let contextData = contextData {
            messageData["contextType"] = contextType.rawValue
            messageData["contextId"] = contextId  // This should be the actual document ID
            messageData["contextTitle"] = contextData.title
            messageData["contextUserId"] = contextData.userId
            
            if let image = contextData.image {
                messageData["contextImage"] = image
            }
            
            print("📤 Message data with context: contextId = \(contextId)")
        }
        
        // Save message
        let messageRef = try await db.collection("messages").addDocument(data: messageData)
        
        // Update conversation
        let conversationUpdate: [String: Any] = [
            "lastMessage": text,
            "lastMessageTimestamp": Date(),
            "lastMessageSenderId": currentUserId,
            "updatedAt": Date(),
            "unreadCounts.\(recipientId)": FieldValue.increment(Int64(1))
        ]
        
        try await db.collection("conversations")
            .document(conversationId)
            .updateData(conversationUpdate)
        
        // Mark as delivered (in real app, this would happen when recipient receives it)
        try await markMessageAsDelivered(messageRef.documentID)
    }
    
    /// Load messages for a conversation
    func loadMessages(for conversationId: String, limit: Int = 50) async -> [Message] {
        do {
            let snapshot = try await db.collection("messages")
                .whereField("conversationId", isEqualTo: conversationId)
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "timestamp", descending: true)
                .limit(to: limit)
                .getDocuments()
            
            let messages = snapshot.documents.compactMap { doc in
                if var message = try? doc.data(as: Message.self) {
                    message.id = doc.documentID
                    return message
                }
                return nil
            }
            
            // Return in chronological order
            return messages.reversed()
        } catch {
            print("Error loading messages: \(error)")
            return []
        }
    }
    
    // MARK: - Read Receipts
    
    /// Mark message as delivered
    private func markMessageAsDelivered(_ messageId: String) async throws {
        try await db.collection("messages").document(messageId).updateData([
            "isDelivered": true,
            "deliveredAt": Date()
        ])
    }
    
    /// Mark messages as read
    func markMessagesAsRead(in conversationId: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        // Get unread messages
        let unreadMessages = try await db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .whereField("senderId", isNotEqualTo: userId)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()
        
        // Batch update messages as read
        let batch = db.batch()
        let readTime = Date()
        
        for document in unreadMessages.documents {
            batch.updateData([
                "isRead": true,
                "readAt": readTime
            ], forDocument: document.reference)
        }
        
        // Reset unread count for current user
        let conversationRef = db.collection("conversations").document(conversationId)
        batch.updateData([
            "unreadCounts.\(userId)": 0,
            "lastReadTimestamps.\(userId)": readTime
        ], forDocument: conversationRef)
        
        try await batch.commit()
    }
    
    // MARK: - Real-time Listeners
    
    /// Listen to conversation updates
    func listenToConversations(completion: @escaping ([Conversation]) -> Void) -> ListenerRegistration? {
        guard let userId = currentUser?.id else { return nil }
        
        // Remove any existing listener
        conversationsListener?.remove()
        
        // Create and store new listener
        conversationsListener = db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .order(by: "lastMessageTimestamp", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to conversations: \(error)")
                    return
                }
                
                let conversations: [Conversation] = snapshot?.documents.compactMap { doc in
                    if var conversation = try? doc.data(as: Conversation.self) {
                        conversation.id = doc.documentID
                        return conversation
                    }
                    return nil
                } ?? []
                
                // Filter out blocked conversations
                let filteredConversations = conversations.filter { conversation in
                    !conversation.isBlocked(by: userId)
                }
                completion(filteredConversations)
            }
        
        return conversationsListener
    }
    
    /// Listen to messages in a conversation
    func listenToMessages(in conversationId: String, completion: @escaping ([Message]) -> Void) -> ListenerRegistration {
        // Remove any existing listener
        messagesListener?.remove()
        
        // Create and store new listener
        messagesListener = db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to messages: \(error)")
                    return
                }
                
                let messages: [Message] = snapshot?.documents.compactMap { doc in
                    if var message = try? doc.data(as: Message.self) {
                        message.id = doc.documentID
                        return message
                    }
                    return nil
                } ?? []
                
                completion(messages)
            }
        
        return messagesListener!
    }
    
    // MARK: - Blocking & Reporting
    
    /// Block a user
    func blockUser(_ userId: String, in conversationId: String) async throws {
        guard let currentUserId = currentUser?.id else { return }
        
        try await db.collection("conversations").document(conversationId).updateData([
            "blockedUsers": FieldValue.arrayUnion([currentUserId])
        ])
    }
    
    /// Unblock a user
    func unblockUser(_ userId: String, in conversationId: String) async throws {
        guard let currentUserId = currentUser?.id else { return }
        
        try await db.collection("conversations").document(conversationId).updateData([
            "blockedUsers": FieldValue.arrayRemove([currentUserId])
        ])
    }
    
    /// Report a message or conversation
    func reportMessage(
        messageId: String? = nil,
        conversationId: String,
        reportedUserId: String,
        reason: MessageReport.ReportReason,
        details: String? = nil
    ) async throws {
        guard let reporterId = currentUser?.id else { return }
        
        let reportData: [String: Any] = [
            "reporterId": reporterId,
            "reportedUserId": reportedUserId,
            "conversationId": conversationId,
            "reason": reason.rawValue,
            "timestamp": Date(),
            "status": MessageReport.ReportStatus.pending.rawValue
        ]
        
        var mutableReportData = reportData
        if let messageId = messageId {
            mutableReportData["messageId"] = messageId
        }
        if let details = details {
            mutableReportData["additionalDetails"] = details
        }
        
        try await db.collection("reports").addDocument(data: mutableReportData)
    }
    
    // MARK: - Helper Functions
    
    /// Get user info
    private func getUserInfo(userId: String) async throws -> User? {
        let document = try await db.collection("users").document(userId).getDocument()
        if var user = try? document.data(as: User.self) {
            user.id = document.documentID
            return user
        }
        return nil
    }
    
    /// Get total unread message count
    func getTotalUnreadCount() async -> Int {
        guard let userId = currentUser?.id else { return 0 }
        
        let conversations = await loadConversations()
        return conversations.reduce(0) { total, conversation in
            total + (conversation.unreadCounts[userId] ?? 0)
        }
    }
    
    /// Delete a message (soft delete)
    func deleteMessage(_ messageId: String) async throws {
        try await db.collection("messages").document(messageId).updateData([
            "isDeleted": true
        ])
    }
    
    /// Edit a message
    func editMessage(_ messageId: String, newText: String) async throws {
        try await db.collection("messages").document(messageId).updateData([
            "text": newText,
            "isEdited": true,
            "editedAt": Date()
        ])
    }
}

// MARK: - Chat Management Extension
extension FirebaseService {
    
    /// Clear all messages in a conversation (for testing)
    func clearConversation(_ conversationId: String) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "MessagingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Get all messages in the conversation
        let messagesSnapshot = try await db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .getDocuments()
        
        // Delete all messages using batch
        let batch = db.batch()
        for document in messagesSnapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        // Get the other participant's ID
        let conversationDoc = try await db.collection("conversations").document(conversationId).getDocument()
        guard let conversationData = conversationDoc.data(),
              let participantIds = conversationData["participantIds"] as? [String] else {
            throw NSError(domain: "MessagingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid conversation data"])
        }
        
        let otherUserId = participantIds.first { $0 != currentUserId } ?? ""
        
        // Reset conversation metadata
        let conversationRef = db.collection("conversations").document(conversationId)
        batch.updateData([
            "lastMessage": FieldValue.delete(),
            "lastMessageTimestamp": Date(),
            "lastMessageSenderId": FieldValue.delete(),
            "unreadCounts": [
                currentUserId: 0,
                otherUserId: 0
            ],
            "updatedAt": Date()
        ], forDocument: conversationRef)
        
        // Commit the batch
        try await batch.commit()
        
        print("Conversation \(conversationId) cleared successfully")
    }
    
    /// Delete a single conversation entirely (optional - for complete removal)
    func deleteConversation(_ conversationId: String) async throws {
        guard let currentUserId = currentUser?.id else {
            throw NSError(domain: "MessagingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify user is a participant
        let conversationDoc = try await db.collection("conversations").document(conversationId).getDocument()
        guard let data = conversationDoc.data(),
              let participantIds = data["participantIds"] as? [String],
              participantIds.contains(currentUserId) else {
            throw NSError(domain: "MessagingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not authorized to delete this conversation"])
        }
        
        // Delete all messages first
        let messagesSnapshot = try await db.collection("messages")
            .whereField("conversationId", isEqualTo: conversationId)
            .getDocuments()
        
        let batch = db.batch()
        
        // Delete all messages
        for document in messagesSnapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        // Delete the conversation itself
        batch.deleteDocument(conversationDoc.reference)
        
        // Commit the batch
        try await batch.commit()
        
        print("Conversation \(conversationId) and all messages deleted successfully")
    }
    
    /// Get message count for a conversation (for debugging)
    func getMessageCount(for conversationId: String) async -> Int {
        do {
            let snapshot = try await db.collection("messages")
                .whereField("conversationId", isEqualTo: conversationId)
                .getDocuments()
            return snapshot.documents.count
        } catch {
            print("Error getting message count: \(error)")
            return 0
        }
    }
}

// Add these methods to FirebaseService.swift

// MARK: - Edit/Delete Operations Extension
extension FirebaseService {
    
    // MARK: - Batch Operations
    
    /// Delete all expired content for a user
    func cleanupUserContent() async {
        guard let userId = currentUser?.id else { return }
        
        do {
            // Clean up expired statuses
            let expiredStatuses = try await db.collection("statuses")
                .whereField("userId", isEqualTo: userId)
                .whereField("expiresAt", isLessThan: Date())
                .getDocuments()
            
            for document in expiredStatuses.documents {
                try await document.reference.delete()
            }
            
            print("Cleaned up \(expiredStatuses.documents.count) expired statuses")
        } catch {
            print("Error cleaning up user content: \(error)")
        }
    }
    
    /// Get user's content statistics
    func getUserContentStats() async -> (posts: Int, reels: Int, activeStatuses: Int) {
        guard let userId = currentUser?.id else { return (0, 0, 0) }
        
        do {
            // Count posts
            let posts = try await db.collection("posts")
                .whereField("userId", isEqualTo: userId)
                .whereField("status", isEqualTo: ServicePost.PostStatus.active.rawValue)
                .getDocuments()
            
            // Count reels
            let reels = try await db.collection("reels")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            
            // Count active statuses
            let statuses = try await db.collection("statuses")
                .whereField("userId", isEqualTo: userId)
                .whereField("isActive", isEqualTo: true)
                .whereField("expiresAt", isGreaterThan: Date())
                .getDocuments()
            
            return (posts.documents.count, reels.documents.count, statuses.documents.count)
        } catch {
            print("Error getting user content stats: \(error)")
            return (0, 0, 0)
        }
    }
}

// MARK: - Global Listener Management
extension FirebaseService {
    
    /// Remove ALL active listeners (useful for sign out)
    func removeAllListeners() {
        // Remove conversation listeners
        conversationsListener?.remove()
        conversationsListener = nil
        
        // Remove messages listener
        messagesListener?.remove()
        messagesListener = nil
        
        // Remove all reel listeners
        Self.reelListeners.values.forEach { $0.remove() }
        Self.reelListeners.removeAll()
        
        // Remove all likes listeners
        Self.likesListeners.values.forEach { $0.remove() }
        Self.likesListeners.removeAll()
        
        
        
        print("✅ All Firebase listeners cleaned up")
    }
    
    /// Get count of active listeners (for debugging)
    func getActiveListenerCount() -> Int {
        var count = 0
        if conversationsListener != nil { count += 1 }
        if messagesListener != nil { count += 1 }
        count += Self.reelListeners.count
        count += Self.likesListeners.count
        return count
    }
}

#if DEBUG
var listenerDebugTimer: Timer?

func startListenerMonitoring() {
    listenerDebugTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
        let count = FirebaseService.shared.getActiveListenerCount()  // ✅ Fixed - use shared instance
        print("🔍 Active Listeners: \(count)")
    }
}

func stopListenerMonitoring() {
    listenerDebugTimer?.invalidate()
    listenerDebugTimer = nil
}
#endif

