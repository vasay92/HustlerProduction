// UserAvatar.swift
// Path: ClaudeHustlerFirebase/Views/Components/UserAvatar.swift
// A universal component for displaying user profile images with consistent fallbacks

import SwiftUI
import SDWebImageSwiftUI

struct UserAvatar: View {
    let imageURL: String?
    let userName: String?
    let size: CGFloat
    
    // Optional customization
    var fontSize: Font?
    var showBorder: Bool = false
    var borderColor: Color = .blue
    var borderWidth: CGFloat = 2
    var backgroundColor: Color = Color.gray.opacity(0.3)
    
    private var initials: String {
        guard let name = userName, !name.isEmpty else { return "?" }
        let components = name.split(separator: " ")
        
        if components.count >= 2 {
            // First and last name initials
            let first = components.first?.first ?? Character("?")
            let last = components.last?.first ?? Character("?")
            return "\(first)\(last)".uppercased()
        } else if let firstChar = name.first {
            // Just first letter
            return String(firstChar).uppercased()
        } else {
            return "?"
        }
    }
    
    private var gradientColors: [Color] {
        // Generate consistent colors based on username
        guard let name = userName, !name.isEmpty else {
            return [Color.gray, Color.gray.opacity(0.7)]
        }
        
        let hash = name.hashValue
        let hue = Double(abs(hash % 360)) / 360.0
        return [
            Color(hue: hue, saturation: 0.5, brightness: 0.8),
            Color(hue: hue, saturation: 0.7, brightness: 0.6)
        ]
    }
    
    var body: some View {
        ZStack {
            if let urlString = imageURL,
               !urlString.isEmpty,
               let url = URL(string: urlString) {
                // Use WebImage with correct syntax
                WebImage(url: url)
                    .onSuccess { image, data, cacheType in
                        // Image loaded successfully
                    }
                    .resizable()
                    .placeholder(content: {
                        // Loading placeholder
                        Circle()
                            .fill(LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .overlay(
                                Text(initials)
                                    .font(fontSize ?? .system(size: size * 0.4))
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            )
                    })
                    .animated() // This replaces .transition
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Fallback to initials with gradient
                Circle()
                    .fill(LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initials)
                            .font(fontSize ?? .system(size: size * 0.4))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    )
            }
        }
        .overlay(
            showBorder ?
            Circle()
                .stroke(borderColor, lineWidth: borderWidth)
                .frame(width: size + borderWidth, height: size + borderWidth)
            : nil
        )
    }
}

// Convenience initializers for common sizes
extension UserAvatar {
    // Tiny avatar (24px) - for replies, small lists
    static func tiny(imageURL: String?, userName: String?) -> UserAvatar {
        UserAvatar(imageURL: imageURL, userName: userName, size: 24)
    }
    
    // Small avatar (32px) - for comments, chat
    static func small(imageURL: String?, userName: String?) -> UserAvatar {
        UserAvatar(imageURL: imageURL, userName: userName, size: 32)
    }
    
    // Medium avatar (40px) - for posts, reviews
    static func medium(imageURL: String?, userName: String?) -> UserAvatar {
        UserAvatar(imageURL: imageURL, userName: userName, size: 40)
    }
    
    // Large avatar (60px) - for profile sections
    static func large(imageURL: String?, userName: String?) -> UserAvatar {
        UserAvatar(imageURL: imageURL, userName: userName, size: 60)
    }
    
    // Extra large avatar (100px) - for profile headers
    static func extraLarge(imageURL: String?, userName: String?) -> UserAvatar {
        UserAvatar(imageURL: imageURL, userName: userName, size: 100)
    }
    
    // Profile avatar (120px) - for main profile view
    static func profile(imageURL: String?, userName: String?) -> UserAvatar {
        UserAvatar(imageURL: imageURL, userName: userName, size: 120)
    }
}

// Preview
struct UserAvatar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Different sizes
            HStack(spacing: 20) {
                UserAvatar.tiny(imageURL: nil, userName: "John Doe")
                UserAvatar.small(imageURL: nil, userName: "Jane Smith")
                UserAvatar.medium(imageURL: nil, userName: "Bob")
                UserAvatar.large(imageURL: nil, userName: "Alice Wonder")
                UserAvatar.extraLarge(imageURL: nil, userName: "X")
            }
            
            // With borders
            HStack(spacing: 20) {
                UserAvatar(
                    imageURL: nil,
                    userName: "Test User",
                    size: 60,
                    showBorder: true,
                    borderColor: .blue
                )
                
                UserAvatar(
                    imageURL: nil,
                    userName: "Another User",
                    size: 60,
                    showBorder: true,
                    borderColor: .purple,
                    borderWidth: 3
                )
            }
            
            // Different initials
            HStack(spacing: 20) {
                UserAvatar(imageURL: nil, userName: "Single", size: 50)
                UserAvatar(imageURL: nil, userName: "", size: 50)
                UserAvatar(imageURL: nil, userName: nil, size: 50)
                UserAvatar(imageURL: nil, userName: "Three Name Person", size: 50)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}
