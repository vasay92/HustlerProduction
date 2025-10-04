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
    
    // Tag Validation
    static let minTags = 5
    static let maxTags = 10
    static let minTagLength = 3  // excluding #
    static let maxTagLength = 30 // excluding #
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
    
    // MARK: - Tag Validation
    static func validateTags(_ tags: [String]) -> (isValid: Bool, message: String) {
        // Check tag count
        if tags.count < ValidationRules.minTags {
            return (false, "Minimum \(ValidationRules.minTags) tags required")
        }
        
        if tags.count > ValidationRules.maxTags {
            return (false, "Maximum \(ValidationRules.maxTags) tags allowed")
        }
        
        // Validate each tag
        for tag in tags {
            let validation = validateSingleTag(tag)
            if !validation.isValid {
                return validation
            }
        }
        
        // Check for duplicates
        if Set(tags).count != tags.count {
            return (false, "Duplicate tags are not allowed")
        }
        
        return (true, "")
    }
    
    static func validateSingleTag(_ tag: String) -> (isValid: Bool, message: String) {
        // Must start with #
        if !tag.hasPrefix("#") {
            return (false, "Tags must start with #")
        }
        
        // Get tag without #
        let tagContent = tag.replacingOccurrences(of: "#", with: "")
        
        // Check if empty after removing #
        if tagContent.isEmpty {
            return (false, "Tag cannot be just #")
        }
        
        // Check length
        if tagContent.count < ValidationRules.minTagLength {
            return (false, "Tags must be at least \(ValidationRules.minTagLength) characters")
        }
        
        if tagContent.count > ValidationRules.maxTagLength {
            return (false, "Tags must be less than \(ValidationRules.maxTagLength) characters")
        }
        
        // Check for valid characters (alphanumeric and hyphens only)
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        if tagContent.rangeOfCharacter(from: allowedCharacters.inverted) != nil {
            return (false, "Tags can only contain letters, numbers, and hyphens")
        }
        
        // Check it doesn't start or end with hyphen
        if tagContent.hasPrefix("-") || tagContent.hasSuffix("-") {
            return (false, "Tags cannot start or end with a hyphen")
        }
        
        // Check for multiple consecutive hyphens
        if tagContent.contains("--") {
            return (false, "Tags cannot have multiple consecutive hyphens")
        }
        
        return (true, "")
    }
    
    static func formatTag(_ input: String) -> String {
        var formatted = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add # if not present
        if !formatted.hasPrefix("#") {
            formatted = "#" + formatted
        }
        
        // Replace spaces with hyphens
        formatted = formatted.replacingOccurrences(of: " ", with: "-")
        
        // Remove any character that's not alphanumeric, # or -
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "#-"))
        formatted = formatted.components(separatedBy: allowed.inverted).joined()
        
        // Remove multiple consecutive hyphens
        while formatted.contains("--") {
            formatted = formatted.replacingOccurrences(of: "--", with: "-")
        }
        
        // Remove trailing hyphen if exists
        if formatted.hasSuffix("-") && formatted.count > 1 {
            formatted = String(formatted.dropLast())
        }
        
        return formatted
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

// MARK: - Tag Counter View (NEW)
struct TagCounterView: View {
    let current: Int
    let min: Int = ValidationRules.minTags
    let max: Int = ValidationRules.maxTags
    
    private var textColor: Color {
        if current < min {
            return .orange
        } else if current > max {
            return .red
        } else {
            return .secondary
        }
    }
    
    private var countText: String {
        if current < min {
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
