// ReelsView.swift
// Path: ClaudeHustlerFirebase/Views/Reels/ReelsView.swift
// UPDATED: Own status first, eye icon for views

import SwiftUI
import AVKit
import FirebaseFirestore

struct ReelsView: View {
    @StateObject private var viewModel = ReelsViewModel()
    @StateObject private var firebase = FirebaseService.shared
    @State private var selectedStatus: Status?
    @State private var showingCreateOptions = false
    @State private var currentReelIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isFullScreenMode = false
    @State private var showingStatusCreation = false
    
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
                    
                    Divider()
                        .padding(.vertical, 10)
                    
                    // Reels Grid Section
                    reelsGridSection
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadStatuses()
            await viewModel.loadInitialReels()
            await viewModel.cleanupExpiredStatuses()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $showingStatusCreation) {
            CameraView(mode: .status)  // Uses your existing camera flow
        }
        .fullScreenCover(item: $selectedStatus) { status in
            StatusViewerView(status: status)
        }
        .fullScreenCover(isPresented: $isFullScreenMode) {
            VerticalReelScrollView(
                reels: viewModel.reels,
                initialIndex: currentReelIndex,
                viewModel: viewModel
            )
        }
    }
    
    // MARK: - Status Section (UPDATED: User's status first)
    // MARK: - Status Section (UPDATED: User's status first)
    @ViewBuilder
    private var statusSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Show user's own status first (or Add Story button)
                if let currentUserId = firebase.currentUser?.id {
                    if let myStatus = viewModel.statuses.first(where: { $0.userId == currentUserId }) {
                        // User has active status - show it WITHOUT the plus overlay
                        StatusCircle(
                            status: myStatus,
                            isOwnStatus: true,
                            action: { selectStatus(myStatus) }
                        )
                        // REMOVED THE .overlay() WITH THE PLUS BUTTON
                    } else {
                        // Add Story button (no status yet) - THIS is where the plus belongs
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
                    }
                }
                
                // Then show other users' statuses (excluding current user's)
                ForEach(viewModel.statuses.filter { $0.userId != firebase.currentUser?.id }) { status in
                    StatusCircle(
                        status: status,
                        isOwnStatus: false,
                        action: { selectStatus(status) }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Reels Grid Section (UPDATED: Eye icon with views)
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
                        // Track view when reel is opened
                        
                    }
                }
                
                // Load more indicator
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
    
    // MARK: - Helper Methods
    private func selectStatus(_ status: Status) {
        selectedStatus = status
        Task {
            await viewModel.viewStatus(status.id ?? "")
        }
    }
}

// MARK: - Reel Grid Item (UPDATED: Eye icon instead of play)
struct ReelGridItem: View {
    let reel: Reel
    let action: () -> Void
    
    @State private var loadingFailed = false
    @State private var loadingTimer: Timer?
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Background - always show something
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                
                // Thumbnail or fallback
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
                                    // Cancel timer if image loads successfully
                                    loadingTimer?.invalidate()
                                }
                            
                        case .failure(_):
                            // Show fallback on failure
                            fallbackView
                            
                        case .empty:
                            // Show loading only briefly, then fallback
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
                                    // Set a timeout for loading
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
                
                // View count overlay with eye icon
                VStack {
                    Spacer()
                    HStack {
                        // Eye icon with view count
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
            // Clean up timer when view disappears
            loadingTimer?.invalidate()
        }
    }
    
    @ViewBuilder
    private var fallbackView: some View {
        // Fallback view when thumbnail fails to load or times out
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
                // Show video/image icon based on content
                Image(systemName: reel.videoURL.contains(".mp4") || reel.videoURL.contains(".mov") ? "play.rectangle.fill" : "photo.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                // Show title if available
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
    
    // Format view count (e.g., 1.2K, 3M)
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

// MARK: - Status Circle Component
struct StatusCircle: View {
    let status: Status
    let isOwnStatus: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                AsyncImage(url: URL(string: status.mediaURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 70, height: 70)
                        .clipShape(Circle())
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 70, height: 70)
                }
                .overlay(
                    Circle()
                        .stroke(
                            status.viewedBy.contains(FirebaseService.shared.currentUser?.id ?? "") ?
                                Color.gray :
                                (isOwnStatus ? Color.blue : Color.purple),
                            lineWidth: status.viewedBy.contains(FirebaseService.shared.currentUser?.id ?? "") ? 1 : 3
                        )
                )
                
                Text(isOwnStatus ? "Your Story" : (status.userName ?? "User"))
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
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

// MARK: - Keep existing VerticalReelScrollView and FullScreenReelView unchanged
struct VerticalReelScrollView: View {
    let reels: [Reel]
    let initialIndex: Int
    @ObservedObject var viewModel: ReelsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var currentIndex: Int
    
    init(reels: [Reel], initialIndex: Int, viewModel: ReelsViewModel) {
        self.reels = reels
        self.initialIndex = initialIndex
        self.viewModel = viewModel
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
                            viewModel: viewModel
                        )
                        .tag(index)
                        .onAppear {
                            // Track view when reel appears
                            Task {
                                await viewModel.incrementReelView(reel.id ?? "")
                            }
                        }
                    }
                }
                .tabViewStyle(PageTabViewStyle())
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .never))
                
                // Close button
                VStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding()
                        
                        Spacer()
                    }
                    
                    Spacer()
                }
            }
        }
    }
}

// Keep the rest of FullScreenReelView implementation as is...
// StatusViewerView remains unchanged...

// MARK: - Full Screen Reel View (Individual Reel)
struct FullScreenReelView: View {
    let reel: Reel
    let isCurrentReel: Bool
    let onDismiss: () -> Void
    @ObservedObject var viewModel: ReelsViewModel  // UPDATED: Accept from parent
    
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
    
    // Real-time listeners
    @State private var reelListener: ListenerRegistration?
    @State private var currentReel: Reel?
    
    @StateObject private var firebase = FirebaseService.shared
    
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
                
                // Background image/video
                reelBackgroundContent
                
                // Content overlay
                VStack {
                    Spacer()
                    
                    // Bottom content container
                    ZStack(alignment: .bottom) {
                        // Left side - Info (aligned to leading edge)
                        HStack {
                            VStack(alignment: .leading, spacing: 10) {
                                // User info
                                userInfoSection
                                
                                // Caption
                                if !displayReel.title.isEmpty || !displayReel.description.isEmpty {
                                    captionSection
                                }
                                
                                
                            }
                            .frame(maxWidth: geometry.size.width * 0.65, alignment: .leading)
                            .padding(.leading, 16)
                            .padding(.bottom, 80)
                            
                            Spacer()
                        }
                        
                        // Right side - Actions (aligned to trailing edge)
                        HStack {
                            Spacer()
                            rightActionButtons
                        }
                    }
                }
            }
        }
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
            EditReelCaptionView(reel: displayReel, viewModel: viewModel)  // Pass viewModel
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
            let videoURL = displayReel.videoURL
            // Video player would go here
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
            }
            
            // Username
            Text(displayReel.userName ?? "User")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            // Follow button (if not own reel)
            if !isOwnReel {
                Button(action: { toggleFollow() }) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(isFollowing ? Color.clear : Color.red)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isFollowing ? Color.white : Color.clear, lineWidth: 1)
                        )
                        .cornerRadius(4)
                }
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !displayReel.title.isEmpty {
                Text(displayReel.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if !displayReel.description.isEmpty {
                Text(displayReel.description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    @ViewBuilder
    private var rightActionButtons: some View {
        VStack(spacing: 20) {
            // Like button
            ReelActionButton(
                icon: isLiked ? "heart.fill" : "heart",
                text: likesCount > 0 ? "\(likesCount)" : nil,
                color: isLiked ? .red : .white,
                action: { toggleLike() },
                onLongPress: likesCount > 0 ? { showingLikesList = true } : nil
            )
            
            // Comment button
            ReelActionButton(
                icon: "bubble.right",
                text: commentsCount > 0 ? "\(commentsCount)" : nil,
                color: .white,
                action: { showingComments = true }
            )
            
            // Message button (if not own reel)
            if !isOwnReel {
                ReelActionButton(
                    icon: "message",
                    text: nil,
                    color: .white,
                    action: { showingMessageView = true }
                )
            }
            
            // Share button
            ReelActionButton(
                icon: "paperplane",
                text: displayReel.shares > 0 ? "\(displayReel.shares)" : nil,
                color: .white,
                action: { shareReel() }
            )
            
            // Save button
            ReelActionButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                text: nil,
                color: isSaved ? .yellow : .white,
                action: { toggleSave() }
            )
            
            // More options menu
            Menu {
                if isOwnReel {
                    Button(action: { showingEditSheet = true }) {
                        Label("Edit Caption", systemImage: "pencil")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label("Delete Reel", systemImage: "trash")
                    }
                } else {
                    Button(action: {}) {
                        Label("Report", systemImage: "flag")
                    }
                    
                    Button(action: {}) {
                        Label("Not Interested", systemImage: "hand.raised")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 80)  // Space for tab bar
    }
    
    // MARK: - Updated Methods Using ViewModel
    
    private func setupReelView() {
        Task {
            await loadReelData()
            await checkSaveStatus()
            checkFollowingStatus()
            // Note: Real-time listener removed in MVVM migration
        }
    }
    
    private func loadReelData() async {
        isLiked = displayReel.likes.contains(firebase.currentUser?.id ?? "")
        likesCount = displayReel.likes.count
        commentsCount = displayReel.comments
        
        if let reelId = reel.id {
            isSaved = await viewModel.isReelSaved(reelId)  // UPDATED
        }
    }
    
    private func checkSaveStatus() async {
        if let reelId = reel.id {
            isSaved = await viewModel.isReelSaved(reelId)  // UPDATED
        }
    }
    
    private func checkFollowingStatus() {
        isFollowing = viewModel.isFollowingCreator(reel.userId)  // UPDATED
    }
    
    private func toggleLike() {
        Task {
            guard let reelId = reel.id else { return }
            
            if isLiked {
                await viewModel.unlikeReel(reelId)  // UPDATED
                isLiked = false
                likesCount = max(0, likesCount - 1)
            } else {
                await viewModel.likeReel(reelId)  // UPDATED
                isLiked = true
                likesCount += 1
            }
        }
    }
    
    private func toggleFollow() {
        Task {
            do {
                try await viewModel.toggleFollowReelCreator(reel.userId)  // UPDATED
                isFollowing.toggle()
            } catch {
                print("Error toggling follow: \(error)")
            }
        }
    }
    
    private func toggleSave() {
        guard let reelId = reel.id else { return }
        
        Task {
            do {
                isSaved = try await viewModel.toggleSaveReel(reelId)  // UPDATED
            } catch {
                print("Error toggling save: \(error)")
            }
        }
    }
    
    private func shareReel() {
        showingShareSheet = true
        
        Task {
            if let reelId = reel.id {
                await viewModel.shareReel(reelId)  // UPDATED
            }
        }
    }
    
    private func deleteReel() async {
        guard let reelId = reel.id else { return }
        
        isDeleting = true
        
        do {
            try await viewModel.deleteReel(reelId)  // UPDATED
            onDismiss()
        } catch {
            print("Error deleting reel: \(error)")
            isDeleting = false
        }
    }
    
    private func cleanupAllListeners() {
        reelListener?.remove()
        reelListener = nil
    }
}

// MARK: - Reel Viewer View (Standalone for saved reels, etc)
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
    @StateObject private var viewModel = ReelsViewModel()  // ADDED
    
    // Check if current user owns this reel
    var isOwnReel: Bool {
        reel.userId == firebase.currentUser?.id
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Video/Image content
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
            
            // Overlay controls
            VStack {
                // Top bar
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
                
                // Bottom content
                HStack(alignment: .bottom) {
                    // Left side - Info
                    VStack(alignment: .leading, spacing: 10) {
                        // User info
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
                        
                        // Caption
                        if !reel.title.isEmpty {
                            Text(reel.title)
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        
                        if !reel.description.isEmpty {
                            Text(reel.description)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(3)
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Right side - Actions
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
            EditReelCaptionView(reel: reel, viewModel: viewModel)  // Pass viewModel
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
    
    // MARK: - Updated Methods Using ViewModel
    
    private func checkInitialStates() async {
        isFollowing = viewModel.isFollowingCreator(reel.userId)  // UPDATED
        isLiked = reel.likes.contains(firebase.currentUser?.id ?? "")
        
        if let reelId = reel.id {
            isSaved = await viewModel.isReelSaved(reelId)  // UPDATED
        }
    }
    
    private func toggleLike() {
        Task {
            guard let reelId = reel.id else { return }
            
            if isLiked {
                await viewModel.unlikeReel(reelId)  // UPDATED
            } else {
                await viewModel.likeReel(reelId)  // UPDATED
            }
            isLiked.toggle()
        }
    }
    
    private func toggleFollow() {
        Task {
            do {
                try await viewModel.toggleFollowReelCreator(reel.userId)  // UPDATED
                isFollowing.toggle()
            } catch {
                print("Error toggling follow: \(error)")
            }
        }
    }
    
    private func toggleSave() {
        guard let reelId = reel.id else { return }
        
        Task {
            do {
                isSaved = try await viewModel.toggleSaveReel(reelId)  // UPDATED
            } catch {
                print("Error toggling save: \(error)")
            }
        }
    }
    
    private func shareReel() {
        showingShareSheet = true
        
        Task {
            if let reelId = reel.id {
                await viewModel.shareReel(reelId)  // UPDATED
            }
        }
    }
    
    private func deleteReel() async {
        guard let reelId = reel.id else { return }
        
        isDeleting = true
        
        do {
            try await viewModel.deleteReel(reelId)  // UPDATED
            dismiss()
        } catch {
            print("Error deleting reel: \(error)")
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
                
                if let text = text {
                    Text(text)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
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
    @ObservedObject var viewModel: ReelsViewModel  // UPDATED: Accept viewModel
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
            try await viewModel.updateReel(updatedReel)  // UPDATED: Use viewModel
            dismiss()
        } catch {
            print("Error updating reel: \(error)")
        }
        
        isSaving = false
    }
}

// Note: Other supporting views like CreateContentOptionsSheet, CommentsView, etc.
// should be in separate files or remain unchanged if they don't have direct repository calls
