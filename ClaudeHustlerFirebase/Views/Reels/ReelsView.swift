// ReelsView.swift
// Path: ClaudeHustlerFirebase/Views/Reels/ReelsView.swift
// ENHANCED: Added search bar, clickable hashtags, and improved pause functionality

import SwiftUI
import AVKit
import FirebaseFirestore

struct ReelsView: View {
    @StateObject private var viewModel = ReelsViewModel()
    @StateObject private var firebase = FirebaseService.shared
    @State private var selectedStatus: Status?
    @State private var selectedUserId: String? = nil
    @State private var showingCreateOptions = false
    @State private var currentReelIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isFullScreenMode = false
    @State private var showingStatusCreation = false
    
    // MARK: - NEW Search Properties
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchResults: [Reel] = []
    @State private var showingHashtagSearch = false
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Status Section with user's own status first
                    statusSection
                    
                    // NEW: Search Bar Section
                    searchBarSection
                        .padding(.vertical, 10)
                    
                    Divider()
                    
                    // Reels Grid Section - Show search results or regular reels
                    if isSearching && !searchResults.isEmpty {
                        searchResultsSection
                    } else if isSearching {
                        noResultsView
                    } else {
                        reelsGridSection
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadStatuses()
            await viewModel.loadInitialReels()
            await viewModel.cleanupExpiredStatuses()
            await viewModel.loadTrendingHashtags()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $showingStatusCreation) {
            CameraView(mode: .status)
        }
        .fullScreenCover(item: $selectedUserId) { userId in
            StatusViewerView(initialUserId: userId)
        }
        .fullScreenCover(isPresented: $isFullScreenMode) {
            if isSearching && !searchResults.isEmpty {
                VerticalReelScrollView(
                    reels: searchResults,
                    initialIndex: currentReelIndex,
                    viewModel: viewModel,
                    onHashtagTapped: { hashtag in
                        searchQuery = hashtag
                        Task {
                            await searchReels()
                        }
                    }
                )
            } else {
                VerticalReelScrollView(
                    reels: viewModel.reels,
                    initialIndex: currentReelIndex,
                    viewModel: viewModel,
                    onHashtagTapped: { hashtag in
                        searchQuery = hashtag
                        Task {
                            await searchReels()
                        }
                    }
                )
            }
        }
    }
    
    // MARK: - NEW Search Bar Section
    @ViewBuilder
    private var searchBarSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                    
                    TextField("Search reels by title, description, or #hashtags", text: $searchQuery)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .onSubmit {
                            Task {
                                await searchReels()
                            }
                        }
                    
                    if !searchQuery.isEmpty {
                        Button(action: {
                            // Clear search and return to all reels
                            searchQuery = ""
                            isSearching = false
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.system(size: 16))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                // REMOVED: Cancel button - no longer needed
            }
            .padding(.horizontal)
            
            // Popular hashtags suggestion
            if !isSearching && viewModel.trendingHashtags.count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.trendingHashtags.prefix(10), id: \.self) { tag in
                            Button(action: {
                                searchQuery = tag
                                Task {
                                    await searchReels()
                                }
                            }) {
                                Text("#\(tag)")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(15)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    // MARK: - NEW Search Results Section
    @ViewBuilder
    private var searchResultsSection: some View {
        VStack(alignment: .leading) {
            Text("Search Results for: \"\(searchQuery)\"")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 10)
            
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, reel in
                    ReelGridItem(reel: reel) {
                        currentReelIndex = index
                        isFullScreenMode = true
                    }
                }
            }
            .padding(.horizontal, 1)
        }
    }
    
    // MARK: - NEW No Results View
    @ViewBuilder
    private var noResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No reels found")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Try searching with different keywords or hashtags")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 50)
    }
    
    
    // MARK: - Search Function
    private func searchReels() async {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isSearching = false
            searchResults = []
            return
        }
        
        isSearching = true
        
        do {
            searchResults = try await viewModel.searchReels(query: searchQuery)
        } catch {
            
            searchResults = []
        }
    }
    
    // MARK: - Status Section
    @ViewBuilder
    private var statusSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // User's own status circle
                if let currentUserId = firebase.currentUser?.id {
                    let userStatuses = viewModel.statuses.filter { $0.userId == currentUserId }
                    
                    if userStatuses.isEmpty {
                        // No status - show Add Story button with plus
                        Button(action: { showingStatusCreation = true }) {
                            VStack {
                                ZStack {
                                    Circle()
                                        .fill(Color(.systemGray6))
                                        .frame(width: 70, height: 70)
                                    
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                                        .frame(width: 70, height: 70)
                                    
                                    Image(systemName: "plus")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                }
                                
                                Text("Your Story")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                    } else {
                        // Has status - show without plus button
                        StatusCircleWithCount(
                            userId: currentUserId,
                            userName: "Your Story",
                            userProfileImage: firebase.currentUser?.profileImageURL,
                            statuses: userStatuses,
                            isOwnStatus: true,
                            action: {
                                selectedUserId = currentUserId
                            }
                        )
                    }
                }
                
                // Other users' statuses (grouped by user)
                ForEach(uniqueStatusUsers(), id: \.self) { userId in
                    if userId != firebase.currentUser?.id {
                        let userStatuses = viewModel.statuses.filter { $0.userId == userId }
                        if let firstStatus = userStatuses.first {
                            StatusCircleWithCount(
                                userId: userId,
                                userName: firstStatus.userName ?? "User",
                                userProfileImage: firstStatus.userProfileImage,
                                statuses: userStatuses,
                                isOwnStatus: false,
                                action: {
                                    selectedUserId = userId
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Helper method to get unique users with statuses
    private func uniqueStatusUsers() -> [String] {
        let userIds = Set(viewModel.statuses.map { $0.userId })
        return Array(userIds).sorted { userId1, userId2 in
            let user1Latest = viewModel.statuses
                .filter { $0.userId == userId1 }
                .first?.createdAt ?? Date.distantPast
            let user2Latest = viewModel.statuses
                .filter { $0.userId == userId2 }
                .first?.createdAt ?? Date.distantPast
            return user1Latest > user2Latest
        }
    }
    
    // MARK: - Reels Grid Section
    @ViewBuilder
    private var reelsGridSection: some View {
        if viewModel.reels.isEmpty && !viewModel.isLoadingReels {
            EmptyReelsPlaceholder()
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(viewModel.reels.enumerated()), id: \.element.id) { index, reel in
                    ReelGridItem(reel: reel) {
                        currentReelIndex = index
                        isFullScreenMode = true
                    }
                }
                
                if viewModel.hasMoreReels && !viewModel.reels.isEmpty {
                    ProgressView()
                        .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
                        .background(Color.gray.opacity(0.2))
                        .onAppear {
                            Task {
                                await viewModel.loadMoreReels()
                            }
                        }
                }
            }
            .padding(.horizontal, 1)
        }
    }
}


// MARK: - Status Circle Component with Multiple Status Indicator
struct StatusCircleWithCount: View {
    let userId: String
    let userName: String
    let userProfileImage: String?
    let statuses: [Status]
    let isOwnStatus: Bool
    let action: () -> Void
    
    @StateObject private var firebase = FirebaseService.shared
    
    private var hasUnviewedStatus: Bool {
        guard let currentUserId = firebase.currentUser?.id else { return true }
        return statuses.contains { status in
            !status.viewedBy.contains(currentUserId)
        }
    }
    
    private var statusCount: Int {
        statuses.count
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // Multi-segment ring for multiple statuses
                    if statusCount > 1 {
                        SegmentedStatusRing(
                            segments: statusCount,
                            isViewed: !hasUnviewedStatus,
                            isOwnStatus: isOwnStatus
                        )
                        .frame(width: 76, height: 76)
                    } else if statusCount == 1 {
                        // Single ring for one status
                        Circle()
                            .stroke(
                                hasUnviewedStatus ?
                                    (isOwnStatus ? Color.blue : Color.purple) :
                                    Color.gray,
                                lineWidth: hasUnviewedStatus ? 3 : 1.5
                            )
                            .frame(width: 76, height: 76)
                    } else {
                        // No status - just gray circle for others, blue-ish for own
                        Circle()
                            .stroke(
                                isOwnStatus ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2),
                                lineWidth: 1.5
                            )
                            .frame(width: 76, height: 76)
                    }
                    
                    // Profile image
                    if let firstStatus = statuses.first {
                        AsyncImage(url: URL(string: firstStatus.mediaURL)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 70, height: 70)
                                .clipShape(Circle())
                        } placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 70, height: 70)
                                .overlay(
                                    Text(String(userName.first ?? "U"))
                                        .foregroundColor(.white)
                                )
                        }
                    } else if isOwnStatus {
                        // Show user's profile image when no status
                        AsyncImage(url: URL(string: userProfileImage ?? "")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 70, height: 70)
                                .clipShape(Circle())
                        } placeholder: {
                            Circle()
                                .fill(Color(.systemGray6))
                                .frame(width: 70, height: 70)
                                .overlay(
                                    Text(String(userName.first ?? "U"))
                                        .foregroundColor(.gray)
                                )
                        }
                    }
                }
                
                // Username with status count
                HStack(spacing: 2) {
                    Text(userName)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if statusCount > 1 && !isOwnStatus {
                        Text("(\(statusCount))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 70)
            }
        }
    }
}

// MARK: - Segmented Ring for Multiple Statuses
struct SegmentedStatusRing: View {
    let segments: Int
    let isViewed: Bool
    let isOwnStatus: Bool
    
    private let spacing: Double = 3
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<segments, id: \.self) { index in
                    Circle()
                        .trim(
                            from: segmentStart(index),
                            to: segmentEnd(index)
                        )
                        .stroke(
                            isViewed ? Color.gray : (isOwnStatus ? Color.blue : Color.purple),
                            style: StrokeStyle(
                                lineWidth: isViewed ? 1.5 : 3,
                                lineCap: .round
                            )
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
        }
    }
    
    private func segmentStart(_ index: Int) -> CGFloat {
        let segmentSize = 1.0 / Double(segments)
        let gapSize = (spacing / 360.0)
        return CGFloat(Double(index) * segmentSize + (index > 0 ? gapSize : 0))
    }
    
    private func segmentEnd(_ index: Int) -> CGFloat {
        let segmentSize = 1.0 / Double(segments)
        let gapSize = (spacing / 360.0)
        return CGFloat(Double(index + 1) * segmentSize - gapSize)
    }
}

// MARK: - Reel Grid Item
struct ReelGridItem: View {
    let reel: Reel
    let action: () -> Void
    
    @State private var loadingFailed = false
    @State private var loadingTimer: Timer?
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                
                if let thumbnailURL = reel.thumbnailURL, !thumbnailURL.isEmpty {
                    AsyncImage(url: URL(string: thumbnailURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
                                .clipped()
                                .onAppear {
                                    loadingTimer?.invalidate()
                                }
                        case .failure(_):
                            fallbackView
                        case .empty:
                            if loadingFailed {
                                fallbackView
                            } else {
                                ZStack {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                .onAppear {
                                    loadingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                                        loadingFailed = true
                                    }
                                }
                            }
                        @unknown default:
                            fallbackView
                        }
                    }
                } else {
                    fallbackView
                }
                
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.caption)
                            Text("\(formatViewCount(reel.views))")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
            .background(Color.gray.opacity(0.2))
        }
        .onDisappear {
            loadingTimer?.invalidate()
        }
    }
    
    @ViewBuilder
    private var fallbackView: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.6),
                            Color.pink.opacity(0.6)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 8) {
                Image(systemName: reel.videoURL.contains(".mp4") || reel.videoURL.contains(".mov") ? "play.rectangle.fill" : "photo.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                if !reel.title.isEmpty {
                    Text(reel.title)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
    }
    
    private func formatViewCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Empty State
struct EmptyReelsPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No Reels Yet")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Be the first to share a reel!")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 100)
    }
}

// MARK: - Vertical Reel Scroll View
struct VerticalReelScrollView: View {
    let reels: [Reel]
    let initialIndex: Int
    @ObservedObject var viewModel: ReelsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var currentIndex: Int
    @State private var isCleanView = false
    let onHashtagTapped: ((String) -> Void)?
    
    init(reels: [Reel], initialIndex: Int, viewModel: ReelsViewModel, onHashtagTapped: ((String) -> Void)? = nil) {
        self.reels = reels
        self.initialIndex = initialIndex
        self.viewModel = viewModel
        self.onHashtagTapped = onHashtagTapped  // Now this will work
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if !reels.isEmpty {
                TabView(selection: $currentIndex) {
                    ForEach(Array(reels.enumerated()), id: \.element.id) { index, reel in
                        FullScreenReelView(
                            reel: reel,
                            isCurrentReel: index == currentIndex,
                            onDismiss: { dismiss() },
                            viewModel: viewModel,
                            isCleanView: isCleanView,  // PASS IT AS PROP
                            onHashtagTapped: onHashtagTapped
                        )
                        .tag(index)
                        .onAppear {
                            Task {
                                await viewModel.incrementReelView(reel.id ?? "")
                            }
                        }
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
            
            // Top header bar with gradient
            if !isCleanView {
                VStack {
                    // Gradient overlay for top bar
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.6),
                            Color.black.opacity(0.3),
                            Color.black.opacity(0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .ignoresSafeArea()
                    
                    Spacer()
                }
            }
            
            // Top buttons overlay
            VStack {
                HStack {
                    // Close button
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    
                    Spacer()
                    
                    // Clean view toggle
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCleanView.toggle()
                        }
                    }) {
                        Image(systemName: isCleanView ? "eye.slash.fill" : "eye.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 50)
                
                Spacer()
            }
        }
    }
}

// MARK: - Full Screen Reel View
struct FullScreenReelView: View {
    let reel: Reel
    let isCurrentReel: Bool
    let onDismiss: () -> Void
    @ObservedObject var viewModel: ReelsViewModel
    
    @State private var isLiked = false
    @State private var isFollowing = false
    @State private var isSaved = false
    @State private var likesCount = 0
    @State private var commentsCount = 0
    @State private var showingUserProfile = false
    @State private var showingComments = false
    @State private var showingLikesList = false
    @State private var showingMessageView = false
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingShareSheet = false
    @State private var isDeleting = false
    // ADD THESE:
    @State private var showingAuthPrompt = false
    @State private var authPromptAction = ""
    
    // NEW: For hashtag search
    @State private var showingHashtagSearch = false
    @State private var searchQuery = ""
    
    @State private var reelListener: ListenerRegistration?
    @State private var currentReel: Reel?
    
    @StateObject private var firebase = FirebaseService.shared
    let isCleanView: Bool
    let onHashtagTapped: ((String) -> Void)?
    
    var isOwnReel: Bool {
        reel.userId == firebase.currentUser?.id
    }
    
    var displayReel: Reel {
        currentReel ?? reel
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                reelBackgroundContent
                
                // Only show gradient and UI if not in clean view
                if !isCleanView {
                    // Gradient overlay
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0),
                            Color.black.opacity(0),
                            Color.black.opacity(0.3),
                            Color.black.opacity(0.6)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    
                    VStack {
                        Spacer()
                        
                        ZStack(alignment: .bottom) {
                            HStack {
                                VStack(alignment: .leading, spacing: 10) {
                                    userInfoSection
                                    
                                    if !displayReel.title.isEmpty || !displayReel.description.isEmpty {
                                        captionSection
                                    }
                                }
                                .frame(maxWidth: geometry.size.width * 0.65, alignment: .leading)
                                .padding(.leading, 16)
                                .padding(.bottom, 80)
                                
                                Spacer()
                            }
                            
                            HStack {
                                Spacer()
                                rightActionButtons
                            }
                        }
                    }
                }
            }
        }
        // ... rest of your existing modifiers
        .task {
            if isCurrentReel {
                await setupReelView()
            }
        }
        .onChange(of: isCurrentReel) { newValue in
            if newValue {
                Task {
                    await setupReelView()
                }
            } else {
                cleanupAllListeners()
            }
        }
        .fullScreenCover(isPresented: $showingUserProfile) {
            NavigationView {
                EnhancedProfileView(userId: displayReel.userId)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") {
                                showingUserProfile = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(
                reelId: displayReel.id ?? "",
                reelOwnerId: displayReel.userId
            )
        }
        .sheet(isPresented: $showingEditSheet) {
            EditReelCaptionView(reel: displayReel, viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showingMessageView) {
            ChatView(
                recipientId: displayReel.userId,
                contextType: .reel,
                contextId: displayReel.id,
                contextData: (
                    title: displayReel.title.isEmpty ? "Shared a reel" : displayReel.title,
                    image: displayReel.thumbnailURL ?? displayReel.videoURL,
                    userId: displayReel.userId
                ),
                isFromContentView: true
            )
        }
        .confirmationDialog("Delete Reel?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteReel()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ReelShareSheet(items: [
                displayReel.title.isEmpty ? "Check out this reel!" : displayReel.title,
                displayReel.description,
                URL(string: displayReel.thumbnailURL ?? displayReel.videoURL) ?? URL(string: "https://claudehustler.com")!
            ])
        }
        .overlay(
            Group {
                if isDeleting {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                        .overlay(
                            VStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                Text("Deleting...")
                                    .foregroundColor(.white)
                                    .padding(.top)
                            }
                        )
                }
            }
        )
        .sheet(isPresented: $showingAuthPrompt) {
            AuthenticationPromptView(action: authPromptAction)
        }
    }
    
    @ViewBuilder
    private var reelBackgroundContent: some View {
        if let thumbnailURL = displayReel.thumbnailURL {
            AsyncImage(url: URL(string: thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure(_):
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                case .empty:
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                @unknown default:
                    EmptyView()
                }
            }
        } else if !displayReel.videoURL.isEmpty {
            Rectangle()
                .fill(Color.black)
                .overlay(
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.8))
                )
        }
    }
    
    @ViewBuilder
    private var userInfoSection: some View {
        HStack {
            Button(action: { showingUserProfile = true }) {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 35, height: 35)
                    .overlay(
                        Group {
                            if let profileImage = displayReel.userProfileImage {
                                AsyncImage(url: URL(string: profileImage)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Text(String(displayReel.userName?.first ?? "U"))
                                        .foregroundColor(.white)
                                }
                                .clipShape(Circle())
                            } else {
                                Text(String(displayReel.userName?.first ?? "U"))
                                    .foregroundColor(.white)
                            }
                        }
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            
            Text(displayReel.userName ?? "User")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            
            if !isOwnReel {
                Button(action: { toggleFollow() }) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            isFollowing ?
                            Color.white.opacity(0.2) :
                            Color.red
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isFollowing ? Color.white : Color.clear, lineWidth: 1)
                        )
                        .cornerRadius(4)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - ENHANCED Caption Section with Clickable Hashtags
    // In FullScreenReelView, update captionSection:
    @ViewBuilder
    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !displayReel.title.isEmpty {
                Text(displayReel.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            
            if !displayReel.description.isEmpty {
                HashtagTextView(text: displayReel.description) { hashtag in
                    // Pass the hashtag back up before dismissing
                    onHashtagTapped?(hashtag)
                    onDismiss()
                }
                .lineLimit(3)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
        }
    }
    
    @ViewBuilder
    private var rightActionButtons: some View {
        VStack(spacing: 20) {
            ReelActionButton(
                icon: isLiked ? "heart.fill" : "heart",
                text: likesCount > 0 ? "\(likesCount)" : nil,
                color: isLiked ? .red : .white,
                action: {
                    if firebase.isAuthenticated {
                        toggleLike()
                    } else {
                        authPromptAction = "Like Reels"
                        showingAuthPrompt = true
                    }
                },
                onLongPress: likesCount > 0 ? { showingLikesList = true } : nil
            )
            
            ReelActionButton(
                icon: "bubble.right",
                text: commentsCount > 0 ? "\(commentsCount)" : nil,
                color: .white,
                action: {
                    if firebase.isAuthenticated {
                        showingComments = true
                    } else {
                        authPromptAction = "Comment on Reels"
                        showingAuthPrompt = true
                    }
                }
            )
            
            if !isOwnReel {
                ReelActionButton(
                    icon: "message",
                    text: nil,
                    color: .white,
                    action: {
                        if firebase.isAuthenticated {
                            showingMessageView = true
                        } else {
                            authPromptAction = "Send Messages"
                            showingAuthPrompt = true
                        }
                    }
                )
            }
            
            ReelActionButton(
                icon: "paperplane",
                text: displayReel.shares > 0 ? "\(displayReel.shares)" : nil,
                color: .white,
                action: { shareReel() }
            )
            
            ReelActionButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                text: nil,
                color: isSaved ? .yellow : .white,
                action: {
                    if firebase.isAuthenticated {
                        toggleSave()
                    } else {
                        authPromptAction = "Save Reels"
                        showingAuthPrompt = true
                    }
                }
            )
            
            Menu {
                // ... menu content
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 80)
    }
    
    private func setupReelView() async {
        await loadReelData()
        await checkSaveStatus()
        checkFollowingStatus()
    }
    
    private func loadReelData() async {
        isLiked = displayReel.likes.contains(firebase.currentUser?.id ?? "")
        likesCount = displayReel.likes.count
        commentsCount = displayReel.comments
        
        if let reelId = reel.id {
            isSaved = await viewModel.isReelSaved(reelId)
        }
    }
    
    private func checkSaveStatus() async {
        if let reelId = reel.id {
            isSaved = await viewModel.isReelSaved(reelId)
        }
    }
    
    private func checkFollowingStatus() {
        isFollowing = viewModel.isFollowingCreator(reel.userId)
    }
    
    private func toggleLike() {
        Task {
            guard let reelId = reel.id else { return }
            
            if isLiked {
                await viewModel.unlikeReel(reelId)
                isLiked = false
                likesCount = max(0, likesCount - 1)
            } else {
                await viewModel.likeReel(reelId)
                isLiked = true
                likesCount += 1
            }
        }
    }
    
    private func toggleFollow() {
        Task {
            do {
                try await viewModel.toggleFollowReelCreator(reel.userId)
                isFollowing.toggle()
            } catch {
                
            }
        }
    }
    
    private func toggleSave() {
        guard let reelId = reel.id else { return }
        
        Task {
            do {
                isSaved = try await viewModel.toggleSaveReel(reelId)
            } catch {
                
            }
        }
    }
    
    private func shareReel() {
        showingShareSheet = true
        
        Task {
            if let reelId = reel.id {
                await viewModel.shareReel(reelId)
            }
        }
    }
    
    private func deleteReel() async {
        guard let reelId = reel.id else { return }
        
        isDeleting = true
        
        do {
            try await viewModel.deleteReel(reelId)
            onDismiss()
        } catch {
            
            isDeleting = false
        }
    }
    
    private func cleanupAllListeners() {
        reelListener?.remove()
        reelListener = nil
    }
        
}

// MARK: - Reel Viewer View (Simplified version for direct viewing)
struct ReelViewerView: View {
    let reel: Reel
    @Environment(\.dismiss) var dismiss
    @State private var isLiked = false
    @State private var isFollowing = false
    @State private var isSaved = false
    @State private var showingUserProfile = false
    @State private var showingComments = false
    @State private var showingMessageView = false
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingMoreOptions = false
    @State private var isDeleting = false
    @State private var showingShareSheet = false
    @StateObject private var firebase = FirebaseService.shared
    @StateObject private var viewModel = ReelsViewModel()
    
    var isOwnReel: Bool {
        reel.userId == firebase.currentUser?.id
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let thumbnailURL = reel.thumbnailURL {
                AsyncImage(url: URL(string: thumbnailURL)) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.black.opacity(0.3)))
                    }
                    
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: { showingUserProfile = true }) {
                            HStack {
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 35, height: 35)
                                    .overlay(
                                        Text(String(reel.userName?.first ?? "U"))
                                            .foregroundColor(.white)
                                    )
                                
                                Text(reel.userName ?? "User")
                                    .foregroundColor(.white)
                                    .fontWeight(.semibold)
                                
                                if !isOwnReel {
                                    Button(action: { toggleFollow() }) {
                                        Text(isFollowing ? "Following" : "Follow")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 4)
                                            .background(isFollowing ? Color.clear : Color.red)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(isFollowing ? Color.white : Color.clear, lineWidth: 1)
                                            )
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        }
                        
                        if !reel.title.isEmpty {
                            Text(reel.title)
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        
                        if !reel.description.isEmpty {
                            HashtagTextView(text: reel.description) { hashtag in
                                // Handle hashtag tap
                                dismiss()
                            }
                            .lineLimit(3)
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    VStack(spacing: 20) {
                        Button(action: { toggleLike() }) {
                            VStack {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.title)
                                    .foregroundColor(isLiked ? .red : .white)
                                
                                if reel.likes.count > 0 {
                                    Text("\(reel.likes.count)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        
                        Button(action: { showingComments = true }) {
                            VStack {
                                Image(systemName: "bubble.right")
                                    .font(.title)
                                    .foregroundColor(.white)
                                
                                if reel.comments > 0 {
                                    Text("\(reel.comments)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        
                        Button(action: { shareReel() }) {
                            Image(systemName: "paperplane")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                        
                        Button(action: { toggleSave() }) {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.title)
                                .foregroundColor(isSaved ? .yellow : .white)
                        }
                        
                        Menu {
                            if isOwnReel {
                                Button(action: { showingEditSheet = true }) {
                                    Label("Edit Caption", systemImage: "pencil")
                                }
                                
                                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                                    Label("Delete Reel", systemImage: "trash")
                                }
                            } else {
                                Button(action: {}) {
                                    Label("Report", systemImage: "flag")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            await checkInitialStates()
        }
        .fullScreenCover(isPresented: $showingUserProfile) {
            NavigationView {
                EnhancedProfileView(userId: reel.userId)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") {
                                showingUserProfile = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(
                reelId: reel.id ?? "",
                reelOwnerId: reel.userId
            )
        }
        .sheet(isPresented: $showingEditSheet) {
            EditReelCaptionView(reel: reel, viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showingMessageView) {
            ChatView(
                recipientId: reel.userId,
                contextType: .reel,
                contextId: reel.id,
                contextData: (
                    title: reel.title.isEmpty ? "Shared a reel" : reel.title,
                    image: reel.thumbnailURL ?? reel.videoURL,
                    userId: reel.userId
                ),
                isFromContentView: true
            )
        }
        .confirmationDialog("Delete Reel?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteReel()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ReelShareSheet(items: [
                reel.title.isEmpty ? "Check out this reel!" : reel.title,
                reel.description,
                URL(string: reel.thumbnailURL ?? reel.videoURL) ?? URL(string: "https://claudehustler.com")!
            ])
        }
        .overlay(
            Group {
                if isDeleting {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                        .overlay(ProgressView())
                }
            }
        )
    }
    
    private func checkInitialStates() async {
        isFollowing = viewModel.isFollowingCreator(reel.userId)
        isLiked = reel.likes.contains(firebase.currentUser?.id ?? "")
        
        if let reelId = reel.id {
            isSaved = await viewModel.isReelSaved(reelId)
        }
    }
    
    private func toggleLike() {
        Task {
            guard let reelId = reel.id else { return }
            
            if isLiked {
                await viewModel.unlikeReel(reelId)
            } else {
                await viewModel.likeReel(reelId)
            }
            isLiked.toggle()
        }
    }
    
    private func toggleFollow() {
        Task {
            do {
                try await viewModel.toggleFollowReelCreator(reel.userId)
                isFollowing.toggle()
            } catch {
                
            }
        }
    }
    
    private func toggleSave() {
        guard let reelId = reel.id else { return }
        
        Task {
            do {
                isSaved = try await viewModel.toggleSaveReel(reelId)
            } catch {
                
            }
        }
    }
    
    private func shareReel() {
        showingShareSheet = true
        
        Task {
            if let reelId = reel.id {
                await viewModel.shareReel(reelId)
            }
        }
    }
    
    private func deleteReel() async {
        guard let reelId = reel.id else { return }
        
        isDeleting = true
        
        do {
            try await viewModel.deleteReel(reelId)
            dismiss()
        } catch {
           
            isDeleting = false
        }
    }
}

// MARK: - Action Button Component
struct ReelActionButton: View {
    let icon: String
    let text: String?
    let color: Color
    let action: () -> Void
    var onLongPress: (() -> Void)? = nil
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(color)
                    .scaleEffect(color == .red || color == .yellow ? 1.1 : 1.0)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                
                if let text = text {
                    Text(text)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
            }
            .frame(width: 44, height: 44)
        }
        .simultaneousGesture(
            LongPressGesture().onEnded { _ in
                onLongPress?()
            }
        )
    }
}
// MARK: - Share Sheet
struct ReelShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Edit Reel Caption View
struct EditReelCaptionView: View {
    let reel: Reel
    @ObservedObject var viewModel: ReelsViewModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var title: String
    @State private var description: String
    @State private var isSaving = false
    
    init(reel: Reel, viewModel: ReelsViewModel) {
        self.reel = reel
        self.viewModel = viewModel
        _title = State(initialValue: reel.title)
        _description = State(initialValue: reel.description)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Title") {
                    TextField("Enter title", text: $title)
                }
                
                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Edit Reel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
    
    private func saveChanges() async {
        isSaving = true
        
        var updatedReel = reel
        updatedReel.title = title
        updatedReel.description = description
        
        do {
            try await viewModel.updateReel(updatedReel)
            dismiss()
        } catch {
            
        }
        
        isSaving = false
    }
}
