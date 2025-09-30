// HomeView.swift
// Path: ClaudeHustlerFirebase/Views/Home/HomeView.swift

import SwiftUI
import FirebaseFirestore

struct HomeView: View {
    @StateObject private var firebase = FirebaseService.shared
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var notificationsViewModel = NotificationsViewModel()
    @State private var showingMessages = false
    @State private var showingNotifications = false
    @State private var showingCategories = false
    @State private var showingCreatePost = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Custom Navigation Bar
                    HStack {
                        Text("Hustler")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Spacer()
                        
                        // Top-right buttons
                        HStack(spacing: 12) {
                            // Notifications button with badge
                            Button(action: { showingNotifications = true }) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "bell")
                                        .font(.title2)
                                        .foregroundColor(.primary)
                                    
                                    // Unread badge for BELL notifications only
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
                            
                            // Messages button with badge
                            Button(action: { showingMessages = true }) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "message")
                                        .font(.title2)
                                        .foregroundColor(.primary)
                                    
                                    // Unread badge for MESSAGE notifications
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
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    // Search Bar with Categories button
                    HStack(spacing: 10) {
                        // Search field
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            
                            TextField("Search services...", text: $viewModel.searchText)
                                .textFieldStyle(PlainTextFieldStyle())
                            
                            if !viewModel.searchText.isEmpty {
                                Button(action: { viewModel.searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        
                        // Categories button
                        Button(action: { showingCategories = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.grid.2x2")
                                Text("Categories")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                    
                    // Content Section with Loading States
                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        // INITIAL LOADING - Show skeletons
                        VStack(spacing: 15) {
                            ForEach(0..<5, id: \.self) { _ in
                                ServiceCardSkeleton()
                            }
                        }
                        .padding(.horizontal)
                    } else if viewModel.posts.isEmpty && !viewModel.isLoading {
                        // EMPTY STATE - No posts exist
                        EmptyStateView(
                            icon: "house",
                            title: "No Posts Yet",
                            message: "Be the first to share something with the community!",
                            buttonTitle: "Create Post",
                            action: {
                                showingCreatePost = true
                            }
                        )
                        .frame(minHeight: 400)
                    } else {
                        // CONTENT EXISTS - Show actual posts
                        
                        // Trending Services Section
                        if !viewModel.trendingPosts.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("Trending", systemImage: "flame.fill")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 15) {
                                        ForEach(viewModel.trendingPosts) { post in
                                            NavigationLink(destination: PostDetailView(post: post)) {
                                                MiniServiceCard(post: post)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        // Recent Activity
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recent Activity")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            if viewModel.filteredPosts.isEmpty && !searchText.isEmpty {
                                // Search empty state
                                EmptyStateView(
                                    icon: "magnifyingglass",
                                    title: "No Results Found",
                                    message: "Try adjusting your search or filters",
                                    buttonTitle: "Clear Search",
                                    action: {
                                        viewModel.updateSearchText("")
                                    }
                                )
                                .frame(height: 300)
                            } else {
                                LazyVStack(spacing: 15) {
                                    ForEach(viewModel.filteredPosts) { post in
                                        NavigationLink(destination: PostDetailView(post: post)) {
                                            ServicePostCard(post: post)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .onAppear {
                                            // Load more when reaching the last item
                                            if post.id == viewModel.filteredPosts.last?.id && viewModel.hasMore {
                                                Task {
                                                    await viewModel.loadMorePosts()
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Loading indicator for pagination
                        if viewModel.isLoading && !viewModel.posts.isEmpty {
                            ProgressView()
                                .padding()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .refreshable {
                await viewModel.refresh()
            }
            .sheet(isPresented: $showingCategories) {
                CategoriesView()
            }
            .fullScreenCover(isPresented: $showingNotifications) {
                NotificationsView()  // REMOVED NavigationView wrapper
            }
            .fullScreenCover(isPresented: $showingMessages) {
                ConversationsListView()  // REMOVED NavigationView wrapper
            }
            .sheet(isPresented: $showingCreatePost) {
                NavigationView {  // Keep this one as sheets often need the wrapper
                    ServiceFormView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Cancel") {
                                    showingCreatePost = false
                                }
                            }
                        }
                }
            }
            .onAppear {
                notificationsViewModel.startListening()
            }
            .onDisappear {
                notificationsViewModel.stopListening()
            }
        }
    }
    
    // MARK: - Computed Properties
    private var searchText: String {
        viewModel.searchText
    }
    
    // MARK: - Service Post Card
    struct ServicePostCard: View {
        let post: ServicePost
        @StateObject private var firebase = FirebaseService.shared
        @State private var isSaved = false
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                // Image section if images exist
                if !post.imageURLs.isEmpty {
                    TabView {
                        ForEach(post.imageURLs, id: \.self) { imageURL in
                            CachedAsyncImage(url: imageURL) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundColor(.gray)
                                    )
                            }
                            .frame(height: 200)
                            .clipped()
                        }
                    }
                    .frame(height: 200)
                    .tabViewStyle(PageTabViewStyle())
                    .cornerRadius(12)
                }
                
                // Header
                HStack {
                    // User info
                    HStack(spacing: 10) {
                        UserAvatar(
                            imageURL: post.userProfileImage,
                            userName: post.userName,
                            size: 40
                        )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.userName ?? "User")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 4) {
                                if let location = post.location, !location.isEmpty {
                                    Image(systemName: "location")
                                        .font(.caption2)
                                    Text(location)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Image(systemName: "location")
                                        .font(.caption2)
                                    Text("Aurora")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        if post.isRequest {
                            Text("REQUEST")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        Text(post.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Title and Description
                VStack(alignment: .leading, spacing: 6) {
                    Text(post.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(post.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Footer
                HStack {
                    // Price
                    if let price = post.price {
                        Text("$\(Int(price))")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    
                    // Category
                    Text(post.category.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    // Actions
                    HStack(spacing: 15) {
                        Button(action: { toggleSave() }) {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .foregroundColor(isSaved ? .blue : .gray)
                                .scaleEffect(isSaved ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: isSaved)
                        }
                        
                        Image(systemName: "bubble.right")
                            .foregroundColor(.gray)
                        
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            .task {
                await checkSaveStatus()
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
    
    // MARK: - Mini Service Card (Trending)
    struct MiniServiceCard: View {
        let post: ServicePost
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Image or placeholder
                if !post.imageURLs.isEmpty, let firstImageURL = post.imageURLs.first {
                    AsyncImage(url: URL(string: firstImageURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 150, height: 150)
                                .clipped()
                                .cornerRadius(10)
                        case .failure(_):
                            imagePlaceholder
                        case .empty:
                            ZStack {
                                imagePlaceholder
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                        @unknown default:
                            imagePlaceholder
                        }
                    }
                } else {
                    imagePlaceholder
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                    
                    if let price = post.price {
                        Text("$\(Int(price))")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                }
            }
            .frame(width: 150)
            .padding(10)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        
        private var imagePlaceholder: some View {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 150, height: 150)
                .cornerRadius(10)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.white)
                        .font(.largeTitle)
                )
        }
    }
    
    // MARK: - Categories View
    struct CategoriesView: View {
        @Environment(\.dismiss) var dismiss
        @State private var selectedCategory: ServiceCategory?
        
        let columns = [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ]
        
        let categories = ServiceCategory.allCases
        
        var body: some View {
            NavigationView {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 15) {
                        ForEach(categories, id: \.self) { category in
                            Button(action: {
                                selectedCategory = category
                                // TODO: Apply category filter
                                dismiss()
                            }) {
                                VStack(spacing: 8) {
                                    Image(systemName: getCategoryIcon(for: category))
                                        .font(.title2)
                                        .frame(width: 50, height: 50)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(10)
                                    
                                    Text(category.displayName)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.systemGray6))
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                }
                .navigationTitle("Categories")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        
        private func getCategoryIcon(for category: ServiceCategory) -> String {
            switch category {
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
}
