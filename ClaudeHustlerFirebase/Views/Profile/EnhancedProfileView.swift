// EnhancedProfileView.swift
// Path: ClaudeHustlerFirebase/Views/Profile/EnhancedProfileView.swift

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct EnhancedProfileView: View {
    let userId: String
    let highlightReviewId: String?  // ADDED - optional parameter for highlighting reviews
    
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
    @State private var showingMessageView = false
    @State private var selectedStarFilter: Int? = nil
    @State private var showAllReviews = false
    @State private var showingReviewForm = false
    @State private var hasScrolledToReview = false  // ADDED
    
    // UPDATED init to accept optional highlightReviewId
    init(userId: String, highlightReviewId: String? = nil) {
        self.userId = userId
        self.highlightReviewId = highlightReviewId
        self._viewModel = StateObject(wrappedValue: ProfileViewModel(userId: userId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                ScrollViewReader { scrollProxy in  // ADDED - wrap in ScrollViewReader
                    ScrollView {
                        VStack(spacing: 20) {
                            headerSection
                            statsSection
                            actionButtons
                            
                            // Tab selection - REORDERED: Portfolio, Services, Saved (if own), Reviews
                            Picker("Profile Section", selection: $selectedTab) {
                                Text("Portfolio").tag(0)
                                Text("Services").tag(1)
                                if viewModel.isOwnProfile {
                                    Text("Saved").tag(2)
                                }
                                Text("Reviews").tag(viewModel.isOwnProfile ? 3 : 2)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .padding(.horizontal)
                            
                            tabContent(scrollProxy: scrollProxy)  // ADDED parameter
                        }
                    }
                    .onAppear {
                        // ADDED - Scroll to review after delay
                        if let reviewId = highlightReviewId, !hasScrolledToReview {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    scrollProxy.scrollTo(reviewId, anchor: .center)
                                }
                                hasScrolledToReview = true
                            }
                        }
                    }
                }
                
                // Floating add button for portfolio (own profile only)
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
                            .padding()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .onAppear {
                Task {
                    await viewModel.loadProfileData()
                    
                    // ADDED - Auto-switch to Reviews tab if highlighting
                    if highlightReviewId != nil {
                        selectedTab = viewModel.isOwnProfile ? 3 : 2
                        showAllReviews = true  // Show all reviews to ensure the highlighted one is visible
                    }
                }
            }
            .refreshable {
                await viewModel.refreshProfileData()
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingFollowers) {
                FollowersListView(userId: userId)
            }
            .sheet(isPresented: $showingFollowing) {
                FollowingListView(userId: userId)
            }
            .sheet(isPresented: $showingCreateCard) {
                CreatePortfolioCardView()
                    .onDisappear {
                        Task { await viewModel.loadPortfolioCards() }
                    }
            }
            .sheet(isPresented: $showingReviewForm) {
                CreateReviewView(userId: userId)
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
            
            // Name
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
                Button(action: { selectedTab = viewModel.isOwnProfile ? 3 : 2 }) {
                    HStack(spacing: 4) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < Int(rating) ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                        Text(String(format: "%.1f", rating))
                            .font(.caption)
                            .fontWeight(.medium)
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
        HStack(spacing: 20) {
            // Followers - Clickable
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
            
            // Following - Clickable
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
            Button(action: { selectedTab = viewModel.isOwnProfile ? 3 : 2 }) {
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
            }
        }
        .padding(.horizontal)
    }
    
    // UPDATED - Added scrollProxy parameter
    @ViewBuilder
    private func tabContent(scrollProxy: ScrollViewProxy) -> some View {
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
            // This is either Saved (for own profile) or Reviews (for other profiles)
            if viewModel.isOwnProfile {
                // Saved Tab - Use the existing SavedItemsView component
                SavedItemsView(
                    savedPosts: viewModel.savedPosts,
                    savedReels: viewModel.savedReels
                )
            } else {
                // Reviews Tab for other profiles
                reviewsSection(scrollProxy: scrollProxy)
            }
            
        case 3:
            // Reviews Tab for own profile
            reviewsSection(scrollProxy: scrollProxy)
            
        default:
            EmptyView()
        }
    }
    
    // ADDED - Separate reviews section with scroll proxy
    @ViewBuilder
    private func reviewsSection(scrollProxy: ScrollViewProxy) -> some View {
        VStack(spacing: 16) {
            // Star filter buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // All button
                    Button(action: {
                        selectedStarFilter = nil
                        showAllReviews = false
                    }) {
                        Text("All (\(viewModel.reviews.count))")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedStarFilter == nil ? Color.blue : Color(.systemGray5))
                            .foregroundColor(selectedStarFilter == nil ? .white : .primary)
                            .cornerRadius(20)
                    }
                    
                    // 5-1 star buttons
                    ForEach((1...5).reversed(), id: \.self) { rating in
                        let count = viewModel.reviews.filter { $0.rating == rating }.count
                        if count > 0 {
                            Button(action: {
                                selectedStarFilter = rating
                                showAllReviews = false
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                    Text("\(rating) (\(count))")
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedStarFilter == rating ? Color.blue : Color(.systemGray5))
                                .foregroundColor(selectedStarFilter == rating ? .white : .primary)
                                .cornerRadius(20)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            // Filtered reviews
            let filteredReviews = selectedStarFilter == nil ?
                viewModel.reviews :
                viewModel.reviews.filter { $0.rating == selectedStarFilter }
            
            let displayedReviews = showAllReviews ?
                filteredReviews :
                Array(filteredReviews.prefix(2))
            
            if filteredReviews.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "No Reviews",
                    message: selectedStarFilter != nil ?
                        "No \(selectedStarFilter!) star reviews" :
                        "No reviews yet"
                )
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(displayedReviews) { review in
                        ReviewCardWithHighlight(
                            review: review,
                            isProfileOwner: viewModel.isOwnProfile,
                            isHighlighted: review.id == highlightReviewId  // ADDED
                        )
                        .id(review.id)  // ADDED - for ScrollViewReader
                    }
                    
                    // Show more/less button
                    if filteredReviews.count > 2 {
                        Button(action: { showAllReviews.toggle() }) {
                            Text(showAllReviews ? "Show Less" : "Show More (\(filteredReviews.count - 2) more)")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding()
                
                if firebase.currentUser != nil && !viewModel.isOwnProfile {
                    Button(action: { showingReviewForm = true }) {
                        Label("Write a Review", systemImage: "pencil")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
    }
}

// MARK: - User Post Card
struct UserPostCard: View {
    let post: ServicePost
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let firstImage = post.imageURLs.first {
                AsyncImage(url: URL(string: firstImage)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipped()
                        .cornerRadius(8)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                        .overlay(
                            Image(systemName: post.isRequest ? "magnifyingglass" : "briefcase")
                                .foregroundColor(.gray)
                        )
                }
            } else {
                Rectangle()
                    .fill(post.isRequest ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .overlay(
                        Image(systemName: post.isRequest ? "magnifyingglass" : "briefcase")
                            .foregroundColor(post.isRequest ? .orange : .blue)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(post.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    if let price = post.price {
                        Text(post.isRequest ? "Budget: $\(Int(price))" : "$\(Int(price))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(post.isRequest ? .orange : .blue)
                    }
                    
                    Spacer()
                    
                    Text(post.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// ADDED - Review Card with Highlight wrapper
struct ReviewCardWithHighlight: View {
    let review: Review
    let isProfileOwner: Bool
    let isHighlighted: Bool
    
    @State private var highlightAnimation = false
    
    var body: some View {
        ReviewCard(review: review, isProfileOwner: isProfileOwner)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHighlighted && highlightAnimation ? Color.blue.opacity(0.1) : Color.clear)
                    .animation(.easeInOut(duration: 0.5), value: highlightAnimation)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHighlighted && highlightAnimation ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
                    .animation(.easeInOut(duration: 0.5), value: highlightAnimation)
            )
            .onAppear {
                if isHighlighted {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        highlightAnimation = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(.easeOut(duration: 1)) {
                                highlightAnimation = false
                            }
                        }
                    }
                }
            }
    }
}

// MARK: - Saved Items View
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
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(savedPosts) { post in
                                NavigationLink(destination: PostDetailView(post: post)) {
                                    SavedPostCard(post: post)
                                }
                            }
                        }
                        .padding()
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
                    ScrollView {
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
}

// NOTE: SavedPostCard and SavedReelThumbnail are already in ProfileSupportingViews.swift
// NOTE: ProfileImageView, EmptyStateView, and PortfolioCardView are imported from their respective files:
// - ProfileImageView is in CachedAsyncImage.swift
// - EmptyStateView is in Components/EmptyStateView.swift
// - PortfolioCardView is in ProfileSupportingViews.swift
