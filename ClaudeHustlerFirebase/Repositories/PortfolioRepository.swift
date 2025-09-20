// PortfolioRepository.swift
// Path: ClaudeHustlerFirebase/Repositories/PortfolioRepository.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class PortfolioRepository {
    // Singleton
    static let shared = PortfolioRepository()
    
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    
    private init() {}
    
    // MARK: - Portfolio Cards
    
    func createPortfolioCard(_ card: PortfolioCard) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PortfolioRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Create new card with userId set
        let newCard = PortfolioCard(
            userId: userId,
            title: card.title,
            coverImageURL: card.coverImageURL,
            mediaURLs: card.mediaURLs,
            description: card.description,
            displayOrder: card.displayOrder
        )
        
        let docRef = try await db.collection("portfolioCards").addDocument(from: newCard)
        
        // Clear cache
        cache.remove(for: "portfolio_\(userId)")
        
        return docRef.documentID
    }
    
    // In PortfolioRepository.swift, replace updatePortfolioCard with:

    func updatePortfolioCard(_ card: PortfolioCard) async throws {
        guard let cardId = card.id,
              let userId = Auth.auth().currentUser?.uid,
              card.userId == userId else {
            throw NSError(domain: "PortfolioRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        }
        
        // Use updateData instead of setData to avoid DocumentID issues
        let updateData: [String: Any] = [
            "title": card.title,
            "coverImageURL": card.coverImageURL ?? "",
            "mediaURLs": card.mediaURLs,
            "description": card.description ?? "",
            "updatedAt": Date(),
            "displayOrder": card.displayOrder
        ]
        
        try await db.collection("portfolioCards").document(cardId).updateData(updateData)
        
        // Clear cache
        cache.remove(for: "portfolio_\(userId)")
    }
    func deletePortfolioCard(_ cardId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Verify ownership
        let doc = try await db.collection("portfolioCards").document(cardId).getDocument()
        guard let data = doc.data(),
              data["userId"] as? String == userId else {
            throw NSError(domain: "PortfolioRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        }
        
        try await db.collection("portfolioCards").document(cardId).delete()
        
        // Clear cache
        cache.remove(for: "portfolio_\(userId)")
    }
    
    func fetchPortfolioCards(for userId: String) async throws -> [PortfolioCard] {
        // Check cache
        if let cached: [PortfolioCard] = cache.retrieve([PortfolioCard].self, for: "portfolio_\(userId)"),
           !cache.isExpired(for: "portfolio_\(userId)", maxAge: 1800) { // 30 minutes
            return cached
        }
        
        let snapshot = try await db.collection("portfolioCards")
            .whereField("userId", isEqualTo: userId)
            .order(by: "displayOrder", descending: false)
            .getDocuments()
        
        let cards = snapshot.documents.compactMap { doc -> PortfolioCard? in
            var card = try? doc.data(as: PortfolioCard.self)
            card?.id = doc.documentID
            return card
        }
        
        // Cache results
        cache.store(cards, for: "portfolio_\(userId)")
        
        return cards
    }
    
    func reorderPortfolioCards(_ cardIds: [String]) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let batch = db.batch()
        
        for (index, cardId) in cardIds.enumerated() {
            let ref = db.collection("portfolioCards").document(cardId)
            batch.updateData(["displayOrder": index], forDocument: ref)
        }
        
        try await batch.commit()
        
        // Clear cache
        cache.remove(for: "portfolio_\(userId)")
    }
}
