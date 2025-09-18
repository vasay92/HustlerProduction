

// HomeViewModel.swift
// Path: ClaudeHustlerFirebase/ViewModels/HomeViewModel.swift

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Home ViewModel
@MainActor
final class HomeViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var posts: [ServicePost] = []
    @Published var trendingPosts: [ServicePost] = []
    @Published var isLoading = false
    @Published var hasMore = true
    @Published var error: Error?
    @Published var searchText = ""
    @Published var selectedCategory: ServiceCategory?
    
    // MARK: - Computed Properties
    var filteredPosts: [ServicePost] {
        var result = posts
        
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result
    }
    
    // MARK: - Private Properties
    private let repository = PostRepository()
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 20
    private let cache = CacheService.shared
    
    // MARK: - Initialization
    init() {
        Task {
            await loadInitialData()
        }
    }
    
    // MARK: - Public Methods
    
    func loadInitialData() async {
        guard !isLoading else { return }
        
        // Check cache first for instant loading
        if let cachedPosts: [ServicePost] = cache.retrieve([ServicePost].self, for: "posts_page_1"),
           !cache.isExpired(for: "posts_page_1", maxAge: 300) {
            self.posts = cachedPosts
            self.trendingPosts = Array(cachedPosts.prefix(5))
        }
        
        isLoading = true
        error = nil
        lastDocument = nil
        
        do {
            let (fetchedPosts, lastDoc) = try await repository.fetch(limit: pageSize)
            
            await MainActor.run {
                self.posts = fetchedPosts
                self.trendingPosts = Array(fetchedPosts.prefix(5))
                self.lastDocument = lastDoc
                self.hasMore = fetchedPosts.count == pageSize
                self.isLoading = false
            }
            
            // Cache the results
            cache.store(fetchedPosts, for: "posts_page_1")
            
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
            print("Error loading posts: \(error)")
        }
    }
    
    func loadMore() async {
        guard !isLoading,
              hasMore,
              let lastDoc = lastDocument else { return }
        
        isLoading = true
        
        do {
            let (morePosts, newLastDoc) = try await repository.fetch(
                limit: pageSize,
                lastDocument: lastDoc
            )
            
            await MainActor.run {
                self.posts.append(contentsOf: morePosts)
                self.lastDocument = newLastDoc
                self.hasMore = morePosts.count == pageSize
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    func refresh() async {
        // Clear cache for fresh data
        cache.remove(for: "posts_page_1")
        
        lastDocument = nil
        hasMore = true
        await loadInitialData()
    }
    
    func search(_ query: String) async {
        guard !query.isEmpty else {
            await loadInitialData()
            return
        }
        
        isLoading = true
        
        do {
            let results = try await repository.search(query: query)
            
            await MainActor.run {
                self.posts = results
                self.isLoading = false
                self.hasMore = false // Search doesn't support pagination yet
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
}
