// StatusRepository_FIXED.swift
// This fixes Status to work like Instagram/WhatsApp - multiple statuses under ONE circle per user
// Replace StatusRepository.swift content with this

import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

@MainActor
final class StatusRepository: RepositoryProtocol {
    typealias Model = Status
    
    // Singleton
    static let shared = StatusRepository()
    
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    private let cacheMaxAge: TimeInterval = 300 // 5 minutes for statuses
    
    private init() {}
    
    // MARK: - RepositoryProtocol Implementation (unchanged)
    
    func fetch(limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [Status], lastDoc: DocumentSnapshot?) {
        var query = db.collection("statuses")
            .whereField("isActive", isEqualTo: true)
            .whereField("expiresAt", isGreaterThan: Date())
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        
        if let lastDoc = lastDocument {
            query = query.start(afterDocument: lastDoc)
        }
        
        let snapshot = try await query.getDocuments()
        
        let statuses = snapshot.documents.compactMap { doc -> Status? in
            var status = try? doc.data(as: Status.self)
            status?.id = doc.documentID
            return status?.isExpired == false ? status : nil
        }
        
        return (statuses, snapshot.documents.last)
    }
    
    func fetchById(_ id: String) async throws -> Status? {
        let doc = try await db.collection("statuses").document(id).getDocument()
        var status = try? doc.data(as: Status.self)
        status?.id = doc.documentID
        return status?.isExpired == false ? status : nil
    }
    
    func create(_ item: Status) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "StatusRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let newStatus = Status(
            userId: userId,
            userName: item.userName,
            userProfileImage: item.userProfileImage,
            mediaURL: item.mediaURL,
            caption: item.caption,
            mediaType: item.mediaType,
            expiresAt: Calendar.current.date(byAdding: .hour, value: 24, to: Date()) ?? Date(),
            viewedBy: item.viewedBy,
            isActive: item.isActive
        )
        
        let docRef = try await db.collection("statuses").addDocument(from: newStatus)
        
        // Clear cache
        cache.remove(for: "statuses_following")
        cache.remove(for: "user_all_statuses_\(userId)")
        
        return docRef.documentID
    }
    
    func update(_ item: Status) async throws {
        guard let statusId = item.id else {
            throw NSError(domain: "StatusRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Status ID required"])
        }
        
        try db.collection("statuses").document(statusId).setData(from: item, merge: true)
        cache.remove(for: "status_\(statusId)")
    }
    
    func delete(_ id: String) async throws {
        try await db.collection("statuses").document(id).updateData([
            "isActive": false
        ])
        
        cache.remove(for: "status_\(id)")
        cache.remove(for: "statuses_following")
        
        if let userId = Auth.auth().currentUser?.uid {
            cache.remove(for: "user_all_statuses_\(userId)")
        }
    }
    
    // MARK: - FIXED: Fetch ALL statuses grouped by user
    
    func fetchStatusesFromFollowing(userIds: [String]) async throws -> [Status] {
        if userIds.isEmpty { return [] }
        
        // Check cache first
        if let cached: [Status] = cache.retrieve([Status].self, for: "statuses_following"),
           !cache.isExpired(for: "statuses_following", maxAge: cacheMaxAge) {
            return cached.filter { !$0.isExpired }
        }
        
        // Fetch ALL active statuses from all users
        let snapshot = try await db.collection("statuses")
            .whereField("userId", in: userIds)
            .whereField("isActive", isEqualTo: true)
            .whereField("expiresAt", isGreaterThan: Date())
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        let statuses = snapshot.documents.compactMap { doc -> Status? in
            var status = try? doc.data(as: Status.self)
            status?.id = doc.documentID
            return status?.isExpired == false ? status : nil
        }
        
        // Cache the results
        cache.store(statuses, for: "statuses_following")
        
        return statuses
    }
    
    // MARK: - NEW: Fetch ALL statuses for a specific user (for viewing)
    func fetchAllUserStatuses(for userId: String) async throws -> [Status] {
        let cacheKey = "user_all_statuses_\(userId)"
        
        // Check cache
        if let cached: [Status] = cache.retrieve([Status].self, for: cacheKey),
           !cache.isExpired(for: cacheKey, maxAge: 60) {
            return cached.filter { !$0.isExpired }
        }
        
        // Fetch ALL active statuses for this user
        let snapshot = try await db.collection("statuses")
            .whereField("userId", isEqualTo: userId)
            .whereField("isActive", isEqualTo: true)
            .whereField("expiresAt", isGreaterThan: Date())
            .order(by: "createdAt", descending: false)  // Oldest first for viewing order
            .getDocuments()
        
        let statuses = snapshot.documents.compactMap { doc -> Status? in
            var status = try? doc.data(as: Status.self)
            status?.id = doc.documentID
            return status?.isExpired == false ? status : nil
        }
        
        // Cache results
        cache.store(statuses, for: cacheKey)
        
        return statuses
    }
    
    // MARK: - Get status count for a user (for UI indicator)
    func getUserStatusCount(for userId: String) async throws -> Int {
        let statuses = try await fetchAllUserStatuses(for: userId)
        return statuses.count
    }
    
    // MARK: - Check if user has any status (for showing circle)
    func userHasActiveStatus(userId: String) async throws -> Bool {
        let statuses = try await fetchAllUserStatuses(for: userId)
        return !statuses.isEmpty
    }
    
    // MARK: - Mark all user's statuses as viewed
    func markUserStatusesAsViewed(_ userId: String, by viewerId: String) async throws {
        let statuses = try await fetchAllUserStatuses(for: userId)
        
        let batch = db.batch()
        for status in statuses where status.id != nil {
            let ref = db.collection("statuses").document(status.id!)
            batch.updateData([
                "viewedBy": FieldValue.arrayUnion([viewerId])
            ], forDocument: ref)
        }
        
        try await batch.commit()
        
        // Clear cache
        cache.remove(for: "user_all_statuses_\(userId)")
    }
    
    func markAsViewed(_ statusId: String, by userId: String) async throws {
        try await db.collection("statuses").document(statusId).updateData([
            "viewedBy": FieldValue.arrayUnion([userId])
        ])
        
        cache.remove(for: "status_\(statusId)")
    }
    
    func cleanupExpiredStatuses() async throws {
        let expiredStatuses = try await db.collection("statuses")
            .whereField("expiresAt", isLessThan: Date())
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        
        let batch = db.batch()
        
        for doc in expiredStatuses.documents {
            batch.updateData(["isActive": false], forDocument: doc.reference)
        }
        
        try await batch.commit()
        
        cache.remove(for: "statuses_following")
    }
    
    // MARK: - Legacy method for backward compatibility
    func getUserStatus(for userId: String) async throws -> Status? {
        let statuses = try await fetchAllUserStatuses(for: userId)
        return statuses.first
    }
    
    // MARK: - Create Status helper
    func createStatus(image: UIImage, caption: String?) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "StatusRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Upload image
        let imageURL = try await FirebaseService.shared.uploadImage(
            image,
            path: "statuses/\(userId)/\(UUID().uuidString).jpg"
        )
        
        // Get user info
        let userDoc = try await db.collection("users").document(userId).getDocument()
        let userData = try? userDoc.data(as: User.self)
        
        // Create status
        let status = Status(
            userId: userId,
            userName: userData?.name ?? "Unknown",
            userProfileImage: userData?.profileImageURL ?? "",
            mediaURL: imageURL,
            caption: caption,
            mediaType: .image,
            expiresAt: Calendar.current.date(byAdding: .hour, value: 24, to: Date()) ?? Date(),
            viewedBy: [],
            isActive: true
        )
        
        return try await create(status)
    }
    
    func getCurrentUserActiveStatus() async throws -> Status? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        let statuses = try await fetchAllUserStatuses(for: userId)
        return statuses.first
    }
}
