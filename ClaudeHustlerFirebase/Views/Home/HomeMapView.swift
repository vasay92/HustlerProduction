// HomeMapView.swift
// Path: ClaudeHustlerFirebase/Views/Home/HomeMapView.swift

import SwiftUI
import MapKit

struct HomeMapView: View {
    @StateObject private var viewModel = HomeMapViewModel()
    @StateObject private var locationService = LocationService.shared
    @State private var showingCreatePost = false
    @State private var mapSelection: ServicePost?
    
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
                    // Search and Filter Bar
                    VStack(spacing: 12) {
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
                            
                            // Location Button
                            Button(action: viewModel.centerOnUserLocation) {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 40, height: 40)
                                    .background(Color(.systemBackground))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 50)
                    
                    Spacer()
                    
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
                locationService.startUpdatingLocation()
            }
            .onDisappear {
                locationService.stopUpdatingLocation()
            }
            .sheet(isPresented: $showingCreatePost) {
                NavigationView {
                    ServiceFormView()
                }
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

// MARK: - Post Preview Card
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
            
            // Card Content
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    // Category Badge
                    Label(post.category.displayName, systemImage: getIcon())
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(post.isRequest ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                        .foregroundColor(post.isRequest ? .orange : .blue)
                        .cornerRadius(15)
                    
                    Spacer()
                    
                    // Type Badge
                    Text(post.isRequest ? "REQUEST" : "OFFER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(post.isRequest ? Color.orange : Color.blue)
                        .cornerRadius(4)
                }
                
                // Title
                Text(post.title)
                    .font(.headline)
                    .lineLimit(2)
                
                // Description
                Text(post.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                
                // Price and Location
                HStack {
                    if let price = post.price {
                        Label("$\(Int(price))", systemImage: "dollarsign.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    if let location = post.location {
                        Label(location, systemImage: "location.circle.fill")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                // User Info
                HStack {
                    // Avatar
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(post.userName?.first ?? "U"))
                                .font(.caption)
                                .foregroundColor(.white)
                        )
                    
                    Text(post.userName ?? "Unknown User")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // View Details Button
                    Button(action: { showingFullDetail = true }) {
                        Text("View Details")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(radius: 10)
        .frame(maxHeight: 300)
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
            }
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
