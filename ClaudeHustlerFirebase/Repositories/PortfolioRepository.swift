// PortfolioRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/PortfolioRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class PortfolioRepository {
    static let shared = PortfolioRepository()
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    
    private init() {}
    
    // MARK: - Fetch User Portfolio Cards
    func fetchUserPortfolioCards(userId: String) async throws -> [PortfolioCard] {
        let snapshot = try await db.collection("portfolioCards")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)  // Changed to show newest first
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> PortfolioCard? in
            var card = try? doc.data(as: PortfolioCard.self)
            card?.id = doc.documentID
            return card
        }
    }
    
    // Alias for fetchUserPortfolioCards (for compatibility)
    func fetchPortfolioCards(for userId: String) async throws -> [PortfolioCard] {
        return try await fetchUserPortfolioCards(userId: userId)
    }
    
    // MARK: - Create Portfolio Card
    func create(_ card: PortfolioCard) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PortfolioRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Create new card with proper userId and add createdAt timestamp
        let newCard = PortfolioCard(
            userId: userId,
            title: card.title,
            coverImageURL: card.coverImageURL,
            mediaURLs: card.mediaURLs,
            description: card.description,
            displayOrder: card.displayOrder,
            createdAt: Date()  // Add creation timestamp
        )
        
        let docRef = try await db.collection("portfolioCards").addDocument(from: newCard)
        return docRef.documentID
    }
    
    // Alias for create (for compatibility with existing code)
    func createPortfolioCard(_ card: PortfolioCard) async throws -> String {
        return try await create(card)
    }
    
    // MARK: - Delete Portfolio Card
    func delete(_ cardId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PortfolioRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Verify ownership before deleting
        let doc = try await db.collection("portfolioCards").document(cardId).getDocument()
        guard let data = doc.data(),
              let cardUserId = data["userId"] as? String,
              cardUserId == userId else {
            throw NSError(domain: "PortfolioRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized to delete this card"])
        }
        
        try await db.collection("portfolioCards").document(cardId).delete()
    }
    
    // Alias for delete (for compatibility)
    func deletePortfolioCard(_ cardId: String) async throws {
        try await delete(cardId)
    }
    
    // MARK: - Update Portfolio Card
    func update(_ card: PortfolioCard) async throws {
        guard let cardId = card.id else {
            throw NSError(domain: "PortfolioRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Card ID required"])
        }
        
        // Use updateData instead of setData to avoid the warning
        let data: [String: Any] = [
            "title": card.title,
            "coverImageURL": card.coverImageURL as Any,
            "mediaURLs": card.mediaURLs,
            "description": card.description as Any,
            "updatedAt": Date(),
            "displayOrder": card.displayOrder
        ]
        
        try await db.collection("portfolioCards").document(cardId).updateData(data)
    }
    
    // Alias for update (for compatibility)
    func updatePortfolioCard(_ card: PortfolioCard) async throws {
        try await update(card)
    }
}
