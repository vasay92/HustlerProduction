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
            .order(by: "displayOrder")
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> PortfolioCard? in
            var card = try? doc.data(as: PortfolioCard.self)
            card?.id = doc.documentID
            return card
        }
    }
    
    // MARK: - Create Portfolio Card
    func create(_ card: PortfolioCard) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PortfolioRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        var newCard = card
        newCard.userId = userId
        
        let docRef = try await db.collection("portfolioCards").addDocument(from: newCard)
        return docRef.documentID
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
    
    // MARK: - Update Portfolio Card
    func update(_ card: PortfolioCard) async throws {
        guard let cardId = card.id else {
            throw NSError(domain: "PortfolioRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "Card ID required"])
        }
        
        try await db.collection("portfolioCards").document(cardId).setData(from: card)
    }
}
