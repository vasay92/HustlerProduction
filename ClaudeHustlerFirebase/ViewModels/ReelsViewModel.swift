

// ReelsViewModel.swift
// Path: ClaudeHustlerFirebase/ViewModels/ReelsViewModel.swift

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
    private let firebase = FirebaseService.shared
    private var reelsLastDocument: DocumentSnapshot?
    private var userReelsLastDocument: DocumentSnapshot?
    private let pageSize = 20
    
    // Listeners
    private var statusListener: ListenerRegistration?
    private var reelListeners: [String: ListenerRegistration] = [:]
    
    // Current user
    private var currentUserId: String?

    
    // MARK: - Initialization
    init() {
        Self.shared = self
        // Initialize current user ID
        self.currentUserId = Auth.auth().currentUser?.uid
        
        Task {
            await loadInitialData()
        }
    }
    
    deinit {
        reelListeners.values.forEach { $0.remove() }
            reelListeners.removeAll()
            statusListener?.remove()
            statusListener = nil
    }
    
    // MARK: - Public Methods - Data Loading
    
    func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadStatuses() }
            group.addTask { await self.loadInitialReels() }
            group.addTask { await self.loadTrendingReels() }
        }
    }
    
    func loadInitialReels() async {
        guard !isLoadingReels else { return }
        
        isLoadingReels = true
        reelsLastDocument = nil
        hasMoreReels = true
        
        do {
            let result = try await reelRepository.fetch(limit: pageSize)
            
            await MainActor.run {
                self.reels = result.items
                self.reelsLastDocument = result.lastDoc
                self.hasMoreReels = result.items.count == pageSize
                self.isLoadingReels = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoadingReels = false
            }
            print("Error loading reels: \(error)")
        }
    }
    
    func loadMoreReels() async {
        guard !isLoadingReels,
              hasMoreReels,
              let lastDoc = reelsLastDocument else { return }
        
        isLoadingReels = true
        
        do {
            let result = try await reelRepository.fetch(
                limit: pageSize,
                lastDocument: lastDoc
            )
            
            await MainActor.run {
                self.reels.append(contentsOf: result.items)
                self.reelsLastDocument = result.lastDoc
                self.hasMoreReels = result.items.count == pageSize
                self.isLoadingReels = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoadingReels = false
            }
        }
    }
    
    func loadTrendingReels() async {
        do {
            let trending = try await reelRepository.fetchTrending(limit: 10)
            
            await MainActor.run {
                self.trendingReels = trending
            }
        } catch {
            print("Error loading trending reels: \(error)")
        }
    }
    
    func loadUserReels(userId: String) async {
        do {
            let result = try await reelRepository.fetchUserReels(
                userId,
                limit: pageSize
            )
            
            await MainActor.run {
                self.userReels = result.items
                self.userReelsLastDocument = result.lastDoc
            }
        } catch {
            print("Error loading user reels: \(error)")
        }
    }
    
    func loadReelsByCategory(_ category: ServiceCategory) async {
        isLoadingReels = true
        
        do {
            let result = try await reelRepository.fetchByCategory(
                category,
                limit: pageSize
            )
            
            await MainActor.run {
                self.reels = result.items
                self.reelsLastDocument = result.lastDoc
                self.hasMoreReels = result.items.count == pageSize
                self.isLoadingReels = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoadingReels = false
            }
        }
    }
    
    func searchReels(query: String) async {
        guard !query.isEmpty else {
            await loadInitialReels()
            return
        }
        
        isLoadingReels = true
        
        do {
            let results = try await reelRepository.search(
                query: query,
                limit: pageSize
            )
            
            await MainActor.run {
                self.reels = results
                self.hasMoreReels = false
                self.isLoadingReels = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoadingReels = false
            }
        }
    }
    
    func refresh() async {
        reels = []
        statuses = []
        reelsLastDocument = nil
        hasMoreReels = true
        
        await loadInitialData()
    }
    
    // MARK: - Status Operations (until StatusRepository exists)
    
    func loadStatuses() async {
        isLoadingStatuses = true
        
        guard let currentUser = firebase.currentUser else {
            statuses = []
            isLoadingStatuses = false
            return
        }
        
        // Get user IDs to load statuses from
        var userIds = currentUser.following
        if let myId = currentUser.id {
            userIds.append(myId)
        }
        
        do {
            statuses = try await statusRepository.fetchStatusesFromFollowing(userIds: userIds)
            
            // Check if current user has a status
            if let userId = currentUserId {
                currentUserStatus = statuses.first { $0.userId == userId }
            }
        } catch {
            print("Error loading statuses: \(error)")
            statuses = []
        }
        
        isLoadingStatuses = false
    }
    
    func cleanupExpiredStatuses() async {
        // Remove expired statuses from local array
        statuses.removeAll { $0.isExpired }
        
        // Clean up in Firebase
        do {
            try await statusRepository.cleanupExpiredStatuses()
        } catch {
            print("Error cleaning up statuses: \(error)")
        }
    }
    
    func createStatus(_ status: Status) async throws {
        // This would be moved to StatusRepository
        _ = try await firebase.createStatus(
            image: UIImage(), // You'd pass the actual image
            caption: status.caption
        )
        
        await loadStatuses()
    }
    
    func deleteStatus(_ statusId: String) async throws {
        try await firebase.deleteStatus(statusId)
        
        // Remove from local array
        statuses.removeAll { $0.id == statusId }
        
        if currentUserStatus?.id == statusId {
            currentUserStatus = nil
        }
    }
    
    func viewStatus(_ statusId: String) async {
        await firebase.viewStatus(statusId)
    }
    
    // MARK: - Reel Interactions
    
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
    
    func createReel(
        title: String,
        description: String,
        videoURL: String,
        thumbnailURL: String? = nil,
        category: ServiceCategory? = nil,
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
            category: category,
            hashtags: hashtags
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
    
    func deleteReel(_ reelId: String) async throws {
        try await reelRepository.delete(reelId)
        
        // Remove from local arrays
        reels.removeAll { $0.id == reelId }
        trendingReels.removeAll { $0.id == reelId }
        userReels.removeAll { $0.id == reelId }
    }
    
    func saveReel(_ reelId: String) async throws -> Bool {
        return try await SavedItemsRepository.shared.toggleSave(
            itemId: reelId,
            type: .reel
        )
    }
    
    // MARK: - Real-time Listeners
    
    func startListeningToReel(_ reelId: String) {
        // Remove existing listener if any
        stopListeningToReel(reelId)
        
        let listener = firebase.listenToReel(reelId) { [weak self] updatedReel in
            guard let self = self, let updatedReel = updatedReel else { return }
            
            // Update in all arrays
            if let index = self.reels.firstIndex(where: { $0.id == reelId }) {
                self.reels[index] = updatedReel
            }
            
            if let index = self.trendingReels.firstIndex(where: { $0.id == reelId }) {
                self.trendingReels[index] = updatedReel
            }
            
            if let index = self.userReels.firstIndex(where: { $0.id == reelId }) {
                self.userReels[index] = updatedReel
            }
        }
        
        reelListeners[reelId] = listener
    }
    
    func stopListeningToReel(_ reelId: String) {
        reelListeners[reelId]?.remove()
        reelListeners.removeValue(forKey: reelId)
        firebase.stopListeningToReel(reelId)
    }
    
    // MARK: - Cleanup
    
//    nonisolated private func cleanupAllListeners() {
//        // Remove all reel listeners
//        reelListeners.values.forEach { $0.remove() }
//        reelListeners.removeAll()
//        
//        // Remove status listener if exists
//        statusListener?.remove()
//        statusListener = nil
//    }
    
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
}

// MARK: - Status Creation Type
enum StatusContentType {
    case image(UIImage)
    case video(URL)
    case text(String, UIColor)
}
