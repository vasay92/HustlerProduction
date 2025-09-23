// ContentPreviewCard.swift
// Path: ClaudeHustlerFirebase/Views/Messages/ContentPreviewCard.swift

import SwiftUI
import FirebaseFirestore

// MARK: - PostDetailView Wrapper with Close Button
struct PostDetailViewWithClose: View {
    let post: ServicePost
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        // Just show PostDetailView without any additional buttons
        PostDetailView(post: post)
            .onDisappear {
                // This ensures the view can still be dismissed programmatically if needed
            }
    }
}

// MARK: - Main ContentPreviewCard
struct ContentPreviewCard: View {
    let message: Message
    let isCurrentUser: Bool
    var onTap: (() -> Void)?
    
    @State private var contentPost: ServicePost?
    @State private var contentReel: Reel?
    @State private var contentStatus: Status?
    @State private var isLoading = true
    @State private var showingContent = false
    @State private var loadError = false
    @State private var contentExists = true
    @State private var isChecking = false
    @StateObject private var firebase = FirebaseService.shared
    
    private var contentTitle: String {
        message.contextTitle ?? "Shared Content"
    }
    
    private var contentImage: String? {
        message.contextImage
    }
    
    private var contextIcon: String {
        switch message.contextType {
        case .post:
            return "briefcase.fill"
        case .reel:
            return "play.rectangle.fill"
        case .status:
            return "circle.dashed"
        case .none:
            return "square.fill"
        }
    }
    
    private var contentTypeColor: Color {
        switch message.contextType {
        case .post:
            return .blue
        case .reel:
            return .purple
        case .status:
            return .orange
        case .none:
            return .gray
        }
    }
    
    private var contextTypeLabel: String {
        switch message.contextType {
        case .post:
            return "Service Post"
        case .reel:
            return "Reel"
        case .status:
            return "Status"
        case .none:
            return "Content"
        }
    }
    
    var body: some View {
        Button(action: {
            if contentExists && !isLoading && !loadError {
                onTap?()
            }
        }) {
            HStack(spacing: 8) {
                // Check if content doesn't exist
                if !contentExists {
                    // Content deleted/unavailable UI
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .frame(width: 50, height: 50)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(contextTypeLabel) Unavailable")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                        
                        Text("This content is no longer available")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                } else if isChecking || isLoading {
                    // Loading state
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 50, height: 50)
                    
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                } else {
                    // Normal preview with content available
                    // Thumbnail
                    if let imageURL = contentImage {
                        AsyncImage(url: URL(string: imageURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 50)
                                    .clipped()
                                    .cornerRadius(8)
                            case .failure(_):
                                placeholderImage
                            case .empty:
                                placeholderImage
                                    .overlay(ProgressView().scaleEffect(0.5))
                            @unknown default:
                                placeholderImage
                            }
                        }
                    } else {
                        placeholderImage
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contextTypeLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(contentTitle)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .foregroundColor(isCurrentUser ? .white : .primary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(
                !contentExists ?
                Color.orange.opacity(0.1) :
                (isCurrentUser ? Color.blue.opacity(0.8) : Color(.systemGray6))
            )
            .cornerRadius(12)
            .opacity(isLoading ? 0.6 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!contentExists || isLoading || loadError)
        .task {
            await checkContentAvailability()
        }
        .fullScreenCover(isPresented: $showingContent) {
            contentDetailView
        }
    }
    
    @ViewBuilder
    private var placeholderImage: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [contentTypeColor.opacity(0.3), contentTypeColor.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 50, height: 50)
            .cornerRadius(8)
            .overlay(
                Image(systemName: contextIcon)
                    .font(.title3)
                    .foregroundColor(.white)
            )
    }
    
    @ViewBuilder
    private var contentDetailView: some View {
        Group {
            switch message.contextType {
            case .post:
                if let post = contentPost {
                    // Use the wrapper with close button for posts
                    PostDetailViewWithClose(post: post)
                } else {
                    ContentNotFoundView()
                }
            case .reel:
                if let reel = contentReel {
                    // ReelViewerView is already defined in ReelsView.swift
                    NavigationView {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                // Reel thumbnail or video
                                AsyncImage(url: URL(string: reel.thumbnailURL ?? reel.videoURL)) { image in
                                    image
                                        .resizable()
                                        .scaledToFit()
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 400)
                                        .overlay(ProgressView())
                                }
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(reel.title)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    Text(reel.description)
                                        .font(.body)
                                    
                                    if !reel.hashtags.isEmpty {
                                        Text(reel.hashtags.map { "#\($0)" }.joined(separator: " "))
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    HStack {
                                        Label("\(reel.likes.count)", systemImage: "heart.fill")
                                            .foregroundColor(.red)
                                        
                                        Label("\(reel.comments)", systemImage: "bubble.left.fill")
                                            .foregroundColor(.blue)
                                        
                                        Label("\(reel.views)", systemImage: "eye.fill")
                                            .foregroundColor(.gray)
                                    }
                                    .font(.caption)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .navigationTitle("Reel")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Close") {
                                    showingContent = false
                                }
                            }
                        }
                    }
                } else {
                    ContentNotFoundView()
                }
            case .status:
                if let status = contentStatus {
                    StatusViewerView(status: status)
                } else {
                    ContentNotFoundView()
                }
            case .none:
                ContentNotFoundView()
            }
        }
    }
    
    @MainActor
    private func checkContentAvailability() async {
        guard let contextId = message.contextId,
              let contextType = message.contextType else {
            contentExists = false
            isLoading = false
            return
        }
        
        isChecking = true
        isLoading = true
        loadError = false
        
        do {
            switch contextType {
            case .post:
                let post = try await PostRepository.shared.fetchById(contextId)
                contentExists = (post != nil)
                contentPost = post
            case .reel:
                let reel = try await ReelRepository.shared.fetchById(contextId)
                contentExists = (reel != nil)
                contentReel = reel
            case .status:
                let status = try await StatusRepository.shared.fetchById(contextId)
                contentExists = (status != nil)
                contentStatus = status
            }
        } catch {
            print("Error checking content availability: \(error)")
            contentExists = false
            loadError = true
        }
        
        isChecking = false
        isLoading = false
    }
    
    @MainActor
    private func loadContent() async {
        // This function is kept for backward compatibility but now
        // checkContentAvailability handles the loading
        await checkContentAvailability()
    }
}

// MARK: - Content Not Found View
struct ContentNotFoundView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text("Content Not Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("This content may have been deleted or is no longer available.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button(action: { dismiss() }) {
                    Text("Return to Chat")
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Content Unavailable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
    }
}
