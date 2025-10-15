// HomeMapViewModel.swift - Fixed version
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
    
    // Start with Chicago as default, will update with user location
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.9742, longitude: -87.9073),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1) // Zoomed out view
    )
    
    // Track if we've set initial location
    private var hasSetInitialLocation = false
    
    // MARK: - User Rating Properties for Dynamic Pins
    @Published var userRatings: [String: Double] = [:]
    @Published var userReviewCounts: [String: Int] = [:]
    
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
        
        // Start location updates
        locationService.startUpdatingLocation()
        
        // Set up a timer to check for initial location
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                // Check if we have user location and haven't set initial position yet
                if let userLocation = self.locationService.userLocation,
                   !self.hasSetInitialLocation {
                    // Set initial map region centered on user but zoomed out
                    self.setInitialMapRegion(center: userLocation)
                    self.hasSetInitialLocation = true
                    timer.invalidate() // Stop checking once we've set it
                }
            }
        }
    }
    
    // Set initial map region (zoomed out to show area)
    private func setInitialMapRegion(center: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.5)) {
            mapRegion = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(
                    latitudeDelta: 0.1,  // About 11km - shows neighborhood/area
                    longitudeDelta: 0.1
                )
            )
        }
        print("📍 Initial map region set to user location (zoomed out)")
    }
    
    // MARK: - Location Methods
    
    // Called when user taps location button - centers and zooms in
    func centerOnUserLocation() {
        guard let userLocation = locationService.userLocation else {
            print("❌ No user location available")
            
            // Request permission if not granted
            if locationService.authorizationStatus == .notDetermined {
                locationService.requestLocationPermission()
            } else if locationService.authorizationStatus == .denied ||
                      locationService.authorizationStatus == .restricted {
                // Could show alert here about enabling location in settings
                print("❌ Location permission denied")
            }
            return
        }
        
        // Animate to user location with closer zoom for precision
        withAnimation(.easeInOut(duration: 0.5)) {
            mapRegion = MKCoordinateRegion(
                center: userLocation,
                span: MKCoordinateSpan(
                    latitudeDelta: 0.02,  // About 2km - closer view
                    longitudeDelta: 0.02
                )
            )
        }
        print("📍 Centered on user location (zoomed in)")
    }
    
    // Update map region without animation (for manual pan/zoom)
    func updateMapRegion(center: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil) {
        mapRegion = MKCoordinateRegion(
            center: center,
            span: span ?? mapRegion.span
        )
    }
    
    // MARK: - Data Loading
    func loadPosts() async {
        isLoading = true
        
        do {
            // First, check ALL posts to see what we have
            let allPostsResult = try await repository.fetch(limit: 500)
            
            // Filter for posts with coordinates
            let postsWithCoords = allPostsResult.items.filter { $0.coordinates != nil }
            
            // Log posts without coordinates for debugging
            let postsWithoutCoords = allPostsResult.items.filter { $0.coordinates == nil }
            if !postsWithoutCoords.isEmpty {
                
            }
            
            // Store posts with coordinates
            posts = postsWithCoords
            filterPosts()
            
            // Load user ratings
            await loadUserRatings(for: posts)
            
        } catch {
            
        }
        
        isLoading = false
    }
    
    // MARK: - User Ratings
    func loadUserRatings(for posts: [ServicePost]) async {
        for post in posts {
            // userId is not optional, so we can use it directly
            let userId = post.userId
            
            do {
                let userDoc = try await Firestore.firestore()
                    .collection("users")
                    .document(userId)
                    .getDocument()
                
                if let data = userDoc.data() {
                    let rating = data["rating"] as? Double ?? 0.0
                    let reviewCount = data["reviewCount"] as? Int ?? 0
                    
                    await MainActor.run {
                        self.userRatings[userId] = rating
                        self.userReviewCounts[userId] = reviewCount
                    }
                }
            } catch {
                print("Error loading rating for user \(userId): \(error)")
            }
        }
    }
    
    // MARK: - Post Selection
    func selectPost(_ post: ServicePost) {
        selectedPost = post
        showingPostPreview = true
    }
    
    func dismissPostPreview() {
        showingPostPreview = false
        // Delay clearing selection for animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.selectedPost = nil
        }
    }
    
    // MARK: - Filtering
    func filterPosts() {
        var filtered = posts
        
        // Apply type filters
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
                (post.location?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        filteredPosts = filtered
    }
    
    func toggleOfferFilter() {
        showOnlyOffers.toggle()
        if showOnlyOffers {
            showOnlyRequests = false
        }
        filterPosts()
    }
    
    func toggleRequestFilter() {
        showOnlyRequests.toggle()
        if showOnlyRequests {
            showOnlyOffers = false
        }
        filterPosts()
    }
    
    // MARK: - Refresh
    func refresh() async {
        await loadPosts()
    }
    
    // MARK: - Helper Methods
    func getAnnotationColor(for post: ServicePost) -> Color {
        post.isRequest ? .orange : .blue
    }
    
    // MARK: - Zoom Methods
    func zoomIn() {
        let newSpan = MKCoordinateSpan(
            latitudeDelta: mapRegion.span.latitudeDelta * 0.5,
            longitudeDelta: mapRegion.span.longitudeDelta * 0.5
        )
        // Limit maximum zoom
        if newSpan.latitudeDelta > 0.001 {
            withAnimation(.easeInOut(duration: 0.3)) {
                updateMapRegion(center: mapRegion.center, span: newSpan)
            }
        }
    }

    func zoomOut() {
        let newSpan = MKCoordinateSpan(
            latitudeDelta: mapRegion.span.latitudeDelta * 2.0,
            longitudeDelta: mapRegion.span.longitudeDelta * 2.0
        )
        // Limit minimum zoom
        if newSpan.latitudeDelta < 10.0 {
            withAnimation(.easeInOut(duration: 0.3)) {
                updateMapRegion(center: mapRegion.center, span: newSpan)
            }
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
