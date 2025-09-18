

// CacheService.swift
// Path: ClaudeHustlerFirebase/Services/CacheService.swift

import Foundation
import UIKit

// MARK: - Cache Service
final class CacheService: CacheProtocol {
    static let shared = CacheService()
    
    private let memoryCache = NSCache<NSString, AnyObject>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let cacheQueue = DispatchQueue(label: "com.claudehustler.cache", attributes: .concurrent)
    
    private var timestamps: [String: Date] = [:]
    
    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ClaudeHustlerCache")
        
        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure memory cache
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        
        // Setup memory warning observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    func store<T: Encodable>(_ object: T, for key: String) {
        cacheQueue.async(flags: .barrier) {
            // Store in memory cache
            if let data = try? self.encoder.encode(object) {
                self.memoryCache.setObject(data as NSData, forKey: key as NSString)
            }
            
            // Store on disk
            let fileURL = self.cacheDirectory.appendingPathComponent(key.sanitizedForFileName)
            if let data = try? self.encoder.encode(object) {
                try? data.write(to: fileURL)
                self.timestamps[key] = Date()
            }
        }
    }
    
    func retrieve<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        // Check memory cache first
        if let data = memoryCache.object(forKey: key as NSString) as? Data {
            return try? decoder.decode(type, from: data)
        }
        
        // Check disk cache
        var result: T?
        cacheQueue.sync {
            let fileURL = cacheDirectory.appendingPathComponent(key.sanitizedForFileName)
            if let data = try? Data(contentsOf: fileURL) {
                result = try? decoder.decode(type, from: data)
                
                // Store in memory cache for faster access next time
                memoryCache.setObject(data as NSData, forKey: key as NSString)
            }
        }
        return result
    }
    
    func remove(for key: String) {
        cacheQueue.async(flags: .barrier) {
            // Remove from memory cache
            self.memoryCache.removeObject(forKey: key as NSString)
            
            // Remove from disk
            let fileURL = self.cacheDirectory.appendingPathComponent(key.sanitizedForFileName)
            try? self.fileManager.removeItem(at: fileURL)
            
            // Remove timestamp
            self.timestamps.removeValue(forKey: key)
        }
    }
    
    func clearAll() {
        cacheQueue.async(flags: .barrier) {
            // Clear memory cache
            self.memoryCache.removeAllObjects()
            
            // Clear disk cache
            if let files = try? self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil) {
                for file in files {
                    try? self.fileManager.removeItem(at: file)
                }
            }
            
            // Clear timestamps
            self.timestamps.removeAll()
        }
    }
    
    func isExpired(for key: String, maxAge: TimeInterval) -> Bool {
        guard let timestamp = timestamps[key] else { return true }
        return Date().timeIntervalSince(timestamp) > maxAge
    }
    
    // MARK: - Private Methods
    
    @objc private func handleMemoryWarning() {
        memoryCache.removeAllObjects()
    }
}

// MARK: - Helper Extensions
private extension String {
    var sanitizedForFileName: String {
        return self.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
