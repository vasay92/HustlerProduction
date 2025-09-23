// ReelsView.swift
// Path: ClaudeHustlerFirebase/Views/Reels/ReelsView.swift
// UPDATED VERSION - Phase 2.1 MVVM Migration Complete

import SwiftUI
import AVKit
import FirebaseFirestore

struct ReelsView: View {
    @StateObject private var viewModel = ReelsViewModel()
    @State private var selectedStatus: Status?
    @State private var showingCreateOptions = false
    @State private var currentReelIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isFullScreenMode = false
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Status Section
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
        .sheet(isPresented: $showingCreateOptions) {
            CreateContentOptionsSheet()
        }
        .fullScreenCover(item: $selectedStatus) { status in
            StatusViewerView(status: status)
        }
        .fullScreenCover(isPresented: $isFullScreenMode) {
            VerticalReelScrollView(
                reels: viewModel.reels,
                initialIndex: currentReelIndex,
                viewModel: viewModel  // Pass viewModel to child view
            )
        }
    }
    
    // MARK: - Status Section
    @ViewBuilder
    private var statusSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Add Status button
                AddStatusButton {
                    showingCreateOptions = true
                }
                
                // Status circles from ViewModel
                ForEach(viewModel.statuses) { status in
                    StatusCircle(
                        status: status,
                        isOwnStatus: status.userId == FirebaseService.shared.currentUser?.id,
                        action: { selectStatus(status) }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
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

// MARK: - Status Components
struct AddStatusButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 75, height: 75)
                    
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                Text("Add Story")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
    }
}

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
                            status.viewedBy.contains(FirebaseService.shared.currentUser?.id ?? "") ? Color.gray : isOwnStatus ? Color.blue : Color.purple,
                            lineWidth: status.viewedBy.contains(FirebaseService.shared.currentUser?.id ?? "") ? 1 : 3
                        )
                        .frame(width: 75, height: 75)
                )
                
                Text(isOwnStatus ? "Your Story" : (status.userName ?? "User"))
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }
        }
    }
}

// MARK: - Status Viewer
struct StatusViewerView: View {
    let status: Status
    @Environment(\.dismiss) var dismiss
    @State private var isDeleting = false
    @StateObject private var firebase = FirebaseService.shared
    @StateObject private var viewModel = ReelsViewModel()  // ADDED
    
    var isOwnStatus: Bool {
        status.userId == firebase.currentUser?.id
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Status content
            if status.mediaType == .image {
                AsyncImage(url: URL(string: status.mediaURL)) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            
            // Top bar
            VStack {
                HStack {
                    // User info
                    HStack {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 40, height: 40)
                        
                        VStack(alignment: .leading) {
                            Text(status.userName ?? "User")
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                            
                            Text(status.createdAt, style: .relative)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
                    Spacer()
                    
                    // Close button
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                .padding()
                
                Spacer()
                
                // Caption
                if let caption = status.caption {
                    Text(caption)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(10)
                        .padding()
                }
                
                // Delete button for own status
                if isOwnStatus {
                    Button(action: deleteStatus) {
                        Text("Delete Status")
                            .foregroundColor(.red)
                            .padding()
                    }
                }
            }
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
    
    private func deleteStatus() {
        Task {
            isDeleting = true
            do {
                try await viewModel.deleteStatus(status.id ?? "")  // UPDATED: Use viewModel
                dismiss()
            } catch {
                print("Error deleting status: \(error)")
                isDeleting = false
            }
        }
    }
}

// MARK: - Reel Grid Item
struct ReelGridItem: View {
    let reel: Reel
    let action: () -> Void
    
    var placeholderView: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
    }
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail or video preview
                if let thumbnailURL = reel.thumbnailURL {
                    AsyncImage(url: URL(string: thumbnailURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
                                .clipped()
                        case .failure(_):
                            placeholderView
                        case .empty:
                            placeholderView
                                .overlay(ProgressView())
                        @unknown default:
                            placeholderView
                        }
                    }
                } else {
                    placeholderView
                }
                
                // Overlay with play icon and view count
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                            Text("\(reel.views)")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
            .background(Color.gray.opacity(0.2))
        }
    }
}

// MARK: - Vertical Reel Scroll View (Full Screen Mode)
struct VerticalReelScrollView: View {
    let reels: [Reel]
    let initialIndex: Int
    @ObservedObject var viewModel: ReelsViewModel  // UPDATED: Changed from creating new instance
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
                            viewModel: viewModel  // Pass viewModel down
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .ignoresSafeArea()
                
                // Top bar overlay
                VStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding()
                                .background(Circle().fill(Color.black.opacity(0.3)))
                        }
                        .padding()
                        
                        Spacer()
                        
                        Text("Reels")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Placeholder for balance
                        Color.clear
                            .frame(width: 44, height: 44)
                            .padding()
                    }
                    
                    Spacer()
                }
            } else {
                VStack {
                    Text("No reels available")
                        .foregroundColor(.white)
                    
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
            }
        }
    }
}

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
                                
                                // Category
                                if let category = displayReel.category {
                                    Text(category.displayName)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.2))
                                        .cornerRadius(4)
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
        } else if let videoURL = displayReel.videoURL {
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

// MARK: - Supporting Components

struct EmptyReelsPlaceholder: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Reels Yet")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Be the first to share your skills!")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
