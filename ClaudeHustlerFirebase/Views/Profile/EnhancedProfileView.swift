// EnhancedProfileView.swift
// Path: ClaudeHustlerFirebase/Views/Profile/EnhancedProfileView.swift

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct EnhancedProfileView: View {
    let userId: String
    
    @StateObject private var viewModel: ProfileViewModel
    @StateObject private var firebase = FirebaseService.shared
    @Environment(\.dismiss) var dismiss
    
    // UI States
    @State private var selectedTab = 0
    @State private var showingEditProfile = false
    @State private var showingFollowers = false
    @State private var showingFollowing = false
    @State private var showingSettings = false
    @State private var showingCreateCard = false
    @State private var showingReviewForm = false
    @State private var showingMessageView = false
    
    init(userId: String) {
        self.userId = userId
        self._viewModel = StateObject(wrappedValue: ProfileViewModel(userId: userId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        statsSection
                        actionButtons
                        
                        // Tab selection - REORDERED: Portfolio, Services, Saved, Reviews
                        Picker("Profile Section", selection: $selectedTab) {
                            Text("Portfolio").tag(0)
                            Text("Services").tag(1)
                            if viewModel.isOwnProfile {
                                Text("Saved").tag(2)
                            }
                            Text("Reviews").tag(3)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        
                        // Tab content
                        tabContent
                    }
                }
                
                // Floating Add Portfolio Button (only for own profile)
                if viewModel.isOwnProfile && selectedTab == 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { showingCreateCard = true }) {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                    .shadow(radius: 4)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
                
                if viewModel.isLoadingProfile {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Loading...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 4)
                }
            }
            .navigationBarHidden(true)
            .task {
                await viewModel.loadProfileData()
            }
            .onDisappear {
                viewModel.cleanupListeners()
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
                    .onDisappear {
                        Task {
                            await viewModel.refreshProfileData()
                        }
                    }
            }
            .sheet(isPresented: $showingFollowers) {
                FollowersListView(userId: userId)
            }
            .sheet(isPresented: $showingFollowing) {
                FollowingListView(userId: userId)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingCreateCard) {
                CreatePortfolioCardView()
                    .onDisappear {
                        Task {
                            await viewModel.loadPortfolioCards()
                        }
                    }
            }
            .sheet(isPresented: $showingReviewForm) {
                CreateReviewView(userId: userId)
                    .onDisappear {
                        Task {
                            await viewModel.loadProfileData()
                        }
                    }
            }
            .fullScreenCover(isPresented: $showingMessageView) {
                ChatView(
                    recipientId: userId,
                    isFromContentView: false
                )
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Settings button for own profile
            if viewModel.isOwnProfile {
                HStack {
                    Spacer()
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal)
            }
            
            // Profile image with Edit overlay for own profile
            ZStack(alignment: .bottomTrailing) {
                ProfileImageView(imageURL: viewModel.user?.profileImageURL, size: 100)
                
                if viewModel.isOwnProfile {
                    Button(action: { showingEditProfile = true }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                            .background(Circle().fill(Color.white))
                            .clipShape(Circle())
                    }
                    .offset(x: -5, y: -5)
                }
            }
            
            // Name (removed location)
            VStack(spacing: 4) {
                Text(viewModel.user?.name ?? "Loading...")
                    .font(.title)
                    .fontWeight(.bold)
            }
            
            // Bio
            if let bio = viewModel.user?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundColor(.secondary)
            }
            
            // Rating
            if let rating = viewModel.user?.rating,
               let reviewCount = viewModel.user?.reviewCount,
               reviewCount > 0 {
                Button(action: { selectedTab = 3 }) {
                    HStack(spacing: 4) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < Int(rating) ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                        Text("(\(reviewCount))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var statsSection: some View {
        HStack(spacing: 30) {
            // Posts - Clickable to navigate to Services tab
            Button(action: { selectedTab = 1 }) {
                VStack {
                    Text("\(viewModel.userPosts.count)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Posts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Followers
            Button(action: { showingFollowers = true }) {
                VStack {
                    Text("\(viewModel.user?.followers.count ?? 0)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Followers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Following
            Button(action: { showingFollowing = true }) {
                VStack {
                    Text("\(viewModel.user?.following.count ?? 0)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Following")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Reviews - Clickable to navigate to Reviews tab
            Button(action: { selectedTab = 3 }) {
                VStack {
                    Text("\(viewModel.reviews.count)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Reviews")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            if viewModel.isOwnProfile {
                // No Edit Profile button here anymore - moved to profile image
            } else {
                // Follow/Unfollow button
                Button(action: {
                    Task {
                        await viewModel.toggleFollow()
                    }
                }) {
                    Text(viewModel.isFollowing ? "Unfollow" : "Follow")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(viewModel.isFollowing ? Color(.systemGray5) : Color.blue)
                        .foregroundColor(viewModel.isFollowing ? .primary : .white)
                        .cornerRadius(8)
                }
                
                // Message button
                Button(action: { showingMessageView = true }) {
                    Label("Message", systemImage: "message.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
                
                // Review button
                Button(action: { showingReviewForm = true }) {
                    Image(systemName: "star.fill")
                        .font(.subheadline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundColor(.yellow)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            // Portfolio Tab - First tab now
            if viewModel.portfolioCards.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "No Portfolio Items",
                    message: viewModel.isOwnProfile ?
                        "Tap the + button to showcase your work" :
                        "No portfolio items to show"
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(viewModel.portfolioCards) { card in
                        PortfolioCardView(
                            card: card,
                            isOwner: viewModel.isOwnProfile,
                            profileViewModel: viewModel
                        )
                    }
                }
                .padding()
            }
            
        case 1:
            // Services Tab - Second tab now
            if viewModel.userPosts.isEmpty {
                EmptyStateView(
                    icon: "briefcase",
                    title: "No Services Yet",
                    message: viewModel.isOwnProfile ?
                        "Start offering or requesting services" :
                        "This user hasn't posted any services yet"
                )
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.userPosts) { post in
                        NavigationLink(destination: PostDetailView(post: post)) {
                            UserPostCard(post: post)
                        }
                    }
                }
                .padding()
            }
            
        case 2:
            // Saved Tab - Third tab (only for own profile)
            if viewModel.isOwnProfile {
                SavedItemsView(
                    savedPosts: viewModel.savedPosts,
                    savedReels: viewModel.savedReels
                )
                .padding()
            }
            
        case 3:
            // Reviews Tab - Fourth tab now
            if viewModel.reviews.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "No Reviews Yet",
                    message: viewModel.isOwnProfile ?
                        "Complete services to receive reviews" :
                        "No reviews for this user yet"
                )
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.reviews) { review in
                        ReviewCard(review: review, isProfileOwner: viewModel.isOwnProfile)
                    }
                }
                .padding()
            }
            
        default:
            EmptyView()
        }
    }
}

// MARK: - Supporting Views
// Note: ProfileImageView and EmptyStateView are imported from Components folder

struct UserPostCard: View {
    let post: ServicePost
    
    var body: some View {
        HStack(spacing: 12) {
            // Image or placeholder
            if !post.imageURLs.isEmpty, let firstImageURL = post.imageURLs.first {
                AsyncImage(url: URL(string: firstImageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipped()
                        .cornerRadius(10)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: 80, height: 80)
                        .cornerRadius(10)
                        .overlay(ProgressView())
                }
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: post.isRequest ?
                                [Color.orange.opacity(0.3), Color.red.opacity(0.3)] :
                                [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .cornerRadius(10)
                    .overlay(
                        Image(systemName: categoryIcon(for: post.category))
                            .foregroundColor(.white)
                            .font(.title2)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(post.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    if let price = post.price {
                        Text("$\(Int(price))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    Text(post.isRequest ? "REQUEST" : "OFFER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(post.isRequest ? .orange : .blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            (post.isRequest ? Color.orange : Color.blue).opacity(0.1)
                        )
                        .cornerRadius(4)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func categoryIcon(for category: ServiceCategory) -> String {
        switch category {
        case .cleaning: return "sparkles"
        case .tutoring: return "book.fill"
        case .delivery: return "shippingbox.fill"
        case .electrical: return "bolt.fill"
        case .plumbing: return "drop.fill"
        case .carpentry: return "hammer.fill"
        case .painting: return "paintbrush.fill"
        case .landscaping: return "leaf.fill"
        case .moving: return "box.truck.fill"
        case .technology: return "desktopcomputer"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

struct SavedItemsView: View {
    let savedPosts: [ServicePost]
    let savedReels: [Reel]
    @State private var selectedSegment = 0
    
    var body: some View {
        VStack {
            Picker("Saved Type", selection: $selectedSegment) {
                Text("Posts").tag(0)
                Text("Reels").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            if selectedSegment == 0 {
                // Saved Posts
                if savedPosts.isEmpty {
                    EmptyStateView(
                        icon: "bookmark",
                        title: "No Saved Posts",
                        message: "Posts you save will appear here"
                    )
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(savedPosts) { post in
                            NavigationLink(destination: PostDetailView(post: post)) {
                                SavedPostCard(post: post)
                            }
                        }
                    }
                }
            } else {
                // Saved Reels
                if savedReels.isEmpty {
                    EmptyStateView(
                        icon: "bookmark",
                        title: "No Saved Reels",
                        message: "Reels you save will appear here"
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2)
                    ], spacing: 2) {
                        ForEach(savedReels) { reel in
                            SavedReelThumbnail(reel: reel)
                        }
                    }
                }
            }
        }
    }
}
