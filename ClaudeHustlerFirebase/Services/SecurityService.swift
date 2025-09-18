

// SecurityService.swift
// Path: ClaudeHustlerFirebase/Services/SecurityService.swift

import Foundation
import UIKit

class SecurityService {
    
    // MARK: - Email Validation
    static func validateEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    // MARK: - Password Validation
    static func validatePassword(_ password: String) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if password.count < 8 {
            errors.append("Password must be at least 8 characters")
        }
        
        if password.count > 128 {
            errors.append("Password must be less than 128 characters")
        }
        
        if !password.contains(where: { $0.isUppercase }) {
            errors.append("Password must contain at least one uppercase letter")
        }
        
        if !password.contains(where: { $0.isLowercase }) {
            errors.append("Password must contain at least one lowercase letter")
        }
        
        if !password.contains(where: { $0.isNumber }) {
            errors.append("Password must contain at least one number")
        }
        
        let specialCharacters = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?")
        if password.rangeOfCharacter(from: specialCharacters) == nil {
            errors.append("Password must contain at least one special character")
        }
        
        return (errors.isEmpty, errors)
    }
    
    // MARK: - Input Sanitization
    static func sanitizeInput(_ input: String) -> String {
        // Remove leading/trailing whitespace
        var sanitized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove potential script injection characters
        let dangerousCharacters = ["<", ">", "&", "\"", "'", "/", "\\", "`", "="]
        for char in dangerousCharacters {
            sanitized = sanitized.replacingOccurrences(of: char, with: "")
        }
        
        // Limit length
        if sanitized.count > 500 {
            sanitized = String(sanitized.prefix(500))
        }
        
        return sanitized
    }
    
    // MARK: - Name Validation
    static func validateName(_ name: String) -> (isValid: Bool, error: String?) {
        let sanitized = sanitizeInput(name)
        
        if sanitized.isEmpty {
            return (false, "Name cannot be empty")
        }
        
        if sanitized.count < 2 {
            return (false, "Name must be at least 2 characters")
        }
        
        if sanitized.count > 50 {
            return (false, "Name must be less than 50 characters")
        }
        
        // Check for inappropriate content (basic profanity filter)
        let inappropriateWords = ["admin", "administrator", "root", "test", "fuck", "shit"]
        for word in inappropriateWords {
            if sanitized.lowercased().contains(word) {
                return (false, "Name contains inappropriate content")
            }
        }
        
        return (true, nil)
    }
    
    // MARK: - Image Validation
    static func validateImage(_ image: UIImage) -> (isValid: Bool, error: String?) {
        // Check file size (max 10MB)
        guard let imageData = image.jpegData(compressionQuality: 1.0) else {
            return (false, "Invalid image format")
        }
        
        let maxSizeInBytes = 10 * 1024 * 1024 // 10MB
        if imageData.count > maxSizeInBytes {
            return (false, "Image size must be less than 10MB")
        }
        
        // Check dimensions (max 4096x4096)
        let maxDimension: CGFloat = 4096
        if image.size.width > maxDimension || image.size.height > maxDimension {
            return (false, "Image dimensions must be less than 4096x4096")
        }
        
        // Check minimum dimensions
        let minDimension: CGFloat = 100
        if image.size.width < minDimension || image.size.height < minDimension {
            return (false, "Image dimensions must be at least 100x100")
        }
        
        return (true, nil)
    }
    
    // MARK: - Text Content Validation
    static func validateTextContent(_ text: String, fieldName: String, minLength: Int = 1, maxLength: Int = 1000) -> (isValid: Bool, error: String?) {
        let sanitized = sanitizeInput(text)
        
        if sanitized.count < minLength {
            return (false, "\(fieldName) must be at least \(minLength) characters")
        }
        
        if sanitized.count > maxLength {
            return (false, "\(fieldName) must be less than \(maxLength) characters")
        }
        
        // Check for spam patterns
        if isSpamContent(sanitized) {
            return (false, "\(fieldName) appears to contain spam")
        }
        
        return (true, nil)
    }
    
    // MARK: - Price Validation
    static func validatePrice(_ priceString: String) -> (isValid: Bool, price: Double?, error: String?) {
        let sanitized = priceString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let price = Double(sanitized) else {
            return (false, nil, "Invalid price format")
        }
        
        if price < 0 {
            return (false, nil, "Price cannot be negative")
        }
        
        if price > 100000 {
            return (false, nil, "Price cannot exceed $100,000")
        }
        
        return (true, price, nil)
    }
    
    // MARK: - Helper Methods
    private static func isSpamContent(_ text: String) -> Bool {
        let spamPatterns = [
            "buy now",
            "click here",
            "limited time offer",
            "act now",
            "100% free",
            "winner",
            "congratulations",
            "prize"
        ]
        
        let lowercasedText = text.lowercased()
        
        // Check for excessive caps (more than 50% capitals)
        let capitalCount = text.filter { $0.isUppercase }.count
        if text.count > 10 && Double(capitalCount) / Double(text.count) > 0.5 {
            return true
        }
        
        // Check for spam patterns
        for pattern in spamPatterns {
            if lowercasedText.contains(pattern) {
                return true
            }
        }
        
        // Check for excessive special characters or numbers
        let specialCharCount = text.filter { !$0.isLetter && !$0.isWhitespace }.count
        if text.count > 10 && Double(specialCharCount) / Double(text.count) > 0.3 {
            return true
        }
        
        return false
    }
    
    // MARK: - Rate Limiting
    static let rateLimiter = RateLimiter()
}

// MARK: - Rate Limiter
class RateLimiter {
    private var requestCounts: [String: [Date]] = [:]
    private let queue = DispatchQueue(label: "com.claudehustler.ratelimiter", attributes: .concurrent)
    
    func shouldAllowRequest(for key: String, limit: Int = 10, window: TimeInterval = 60) -> Bool {
        queue.sync(flags: .barrier) {
            let now = Date()
            let windowStart = now.addingTimeInterval(-window)
            
            // Clean old entries
            requestCounts[key] = requestCounts[key]?.filter { $0 > windowStart } ?? []
            
            // Check if under limit
            let currentCount = requestCounts[key]?.count ?? 0
            if currentCount < limit {
                requestCounts[key]?.append(now)
                return true
            }
            
            return false
        }
    }
    
    func resetLimit(for key: String) {
        queue.async(flags: .barrier) {
            self.requestCounts[key] = []
        }
    }
}
