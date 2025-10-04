// PostRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/PostRepository.swift
// UPDATED: Complete file with tag support, removed category methods

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
    
    // MARK: - Fetch by Tags (NEW)
    func fetchByTags(_ tags: [String], limit: Int = 20, lastDocument: DocumentSnapshot? = nil, isRequest: Bool? = nil) async throws -> (items: [ServicePost], lastDoc: DocumentSnapshot?) {
        guard !tags.isEmpty else {
            // If no tags specified, return regular fetch
            if let isRequest = isRequest {
                return isRequest ?
                    try await fetchRequests(limit: limit, lastDocument: lastDocument) :
                    try await fetchOffers(limit: limit, lastDocument: lastDocument)
            } else {
                return try await fetch(limit: limit, lastDocument: lastDocument)
            }
        }
        
        // Build query
        var query = db.collection("posts")
            .whereField("tags", arrayContainsAny: tags)
        
        // Add request filter if specified
        if let isRequest = isRequest {
            query = query.whereField("isRequest", isEqualTo: isRequest)
        }
        
        query = query
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
    
    // MARK: - Search Posts with Tags (NEW)
    func searchPostsWithTags(query searchText: String, tags: [String]? = nil, limit: Int = 50) async throws -> [ServicePost] {
        // Note: This is a basic implementation using client-side filtering
        // For production, consider using a search service like Algolia
        
        // First fetch posts (with tag filter if provided)
        let (posts, _) = if let tags = tags, !tags.isEmpty {
            try await fetchByTags(tags, limit: limit)
        } else {
            try await fetch(limit: limit)
        }
        
        // If no search text, return all posts
        guard !searchText.isEmpty else {
            return posts
        }
        
        let searchLower = searchText.lowercased()
        
        // Filter posts by search text
        return posts.filter { post in
            // Search in title
            if post.title.lowercased().contains(searchLower) {
                return true
            }
            
            // Search in description
            if post.description.lowercased().contains(searchLower) {
                return true
            }
            
            // Search in tags
            if post.tags.contains(where: { tag in
                tag.lowercased().contains(searchLower)
            }) {
                return true
            }
            
            // Search in location
            if let location = post.location,
               location.lowercased().contains(searchLower) {
                return true
            }
            
            return false
        }
    }
    
    // MARK: - Fetch Popular Tags for Posts (NEW)
    func fetchPopularPostTags(limit: Int = 20) async throws -> [String] {
        // This aggregates tags from recent posts
        let snapshot = try await db.collection("posts")
            .order(by: "updatedAt", descending: true)
            .limit(to: 100)  // Sample from last 100 posts
            .getDocuments()
        
        var tagCounts: [String: Int] = [:]
        
        // Count tag occurrences
        for doc in snapshot.documents {
            if let post = try? doc.data(as: ServicePost.self) {
                for tag in post.tags {
                    tagCounts[tag, default: 0] += 1
                }
            }
        }
        
        // Sort by count and return top tags
        let sortedTags = tagCounts.sorted { $0.value > $1.value }
        return Array(sortedTags.prefix(limit).map { $0.key })
    }
    
    // MARK: - Fetch Posts by Multiple Tags AND operation (NEW)
    func fetchByAllTags(_ tags: [String], limit: Int = 20) async throws -> [ServicePost] {
        guard !tags.isEmpty else {
            let (posts, _) = try await fetch(limit: limit)
            return posts
        }
        
        // Firestore doesn't support multiple arrayContains queries
        // So we fetch with one tag and filter the rest client-side
        let firstTag = tags.first!
        let remainingTags = Array(tags.dropFirst())
        
        let query = db.collection("posts")
            .whereField("tags", arrayContains: firstTag)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit * 2)  // Fetch more to account for filtering
        
        let snapshot = try await query.getDocuments()
        
        let posts = snapshot.documents.compactMap { doc -> ServicePost? in
            var post = try? doc.data(as: ServicePost.self)
            post?.id = doc.documentID
            
            // Check if post contains all required tags
            guard let postTags = post?.tags else { return nil }
            
            for tag in remainingTags {
                if !postTags.contains(tag) {
                    return nil
                }
            }
            
            return post
        }
        
        return Array(posts.prefix(limit))
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
        
        // Create a new post with the userId set
        var postData = ServicePost(
            id: post.id,
            userId: userId,
            userName: post.userName,
            userProfileImage: post.userProfileImage,
            title: post.title,
            description: post.description,
            tags: post.tags,  // UPDATED: Use tags instead of category
            price: post.price,
            location: post.location,
            imageURLs: post.imageURLs,
            isRequest: post.isRequest,
            status: post.status,
            updatedAt: Date(),
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
            "tags": post.tags,  // UPDATED: Use tags instead of category
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
    
    // MARK: - Search Posts (UPDATED: Removed category parameter)
    func searchPosts(
        query: String,
        isRequest: Bool? = nil,
        limit: Int = 20
    ) async throws -> [ServicePost] {
        var firestoreQuery = db.collection("posts")
            .order(by: "updatedAt", descending: true)
        
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
            $0.description.localizedCaseInsensitiveContains(query) ||
            $0.tags.contains { tag in
                tag.localizedCaseInsensitiveContains(query)
            }
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
}

// MARK: - Location Extension
extension PostRepository {
    // MARK: - Location-Based Queries
    
    /// Fetch posts within a certain radius of a coordinate
    func fetchPostsNearLocation(
        center: CLLocationCoordinate2D,
        radiusInMeters: Double,
        isRequest: Bool? = nil,
        limit: Int = 20
    ) async throws -> [ServicePost] {
        // Note: For true geospatial queries, consider using GeoFirestore or similar
        // This is a basic implementation that fetches all and filters
        let (posts, _) = try await fetch(limit: 100)
        
        return posts.filter { post in
            // Filter by request type if specified
            if let isRequest = isRequest, post.isRequest != isRequest {
                return false
            }
            
            // Check if post has coordinates
            guard let coordinates = post.coordinates else { return false }
            
            let postLocation = CLLocationCoordinate2D(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude
            )
            
            let distance = LocationService.shared.distance(
                from: center,
                to: postLocation
            )
            
            return distance <= radiusInMeters
        }
    }
    
    /// Fetch posts by city name
    func fetchPostsByCity(_ city: String, limit: Int = 20) async throws -> [ServicePost] {
        let snapshot = try await db.collection("posts")
            .whereField("location", isGreaterThanOrEqualTo: city)
            .whereField("location", isLessThanOrEqualTo: city + "\u{f8ff}")
            .order(by: "location")
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> ServicePost? in
            var post = try? doc.data(as: ServicePost.self)
            post?.id = doc.documentID
            return post
        }
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
