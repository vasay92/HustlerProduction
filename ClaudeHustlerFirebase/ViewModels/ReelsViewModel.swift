// ReelsViewModel.swift
// Path: ClaudeHustlerFirebase/ViewModels/ReelsViewModel.swift
// UPDATED VERSION - Phase 2.1 MVVM Migration

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine
import Firebase

// MARK: - Reels ViewModel
@MainActor
final class ReelsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var reels: [Reel] = []
    @Published var trendingReels: [Reel] = []
    @Published var userReels: [Reel] = []
    @Published var statuses: [Status] = []
    @Published var isLoadingReels = false
    @Published var isLoadingStatuses = false
    @Published var hasMoreReels = true
    @Published var error: Error?
    @Published var currentUserStatus: Status?
    static weak var shared: ReelsViewModel?
    
    // MARK: - Private Properties
    private let reelRepository = ReelRepository.shared
    private let statusRepository = StatusRepository.shared
    private let savedItemsRepository = SavedItemsRepository.shared
    private let userRepository = UserRepository.shared
    private let firebase = FirebaseService.shared
    private var reelsLastDocument: DocumentSnapshot?
    private var userReelsLastDocument: DocumentSnapshot?
    private let pageSize = 20
    
    // Listeners
    private var statusListener: ListenerRegistration?
    private var reelListeners: [String: ListenerRegistration] = [:]
    
    // Current user
    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    // MARK: - Initialization
    init() {
        Self.shared = self
        // REMOVED: self.currentUserId = Auth.auth().currentUser?.uid
        
        Task {
            await loadInitialData()
        }
    }

    deinit {
        statusListener?.remove()
        for (_, listener) in reelListeners {
            listener.remove()  // FIXED: Removed optional chaining
        }
    }

    
    // MARK: - Initial Data Loading
    
    func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadStatuses() }
            group.addTask { await self.loadInitialReels() }
            group.addTask { await self.loadTrendingReels() }
        }
    }
    
    func refresh() async {
        reelsLastDocument = nil
        userReelsLastDocument = nil
        await loadInitialData()
    }
    
    // MARK: - Status Methods
    
    func loadStatuses() async {
        isLoadingStatuses = true
        
        do {
            guard let userId = currentUserId else {
                isLoadingStatuses = false
                return
            }
            
            // Get current user's following list
            let currentUser = try await userRepository.fetchById(userId)
            var userIds = currentUser?.following ?? []
            userIds.append(userId) // Include own statuses
            
            // Fetch statuses from following users
            statuses = try await statusRepository.fetchStatusesFromFollowing(userIds: userIds)
            
            // Check if current user has a status
            currentUserStatus = statuses.first { $0.userId == userId }
            
        } catch {
            self.error = error
        }
        
        isLoadingStatuses = false
    }
    
    func createStatus(
        image: UIImage? = nil,
        videoURL: URL? = nil,
        caption: String? = nil
    ) async throws {
        guard let userId = currentUserId else {
            throw NSError(domain: "ReelsViewModel", code: 0,
                         userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        var mediaURL = ""
        
        // Upload media if provided
        if let image = image {
            let path = "statuses/\(userId)/\(UUID().uuidString).jpg"
            mediaURL = try await firebase.uploadImage(image, path: path)
        } else if let videoURL = videoURL {
            // Handle video upload if needed
            mediaURL = videoURL.absoluteString
        }
        
        let status = Status(
            userId: userId,
            userName: firebase.currentUser?.name,
            userProfileImage: firebase.currentUser?.profileImageURL,
            mediaURL: mediaURL,
            caption: caption,
            mediaType: image != nil ? .image : .video,
            expiresAt: Date().addingTimeInterval(24 * 60 * 60) // 24 hours
        )
        
        _ = try await statusRepository.create(status)
        
        // Reload statuses
        await loadStatuses()
    }
    
    func deleteStatus(_ statusId: String) async throws {
        try await statusRepository.delete(statusId)
        
        // Remove from local array
        statuses.removeAll { $0.id == statusId }
        
        if currentUserStatus?.id == statusId {
            currentUserStatus = nil
        }
    }
    
    func viewStatus(_ statusId: String) async {
        guard let userId = currentUserId else { return }
        
        do {
            try await statusRepository.markAsViewed(statusId, by: userId)
        } catch {
            print("Error viewing status: \(error)")
        }
    }
    
    func cleanupExpiredStatuses() async {
        do {
            try await statusRepository.cleanupExpiredStatuses()
            // Remove expired statuses from local array
            statuses.removeAll { $0.isExpired }
        } catch {
            print("Error cleaning up expired statuses: \(error)")
        }
    }
    
    // MARK: - Reels Loading
    
    func loadInitialReels() async {
        guard !isLoadingReels else { return }
        
        isLoadingReels = true
        
        do {
            let (fetchedReels, lastDoc) = try await reelRepository.fetch(limit: pageSize)
            
            reels = fetchedReels
            reelsLastDocument = lastDoc
            hasMoreReels = fetchedReels.count == pageSize
            
        } catch {
            self.error = error
        }
        
        isLoadingReels = false
    }
    
    func loadMoreReels() async {
        guard !isLoadingReels,
              hasMoreReels,
              let lastDoc = reelsLastDocument else { return }
        
        isLoadingReels = true
        
        do {
            let (fetchedReels, newLastDoc) = try await reelRepository.fetch(
                limit: pageSize,
                lastDocument: lastDoc
            )
            
            reels.append(contentsOf: fetchedReels)
            reelsLastDocument = newLastDoc
            hasMoreReels = fetchedReels.count == pageSize
            
        } catch {
            self.error = error
        }
        
        isLoadingReels = false
    }
    
    func loadTrendingReels() async {
        do {
            trendingReels = try await reelRepository.fetchTrending(limit: 10)
        } catch {
            print("Error loading trending reels: \(error)")
        }
    }
    
    // MARK: - Load User Reels
    func loadUserReels(userId: String) async {
        do {
            // fetchUserReels returns a tuple (items: [Reel], lastDoc: DocumentSnapshot?)
            // We only need the items part
            let (reels, _) = try await reelRepository.fetchUserReels(userId, limit: 20)
            userReels = reels
        } catch {
            print("Error loading user reels: \(error)")
        }
    }
    
    // MARK: - Reel Interactions (UPDATED FOR MVVM)
    
    func likeReel(_ reelId: String) async {
        do {
            try await reelRepository.likeReel(reelId)
            
            // Update local state
            if let index = reels.firstIndex(where: { $0.id == reelId }),
               let userId = currentUserId {
                reels[index].likes.append(userId)
            }
        } catch {
            print("Error liking reel: \(error)")
        }
    }
    
    func unlikeReel(_ reelId: String) async {
        do {
            try await reelRepository.unlikeReel(reelId)
            
            // Update local state
            if let index = reels.firstIndex(where: { $0.id == reelId }),
               let userId = currentUserId {
                reels[index].likes.removeAll { $0 == userId }
            }
        } catch {
            print("Error unliking reel: \(error)")
        }
    }
    
    func toggleLikeReel(_ reelId: String) async throws {
        guard let userId = currentUserId,
              let reel = reels.first(where: { $0.id == reelId }) else { return }
        
        if reel.likes.contains(userId) {
            await unlikeReel(reelId)
        } else {
            await likeReel(reelId)
        }
    }
    
    func shareReel(_ reelId: String) async {
        do {
            try await reelRepository.incrementShareCount(for: reelId)
            
            // Update local state
            if let index = reels.firstIndex(where: { $0.id == reelId }) {
                reels[index].shares += 1
            }
        } catch {
            print("Error sharing reel: \(error)")
        }
    }
    
    func deleteReel(_ reelId: String) async throws {
        try await reelRepository.delete(reelId)
        
        // Remove from local arrays
        reels.removeAll { $0.id == reelId }
        trendingReels.removeAll { $0.id == reelId }
        userReels.removeAll { $0.id == reelId }
    }
    
    // MARK: - Save/Unsave Methods (NEW)
    
    func saveReel(_ reelId: String) async throws -> Bool {
        return try await savedItemsRepository.toggleSave(
            itemId: reelId,
            type: .reel
        )
    }
    
    func toggleSaveReel(_ reelId: String) async throws -> Bool {
        return try await savedItemsRepository.toggleSave(
            itemId: reelId,
            type: .reel
        )
    }
    
    func isReelSaved(_ reelId: String) async -> Bool {
        return await savedItemsRepository.isItemSaved(
            itemId: reelId,
            type: .reel
        )
    }
    
    // MARK: - Follow/Unfollow Methods (NEW)
    
    func followReelCreator(_ userId: String) async throws {
        try await userRepository.followUser(userId)
        
        // Update local current user state if needed
        firebase.currentUser?.following.append(userId)
    }
    
    func unfollowReelCreator(_ userId: String) async throws {
        try await userRepository.unfollowUser(userId)
        
        // Update local current user state if needed
        firebase.currentUser?.following.removeAll { $0 == userId }
    }
    
    func toggleFollowReelCreator(_ userId: String) async throws {
        guard let currentUser = firebase.currentUser else { return }
        
        if currentUser.following.contains(userId) {
            try await unfollowReelCreator(userId)
        } else {
            try await followReelCreator(userId)
        }
    }
    
    func isFollowingCreator(_ userId: String) -> Bool {
        return firebase.currentUser?.following.contains(userId) ?? false
    }
    
    // MARK: - Create/Update Reel
    
    func createReel(
            title: String,
            description: String,
            videoURL: String,
            thumbnailURL: String? = nil,
            hashtags: [String] = []
        ) async throws -> String {
            guard let userId = currentUserId,
                  let userName = firebase.currentUser?.name else {
                throw NSError(domain: "ReelsViewModel", code: 0,
                             userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
            }
            
            let reel = Reel(
                userId: userId,
                userName: userName,
                userProfileImage: firebase.currentUser?.profileImageURL,
                videoURL: videoURL,
                thumbnailURL: thumbnailURL ?? videoURL,
                title: title,
                description: description,
                tags: hashtags  // No more category
            )
            
            let reelId = try await reelRepository.create(reel)
            
            // Reload reels to show the new one
            await loadInitialReels()
            
            return reelId
        }

    
    func updateReel(_ reel: Reel) async throws {
        try await reelRepository.update(reel)
        
        // Update local state
        if let index = reels.firstIndex(where: { $0.id == reel.id }) {
            reels[index] = reel
        }
    }
    
    // MARK: - Real-time Listeners
    
    func startListeningToReel(_ reelId: String) -> ListenerRegistration? {
        // Real-time listeners have been moved to repository
        // For now, just load the reel once
        Task { @MainActor in
            do {
                if let reel = try await reelRepository.fetchById(reelId) {
                    // Update the reel in the array
                    if let index = self.reels.firstIndex(where: { $0.id == reelId }) {
                        self.reels[index] = reel
                    }
                }
            } catch {
                print("Error loading reel: \(error)")
            }
        }
        return nil
    }
    
    func stopListeningToReel(_ reelId: String) {
        // No longer using listeners - nothing to stop
        // This function is kept for compatibility but does nothing
    }
    
    // MARK: - Helper Methods
    
    func isReelLiked(_ reelId: String) -> Bool {
        guard let userId = currentUserId,
              let reel = reels.first(where: { $0.id == reelId }) else {
            return false
        }
        return reel.likes.contains(userId)
    }
    
    func isOwnReel(_ reel: Reel) -> Bool {
        return reel.userId == currentUserId
    }
    
    func getReelIndex(_ reel: Reel) -> Int {
        return reels.firstIndex(where: { $0.id == reel.id }) ?? 0
    }
    // Track reel view
    func incrementReelView(_ reelId: String) async {
        guard !reelId.isEmpty else { return }
        
        do {
            try await reelRepository.incrementViewCount(for: reelId)
            
            // Update local state
            if let index = reels.firstIndex(where: { $0.id == reelId }) {
                reels[index].views += 1
            }
        } catch {
            print("Error incrementing view count: \(error)")
        }
    }
}

// MARK: - Status Creation Type
enum StatusContentType {
    case image(UIImage)
    case video(URL)
    case text(String, UIColor)
}
