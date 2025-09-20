// StatusRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/StatusRepository.swift

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
    
    // MARK: - RepositoryProtocol Implementation
    
    func fetch(limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> (items: [Status], lastDoc: DocumentSnapshot?) {
        // Fetch all active statuses
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
        
        // Create a new Status with the required properties
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
        // Soft delete - mark as inactive
        try await db.collection("statuses").document(id).updateData([
            "isActive": false
        ])
        
        cache.remove(for: "status_\(id)")
        cache.remove(for: "statuses_following")
    }
    
    // MARK: - Status-Specific Methods
    
    func fetchStatusesFromFollowing(userIds: [String]) async throws -> [Status] {
        if userIds.isEmpty { return [] }
        
        // Check cache first
        if let cached: [Status] = cache.retrieve([Status].self, for: "statuses_following"),
           !cache.isExpired(for: "statuses_following", maxAge: cacheMaxAge) {
            return cached.filter { !$0.isExpired }
        }
        
        let snapshot = try await db.collection("statuses")
            .whereField("userId", in: userIds)
            .whereField("isActive", isEqualTo: true)
            .whereField("expiresAt", isGreaterThan: Date())
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
    
    func getUserStatus(for userId: String) async throws -> Status? {
        let snapshot = try await db.collection("statuses")
            .whereField("userId", isEqualTo: userId)
            .whereField("isActive", isEqualTo: true)
            .whereField("expiresAt", isGreaterThan: Date())
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments()
        
        guard let doc = snapshot.documents.first else { return nil }
        var status = try doc.data(as: Status.self)
        status.id = doc.documentID
        return status.isExpired == false ? status : nil
    }
    
    // Add to StatusRepository.swift
    func createStatus(image: UIImage, caption: String?) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "StatusRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Upload image using FirebaseService
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
}
