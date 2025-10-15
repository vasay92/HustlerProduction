// PostDetailView.swift
// Path: ClaudeHustlerFirebase/Views/Post/PostDetailView.swift
// UPDATED: Removed price, Active status, improved time format, added clickable photos and hashtags, rating display

import SwiftUI
import Firebase

struct PostDetailView: View {
    let post: ServicePost
    @StateObject private var firebase = FirebaseService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedPhotoIndex = 0
    @State private var isSaved = false
    @State private var showingShareSheet = false
    @State private var showingMessageView = false
    @State private var posterInfo: User?
    @State private var showingEditView = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showingFullScreenImage = false
    @State private var selectedImageIndex = 0
    @State private var showingImageViewer = false
    @State private var selectedImageURL: String?
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Photo Gallery
                    photoGallerySection
                    
                    // Post Details
                    postDetailsSection
                    
                    // User Info
                    userInfoSection
                    
                    // Action Buttons
                    actionButtonsSection
                    
                    Spacer(minLength: 20)
                }
            }
            
            // Loading overlay for deletion
            if isDeleting {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView("Deleting...")
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 5)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if post.userId == firebase.currentUser?.id {
                        Button(action: { showingEditView = true }) {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    
                    Button(action: { showingShareSheet = true }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .task {
            await loadPosterInfo()
            await checkSaveStatus()
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [shareContent()])
        }
        .sheet(isPresented: $showingEditView) {
            ServiceFormView(post: post)
        }
        .fullScreenCover(isPresented: $showingImageViewer) {
            if let imageURL = selectedImageURL,
               let index = post.imageURLs.firstIndex(of: imageURL) {
                ReviewImageViewer(
                    imageURLs: post.imageURLs,
                    selectedIndex: index
                )
            }
        }
        // FIX #2: ADD MESSAGE NAVIGATION
        .fullScreenCover(isPresented: $showingMessageView) {
            ChatView(
                recipientId: post.userId,  // Direct use - no if let needed
                contextType: .post,
                contextId: post.id,
                contextData: (
                    title: post.title,
                    image: post.imageURLs.first,
                    userId: post.userId
                ),
                isFromContentView: false
            )
        }
        .confirmationDialog("Delete Post?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await deletePost()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        
    }
    
    // MARK: - Photo Gallery Section with Clickable Images
    @ViewBuilder
    private var photoGallerySection: some View {
        if !post.imageURLs.isEmpty {
            VStack(spacing: 0) {
                // Main Image - Now Clickable
                TabView(selection: $selectedPhotoIndex) {
                    ForEach(Array(post.imageURLs.enumerated()), id: \.offset) { index, imageURL in
                        AsyncImage(url: URL(string: imageURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 350)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedImageIndex = index
                                        showingFullScreenImage = true
                                    }
                                    .tag(index)
                            case .failure(_):
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                                    .frame(maxHeight: 350)
                            case .empty:
                                ProgressView()
                                    .frame(maxHeight: 350)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }
                .frame(height: 350)
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                
                // Thumbnail Strip
                if post.imageURLs.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(post.imageURLs.enumerated()), id: \.offset) { index, imageURL in
                                AsyncImage(url: URL(string: imageURL)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 60, height: 60)
                                            .clipped()
                                            .cornerRadius(8)
                                    case .failure(_):
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 60, height: 60)
                                    case .empty:
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 60, height: 60)
                                            .overlay(ProgressView().scaleEffect(0.5))
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedPhotoIndex == index ? Color.blue : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture {
                                    withAnimation {
                                        selectedPhotoIndex = index
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 70)
                    .padding(.vertical, 10)
                }
            }
        } else {
            // Default image placeholder when no images
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            post.isRequest ? Color.orange.opacity(0.3) : Color.blue.opacity(0.3),
                            post.isRequest ? Color.red.opacity(0.3) : Color.purple.opacity(0.3)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 350)
                .overlay(
                    VStack(spacing: 10) {
                        Image(systemName: post.isRequest ? "hand.raised.fill" : "wrench.and.screwdriver.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.8))
                        Text(post.isRequest ? "Service Request" : "Service Offer")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                )
        }
    }
    
    // MARK: - Post Details Section (without price and Active status)
    @ViewBuilder
    private var postDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(post.title)
                .font(.title2)
                .fontWeight(.bold)
            
            // Location
            if let location = post.location, !location.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(location)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            // UPDATED: Clickable Tags
            if !post.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(post.tags, id: \.self) { tag in
                            Button(action: {
                                // Navigate to ServicesView with tag filter
                                dismiss() // Close the detail view first
                                
                                // Small delay to ensure dismiss completes
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    TabSelection.shared.selectedTab = 1 // Services tab
                                    // Add tag to filter in ServicesViewModel
                                    ServicesViewModel.shared?.addTagFilter(tag)
                                }
                            }) {
                                TagChip(
                                    tag: tag,
                                    isClickable: true
                                )
                            }
                        }
                    }
                }
            }
            
            // Request/Offer badge only
            HStack {
                if post.isRequest {
                    RequestBadge()
                }
                
                Spacer()
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Description
            Text("Description")
                .font(.headline)
            
            Text(post.description)
                .font(.body)
                .foregroundColor(.primary.opacity(0.9))
            
            // Posted Date with improved format
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("Posted \(timeAgo(from: post.createdAt))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - User Info Section with Rating Display
    @ViewBuilder
    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Posted by")
                .font(.headline)
            
            NavigationLink(destination: EnhancedProfileView(userId: post.userId)) {
                HStack(spacing: 12) {
                    // Profile Photo
                    UserProfileImage(imageURL: posterInfo?.profileImageURL, userName: posterInfo?.name ?? post.userName)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(posterInfo?.name ?? post.userName ?? "Unknown User")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // Rating Display
                        if let rating = posterInfo?.rating,
                           let reviewCount = posterInfo?.reviewCount,
                           reviewCount > 0 {
                            HStack(spacing: 4) {
                                ForEach(0..<5) { index in
                                    Image(systemName: index < Int(rating) ? "star.fill" : "star")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                Text(String(format: "%.1f", rating))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("(\(reviewCount))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("No reviews yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let memberSince = posterInfo?.createdAt {
                            Text("Member since \(yearFormatter.string(from: memberSince))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // FIX #1: CORRECT BUTTON ORDER
    // MARK: - Action Buttons Section
    @ViewBuilder
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            // MESSAGE FIRST (only if not own post)
            if post.userId != firebase.currentUser?.id {
                PostActionButton(
                    icon: "message",
                    title: "Message",
                    color: .green,
                    action: { showingMessageView = true }
                )
            }
            
            // SAVE SECOND
            PostActionButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                title: "Save",
                color: isSaved ? .orange : .gray,
                action: toggleSave
            )
            
            // SHARE THIRD
            PostActionButton(
                icon: "square.and.arrow.up",
                title: "Share",
                color: .blue,
                action: { showingShareSheet = true }
            )
        }
        .padding()
    }
    
    // MARK: - Helper Functions
    
    // Improved time format function
    private func timeAgo(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .weekOfYear, .day, .hour, .minute], from: date, to: now)
        
        if let year = components.year, year >= 2 {
            return "\(year) years ago"
        } else if let year = components.year, year >= 1 {
            return "1 year ago"
        } else if let month = components.month, month >= 2 {
            return "\(month) months ago"
        } else if let month = components.month, month >= 1 {
            return "1 month ago"
        } else if let week = components.weekOfYear, week >= 2 {
            return "\(week) weeks ago"
        } else if let week = components.weekOfYear, week >= 1 {
            return "1 week ago"
        } else if let day = components.day, day >= 2 {
            return "\(day) days ago"
        } else if let day = components.day, day >= 1 {
            return "1 day ago"
        } else if let hour = components.hour, hour >= 2 {
            return "\(hour) hours ago"
        } else if let hour = components.hour, hour >= 1 {
            return "1 hour ago"
        } else if let minute = components.minute, minute >= 2 {
            return "\(minute) minutes ago"
        } else if let minute = components.minute, minute >= 1 {
            return "1 minute ago"
        } else {
            return "just now"
        }
    }
    
    private func shareContent() -> String {
        var content = "\(post.title)\n\n"
        content += "\(post.description)\n\n"
        
        if !post.tags.isEmpty {
            content += "Tags: \(post.tags.joined(separator: " "))\n"
        }
        
        if let location = post.location {
            content += "Location: \(location)\n"
        }
        
        return content
    }
    
    private func loadPosterInfo() async {
        do {
            let document = try await Firestore.firestore()
                .collection("users")
                .document(post.userId)
                .getDocument()
            
            if document.exists {
                posterInfo = try? document.data(as: User.self)
                posterInfo?.id = document.documentID
            }
        } catch {
            print("Error loading poster info: \(error)")
        }
    }
    
    private func checkSaveStatus() async {
        if let postId = post.id {
            isSaved = await SavedItemsRepository.shared.isItemSaved(
                itemId: postId,
                type: .post
            )
        }
    }
    
    private func toggleSave() {
        guard let postId = post.id else { return }
        
        Task {
            do {
                isSaved = try await SavedItemsRepository.shared.toggleSave(
                    itemId: postId,
                    type: .post
                )
            } catch {
                print("Error toggling save: \(error)")
            }
        }
    }
    
    private func deletePost() async {
        guard let postId = post.id else { return }
        
        isDeleting = true
        
        do {
            try await PostRepository.shared.delete(postId)
            dismiss()
        } catch {
            print("Error deleting post: \(error)")
            isDeleting = false
        }
    }
    
    private var yearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }
}

// MARK: - Supporting Views

struct RequestBadge: View {
    var body: some View {
        Text("REQUEST")
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.1))
            .foregroundColor(.orange)
            .cornerRadius(12)
    }
}

struct UserProfileImage: View {
    let imageURL: String?
    let userName: String?
    
    var body: some View {
        if let imageURL = imageURL {
            AsyncImage(url: URL(string: imageURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 60, height: 60)
                .overlay(
                    Text(String(userName?.first ?? "U"))
                        .font(.title3)
                        .foregroundColor(.white)
                )
        }
    }
}

// RENAMED FROM ActionButton TO PostActionButton
struct PostActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct PostDetailStarRatingView: View {
    let rating: Double
    let maxRating: Int
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...maxRating, id: \.self) { index in
                Image(systemName: index <= Int(rating) ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Sheet Views

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
