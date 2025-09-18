

// ServicesViewModel.swift
// Path: ClaudeHustlerFirebase/ViewModels/ServicesViewModel.swift

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
    
    // MARK: - Private Properties
    private let repository = PostRepository()
    private var offersLastDocument: DocumentSnapshot?
    private var requestsLastDocument: DocumentSnapshot?
    private let pageSize = 20
    
    // MARK: - Initialization
    init() {
        Task {
            await loadInitialData()
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
            let (posts, lastDoc) = try await repository.fetchOffers(limit: pageSize)
            
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
            let (posts, newLastDoc) = try await repository.fetchOffers(
                limit: pageSize,
                lastDocument: lastDoc
            )
            
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
            let (posts, lastDoc) = try await repository.fetchRequests(limit: pageSize)
            
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
        }
    }
    
    func loadMoreRequests() async {
        guard !isLoadingRequests,
              requestsHasMore,
              let lastDoc = requestsLastDocument else { return }
        
        isLoadingRequests = true
        
        do {
            let (posts, newLastDoc) = try await repository.fetchRequests(
                limit: pageSize,
                lastDocument: lastDoc
            )
            
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
}
