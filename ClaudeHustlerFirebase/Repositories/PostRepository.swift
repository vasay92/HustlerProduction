// PostRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/PostRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

// MARK: - Post Repository
final class PostRepository: RepositoryProtocol {
    typealias Model = ServicePost
    static let shared = PostRepository()
    
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    private let cacheMaxAge: TimeInterval = 300 // 5 minutes
    
    // MARK: - Fetch Posts with Pagination
    func fetch(limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [ServicePost], lastDoc: DocumentSnapshot?) {
        // Create query
        var query = db.collection("posts")
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
        
        // Add pagination if we have a last document
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        // Execute query
        let snapshot = try await query.getDocuments()
        
        // Parse documents
        let posts = snapshot.documents.compactMap { doc -> ServicePost? in
            var post = try? doc.data(as: ServicePost.self)
            post?.id = doc.documentID
            return post
        }
        
        // Get last document for next pagination
        let lastDoc = snapshot.documents.last
        
        // Cache the first page if it's a fresh fetch
        if lastDocument == nil && !posts.isEmpty {
            cache.store(posts, for: "posts_page_1")
        }
        
        return (posts, lastDoc)
    }
    
    // MARK: - Fetch Single Post
    func fetchById(_ id: String) async throws -> ServicePost? {
        // Check cache first
        let cacheKey = "post_\(id)"
        if !cache.isExpired(for: cacheKey, maxAge: cacheMaxAge),
           let cachedPost: ServicePost = cache.retrieve(ServicePost.self, for: cacheKey) {
            return cachedPost
        }
        
        // Fetch from Firestore
        let document = try await db.collection("posts").document(id).getDocument()
        
        guard document.exists else { return nil }
        
        var post = try document.data(as: ServicePost.self)
        post.id = document.documentID
        
        // Cache the post
        cache.store(post, for: cacheKey)
        
        return post
    }
    
    
    
    // MARK: - Fetch Offers
    func fetchOffers(limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [ServicePost], lastDoc: DocumentSnapshot?) {
        var query = db.collection("posts")
            .whereField("isRequest", isEqualTo: false)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let posts = snapshot.documents.compactMap { doc -> ServicePost? in
            var post = try? doc.data(as: ServicePost.self)
            post?.id = doc.documentID
            return post
        }
        
        return (posts, snapshot.documents.last)
    }
    
    // MARK: - Fetch Requests
    func fetchRequests(limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [ServicePost], lastDoc: DocumentSnapshot?) {
        var query = db.collection("posts")
            .whereField("isRequest", isEqualTo: true)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let posts = snapshot.documents.compactMap { doc -> ServicePost? in
            var post = try? doc.data(as: ServicePost.self)
            post?.id = doc.documentID
            return post
        }
        
        return (posts, snapshot.documents.last)
    }
    
    // MARK: - Create Post (Updated with Location Support)
    func create(_ post: ServicePost) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PostRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Create a new post with the userId set (matching the order in DataModels.swift)
        var postData = ServicePost(
            id: post.id,
            userId: userId,
            userName: post.userName,
            userProfileImage: post.userProfileImage,
            title: post.title,
            description: post.description,
            category: post.category,
            price: post.price,
            location: post.location,
            imageURLs: post.imageURLs,
            isRequest: post.isRequest,
            status: post.status,
            updatedAt: Date(),  // This comes before the location fields
            coordinates: post.coordinates,
            locationPrivacy: post.locationPrivacy,
            approximateRadius: post.approximateRadius
        )
        
        // Handle location privacy
        if let coordinates = post.coordinates, post.locationPrivacy == .approximate {
            // Need to await the async call to LocationService
            let obfuscated = await LocationService.shared.obfuscateCoordinate(
                CLLocationCoordinate2D(
                    latitude: coordinates.latitude,
                    longitude: coordinates.longitude
                ),
                radiusInMeters: post.approximateRadius ?? 1000
            )
            postData.coordinates = GeoPoint(
                latitude: obfuscated.latitude,
                longitude: obfuscated.longitude
            )
        }
        
        // Create document
        let docRef = try await db.collection("posts").addDocument(from: postData)
        
        // Clear cache for posts list
        cache.remove(for: "posts_page_1")
        
        return docRef.documentID
    }
    
    // MARK: - Update Post (Updated with Location Support)
    func update(_ post: ServicePost) async throws {
        guard let postId = post.id else {
            throw NSError(domain: "PostRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Post ID is required"])
        }
        
        // Verify ownership before updating
        let document = try await db.collection("posts").document(postId).getDocument()
        guard let data = document.data(),
              let postUserId = data["userId"] as? String,
              postUserId == Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PostRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not authorized to update this post"])
        }
        
        // Prepare update data
        var updateData: [String: Any] = [
            "title": post.title,
            "description": post.description,
            "category": post.category.rawValue,
            "price": post.price as Any,
            "location": post.location as Any,
            "imageURLs": post.imageURLs,
            "isRequest": post.isRequest,
            "status": post.status.rawValue,
            "updatedAt": Timestamp(date: Date()),
            "locationPrivacy": post.locationPrivacy.rawValue
        ]
        
        // Handle coordinates based on privacy setting
        if let coordinates = post.coordinates {
            if post.locationPrivacy == .approximate {
                // Obfuscate for approximate location
                // In the update method, change this line:
                let obfuscated = await LocationService.shared.obfuscateCoordinate(
                    CLLocationCoordinate2D(
                        latitude: coordinates.latitude,
                        longitude: coordinates.longitude
                    ),
                    radiusInMeters: post.approximateRadius ?? 1000
                )
                updateData["coordinates"] = GeoPoint(
                    latitude: obfuscated.latitude,
                    longitude: obfuscated.longitude
                )
            } else {
                // Use exact coordinates
                updateData["coordinates"] = coordinates
            }
        }
        
        if let radius = post.approximateRadius {
            updateData["approximateRadius"] = radius
        }
        
        // Update document
        try await db.collection("posts").document(postId).updateData(updateData)
        
        // Clear cache
        cache.remove(for: "post_\(postId)")
        cache.remove(for: "posts_page_1")
    }
    
    // MARK: - Delete Post
    func delete(_ id: String) async throws {
        guard Auth.auth().currentUser?.uid != nil else {
            throw NSError(domain: "PostRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        try await db.collection("posts").document(id).delete()
        
        // Clear cache
        cache.remove(for: "post_\(id)")
        cache.remove(for: "posts_page_1")
    }
    
    // MARK: - Search Posts
    func search(query: String, limit: Int = 20) async throws -> [ServicePost] {
        // Note: For proper text search, consider using Algolia or ElasticSearch
        // This is a basic implementation
        let snapshot = try await db.collection("posts")
            .order(by: "updatedAt", descending: true)
            .limit(to: 100)
            .getDocuments()
        
        let posts = snapshot.documents.compactMap { doc -> ServicePost? in
            var post = try? doc.data(as: ServicePost.self)
            post?.id = doc.documentID
            return post
        }.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query)
        }
        
        return Array(posts.prefix(limit))
    }
    
    // MARK: - User Posts
    func fetchUserPosts(userId: String, limit: Int = 100) async throws -> [ServicePost] {
        let snapshot = try await db.collection("posts")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let posts = snapshot.documents.compactMap { doc -> ServicePost? in
            var post = try? doc.data(as: ServicePost.self)
            post?.id = doc.documentID
            return post
        }
        
        // Cache user posts
        cache.store(posts, for: "user_posts_\(userId)")
        
        return posts
    }

    func fetchUserPostCount(userId: String) async throws -> Int {
        let snapshot = try await db.collection("posts")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", isEqualTo: ServicePost.PostStatus.active.rawValue)
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    // Add to PostRepository.swift
    func searchPosts(
        query: String,
        category: ServiceCategory? = nil,
        isRequest: Bool? = nil,
        limit: Int = 20
    ) async throws -> [ServicePost] {
        var firestoreQuery = db.collection("posts")
            .order(by: "updatedAt", descending: true)
        
        if let category = category {
            firestoreQuery = firestoreQuery.whereField("category", isEqualTo: category.rawValue)
        }
        
        if let isRequest = isRequest {
            firestoreQuery = firestoreQuery.whereField("isRequest", isEqualTo: isRequest)
        }
        
        let snapshot = try await firestoreQuery.limit(to: 100).getDocuments()
        
        let posts = snapshot.documents.compactMap { doc -> ServicePost? in
            var post = try? doc.data(as: ServicePost.self)
            post?.id = doc.documentID
            return post
        }.filter {
            query.isEmpty ||
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query)
        }
        
        return Array(posts.prefix(limit))
    }
}

// MARK: - Location Extension
extension PostRepository {
    // MARK: - Location-Based Queries
    
    /// Fetch posts within a certain radius of a coordinate
    func fetchPostsNearLocation(
        center: CLLocationCoordinate2D,
        radiusInMeters: Double,
        isRequest: Bool? = nil,
        limit: Int = 50
    ) async throws -> [ServicePost] {
        // Convert radius to approximate latitude/longitude bounds
        // 1 degree latitude ≈ 111km
        let latitudeDelta = radiusInMeters / 111000.0
        let longitudeDelta = radiusInMeters / (111000.0 * cos(center.latitude * .pi / 180))
        
        let minLat = center.latitude - latitudeDelta
        let maxLat = center.latitude + latitudeDelta
        let minLon = center.longitude - longitudeDelta
        let maxLon = center.longitude + longitudeDelta
        
        // Create a compound query for posts within bounds
        var query = db.collection("posts")
            .whereField("coordinates", isGreaterThan: GeoPoint(latitude: minLat, longitude: minLon))
            .whereField("coordinates", isLessThan: GeoPoint(latitude: maxLat, longitude: maxLon))
        
        // Add request filter if specified
        if let isRequest = isRequest {
            query = query.whereField("isRequest", isEqualTo: isRequest)
        }
        
        let snapshot = try await query.limit(to: limit).getDocuments()
        
        var posts = snapshot.documents.compactMap { doc -> ServicePost? in
            var post = try? doc.data(as: ServicePost.self)
            post?.id = doc.documentID
            return post
        }
        
        // Further filter by exact distance (since Firestore query is rectangular)
        posts = posts.filter { post in
            guard let coordinates = post.coordinates else { return false }
            
            let postLocation = CLLocation(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude
            )
            let centerLocation = CLLocation(
                latitude: center.latitude,
                longitude: center.longitude
            )
            
            return postLocation.distance(from: centerLocation) <= radiusInMeters
        }
        
        return posts
    }
    
    /// Fetch all posts with coordinates for map display
    func fetchAllPostsWithLocation(
        isRequest: Bool? = nil,
        limit: Int = 200
    ) async throws -> [ServicePost] {
        var query = db.collection("posts")
            .whereField("coordinates", isNotEqualTo: NSNull())
            .whereField("status", isEqualTo: ServicePost.PostStatus.active.rawValue)
            .order(by: "coordinates")
            .order(by: "updatedAt", descending: true)
        
        if let isRequest = isRequest {
            query = query.whereField("isRequest", isEqualTo: isRequest)
        }
        
        let snapshot = try await query.limit(to: limit).getDocuments()
        
        let posts = snapshot.documents.compactMap { doc -> ServicePost? in
            var post = try? doc.data(as: ServicePost.self)
            post?.id = doc.documentID
            return post
        }
        
        return posts
    }
    
    /// Update existing posts to add GeoPoint from location string
    func migrateLocationStringToGeoPoint(for postId: String) async throws {
        guard let post = try await fetchById(postId),
              let locationString = post.location,
              post.coordinates == nil else { return }
        
        do {
            let coordinate = try await LocationService.shared.geocodeAddress(locationString)
            
            try await db.collection("posts").document(postId).updateData([
                "coordinates": GeoPoint(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ),
                "locationPrivacy": ServicePost.LocationPrivacy.exact.rawValue
            ])
            
            // Clear cache
            cache.remove(for: "post_\(postId)")
        } catch {
            print("Failed to geocode location for post \(postId): \(error)")
        }
    }
}
