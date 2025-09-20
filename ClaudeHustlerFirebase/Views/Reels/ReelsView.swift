// ReelsView.swift
// Path: ClaudeHustlerFirebase/Views/Reels/ReelsView.swift

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
                initialIndex: currentReelIndex
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
                        action: { selectedStatus = status }
                    )
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
    }
    
    // MARK: - Reels Grid Section
    @ViewBuilder
    private var reelsGridSection: some View {
        if viewModel.isLoadingReels && viewModel.reels.isEmpty {
            // Loading state
            VStack {
                ProgressView()
                    .padding(.top, 50)
                Text("Loading reels...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        } else if viewModel.reels.isEmpty {
            // Empty state
            VStack(spacing: 20) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text("No Reels Yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Be the first to share a reel!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: { showingCreateOptions = true }) {
                    Label("Create Reel", systemImage: "plus.circle.fill")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                }
            }
            .padding(.top, 50)
        } else {
            // Reels grid
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(viewModel.reels.enumerated()), id: \.element.id) { index, reel in
                    ReelGridItem(reel: reel) {
                        currentReelIndex = index
                        isFullScreenMode = true
                    }
                    .onAppear {
                        // Load more when reaching the end
                        if index == viewModel.reels.count - 3 && viewModel.hasMoreReels {
                            Task {
                                await viewModel.loadMoreReels()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 1)
            
            // Loading indicator for pagination
            if viewModel.isLoadingReels && !viewModel.reels.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
}

// Keep all the existing supporting views (StatusCircle, ReelGridItem, etc.) as they are

// MARK: - Vertical Reel Scroll View (Full Screen Mode)
struct VerticalReelScrollView: View {
    let reels: [Reel]
    let initialIndex: Int
    @Environment(\.dismiss) var dismiss
    @State private var currentIndex: Int
    
    init(reels: [Reel], initialIndex: Int) {
        self.reels = reels
        self.initialIndex = initialIndex
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
                            onDismiss: { dismiss() }
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
                
                // Content overlay - FIXED LAYOUT
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
                                        .background(Color.blue.opacity(0.6))
                                        .cornerRadius(4)
                                }
                            }
                            .frame(maxWidth: geometry.size.width * 0.7, alignment: .leading)
                            .padding(.leading, 16)
                            .padding(.bottom, 80)  // Space for tab bar
                            
                            Spacer()
                        }
                        
                        // Right side - Action buttons (aligned to trailing edge)
                        HStack {
                            Spacer()
                            
                            rightActionButtons
                        }
                    }
                }
                
                // Top close button (if not part of feed)
                if !isCurrentReel {
                    VStack {
                        HStack {
                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Circle().fill(Color.black.opacity(0.3)))
                            }
                            .padding()
                            
                            Spacer()
                        }
                        
                        Spacer()
                    }
                }
                
                // Deleting overlay
                if isDeleting {
                    deletingOverlay
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingUserProfile) {
            NavigationView {
                EnhancedProfileView(userId: displayReel.userId)
            }
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(
                reelId: reel.id ?? "",
                reelOwnerId: reel.userId
            )
        }
        .sheet(isPresented: $showingLikesList) {
            LikesListView(reelId: reel.id ?? "")
        }
        .sheet(isPresented: $showingMessageView) {
            if let reelId = reel.id {
                ChatView(  // Fixed: Changed from MessageUserView to ChatView
                    recipientId: reel.userId,
                    contextType: .reel,
                    contextId: reelId,
                    contextData: (
                        title: reel.title,
                        image: reel.thumbnailURL,
                        userId: reel.userId
                    ),
                    isFromContentView: true
                )
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditReelCaptionView(reel: reel)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let reelId = reel.id,
               let url = URL(string: "https://yourapp.com/reel/\(reelId)") {
                ShareSheet(items: [url])
            }
        }
        .confirmationDialog("Delete Reel?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteReel()
                }
            }
        } message: {
            Text("This action cannot be undone")
        }
        .onAppear {
            setupReelView()
        }
        .onDisappear {
            cleanupAllListeners()
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var reelBackgroundContent: some View {
        GeometryReader { geometry in
            if let thumbnailURL = displayReel.thumbnailURL,
               let url = URL(string: thumbnailURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } placeholder: {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
            } else {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
        }
        .ignoresSafeArea()
        .overlay(
            Color.black.opacity(0.3)
                .ignoresSafeArea()
        )
    }
    
    @ViewBuilder
    private var userInfoSection: some View {
        HStack(spacing: 10) {
            // Profile image button
            Button(action: { showingUserProfile = true }) {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Group {
                            if let imageURL = displayReel.userProfileImage,
                               let url = URL(string: imageURL) {
                                AsyncImage(url: url) { image in
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
            
            Spacer()  // Push everything to the left
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
    
    @ViewBuilder
    private var deletingOverlay: some View {
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
    
    // MARK: - Methods
    
    private func setupReelView() {
        Task {
            await loadReelData()
            await checkSaveStatus()
            checkFollowingStatus()
            setupReelListener()
        }
    }
    
    private func setupReelListener() {
        guard let reelId = reel.id else { return }
        
        // Fixed: Removed [weak self] as structs can't be weak referenced
        reelListener = firebase.listenToReel(reelId) { updatedReel in
            guard let updatedReel = updatedReel else { return }
            
            Task { @MainActor in
                self.currentReel = updatedReel
                self.likesCount = updatedReel.likes.count
                self.commentsCount = updatedReel.comments
            }
        }
    }
    
    private func loadReelData() async {
        isLiked = firebase.currentUser?.id != nil &&
                 displayReel.likes.contains(firebase.currentUser?.id ?? "")
        likesCount = displayReel.likes.count
        commentsCount = displayReel.comments
        
        if let reelId = reel.id {
            isSaved = await firebase.isItemSaved(itemId: reelId, type: .reel)
        }
    }
    
    private func checkSaveStatus() async {
        if let reelId = reel.id {
            isSaved = await firebase.isItemSaved(itemId: reelId, type: .reel)
        }
    }
    
    private func checkFollowingStatus() {
        guard let currentUser = firebase.currentUser else { return }
        isFollowing = currentUser.following.contains(reel.userId)
    }
    
    private func toggleLike() {
        Task {
            do {
                if isLiked {
                    try await ReelRepository.shared.unlikeReel(reel.id ?? "")
                    isLiked = false
                    likesCount = max(0, likesCount - 1)
                } else {
                    try await ReelRepository.shared.likeReel(reel.id ?? "")
                    isLiked = true
                    likesCount += 1
                }
            } catch {
                print("Error toggling like: \(error)")
            }
        }
    }
    
    private func toggleFollow() {
        Task {
            do {
                if isFollowing {
                    try await firebase.unfollowUser(reel.userId)
                    isFollowing = false
                } else {
                    try await firebase.followUser(reel.userId)
                    isFollowing = true
                }
            } catch {
                print("Error toggling follow: \(error)")
            }
        }
    }
    
    private func toggleSave() {
        guard let reelId = reel.id else { return }
        
        Task {
            do {
                isSaved = try await firebase.toggleReelSave(reelId)
            } catch {
                print("Error toggling save: \(error)")
            }
        }
    }
    
    private func shareReel() {
        showingShareSheet = true
        
        // Fixed: Use ReelRepository for incrementShareCount
        Task {
            if let reelId = reel.id {
                do {
                    try await ReelRepository.shared.incrementShareCount(for: reelId)
                } catch {
                    print("Error incrementing share count: \(error)")
                }
            }
        }
    }
    
    private func deleteReel() async {
        guard let reelId = reel.id else { return }
        
        isDeleting = true
        
        do {
            try await ReelRepository.shared.delete(reelId)
            onDismiss()  // or dismiss() depending on the view
        } catch {
            print("Error deleting reel: \(error)")
            isDeleting = false
        }
    }
    
    private func cleanupAllListeners() {
        reelListener?.remove()
        reelListener = nil
        
        if let reelId = reel.id {
            firebase.stopListeningToReel(reelId)
        }
        
        if showingComments {
            firebase.stopListeningToComments(reel.id ?? "")
        }
        
        if showingLikesList {
            firebase.stopListeningToLikes(reel.id ?? "")
        }
    }
}

// MARK: - Supporting Components

// Add Status Button
struct AddStatusButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 70, height: 70)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.primary)
                        )
                    
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.caption)
                                .foregroundColor(.white)
                        )
                }
                
                Text("Your Story")
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
    }
}

// Status Circle
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
                        .frame(width: 65, height: 65)
                        .clipShape(Circle())
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 65, height: 65)
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

// Reel Grid Item
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

// Empty Reels Placeholder
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
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var title: String
    @State private var description: String
    @State private var isSaving = false
    
    init(reel: Reel) {
        self.reel = reel
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
            .overlay(
                Group {
                    if isSaving {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .overlay(
                                ProgressView("Saving...")
                            )
                    }
                }
            )
        }
    }
    
    private func saveChanges() async {
        guard let reelId = reel.id else { return }
        
        isSaving = true
        
        do {
            try await firebase.updateReelCaption(reelId, title: title, description: description)
            dismiss()
        } catch {
            print("Error updating reel: \(error)")
            isSaving = false
        }
    }
}

// MARK: - Create Content Options Sheet
struct CreateContentOptionsSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var showingStatusCamera = false
    @State private var showingReelCamera = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Create Content")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                
                // Status Option
                Button(action: { showingStatusCamera = true }) {
                    HStack {
                        Image(systemName: "circle.dashed")
                            .font(.title2)
                            .foregroundColor(.orange)
                            .frame(width: 50)
                        
                        VStack(alignment: .leading) {
                            Text("Add Status")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Share a 24-hour update")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Reel Option
                Button(action: { showingReelCamera = true }) {
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                            .font(.title2)
                            .foregroundColor(.purple)
                            .frame(width: 50)
                        
                        VStack(alignment: .leading) {
                            Text("Create Reel")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Showcase your skills")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Spacer()
                
                Button("Cancel") { dismiss() }
                    .foregroundColor(.primary)
            }
            .padding()
            .navigationBarHidden(true)
        }
        .presentationDetents([.height(300)])
        .fullScreenCover(isPresented: $showingStatusCamera) {
            CameraView(mode: .status)
        }
        .fullScreenCover(isPresented: $showingReelCamera) {
            CameraView(mode: .reel)
        }
    }
}

// MARK: - Status Viewer View with Delete
struct StatusViewerView: View {
    let status: Status
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var showingUserProfile = false
    @State private var showingMessageView = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    
    // Check if current user owns this status
    var isOwnStatus: Bool {
        status.userId == firebase.currentUser?.id
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Status Image
            AsyncImage(url: URL(string: status.mediaURL)) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
            
            // Top bar
            VStack {
                HStack {
                    // User info - Make it tappable
                    Button(action: {
                        // Only show profile if it's not the current user's status
                        if !isOwnStatus {
                            showingUserProfile = true
                        }
                    }) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 35, height: 35)
                                .overlay(
                                    Text(String(status.userName?.first ?? "U"))
                                        .foregroundColor(.black)
                                )
                            
                            VStack(alignment: .leading) {
                                Text(status.userName ?? "User")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Text(status.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .disabled(isOwnStatus)
                    
                    Spacer()
                    
                    // Options menu for own status
                    if isOwnStatus {
                        Menu {
                            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                                Label("Delete Status", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding()
                
                Spacer()
                
                // Bottom action bar (if not own status)
                if !isOwnStatus {
                    HStack {
                        Button(action: { showingMessageView = true }) {
                            HStack {
                                Image(systemName: "message")
                                Text("Reply")
                            }
                            .font(.callout)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(20)
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            // Mark as viewed
            await markAsViewed()
        }
        .fullScreenCover(isPresented: $showingUserProfile) {
            NavigationView {
                EnhancedProfileView(userId: status.userId)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") {
                                showingUserProfile = false
                            }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showingMessageView) {
            ChatView(
                recipientId: status.userId,
                contextType: .status,
                contextId: status.id,
                contextData: (
                    title: "Replied to your story",
                    image: status.mediaURL,
                    userId: status.userId
                ),
                isFromContentView: true
            )
        }
        .confirmationDialog("Delete Status?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteStatus()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Your status will be permanently deleted.")
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
    
    private func markAsViewed() async {
        guard let statusId = status.id,
              let userId = firebase.currentUser?.id,
              !status.viewedBy.contains(userId) else { return }
        
        try? await firebase.markStatusAsViewed(statusId)
    }
    
    private func deleteStatus() async {
        guard let statusId = status.id else { return }
        
        isDeleting = true
        
        do {
            try await firebase.deleteStatus(statusId)
            dismiss()
        } catch {
            print("Error deleting status: \(error)")
            isDeleting = false
        }
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
            EditReelCaptionView(reel: reel)
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
    
    private func checkInitialStates() async {
        checkFollowingStatus()
        isLiked = reel.likes.contains(firebase.currentUser?.id ?? "")
        
        if let reelId = reel.id {
            isSaved = await firebase.isItemSaved(itemId: reelId, type: .reel)
        }
    }
    
    // In ReelViewerView struct (around line 1560-1580):
    private func toggleLike() {
        Task {
            do {
                if isLiked {
                    try await ReelRepository.shared.unlikeReel(reel.id ?? "")
                } else {
                    try await ReelRepository.shared.likeReel(reel.id ?? "")
                }
                isLiked.toggle()  // Just toggle, no likesCount
            } catch {
                print("Error toggling like: \(error)")
            }
        }
    }

    // And for deleteReel in ReelViewerView:
    private func deleteReel() async {
        guard let reelId = reel.id else { return }
        
        isDeleting = true
        
        do {
            try await ReelRepository.shared.delete(reelId)
            dismiss()  // NOT onDismiss() - use dismiss
        } catch {
            print("Error deleting reel: \(error)")
            isDeleting = false
        }
    }
    
    private func toggleFollow() {
        Task {
            do {
                if isFollowing {
                    try await firebase.unfollowUser(reel.userId)
                } else {
                    try await firebase.followUser(reel.userId)
                }
                isFollowing.toggle()
            } catch {
                print("Error toggling follow: \(error)")
            }
        }
    }
    
    private func checkFollowingStatus() {
        guard let currentUser = firebase.currentUser else { return }
        isFollowing = currentUser.following.contains(reel.userId)
    }
    
    private func toggleSave() {
        guard let reelId = reel.id else { return }
        
        Task {
            do {
                isSaved = try await firebase.toggleReelSave(reelId)
            } catch {
                print("Error toggling save: \(error)")
            }
        }
    }
    
    private func shareReel() {
        showingShareSheet = true
    }
    
    
}



// Note: CameraView is implemented in a separate file (CameraView.swift)
// It handles the actual camera functionality for capturing photos/videos
