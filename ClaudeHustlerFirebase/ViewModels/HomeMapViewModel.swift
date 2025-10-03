// HomeMapViewModel.swift
// Path: ClaudeHustlerFirebase/ViewModels/HomeMapViewModel.swift

import Foundation
import SwiftUI
import MapKit
import FirebaseFirestore

@MainActor
final class HomeMapViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var posts: [ServicePost] = []
    @Published var filteredPosts: [ServicePost] = []
    @Published var selectedPost: ServicePost?
    @Published var showingPostPreview = false
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var showOnlyRequests = false
    @Published var showOnlyOffers = false
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.9742, longitude: -87.9073), // Chicago area
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )
    
    // MARK: - Private Properties
    private let repository = PostRepository.shared
    private let locationService = LocationService.shared
    
    // Static reference for updates
    static weak var shared: HomeMapViewModel?
    
    init() {
        Self.shared = self
        setupLocationTracking()
    }
    
    // MARK: - Setup Methods
    private func setupLocationTracking() {
        // Request location permission if needed
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestLocationPermission()
        }
        
        // Observe user location changes
        Task { @MainActor in
            for await _ in locationService.$userLocation.values {
                if let location = locationService.userLocation {
                    updateMapRegion(center: location)
                }
            }
        }
    }
    
    // MARK: - Data Loading
    func loadPosts() async {
        isLoading = true
        
        do {
            // First, check ALL posts to see what we have
            let allPostsResult = try await repository.fetch(limit: 100)
            print("📊 Total posts in database: \(allPostsResult.items.count)")
            
            // Check how many have coordinates
            let postsWithCoords = allPostsResult.items.filter { $0.coordinates != nil }
            print("📍 Posts with coordinates: \(postsWithCoords.count)")
            
            // Log posts without coordinates for debugging
            let postsWithoutCoords = allPostsResult.items.filter { $0.coordinates == nil }
            if !postsWithoutCoords.isEmpty {
                print("⚠️ Posts WITHOUT coordinates:")
                postsWithoutCoords.forEach { post in
                    print("  - \(post.title) (location: \(post.location ?? "none"))")
                }
            }
            
            // Now fetch posts with location data
            let fetchedPosts = try await repository.fetchAllPostsWithLocation(limit: 500)
            print("🗺️ fetchAllPostsWithLocation returned: \(fetchedPosts.count) posts")
            
            // Handle location privacy
            posts = fetchedPosts.map { post in
                var modifiedPost = post
                
                // If location privacy is approximate, obfuscate the coordinates
                if post.locationPrivacy == .approximate,
                   let coordinates = post.coordinates {
                    let obfuscated = locationService.obfuscateCoordinate(
                        CLLocationCoordinate2D(
                            latitude: coordinates.latitude,
                            longitude: coordinates.longitude
                        ),
                        radiusInMeters: post.approximateRadius ?? 1000
                    )
                    modifiedPost.coordinates = GeoPoint(
                        latitude: obfuscated.latitude,
                        longitude: obfuscated.longitude
                    )
                }
                
                return modifiedPost
            }
            
            print("✅ Final posts array has: \(posts.count) posts")
            filterPosts()
            print("✅ After filtering: \(filteredPosts.count) posts")
            
        } catch {
            print("❌ Error loading posts for map: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
        
        isLoading = false
    }

    func refresh() async {
        posts = []
        filteredPosts = []
        selectedPost = nil
        await loadPosts()
    }
    
    // MARK: - Filtering
    func filterPosts() {
        var filtered = posts
        
        // Apply offer/request filter
        if showOnlyRequests && !showOnlyOffers {
            filtered = filtered.filter { $0.isRequest }
        } else if showOnlyOffers && !showOnlyRequests {
            filtered = filtered.filter { !$0.isRequest }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { post in
                post.title.localizedCaseInsensitiveContains(searchText) ||
                post.description.localizedCaseInsensitiveContains(searchText) ||
                post.location?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        filteredPosts = filtered
    }
    
    func toggleRequestFilter() {
        showOnlyRequests.toggle()
        if showOnlyRequests {
            showOnlyOffers = false
        }
        filterPosts()
    }
    
    func toggleOfferFilter() {
        showOnlyOffers.toggle()
        if showOnlyOffers {
            showOnlyRequests = false
        }
        filterPosts()
    }
    
    func clearFilters() {
        searchText = ""
        showOnlyRequests = false
        showOnlyOffers = false
        filterPosts()
    }
    
    // MARK: - Map Interactions
    func selectPost(_ post: ServicePost) {
        selectedPost = post
        showingPostPreview = true
        
        // Center map on selected post
        if let coordinates = post.coordinates {
            let center = CLLocationCoordinate2D(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude
            )
            updateMapRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
    }
    
    func dismissPostPreview() {
        showingPostPreview = false
        // Don't immediately clear selectedPost to allow for animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.selectedPost = nil
        }
    }
    
    func updateMapRegion(center: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil) {
        mapRegion = MKCoordinateRegion(
            center: center,
            span: span ?? mapRegion.span
        )
    }
    
    // MARK: - Location Methods
    func centerOnUserLocation() {
        if let userLocation = locationService.userLocation {
            updateMapRegion(
                center: userLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
    }
    
    func getAnnotationColor(for post: ServicePost) -> Color {
        post.isRequest ? .orange : .blue
    }
    
    func getAnnotationIcon(for post: ServicePost) -> String {
        switch post.category {
        case .cleaning: return "sparkles"
        case .tutoring: return "book.fill"
        case .delivery: return "shippingbox.fill"
        case .electrical: return "bolt.fill"
        case .plumbing: return "drop.fill"
        case .carpentry: return "hammer.fill"
        case .painting: return "paintbrush.fill"
        case .landscaping: return "leaf.fill"
        case .moving: return "box.truck.fill"
        case .technology: return "desktopcomputer"
        case .other: return "ellipsis.circle.fill"
        }
    }
    
    // MARK: - Zoom Methods
    func zoomIn() {
        let newSpan = MKCoordinateSpan(
            latitudeDelta: mapRegion.span.latitudeDelta * 0.5,
            longitudeDelta: mapRegion.span.longitudeDelta * 0.5
        )
        // Limit maximum zoom
        if newSpan.latitudeDelta > 0.001 {
            updateMapRegion(center: mapRegion.center, span: newSpan)
        }
    }

    func zoomOut() {
        let newSpan = MKCoordinateSpan(
            latitudeDelta: mapRegion.span.latitudeDelta * 2.0,
            longitudeDelta: mapRegion.span.longitudeDelta * 2.0
        )
        // Limit minimum zoom
        if newSpan.latitudeDelta < 10.0 {
            updateMapRegion(center: mapRegion.center, span: newSpan)
        }
    }
}

// MARK: - Map Annotation Model
struct MapAnnotationItem: Identifiable {
    let id = UUID()
    let post: ServicePost
    
    var coordinate: CLLocationCoordinate2D {
        guard let geoPoint = post.coordinates else {
            return CLLocationCoordinate2D()
        }
        return CLLocationCoordinate2D(
            latitude: geoPoint.latitude,
            longitude: geoPoint.longitude
        )
    }
}


