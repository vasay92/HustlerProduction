

// CachedAsyncImage.swift
// Path: ClaudeHustlerFirebase/Views/Components/CachedAsyncImage.swift

import SwiftUI
import SDWebImageSwiftUI

struct CachedAsyncImage: View {
    let url: String?
    let placeholder: AnyView
    
    init(url: String?, @ViewBuilder placeholder: () -> some View = { ProgressView() }) {
        self.url = url
        self.placeholder = AnyView(placeholder())
    }
    
    var body: some View {
        if let urlString = url, let imageURL = URL(string: urlString) {
            WebImage(url: imageURL)
                .resizable()
                .indicator(.activity)
                .transition(.fade(duration: 0.3))
                .scaledToFill()
        } else {
            placeholder
        }
    }
}

// Convenience view for profile images
struct ProfileImageView: View {
    let imageURL: String?
    let size: CGFloat
    
    var body: some View {
        CachedAsyncImage(url: imageURL) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: size))
                .foregroundColor(.gray)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
