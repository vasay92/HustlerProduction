// HomeMapView.swift - Fixed with bottom preview card
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
                        .zIndex(1)
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
                    
                    // Bottom section
                    VStack(spacing: 0) {
                        // Filter Chips
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
                        .padding(.bottom, viewModel.showingPostPreview ? 8 : 20)
                        
                        // Post Preview Card - Now at the very bottom
                        if viewModel.showingPostPreview, let post = viewModel.selectedPost {
                            PostPreviewCard(post: post) {
                                viewModel.dismissPostPreview()
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(.spring(), value: viewModel.showingPostPreview)
                        }
                    }
                }
                
                // Invisible overlay for dismissing preview
                if viewModel.showingPostPreview {
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.dismissPostPreview()
                        }
                        .allowsHitTesting(true)
                        .zIndex(-1)
                }
                
                // FAB for creating posts
                if !viewModel.showingPostPreview {
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
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(), value: viewModel.showingPostPreview)
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

// PostPreviewCard - Fixed compact version at bottom
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
            // Handle bar
            Capsule()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.vertical, 8)
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
            
            // Content - NO SCROLLVIEW, compact layout
            VStack(alignment: .leading, spacing: 8) {
                // Title and Badge Row
                HStack(alignment: .top, spacing: 8) {
                    Text(post.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
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
                
                // User Info - compact
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String(posterInfo?.name.first ?? post.userName?.first ?? "U"))
                                .font(.caption2)
                                .foregroundColor(.white)
                        )
                    
                    Text(posterInfo?.name ?? post.userName ?? "Unknown")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let rating = posterInfo?.rating, posterInfo?.reviewCount ?? 0 > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(String(format: "%.1f", rating))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                // Description - 2 lines max
                Text(post.description)
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                
                // Photos - smaller
                if !post.imageURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(post.imageURLs.prefix(3).enumerated()), id: \.offset) { index, imageURL in
                                AsyncImage(url: URL(string: imageURL)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipped()
                                            .cornerRadius(8)
                                    default:
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 80, height: 80)
                                            .cornerRadius(8)
                                    }
                                }
                                .overlay(
                                    Group {
                                        if index == 2 && post.imageURLs.count > 3 {
                                            Rectangle()
                                                .fill(Color.black.opacity(0.6))
                                                .cornerRadius(8)
                                                .overlay(
                                                    Text("+\(post.imageURLs.count - 3)")
                                                        .font(.headline)
                                                        .fontWeight(.bold)
                                                        .foregroundColor(.white)
                                                )
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 80)
                }
                
                Spacer(minLength: 12)
                
                // Action Buttons
                HStack(spacing: 10) {
                    Button(action: {
                        if post.userId != firebase.currentUser?.id {
                            showingMessageView = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "message.fill")
                                .font(.system(size: 14))
                            Text("Message")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(post.userId == firebase.currentUser?.id ? Color.gray : Color.blue)
                        .cornerRadius(8)
                    }
                    .disabled(post.userId == firebase.currentUser?.id)
                    
                    HStack(spacing: 6) {
                        Button(action: { toggleSave() }) {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 16))
                                .foregroundColor(isSaved ? .blue : .gray)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                        
                        Button(action: { showingShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "flag")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showingFullDetail = true
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(radius: 10)
        .frame(height: 300) // Fixed compact height
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
    
    // Helper functions...
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
}

// Keep your existing PostMapAnnotation and other structs...
struct PostMapAnnotation: View {
    let post: ServicePost
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(post.isRequest ? Color.orange : Color.blue)
                .frame(width: isSelected ? 50 : 40, height: isSelected ? 50 : 40)
            
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
