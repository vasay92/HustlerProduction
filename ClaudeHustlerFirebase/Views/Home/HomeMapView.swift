// HomeMapView.swift
// Path: ClaudeHustlerFirebase/Views/Home/HomeMapView.swift

import SwiftUI
import MapKit
import FirebaseFirestore

struct HomeMapView: View {
    @StateObject private var viewModel = HomeMapViewModel()
    @StateObject private var locationService = LocationService.shared
    @State private var showingCreatePost = false
    @State private var mapSelection: ServicePost?
    @StateObject private var notificationsViewModel = NotificationsViewModel()
    @State private var showingNotifications = false
    @State private var showingMessages = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Map View
                Map(
                    coordinateRegion: $viewModel.mapRegion,
                    showsUserLocation: true,
                    annotationItems: viewModel.filteredPosts
                ) { post in
                    MapAnnotation(coordinate: post.coordinate) {
                        PostMapAnnotation(
                            post: post,
                            isSelected: viewModel.selectedPost?.id == post.id
                        )
                        .onTapGesture {
                            viewModel.selectPost(post)
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)
                
                // Top Controls Overlay
                VStack {
                    // Top Section with search bar and buttons
                    HStack(alignment: .top, spacing: 12) {
                        // Search Bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            
                            TextField("Search offers and requests...", text: $viewModel.searchText)
                                .textFieldStyle(PlainTextFieldStyle())
                                .onChange(of: viewModel.searchText) { _ in
                                    viewModel.filterPosts()
                                }
                            
                            if !viewModel.searchText.isEmpty {
                                Button(action: {
                                    viewModel.searchText = ""
                                    viewModel.filterPosts()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 2)
                        
                        // Notifications button
                        Button(action: { showingNotifications = true }) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                    .background(Color(.systemBackground))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                                
                                // Unread badge
                                if notificationsViewModel.bellNotificationCount > 0 {
                                    Text("\(min(notificationsViewModel.bellNotificationCount, 99))")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .padding(.horizontal, notificationsViewModel.bellNotificationCount > 9 ? 4 : 0)
                                        .background(Color.red)
                                        .clipShape(Capsule())
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        
                        // Vertical stack for messages button and zoom/location controls
                        VStack(spacing: 8) {
                            // Messages button
                            Button(action: { showingMessages = true }) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "message")
                                        .font(.title2)
                                        .foregroundColor(.primary)
                                        .frame(width: 40, height: 40)
                                        .background(Color(.systemBackground))
                                        .clipShape(Circle())
                                        .shadow(radius: 2)
                                    
                                    // Unread badge
                                    if notificationsViewModel.messageNotificationCount > 0 {
                                        Text("\(min(notificationsViewModel.messageNotificationCount, 99))")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .frame(minWidth: 16, minHeight: 16)
                                            .padding(.horizontal, notificationsViewModel.messageNotificationCount > 9 ? 4 : 0)
                                            .background(Color.blue)
                                            .clipShape(Capsule())
                                            .offset(x: 8, y: -8)
                                    }
                                }
                            }
                            
                            // Zoom in
                            Button(action: { viewModel.zoomIn() }) {
                                Image(systemName: "plus")
                                    .foregroundColor(.blue)
                                    .frame(width: 36, height: 36)
                                    .background(Color(.systemBackground))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                            
                            // Zoom out
                            Button(action: { viewModel.zoomOut() }) {
                                Image(systemName: "minus")
                                    .foregroundColor(.blue)
                                    .frame(width: 36, height: 36)
                                    .background(Color(.systemBackground))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                            
                            // Location button
                            Button(action: viewModel.centerOnUserLocation) {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 36, height: 36)
                                    .background(Color(.systemBackground))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 50) // Safe area padding
                    
                    Spacer()
                    
                    // Bottom Filter Chips (horizontal)
                    HStack(spacing: 12) {
                        FilterChip(
                            title: "Offers",
                            isSelected: viewModel.showOnlyOffers,
                            color: .blue,
                            action: viewModel.toggleOfferFilter
                        )
                        
                        FilterChip(
                            title: "Requests",
                            isSelected: viewModel.showOnlyRequests,
                            color: .orange,
                            action: viewModel.toggleRequestFilter
                        )
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    
                    // Post Preview Card
                    if viewModel.showingPostPreview, let post = viewModel.selectedPost {
                        PostPreviewCard(post: post) {
                            viewModel.dismissPostPreview()
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(), value: viewModel.showingPostPreview)
                    }
                }
                
                // FAB for creating posts
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showingCreatePost = true }) {
                            Image(systemName: "plus")
                                .font(.title2)
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
            .navigationBarHidden(true)
            .task {
                await viewModel.loadPosts()
                print("🗺️ Loaded \(viewModel.filteredPosts.count) posts with coordinates")
                locationService.startUpdatingLocation()
                notificationsViewModel.startListening()
            }
            .onDisappear {
                locationService.stopUpdatingLocation()
                notificationsViewModel.stopListening()
            }
            .sheet(isPresented: $showingCreatePost) {
                NavigationView {
                    ServiceFormView()
                }
            }
            .fullScreenCover(isPresented: $showingNotifications) {
                NotificationsView()
            }
            .fullScreenCover(isPresented: $showingMessages) {
                ConversationsListView()
            }
        }
    }
}

// MARK: - Post Map Annotation View
struct PostMapAnnotation: View {
    let post: ServicePost
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(post.isRequest ? Color.orange : Color.blue)
                .frame(width: isSelected ? 50 : 40, height: isSelected ? 50 : 40)
            
            // Icon
            Image(systemName: getIcon())
                .foregroundColor(.white)
                .font(.system(size: isSelected ? 22 : 18))
        }
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        .shadow(radius: isSelected ? 8 : 4)
    }
    
    private func getIcon() -> String {
        switch post.category {
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


// PostPreviewCard - With action buttons matching PostDetailView
struct PostPreviewCard: View {
    let post: ServicePost
    let onDismiss: () -> Void
    @State private var showingFullDetail = false
    @State private var dragOffset: CGSize = .zero
    @State private var posterInfo: User?
    @State private var isSaved = false
    @State private var showingMessageView = false
    @State private var showingShareSheet = false
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle bar - minimal padding
            Capsule()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            if value.translation.height > 50 {
                                onDismiss()
                            } else {
                                withAnimation {
                                    dragOffset = .zero
                                }
                            }
                        }
                )
            
            // Make entire card content tappable
            Button(action: { showingFullDetail = true }) {
                VStack(alignment: .leading, spacing: 8) {
                    // 1. Title and Badge Row - NO TOP PADDING
                    HStack(alignment: .top, spacing: 8) {
                        Text(post.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Type Badge (OFFER/REQUEST)
                        Text(post.isRequest ? "REQUEST" : "OFFER")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(post.isRequest ? Color.orange : Color.blue)
                            .cornerRadius(4)
                    }
                    .padding(.horizontal)
                    .padding(.top, 0)
                    
                    // 2. User Info with Rating
                    HStack(spacing: 8) {
                        // User profile photo or initial
                        if let profileImageURL = posterInfo?.profileImageURL, !profileImageURL.isEmpty {
                            AsyncImage(url: URL(string: profileImageURL)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 32, height: 32)
                                        .clipShape(Circle())
                                case .failure(_):
                                    profileInitialCircle
                                case .empty:
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            ProgressView()
                                                .scaleEffect(0.5)
                                        )
                                @unknown default:
                                    profileInitialCircle
                                }
                            }
                        } else {
                            profileInitialCircle
                        }
                        
                        // User name
                        Text(posterInfo?.name ?? post.userName ?? "Unknown User")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Rating stars with actual data
                        if let rating = posterInfo?.rating, let reviewCount = posterInfo?.reviewCount {
                            HStack(spacing: 2) {
                                ForEach(0..<5) { index in
                                    Image(systemName: getRatingIcon(for: Double(index), rating: rating))
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                if reviewCount > 0 {
                                    Text("(\(reviewCount))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // 3. Description
                    Text(post.description)
                        .font(.subheadline)
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    // 4. Photos Section
                    if !post.imageURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(post.imageURLs.prefix(4).enumerated()), id: \.offset) { index, imageURL in
                                    ZStack(alignment: .center) {
                                        AsyncImage(url: URL(string: imageURL)) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 100, height: 100)
                                                    .clipped()
                                                    .cornerRadius(10)
                                            case .failure(_):
                                                imagePlaceholder(for: index)
                                            case .empty:
                                                ZStack {
                                                    imagePlaceholder(for: index)
                                                    ProgressView()
                                                        .progressViewStyle(CircularProgressViewStyle())
                                                        .scaleEffect(0.7)
                                                }
                                            @unknown default:
                                                imagePlaceholder(for: index)
                                            }
                                        }
                                        
                                        // Show "+X" overlay on last image if more than 4 photos
                                        if index == 3 && post.imageURLs.count > 4 {
                                            Rectangle()
                                                .fill(Color.black.opacity(0.6))
                                                .frame(width: 100, height: 100)
                                                .cornerRadius(10)
                                                .overlay(
                                                    Text("+\(post.imageURLs.count - 4)")
                                                        .font(.title2)
                                                        .fontWeight(.bold)
                                                        .foregroundColor(.white)
                                                )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 100)
                    } else {
                        // No images placeholder
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        post.isRequest ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1),
                                        post.isRequest ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 100)
                            .cornerRadius(10)
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: getIcon())
                                        .font(.title)
                                        .foregroundColor(post.isRequest ? .orange : .blue).opacity(0.5)
                                    Text("No photos")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            )
                            .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // 5. Action Buttons Section (Same as PostDetailView)
            HStack(spacing: 0) {
                // Message Button
                Button(action: {
                    if post.userId != firebase.currentUser?.id {
                        showingMessageView = true
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "message")
                            .font(.title3)
                        Text("Message")
                            .font(.caption2)
                    }
                    .foregroundColor(post.userId == firebase.currentUser?.id ? .gray : .primary)
                    .frame(maxWidth: .infinity)
                }
                .disabled(post.userId == firebase.currentUser?.id)
                
                // Save Button
                Button(action: { toggleSave() }) {
                    VStack(spacing: 4) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.title3)
                        Text(isSaved ? "Saved" : "Save")
                            .font(.caption2)
                    }
                    .foregroundColor(isSaved ? .blue : .primary)
                    .frame(maxWidth: .infinity)
                }
                
                // Share Button
                Button(action: { showingShareSheet = true }) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                        Text("Share")
                            .font(.caption2)
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                }
                
                // Report Button
                Button(action: {
                    // TODO: Implement report functionality (same as PostDetailView)
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "flag")
                            .font(.title3)
                        Text("Report")
                            .font(.caption2)
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
        }
        .background(Color(.systemBackground))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(radius: 10)
        .frame(maxHeight: 380) // Increased to accommodate buttons
        .offset(y: dragOffset.height)
        .task {
            await loadPosterInfo()
            await checkSaveStatus()
        }
        .fullScreenCover(isPresented: $showingFullDetail) {
            NavigationView {
                PostDetailView(post: post)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") {
                                showingFullDetail = false
                            }
                            .fontWeight(.medium)
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showingMessageView) {
            ChatView(
                recipientId: post.userId,
                contextType: .post,
                contextId: post.id,
                contextData: (
                    title: post.title,
                    image: post.imageURLs.first,
                    userId: post.userId
                ),
                isFromContentView: true
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [post.title, post.description])
        }
    }
    
    // MARK: - Helper Views and Functions
    
    @ViewBuilder
    private var profileInitialCircle: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 32, height: 32)
            .overlay(
                Text(String(posterInfo?.name.first ?? post.userName?.first ?? "U"))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            )
    }
    
    private func imagePlaceholder(for index: Int) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 100, height: 100)
            .cornerRadius(10)
            .overlay(
                Image(systemName: "photo")
                    .foregroundColor(.gray.opacity(0.5))
            )
    }
    
    private func loadPosterInfo() async {
        do {
            let document = try await Firestore.firestore()
                .collection("users")
                .document(post.userId)
                .getDocument()
            
            if document.exists {
                posterInfo = try? document.data(as: User.self)
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
    
    private func getRatingIcon(for index: Double, rating: Double) -> String {
        if rating >= index + 1 {
            return "star.fill"
        } else if rating >= index + 0.5 {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
    
    private func getIcon() -> String {
        switch post.category {
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








// MARK: - Filter Chip View
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? color : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

// MARK: - Helper Extensions
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - ServicePost Extension for Map
extension ServicePost {
    var coordinate: CLLocationCoordinate2D {
        guard let geoPoint = coordinates else {
            return CLLocationCoordinate2D()
        }
        return CLLocationCoordinate2D(
            latitude: geoPoint.latitude,
            longitude: geoPoint.longitude
        )
    }
}
