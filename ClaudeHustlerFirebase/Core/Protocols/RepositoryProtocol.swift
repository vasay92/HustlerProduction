

// RepositoryProtocol.swift
// Path: ClaudeHustlerFirebase/Core/Protocols/RepositoryProtocol.swift

import Foundation
import FirebaseFirestore

// MARK: - Base Repository Protocol
protocol RepositoryProtocol {
    associatedtype Model
    
    func fetch(limit: Int, lastDocument: DocumentSnapshot?) async throws -> (items: [Model], lastDoc: DocumentSnapshot?)
    func fetchById(_ id: String) async throws -> Model?
    func create(_ item: Model) async throws -> String
    func update(_ item: Model) async throws
    func delete(_ id: String) async throws
}

// MARK: - Paginated Response
struct PaginatedResponse<T> {
    let items: [T]
    let lastDocument: DocumentSnapshot?
    let hasMore: Bool
    let totalCount: Int?
    
    init(items: [T], lastDocument: DocumentSnapshot?, hasMore: Bool = true, totalCount: Int? = nil) {
        self.items = items
        self.lastDocument = lastDocument
        self.hasMore = hasMore
        self.totalCount = totalCount
    }
}

// MARK: - Cache Protocol
protocol CacheProtocol {
    func store<T: Encodable>(_ object: T, for key: String)
    func retrieve<T: Decodable>(_ type: T.Type, for key: String) -> T?
    func remove(for key: String)
    func clearAll()
    func isExpired(for key: String, maxAge: TimeInterval) -> Bool
}
