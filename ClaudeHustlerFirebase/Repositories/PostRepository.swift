

// PostRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/PostRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

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
    
    // MARK: - Fetch by Category
    func fetchByCategory(_ category: ServiceCategory, limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [ServicePost], lastDoc: DocumentSnapshot?) {
        var query = db.collection("posts")
            .whereField("category", isEqualTo: category.rawValue)
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
    
    // MARK: - Create Post
    func create(_ post: ServicePost) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PostRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Create with correct properties
        let postData = ServicePost(
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
            updatedAt: Date()
        )
        
        let docRef = try await db.collection("posts").addDocument(from: postData)
        
        // Clear cache for posts list
        cache.remove(for: "posts_page_1")
        
        return docRef.documentID
    }

    
    // MARK: - Update Post
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
        
        // Use updateData instead of setData to avoid DocumentID issues
        let updateData: [String: Any] = [
            "title": post.title,
            "description": post.description,
            "category": post.category.rawValue,
            "price": post.price as Any,
            "location": post.location as Any,
            "imageURLs": post.imageURLs,
            "isRequest": post.isRequest,
            "status": post.status.rawValue,
            "updatedAt": Timestamp(date: Date())
        ]
        
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
}
