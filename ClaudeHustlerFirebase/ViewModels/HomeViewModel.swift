

// HomeViewModel.swift
// Path: ClaudeHustlerFirebase/ViewModels/HomeViewModel.swift

import SwiftUI
import Combine
import FirebaseFirestore
import SDWebImageSwiftUI

@MainActor
class HomeViewModel: ObservableObject {
    @Published var posts: [ServicePost] = []
    @Published var filteredPosts: [ServicePost] = []
    @Published var trendingPosts: [ServicePost] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var selectedCategory: ServiceCategory?
    @Published var hasMore = true
    
    private let repository = PostRepository.shared
    private var lastDocument: DocumentSnapshot?
    private var cancellables = Set<AnyCancellable>()
    static weak var shared: HomeViewModel?
    
    init() {
        Self.shared = self
        setupSearchListener()
        Task {
            await loadInitialPosts()
        }
    }
    
    // MARK: - Search & Filter
    
    private func setupSearchListener() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] searchTerm in
                self?.filterPosts()
            }
            .store(in: &cancellables)
    }
    
    func updateSearchText(_ text: String) {
        searchText = text
    }
    
    private func filterPosts() {
        if searchText.isEmpty && selectedCategory == nil {
            filteredPosts = posts
        } else {
            filteredPosts = posts.filter { post in
                let matchesSearch = searchText.isEmpty ||
                    post.title.localizedCaseInsensitiveContains(searchText) ||
                    post.description.localizedCaseInsensitiveContains(searchText)
                
                let matchesCategory = selectedCategory == nil || post.category == selectedCategory
                
                return matchesSearch && matchesCategory
            }
        }
    }
    
    // MARK: - Data Loading
    
    func loadInitialPosts() async {
        isLoading = true
        lastDocument = nil
        hasMore = true
        
        do {
            let result = try await repository.fetch(limit: 20)
            posts = result.items
            lastDocument = result.lastDoc
            hasMore = !result.items.isEmpty && result.items.count == 20
            
            // Extract trending posts (posts with most recent activity)
            trendingPosts = Array(posts.sorted { post1, post2 in
                // You can add more complex trending logic here
                post1.updatedAt > post2.updatedAt
            }.prefix(5))
            
            filterPosts()
            
            // Preload images for better performance
            preloadImages()
            
        } catch {
            print("Error loading posts: \(error)")
            posts = []
            hasMore = false
        }
        
        isLoading = false
    }
    
    func loadMorePosts() async {
        guard !isLoading, hasMore, let lastDoc = lastDocument else { return }
        
        isLoading = true
        
        do {
            let result = try await repository.fetch(limit: 20, lastDocument: lastDoc)
            posts.append(contentsOf: result.items)
            lastDocument = result.lastDoc
            hasMore = !result.items.isEmpty && result.items.count == 20
            
            filterPosts()
            
            // Preload newly loaded images
            preloadImages(for: result.items)
            
        } catch {
            print("Error loading more posts: \(error)")
            hasMore = false
        }
        
        isLoading = false
    }
    
    func refresh() async {
        // Clear existing data
        posts = []
        filteredPosts = []
        trendingPosts = []
        lastDocument = nil
        hasMore = true
        
        // Reload everything
        await loadInitialPosts()
    }
    
    // MARK: - Image Preloading
    
    func preloadImages() {
        let imageURLs = posts.compactMap { post in
            post.imageURLs.first
        }.prefix(10) // Preload first 10 images
        
        preloadURLs(imageURLs)
    }
    
    func preloadImages(for posts: [ServicePost]) {
        let imageURLs = posts.compactMap { post in
            post.imageURLs.first
        }.prefix(5) // Preload first 5 images of new batch
        
        preloadURLs(imageURLs)
    }
    
    private func preloadURLs(_ urlStrings: any Sequence<String>) {
        let urls = urlStrings.compactMap { URL(string: $0) }
        
        if !urls.isEmpty {
            SDWebImagePrefetcher.shared.prefetchURLs(urls) { finishedCount, totalCount in
                print("Preloaded \(finishedCount) of \(totalCount) images")
            }
        }
    }
    
    // MARK: - Category Filter
    
    func selectCategory(_ category: ServiceCategory?) {
        selectedCategory = category
        filterPosts()
    }
    
    func clearFilters() {
        searchText = ""
        selectedCategory = nil
        filterPosts()
    }
    
    
}
