// EnhancedProfileView.swift - Fixed version without duplicates
// Path: ClaudeHustlerFirebase/Views/Profile/EnhancedProfileView.swift

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct EnhancedProfileView: View {
    let userId: String
    
    @StateObject private var viewModel: ProfileViewModel
    @StateObject private var firebase = FirebaseService.shared // Only for current user info
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
                        
                        // Tab selection
                        Picker("Profile Section", selection: $selectedTab) {
                            Text("Services").tag(0)
                            Text("Reviews").tag(1)
                            Text("Portfolio").tag(2)
                            if viewModel.isOwnProfile {
                                Text("Saved").tag(3)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        
                        // Tab content
                        tabContent
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
            
            // Profile image
            ProfileImageView(imageURL: viewModel.user?.profileImageURL, size: 100)
            
            // Name and location
            VStack(spacing: 4) {
                Text(viewModel.user?.name ?? "Loading...")
                    .font(.title)
                    .fontWeight(.bold)
                
                if let location = viewModel.user?.location, !location.isEmpty {
                    Label(location, systemImage: "location.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
    
    @ViewBuilder
    private var statsSection: some View {
        HStack(spacing: 30) {
            // Posts
            VStack {
                Text("\(viewModel.userPosts.count)")
                    .font(.headline)
                Text("Posts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Followers
            Button(action: { showingFollowers = true }) {
                VStack {
                    Text("\(viewModel.user?.followers.count ?? 0)")
                        .font(.headline)
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
                    Text("Following")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Reviews
            VStack {
                Text("\(viewModel.reviews.count)")
                    .font(.headline)
                Text("Reviews")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                // Edit Profile button
                Button(action: { showingEditProfile = true }) {
                    Label("Edit Profile", systemImage: "pencil")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                // Add Portfolio button
                Button(action: { showingCreateCard = true }) {
                    Label("Add Portfolio", systemImage: "plus.square.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
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
            // Services Tab
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
            
        case 1:
            // Reviews Tab - Using correct parameter name
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
            
        case 2:
            // Portfolio Tab - Using existing PortfolioCardView from ProfileSupportingViews
            if viewModel.portfolioCards.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "No Portfolio Items",
                    message: viewModel.isOwnProfile ?
                        "Add your work to showcase your skills" :
                        "No portfolio items to show"
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(viewModel.portfolioCards) { card in
                        // Using the existing PortfolioCardView from ProfileSupportingViews.swift
                        PortfolioCardView(card: card, isOwner: viewModel.isOwnProfile)
                    }
                }
                .padding()
            }
            
        case 3:
            // Saved Tab (only for own profile)
            if viewModel.isOwnProfile {
                SavedItemsView(
                    savedPosts: viewModel.savedPosts,
                    savedReels: viewModel.savedReels
                )
                .padding()
            }
            
        default:
            EmptyView()
        }
    }
}

// MARK: - Supporting Views (only those not in ProfileSupportingViews.swift)

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
                        Image(systemName: "briefcase.fill")
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(post.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Request/Offer Badge
                    Text(post.isRequest ? "REQUEST" : "OFFER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(post.isRequest ? Color.orange : Color.blue)
                        .cornerRadius(4)
                }
                
                Text(post.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    if let price = post.price {
                        Text("$\(Int(price))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    Text(post.category.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray6))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

struct SavedItemsView: View {
    let savedPosts: [ServicePost]
    let savedReels: [Reel]
    
    @State private var selectedType = 0
    
    var body: some View {
        VStack {
            Picker("Saved Type", selection: $selectedType) {
                Text("Posts").tag(0)
                Text("Reels").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            if selectedType == 0 {
                if savedPosts.isEmpty {
                    EmptyStateView(
                        icon: "bookmark",
                        title: "No Saved Posts",
                        message: "Save posts to view them here"
                    )
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(savedPosts) { post in
                            NavigationLink(destination: PostDetailView(post: post)) {
                                UserPostCard(post: post)
                            }
                        }
                    }
                }
            } else {
                if savedReels.isEmpty {
                    EmptyStateView(
                        icon: "bookmark",
                        title: "No Saved Reels",
                        message: "Save reels to view them here"
                    )
                    .padding(.top, 40)
                } else {
                    // Saved reels grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(savedReels) { reel in
                            SavedReelCard(reel: reel)
                        }
                    }
                }
            }
        }
    }
}

struct SavedReelCard: View {
    let reel: Reel
    
    var body: some View {
        NavigationLink(destination: EmptyView()) { // Replace with actual reel viewer
            AsyncImage(url: URL(string: reel.thumbnailURL ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipped()
                    .cornerRadius(12)
            } placeholder: {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 200)
                    .cornerRadius(12)
                    .overlay(
                        Image(systemName: "play.rectangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                    )
            }
            .overlay(
                VStack {
                    Spacer()
                    HStack {
                        Text(reel.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(8)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.7), Color.clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                }
            )
        }
    }
}
