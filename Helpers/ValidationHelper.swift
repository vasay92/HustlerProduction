
// ValidationHelper.swift
// Path: ClaudeHustlerFirebase/Helpers/ValidationHelper.swift

import SwiftUI

// MARK: - Validation Rules (matching Firestore rules)
struct ValidationRules {
    // Post Validation
    static let postTitleMin = 3
    static let postTitleMax = 100
    static let postDescriptionMin = 10
    static let postDescriptionMax = 1000
    static let postPriceMin = 0.0
    static let postPriceMax = 100000.0
    
    // Review Validation
    static let reviewTextMin = 10
    static let reviewTextMax = 500
    static let reviewRatingMin = 1
    static let reviewRatingMax = 5
    
    // Comment Validation
    static let commentTextMin = 1
    static let commentTextMax = 500
    
    // Reel Validation
    static let reelTitleMin = 1
    static let reelTitleMax = 200
    
    // Message Validation
    static let messageTextMin = 1
    static let messageTextMax = 1000
    
    // User Profile Validation
    static let userNameMin = 2
    static let userNameMax = 50
    static let userBioMax = 500
    
    // Status (Story) Validation
    static let statusCaptionMax = 200
}

// MARK: - Validation Helper
class ValidationHelper {
    
    // MARK: - Post Validation
    static func validatePostTitle(_ title: String) -> (isValid: Bool, message: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return (false, "Title is required")
        }
        
        if trimmed.count < ValidationRules.postTitleMin {
            return (false, "Title must be at least \(ValidationRules.postTitleMin) characters")
        }
        
        if trimmed.count > ValidationRules.postTitleMax {
            return (false, "Title must be less than \(ValidationRules.postTitleMax) characters")
        }
        
        return (true, "")
    }
    
    static func validatePostDescription(_ description: String) -> (isValid: Bool, message: String) {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return (false, "Description is required")
        }
        
        if trimmed.count < ValidationRules.postDescriptionMin {
            return (false, "Description must be at least \(ValidationRules.postDescriptionMin) characters")
        }
        
        if trimmed.count > ValidationRules.postDescriptionMax {
            return (false, "Description must be less than \(ValidationRules.postDescriptionMax) characters")
        }
        
        return (true, "")
    }
    
    static func validatePostPrice(_ priceString: String) -> (isValid: Bool, price: Double?, message: String) {
        // Price is optional
        if priceString.isEmpty {
            return (true, nil, "")
        }
        
        guard let price = Double(priceString) else {
            return (false, nil, "Please enter a valid number")
        }
        
        if price < ValidationRules.postPriceMin {
            return (false, nil, "Price cannot be negative")
        }
        
        if price > ValidationRules.postPriceMax {
            return (false, nil, "Price cannot exceed $\(Int(ValidationRules.postPriceMax))")
        }
        
        return (true, price, "")
    }
    
    // MARK: - Review Validation
    static func validateReviewText(_ text: String) -> (isValid: Bool, message: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return (false, "Review text is required")
        }
        
        if trimmed.count < ValidationRules.reviewTextMin {
            return (false, "Review must be at least \(ValidationRules.reviewTextMin) characters")
        }
        
        if trimmed.count > ValidationRules.reviewTextMax {
            return (false, "Review must be less than \(ValidationRules.reviewTextMax) characters")
        }
        
        return (true, "")
    }
    
    static func validateReviewRating(_ rating: Int) -> (isValid: Bool, message: String) {
        if rating < ValidationRules.reviewRatingMin || rating > ValidationRules.reviewRatingMax {
            return (false, "Rating must be between 1 and 5 stars")
        }
        return (true, "")
    }
    
    // MARK: - Comment Validation
    static func validateComment(_ text: String) -> (isValid: Bool, message: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return (false, "Comment cannot be empty")
        }
        
        if trimmed.count > ValidationRules.commentTextMax {
            return (false, "Comment must be less than \(ValidationRules.commentTextMax) characters")
        }
        
        return (true, "")
    }
    
    // MARK: - Message Validation
    static func validateMessage(_ text: String) -> (isValid: Bool, message: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return (false, "Message cannot be empty")
        }
        
        if trimmed.count > ValidationRules.messageTextMax {
            return (false, "Message must be less than \(ValidationRules.messageTextMax) characters")
        }
        
        return (true, "")
    }
    
    // MARK: - User Profile Validation
    static func validateUserName(_ name: String) -> (isValid: Bool, message: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return (false, "Name is required")
        }
        
        if trimmed.count < ValidationRules.userNameMin {
            return (false, "Name must be at least \(ValidationRules.userNameMin) characters")
        }
        
        if trimmed.count > ValidationRules.userNameMax {
            return (false, "Name must be less than \(ValidationRules.userNameMax) characters")
        }
        
        // Check for inappropriate content
        let inappropriateWords = ["admin", "administrator", "root", "test"]
        for word in inappropriateWords {
            if trimmed.lowercased().contains(word) {
                return (false, "Name contains inappropriate content")
            }
        }
        
        return (true, "")
    }
    
    static func validateUserBio(_ bio: String) -> (isValid: Bool, message: String) {
        if bio.count > ValidationRules.userBioMax {
            return (false, "Bio must be less than \(ValidationRules.userBioMax) characters")
        }
        return (true, "")
    }
    
    // MARK: - Reel Validation
    static func validateReelTitle(_ title: String) -> (isValid: Bool, message: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return (false, "Title is required")
        }
        
        if trimmed.count > ValidationRules.reelTitleMax {
            return (false, "Title must be less than \(ValidationRules.reelTitleMax) characters")
        }
        
        return (true, "")
    }
}

// MARK: - Validation View Modifiers
struct ValidationModifier: ViewModifier {
    let validation: (isValid: Bool, message: String)
    @Binding var showError: Bool
    
    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            
            if showError && !validation.isValid {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(validation.message)
                        .font(.caption)
                }
                .foregroundColor(.red)
                .transition(.opacity)
            }
        }
    }
}

extension View {
    func withValidation(_ validation: (isValid: Bool, message: String), showError: Binding<Bool>) -> some View {
        self.modifier(ValidationModifier(validation: validation, showError: showError))
    }
}

// MARK: - Character Counter View
struct CharacterCounterView: View {
    let current: Int
    let min: Int?
    let max: Int
    
    private var textColor: Color {
        if let min = min, current < min {
            return .orange
        } else if current > max {
            return .red
        } else if current > Int(Double(max) * 0.9) { // Within 90% of max
            return .orange
        } else {
            return .secondary
        }
    }
    
    private var countText: String {
        if let min = min, current < min {
            return "\(current)/\(min) min"
        } else {
            return "\(current)/\(max)"
        }
    }
    
    var body: some View {
        Text(countText)
            .font(.caption)
            .foregroundColor(textColor)
    }
}

// MARK: - Requirement Hint View
struct RequirementHintView: View {
    let requirements: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(requirements, id: \.self) { requirement in
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(requirement)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}
