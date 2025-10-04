// TagRepository.swift
// Repository for managing tags and tag analytics

import Foundation
import FirebaseFirestore
import FirebaseAuth

final class TagRepository {
    // Singleton
    static let shared = TagRepository()
    
    private let db = Firestore.firestore()
    private let cache = CacheService.shared
    private let cacheMaxAge: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    // MARK: - Fetch Trending Tags
    func fetchTrendingTags(limit: Int = 20) async throws -> [String] {
        // Check cache first
        let cacheKey = "trending_tags"
        if !cache.isExpired(for: cacheKey, maxAge: cacheMaxAge),
           let cachedTags: [String] = cache.retrieve([String].self, for: cacheKey) {
            return cachedTags
        }
        
        // Fetch from Firestore
        let snapshot = try await db.collection("tagAnalytics")
            .order(by: "trendingScore", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let tags = snapshot.documents.compactMap { doc -> String? in
            guard let analytics = try? doc.data(as: TagAnalytics.self) else { return nil }
            return analytics.tag
        }
        
        // Cache the result
        cache.store(tags, for: cacheKey)
        
        return tags
    }
    
    // MARK: - Fetch User's Recent Tags
    func fetchUserRecentTags(userId: String, limit: Int = 10) async throws -> [String] {
        var recentTags = Set<String>()
        
        // Get from recent posts
        let postsSnapshot = try await db.collection("posts")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .getDocuments()
        
        for doc in postsSnapshot.documents {
            if let post = try? doc.data(as: ServicePost.self) {
                post.tags.forEach { recentTags.insert($0) }
            }
        }
        
        // Get from recent reels
        let reelsSnapshot = try await db.collection("reels")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .getDocuments()
        
        for doc in reelsSnapshot.documents {
            if let reel = try? doc.data(as: Reel.self) {
                reel.tags.forEach { recentTags.insert($0) }
            }
        }
        
        return Array(recentTags.prefix(limit))
    }
    
    // MARK: - Update Tag Analytics
    func updateTagAnalytics(_ tags: [String], type: String) async {
        guard !tags.isEmpty else { return }
        
        let batch = db.batch()
        
        for tag in tags {
            let tagId = tag.replacingOccurrences(of: "#", with: "")
            let docRef = db.collection("tagAnalytics").document(tagId)
            
            // Use FieldValue for atomic operations
            let updates: [String: Any] = [
                "tag": tag,
                "usageCount": FieldValue.increment(Int64(1)),
                "lastUsed": Date(),
                "\(type)Count": FieldValue.increment(Int64(1)),
                "trendingScore": FieldValue.increment(Double(1.0))
            ]
            
            batch.setData(updates, forDocument: docRef, merge: true)
        }
        
        do {
            try await batch.commit()
            
            // Clear trending cache
            cache.remove(for: "trending_tags")
        } catch {
            print("Error updating tag analytics: \(error)")
        }
    }
    
    // MARK: - Search Tags with Autocomplete
    func searchTags(query: String, limit: Int = 10) async -> [String] {
        guard query.count >= 2 else { return [] }
        
        let cleanQuery = query.lowercased()
            .replacingOccurrences(of: " ", with: "-")
        
        do {
            // Search in tag analytics
            let snapshot = try await db.collection("tagAnalytics")
                .order(by: "tag")
                .start(at: [cleanQuery])
                .end(at: [cleanQuery + "\u{f8ff}"])
                .limit(to: limit)
                .getDocuments()
            
            let tags = snapshot.documents.compactMap { doc -> String? in
                guard let analytics = try? doc.data(as: TagAnalytics.self) else { return nil }
                return analytics.tag
            }
            
            // If not enough results, add some default suggestions
            var suggestions = tags
            
            if suggestions.count < 5 {
                let defaults = getDefaultSuggestions(for: cleanQuery)
                suggestions.append(contentsOf: defaults.filter { !suggestions.contains($0) })
            }
            
            return Array(suggestions.prefix(limit))
            
        } catch {
            print("Error searching tags: \(error)")
            return getDefaultSuggestions(for: cleanQuery)
        }
    }
    
    // MARK: - Get Popular Tags by Time Period
    func getPopularTags(days: Int = 7, limit: Int = 20) async throws -> [String] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        let snapshot = try await db.collection("tagAnalytics")
            .whereField("lastUsed", isGreaterThanOrEqualTo: startDate)
            .order(by: "usageCount", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> String? in
            guard let analytics = try? doc.data(as: TagAnalytics.self) else { return nil }
            return analytics.tag
        }
    }
    
    // MARK: - Private Helpers
    private func getDefaultSuggestions(for query: String) -> [String] {
        let commonTags = [
            "#cleaning", "#housecleaning", "#deepclean", "#moveoutclean",
            "#tutoring", "#mathtutoring", "#englishtutor", "#testprep",
            "#plumbing", "#plumber", "#leakrepair", "#emergency",
            "#electrical", "#electrician", "#wiring", "#lighting",
            "#moving", "#movers", "#packinghelp", "#delivery",
            "#landscaping", "#lawncare", "#gardening", "#treeservice",
            "#painting", "#interiorpainting", "#exteriorpainting",
            "#handyman", "#repairs", "#maintenance", "#assembly",
            "#dogwalking", "#petsitting", "#petcare", "#dogtraining",
            "#babysitting", "#childcare", "#nanny", "#afterschool",
            "#photography", "#photoshoot", "#eventphotography",
            "#catering", "#personalchef", "#mealprep", "#baking",
            "#fitness", "#personaltrainer", "#yoga", "#pilates",
            "#massage", "#haircut", "#makeup", "#nails"
        ]
        
        return commonTags.filter { tag in
            tag.lowercased().contains(query.lowercased())
        }.prefix(5).map { $0 }
    }
    
    // MARK: - Cleanup Old Analytics
    func cleanupOldAnalytics(olderThan days: Int = 90) async throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        let snapshot = try await db.collection("tagAnalytics")
            .whereField("lastUsed", isLessThan: cutoffDate)
            .whereField("usageCount", isLessThan: 5)
            .getDocuments()
        
        let batch = db.batch()
        
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        if !snapshot.documents.isEmpty {
            try await batch.commit()
        }
    }
}
