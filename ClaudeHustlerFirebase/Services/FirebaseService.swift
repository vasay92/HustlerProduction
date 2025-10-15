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
    @Published var isLoading = false
    
    
    
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
        // Clear cached data
        currentUser = nil
        
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
    
    

    
    
    // MARK: - Image Upload
    
    func uploadImage(_ image: UIImage, path: String) async throws -> String {
            print("🖼️ FirebaseService.uploadImage called")
            print("  Path: \(path)")
            
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                print("❌ Failed to convert image to JPEG data")
                throw NSError(domain: "ImageError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])
            }
            
            print("  Image data size: \(imageData.count) bytes (\(imageData.count / 1024)KB)")
            
            // Create a fresh reference each time
            let storageRef = Storage.storage().reference().child(path)
            
            // Use metadata
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            do {
                print("  📤 Uploading to Firebase Storage...")
                // Upload the data
                let uploadTask = try await storageRef.putDataAsync(imageData, metadata: metadata)
                print("  ✅ Upload successful")
                
                print("  Getting download URL...")
                // Get the download URL
                let downloadURL = try await storageRef.downloadURL()
                let urlString = downloadURL.absoluteString
                
                print("  ✅ Got download URL: \(urlString)")
                return urlString
            } catch {
                print("  ❌ Upload failed: \(error)")
                print("  Error details: \(error.localizedDescription)")
                throw error
            }
        }

    // MARK: - Following System
    
    // SIMPLIFIED VERSION - Keep in FirebaseService:
    func followUser(_ targetUserId: String) async throws {
        guard let currentUserId = currentUser?.id else { return }
        
        try await UserRepository.shared.followUser(targetUserId)
        
        // Just reload current user
        await loadUser(userId: currentUserId)
    }

    func unfollowUser(_ targetUserId: String) async throws {
        guard let currentUserId = currentUser?.id else { return }
        
        try await UserRepository.shared.unfollowUser(targetUserId)
        
        // Just reload current user
        await loadUser(userId: currentUserId)
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

    func createPortfolioCard(
        title: String,
        coverImage: UIImage?,
        mediaImages: [UIImage],
        description: String?
    ) async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Upload images
        var imageURLs: [String] = []
        
        // Upload cover image if provided
        if let coverImage = coverImage {
            let coverURL = try await uploadImage(coverImage, path: "portfolio/\(userId)/\(UUID().uuidString).jpg")
            imageURLs.append(coverURL)
        }
        
        // Upload media images
        for image in mediaImages {
            let imageURL = try await uploadImage(image, path: "portfolio/\(userId)/\(UUID().uuidString).jpg")
            imageURLs.append(imageURL)
        }
        
        // Get existing cards count for display order
        let existingCards = try await PortfolioRepository.shared.fetchPortfolioCards(for: userId)
        
        // Create portfolio card with CORRECT parameter order from the actual implementation
        let card = PortfolioCard(
            userId: userId,
            title: title,
            coverImageURL: imageURLs.first,      // coverImageURL comes BEFORE mediaURLs
            mediaURLs: imageURLs,                 // mediaURLs comes AFTER coverImageURL
            description: description ?? "",       // description comes AFTER mediaURLs
            displayOrder: existingCards.count     // displayOrder is last
        )
        
        // Use the actual method name from PortfolioRepository
        _ = try await PortfolioRepository.shared.createPortfolioCard(card)
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
        
        
    }
    
  
    
    /// Get message count for a conversation (for debugging)
    func getMessageCount(for conversationId: String) async -> Int {
        do {
            let snapshot = try await db.collection("messages")
                .whereField("conversationId", isEqualTo: conversationId)
                .getDocuments()
            return snapshot.documents.count
        } catch {
            
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
            
            
        } catch {
            
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





