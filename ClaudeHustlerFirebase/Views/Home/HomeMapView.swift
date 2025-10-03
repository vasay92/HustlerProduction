// HomeMapView.swift
// Path: ClaudeHustlerFirebase/Views/Home/HomeMapView.swift

import SwiftUI
import MapKit

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


// Updated PostPreviewCard for HomeMapView.swift
// Now the entire card is tappable and includes a photo preview

struct PostPreviewCard: View {
    let post: ServicePost
    let onDismiss: () -> Void
    @State private var showingFullDetail = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            Capsule()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
            
            // Make entire card content tappable
            Button(action: { showingFullDetail = true }) {
                VStack(alignment: .leading, spacing: 12) {
                    // Header with image preview
                    HStack(alignment: .top, spacing: 12) {
                        // Photo preview (if available)
                        if let firstImageURL = post.imageURLs.first {
                            AsyncImage(url: URL(string: firstImageURL)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipped()
                                        .cornerRadius(10)
                                case .failure(_):
                                    imagePreviewPlaceholder
                                case .empty:
                                    ZStack {
                                        imagePreviewPlaceholder
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .scaleEffect(0.7)
                                    }
                                @unknown default:
                                    imagePreviewPlaceholder
                                }
                            }
                        } else {
                            imagePreviewPlaceholder
                        }
                        
                        // Right side content
                        VStack(alignment: .leading, spacing: 6) {
                            // Badges
                            HStack {
                                // Category Badge
                                HStack(spacing: 4) {
                                    Image(systemName: getIcon())
                                        .font(.caption2)
                                    Text(post.category.displayName)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(post.isRequest ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                                .foregroundColor(post.isRequest ? .orange : .blue)
                                .cornerRadius(12)
                                
                                // Type Badge
                                Text(post.isRequest ? "REQUEST" : "OFFER")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(post.isRequest ? Color.orange : Color.blue)
                                    .cornerRadius(4)
                                
                                Spacer()
                            }
                            
                            // Title
                            Text(post.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            // Price
                            if let price = post.price {
                                Text(post.isRequest ? "Budget: $\(Int(price))" : "$\(Int(price))")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(post.isRequest ? .orange : .green)
                            } else {
                                Text(post.isRequest ? "Budget: Flexible" : "Contact for price")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    // Description Preview
                    Text(post.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Divider()
                    
                    // Bottom section: Location & User
                    HStack {
                        // User info
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text(String(post.userName?.first ?? "U"))
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                )
                            
                            Text(post.userName ?? "Unknown User")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Location
                        if let location = post.location {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.caption2)
                                Text(location)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .foregroundColor(.gray)
                        }
                        
                        // Chevron to indicate tappable
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
                .padding()
            }
            .buttonStyle(PlainButtonStyle()) // Remove default button styling
        }
        .background(Color(.systemBackground))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(radius: 10)
        .frame(maxHeight: 350)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 50 {
                        onDismiss()
                    }
                }
        )
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
    }
    
    @ViewBuilder
    private var imagePreviewPlaceholder: some View {
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
            .frame(width: 80, height: 80)
            .cornerRadius(10)
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: getIcon())
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.8))
                    Text(post.isRequest ? "REQUEST" : "OFFER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.8))
                }
            )
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
