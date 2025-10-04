// ServicesViewModel.swift
// Path: ClaudeHustlerFirebase/ViewModels/ServicesViewModel.swift
// UPDATED: Added tag support

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Services ViewModel
@MainActor
final class ServicesViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var offers: [ServicePost] = []
    @Published var requests: [ServicePost] = []
    @Published var isLoadingOffers = false
    @Published var isLoadingRequests = false
    @Published var offersHasMore = true
    @Published var requestsHasMore = true
    @Published var error: Error?
    
    // MARK: - Tag Properties (ADDED)
    @Published var selectedTags: [String] = []
    @Published var trendingTags: [String] = []
    @Published var isFilteringByTags = false
    
    // MARK: - Private Properties
    private let repository = PostRepository()
    private let tagRepository = TagRepository.shared  // ADDED
    private var offersLastDocument: DocumentSnapshot?
    private var requestsLastDocument: DocumentSnapshot?
    private let pageSize = 20
    static weak var shared: ServicesViewModel?
    
    
    // MARK: - Initialization
    init() {
        Self.shared = self
        Task {
            await loadInitialData()
            await loadTrendingTags()  // ADDED
        }
    }
    
    // MARK: - Public Methods
    
    func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadInitialOffers() }
            group.addTask { await self.loadInitialRequests() }
        }
    }
    
    func loadInitialOffers() async {
        guard !isLoadingOffers else { return }
        
        isLoadingOffers = true
        error = nil
        
        do {
            let (posts, lastDoc): ([ServicePost], DocumentSnapshot?)
            
            // UPDATED: Check if filtering by tags
            if !selectedTags.isEmpty {
                (posts, lastDoc) = try await repository.fetchByTags(
                    selectedTags,
                    limit: pageSize,
                    isRequest: false
                )
            } else {
                (posts, lastDoc) = try await repository.fetchOffers(limit: pageSize)
            }
            
            await MainActor.run {
                self.offers = posts
                self.offersLastDocument = lastDoc
                self.offersHasMore = posts.count == pageSize
                self.isLoadingOffers = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoadingOffers = false
            }
            print("Error loading offers: \(error)")
        }
    }
    
    func loadMoreOffers() async {
        guard !isLoadingOffers,
              offersHasMore,
              let lastDoc = offersLastDocument else { return }
        
        isLoadingOffers = true
        
        do {
            let (posts, newLastDoc): ([ServicePost], DocumentSnapshot?)
            
            // UPDATED: Check if filtering by tags
            if !selectedTags.isEmpty {
                (posts, newLastDoc) = try await repository.fetchByTags(
                    selectedTags,
                    limit: pageSize,
                    lastDocument: lastDoc,
                    isRequest: false
                )
            } else {
                (posts, newLastDoc) = try await repository.fetchOffers(
                    limit: pageSize,
                    lastDocument: lastDoc
                )
            }
            
            await MainActor.run {
                self.offers.append(contentsOf: posts)
                self.offersLastDocument = newLastDoc
                self.offersHasMore = posts.count == pageSize
                self.isLoadingOffers = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoadingOffers = false
            }
        }
    }
    
    func loadInitialRequests() async {
        guard !isLoadingRequests else { return }
        
        isLoadingRequests = true
        error = nil
        
        do {
            let (posts, lastDoc): ([ServicePost], DocumentSnapshot?)
            
            // UPDATED: Check if filtering by tags
            if !selectedTags.isEmpty {
                (posts, lastDoc) = try await repository.fetchByTags(
                    selectedTags,
                    limit: pageSize,
                    isRequest: true
                )
            } else {
                (posts, lastDoc) = try await repository.fetchRequests(limit: pageSize)
            }
            
            await MainActor.run {
                self.requests = posts
                self.requestsLastDocument = lastDoc
                self.requestsHasMore = posts.count == pageSize
                self.isLoadingRequests = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoadingRequests = false
            }
            print("Error loading requests: \(error)")
        }
    }
    
    func loadMoreRequests() async {
        guard !isLoadingRequests,
              requestsHasMore,
              let lastDoc = requestsLastDocument else { return }
        
        isLoadingRequests = true
        
        do {
            let (posts, newLastDoc): ([ServicePost], DocumentSnapshot?)
            
            // UPDATED: Check if filtering by tags
            if !selectedTags.isEmpty {
                (posts, newLastDoc) = try await repository.fetchByTags(
                    selectedTags,
                    limit: pageSize,
                    lastDocument: lastDoc,
                    isRequest: true
                )
            } else {
                (posts, newLastDoc) = try await repository.fetchRequests(
                    limit: pageSize,
                    lastDocument: lastDoc
                )
            }
            
            await MainActor.run {
                self.requests.append(contentsOf: posts)
                self.requestsLastDocument = newLastDoc
                self.requestsHasMore = posts.count == pageSize
                self.isLoadingRequests = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoadingRequests = false
            }
        }
    }
    
    func refresh(type: ServiceType) async {
        switch type {
        case .offers:
            offersLastDocument = nil
            await loadInitialOffers()
        case .requests:
            requestsLastDocument = nil
            await loadInitialRequests()
        }
    }
    
    func deletePost(_ postId: String) async throws {
        try await repository.delete(postId)
        
        // Remove from local arrays
        await MainActor.run {
            self.offers.removeAll { $0.id == postId }
            self.requests.removeAll { $0.id == postId }
        }
    }
    
    // MARK: - Helper Types
    enum ServiceType {
        case offers, requests
    }
    
    // MARK: - Create/Update Methods (UPDATED WITH TAGS)

    func createPost(_ post: ServicePost) async throws -> String {
        let postId = try await repository.create(post)
        
        // ADDED: Update tag analytics
        if !post.tags.isEmpty {
            await tagRepository.updateTagAnalytics(post.tags, type: "post")
        }
        
        // Refresh the appropriate list
        if post.isRequest {
            await loadInitialRequests()
        } else {
            await loadInitialOffers()
        }
        
        return postId
    }

    func updatePost(_ post: ServicePost) async throws {
        try await repository.update(post)
        
        // ADDED: Update tag analytics
        if !post.tags.isEmpty {
            await tagRepository.updateTagAnalytics(post.tags, type: "post")
        }
        
        // Update local state
        if post.isRequest {
            if let index = requests.firstIndex(where: { $0.id == post.id }) {
                requests[index] = post
            }
        } else {
            if let index = offers.firstIndex(where: { $0.id == post.id }) {
                offers[index] = post
            }
        }
    }
    
    // MARK: - Tag Methods (ADDED)
    
    func loadTrendingTags() async {
        do {
            let tags = try await tagRepository.fetchTrendingTags(limit: 15)
            await MainActor.run {
                self.trendingTags = tags
            }
        } catch {
            print("Failed to load trending tags: \(error)")
        }
    }
    
    func toggleTagFilter(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.removeAll { $0 == tag }
        } else {
            selectedTags.append(tag)
        }
        
        isFilteringByTags = !selectedTags.isEmpty
        
        // Reload data with new filters
        Task {
            await refresh(type: .offers)
            await refresh(type: .requests)
        }
    }
    
    func clearTagFilters() {
        selectedTags.removeAll()
        isFilteringByTags = false
        
        // Reload without filters
        Task {
            await refresh(type: .offers)
            await refresh(type: .requests)
        }
    }
    
    func addTagFilter(_ tag: String) {
        if !selectedTags.contains(tag) {
            selectedTags.append(tag)
            isFilteringByTags = true
            
            Task {
                await refresh(type: .offers)
                await refresh(type: .requests)
            }
        }
    }
    
    func removeTagFilter(_ tag: String) {
        selectedTags.removeAll { $0 == tag }
        isFilteringByTags = !selectedTags.isEmpty
        
        Task {
            await refresh(type: .offers)
            await refresh(type: .requests)
        }
    }
    
    // MARK: - Search with Tags (ADDED)
    
    func searchPostsWithTags(query: String, includeOffers: Bool = true, includeRequests: Bool = true) async -> [ServicePost] {
        do {
            let posts = try await repository.searchPostsWithTags(
                query: query,
                tags: selectedTags.isEmpty ? nil : selectedTags
            )
            
            return posts.filter { post in
                if includeOffers && !post.isRequest { return true }
                if includeRequests && post.isRequest { return true }
                return false
            }
        } catch {
            print("Search failed: \(error)")
            return []
        }
    }
}ServiceCategory

