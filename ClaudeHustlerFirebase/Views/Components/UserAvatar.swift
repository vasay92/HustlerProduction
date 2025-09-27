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
    
    private var initials: String {
        guard let name = userName, !name.isEmpty else { return "?" }
        let components = name.split(separator: " ")
        
        if components.count >= 2 {
            // First and last name initials
            return "\(components.first?.first ?? "?")\(components.last?.first ?? "?")"
        } else {
            // Just first letter
            return String(name.first ?? "?")
        }
    }
    
    var body: some View {
        ZStack {
            if let urlString = imageURL,
               !urlString.isEmpty,
               let url = URL(string: urlString) {
                // Use WebImage for caching
                WebImage(url: url)
                    .resizable()
                    .indicator(.activity)
                    .transition(.fade(duration: 0.3))
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Fallback to initials
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initials.uppercased())
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
                .frame(width: size, height: size)
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
}

// Preview
struct UserAvatar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            UserAvatar(imageURL: nil, userName: "John Doe", size: 60)
            UserAvatar(imageURL: nil, userName: "Jane", size: 60)
            UserAvatar(imageURL: nil, userName: nil, size: 60)
            UserAvatar(
                imageURL: nil,
                userName: "Test User",
                size: 60,
                showBorder: true,
                borderColor: .blue
            )
        }
        .padding()
    }
}
