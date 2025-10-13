// DynamicPostAnnotation.swift - Fixed version
// Path: ClaudeHustlerFirebase/Views/Home/DynamicPostAnnotation.swift

import SwiftUI
import MapKit

// MARK: - Dynamic Post Annotation
struct DynamicPostAnnotation: View {
    let post: ServicePost
    let isSelected: Bool
    let zoomLevel: Double
    let viewModel: HomeMapViewModel
    
    @State private var userRating: Double? = nil
    @State private var reviewCount: Int? = nil
    
    // Determine annotation style based on zoom level
    private var annotationStyle: AnnotationStyle {
        if isSelected {
            return .selectedBubble
        } else if zoomLevel < 0.02 {
            return .detailed
        } else if zoomLevel < 0.1 {
            return .compact
        } else {
            return .minimal
        }
    }
    
    enum AnnotationStyle {
        case minimal
        case compact
        case detailed
        case selectedBubble
    }
    
    var body: some View {
        // FIX: Use ZStack instead of Group, or use @ViewBuilder
        ZStack {
            switch annotationStyle {
            case .minimal:
                MinimalDotPin(post: post, isSelected: isSelected)
            case .compact:
                CompactTitlePin(post: post, isSelected: isSelected)
            case .detailed:
                DetailedBadgePin(
                    post: post,
                    isSelected: isSelected,
                    userRating: viewModel.getUserRating(for: post.userId),
                    reviewCount: viewModel.getUserReviewCount(for: post.userId)
                )
            case .selectedBubble:
                SelectedPostBubble(
                    post: post,
                    userRating: viewModel.getUserRating(for: post.userId),
                    reviewCount: viewModel.getUserReviewCount(for: post.userId)
                )
                .offset(y: -50)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

// MARK: - HomeMapViewModel Extension for Helper Methods
extension HomeMapViewModel {
    func getUserRating(for userId: String) -> Double? {
        return userRatings[userId]
    }
    
    func getUserReviewCount(for userId: String) -> Int? {
        return userReviewCounts[userId]
    }
}

// MARK: - Minimal Dot Pin
struct MinimalDotPin: View {
    let post: ServicePost
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: isSelected ? 18 : 14, height: isSelected ? 18 : 14)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            
            Circle()
                .fill(post.isRequest ? Color.orange : Color.blue)
                .frame(width: isSelected ? 14 : 10, height: isSelected ? 14 : 10)
        }
        .scaleEffect(isSelected ? 1.3 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Compact Title Pin
struct CompactTitlePin: View {
    let post: ServicePost
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            // Dot
            MinimalDotPin(post: post, isSelected: false)
            
            // Title
            Text(post.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: 70)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white)
                .cornerRadius(4)
                .shadow(color: .black.opacity(0.1), radius: 2)
        }
    }
}

// MARK: - Detailed Badge Pin
struct DetailedBadgePin: View {
    let post: ServicePost
    let isSelected: Bool
    let userRating: Double?
    let reviewCount: Int?
    
    var body: some View {
        HStack(spacing: 6) {
            // Colored indicator
            Circle()
                .fill(post.isRequest ? Color.orange : Color.blue)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 1) {
                // Title
                Text(post.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Rating or price
                HStack(spacing: 4) {
                    if let rating = userRating, rating > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let price = post.price {
                        Text("$\(Int(price))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(post.isRequest ? .orange : .blue)
                    }
                }
                
                // First tag
                if let firstTag = post.tags.first {
                    Text(firstTag)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(.systemGray6))
                        .cornerRadius(3)
                }
            }
            .padding(6)
            .background(Color.white)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.08), radius: 3)
        }
        .frame(maxWidth: 140)
    }
}

// MARK: - Selected Post Bubble
struct SelectedPostBubble: View {
    let post: ServicePost
    let userRating: Double?
    let reviewCount: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(post.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Close hint
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.gray.opacity(0.7))
            }
            
            // Description
            if !post.description.isEmpty {
                Text(post.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Info Row
            HStack {
                // Type badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(post.isRequest ? Color.orange : Color.blue)
                        .frame(width: 6, height: 6)
                    Text(post.isRequest ? "Request" : "Offer")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(post.isRequest ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                .foregroundColor(post.isRequest ? .orange : .blue)
                .cornerRadius(10)
                
                Spacer()
                
                // Rating
                if let rating = userRating, rating > 0 {
                    HStack(spacing: 4) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < Int(rating) ? "star.fill" : "star")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                        }
                        if let count = reviewCount {
                            Text("(\(count))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Price
            if let price = post.price {
                HStack {
                    Text("$\(Int(price))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(post.isRequest ? .orange : .blue)
                    
                    Text(post.isRequest ? "budget" : "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Tap for details")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(10)
        .frame(width: 200)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.12), radius: 6)
        
        // Pointer triangle is placed outside the VStack
        .overlay(
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundColor(.white)
                .offset(y: -1),
            alignment: .bottom
        )
    }
}
