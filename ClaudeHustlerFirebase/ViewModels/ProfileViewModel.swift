// ProfileViewModel.swift
// Path: ClaudeHustlerFirebase/ViewModels/ProfileViewModel.swift

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ProfileViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var user: User?
    @Published var reviews: [Review] = []
    @Published var portfolioCards: [PortfolioCard] = []
    @Published var savedPosts: [ServicePost] = []
    @Published var savedReels: [Reel] = []
    @Published var userPosts: [ServicePost] = []
    
    @Published var isFollowing = false
    @Published var isLoadingProfile = false
    @Published var isLoadingReviews = false
    @Published var isLoadingPortfolio = false
    @Published var error: Error?
    
    // MARK: - Private Properties
    private let userRepository = UserRepository.shared
    private let reviewRepository = ReviewRepository.shared
    private let portfolioRepository = PortfolioRepository.shared
    private let postRepository = PostRepository.shared
    private let savedItemsRepository = SavedItemsRepository.shared
    
    private var reviewsListener: ListenerRegistration?
    private var userListener: ListenerRegistration?
    
    // Static reference for singleton-like access if needed
    static weak var shared: ProfileViewModel?
    
    // Current profile being viewed
    private(set) var profileUserId: String
    
    // Computed properties
    var isOwnProfile: Bool {
        profileUserId == Auth.auth().currentUser?.uid
    }
    
    // MARK: - Initialization
    init(userId: String) {
        self.profileUserId = userId
        Self.shared = self
        Task {
            await loadProfileData()
            if !isOwnProfile {
                await checkFollowingStatus()
            }
        }
    }
    
    deinit {
        // Clean up listeners to prevent memory leaks
        reviewsListener?.remove()
        userListener?.remove()
    }
    
    // MARK: - Load Profile Data
    
    func loadProfileData() async {
        isLoadingProfile = true
        error = nil
        
        do {
            // Load user profile
            user = try await userRepository.fetchById(profileUserId)
            
            // Load portfolio cards
            await loadPortfolioCards()
            
            // Load reviews with listener
            setupReviewsListener()
            
            // Load user's posts
            await loadUserPosts()
            
            // If it's own profile, load saved items
            if isOwnProfile {
                await loadSavedItems()
            }
            
        } catch {
            self.error = error
            print("Error loading profile: \(error)")
        }
        
        isLoadingProfile = false
    }
    
    func refreshProfileData() async {
        reviews = []
        userPosts = []
        portfolioCards = []
        await loadProfileData()
    }
    
    // MARK: - Follow/Unfollow
    
    func toggleFollow() async {
        guard !isOwnProfile,
              let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            if isFollowing {
                try await userRepository.unfollowUser(profileUserId)
                isFollowing = false
                
                // Update local follower count
                if user != nil {
                    user?.followers.removeAll { $0 == currentUserId }
                }
            } else {
                try await userRepository.followUser(profileUserId)
                isFollowing = true
                
                // Update local follower count
                if user != nil {
                    user?.followers.append(currentUserId)
                }
            }
        } catch {
            self.error = error
            
        }
    }
    
    private func checkFollowingStatus() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let currentUser = try await userRepository.fetchById(currentUserId)
            isFollowing = currentUser?.following.contains(profileUserId) ?? false
        } catch {
            print("Error checking following status: \(error)")
        }
    }
    
    // MARK: - Portfolio Management
    
    func loadPortfolioCards() async {
        isLoadingPortfolio = true
        
        do {
            // Use existing method from PortfolioRepository
            portfolioCards = try await portfolioRepository.fetchUserPortfolioCards(userId: profileUserId)
        } catch {
            self.error = error
            
        }
        
        isLoadingPortfolio = false
    }
    
    func deletePortfolioCard(_ cardId: String) async {
        guard isOwnProfile else { return }
        
        do {
            // Use existing delete method from PortfolioRepository
            try await portfolioRepository.delete(cardId)
            portfolioCards.removeAll { $0.id == cardId }
        } catch {
            
        }
    }
    
    // MARK: - Reviews Management
    
    private func setupReviewsListener() {
        reviewsListener = reviewRepository.listenToUserReviews(userId: profileUserId) { [weak self] reviews in
            self?.reviews = reviews
        }
    }
    
    func cleanupListeners() {
        reviewsListener?.remove()
        userListener?.remove()
        reviewRepository.stopListeningToUserReviews(userId: profileUserId)
    }
    
    // MARK: - Posts Management
    
    func loadUserPosts() async {
        do {
            // Use the existing fetchUserPosts method from PostRepository
            userPosts = try await postRepository.fetchUserPosts(userId: profileUserId, limit: 20)
        } catch {
            
        }
    }
    
    // MARK: - Saved Items
    
    func loadSavedItems() async {
        guard isOwnProfile else { return }
        
        do {
            // Use existing methods from SavedItemsRepository
            // Fetch saved posts
            savedPosts = try await savedItemsRepository.fetchSavedPosts()
            
            // Fetch saved reels
            savedReels = try await savedItemsRepository.fetchSavedReels()
            
        } catch {
            
        }
    }
    
    // MARK: - Get Followers/Following
    
    func getFollowers() async -> [User] {
        do {
            return try await userRepository.fetchFollowers(for: profileUserId)
        } catch {
            
            return []
        }
    }
    
    func getFollowing() async -> [User] {
        do {
            return try await userRepository.fetchFollowing(for: profileUserId)
        } catch {
            
            return []
        }
    }
    
    // MARK: - Portfolio Methods

    func updatePortfolioCard(_ card: PortfolioCard) async throws {
        try await portfolioRepository.update(card)
        
        // Update local state
        if let index = portfolioCards.firstIndex(where: { $0.id == card.id }) {
            portfolioCards[index] = card
        }
    }
}
