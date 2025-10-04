// ServicesView.swift
// Path: ClaudeHustlerFirebase/Views/Services/ServicesView.swift
// COPY THIS ENTIRE FILE AND REPLACE YOUR EXISTING ServicesView.swift

import SwiftUI

struct ServicesView: View {
    
        @StateObject private var viewModel = ServicesViewModel()
        @State private var selectedTab: ServiceTab = .offers
        @State private var selectedCategory: ServiceCategory? = nil
        @State private var searchText = ""
        @State private var showingFilters = false
        @State private var viewMode: ViewMode = .grid
        @State private var showingCreatePost = false
        
        enum ServiceTab {
            case offers, requests
        }
        
        enum ViewMode {
            case grid, list
        }
        
        var currentPosts: [ServicePost] {
            selectedTab == .offers ? viewModel.offers : viewModel.requests
        }
        
        var filteredPosts: [ServicePost] {
            var posts = currentPosts
            
            
            
            if !searchText.isEmpty {
                posts = posts.filter {
                    $0.title.localizedCaseInsensitiveContains(searchText) ||
                    $0.description.localizedCaseInsensitiveContains(searchText)
                }
            }
            
            return posts
        }
        
        // 3 columns for grid
        let columns = [
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2)
        ]
        
        var body: some View {
            NavigationView {
                VStack(spacing: 0) {
                    // Tab Selector
                    HStack(spacing: 0) {
                        Button(action: { selectedTab = .offers }) {
                            VStack(spacing: 4) {
                                Text("Offers")
                                    .font(.headline)
                                    .foregroundColor(selectedTab == .offers ? .primary : .gray)
                                
                                Rectangle()
                                    .fill(selectedTab == .offers ? Color.blue : Color.clear)
                                    .frame(height: 3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        Button(action: { selectedTab = .requests }) {
                            VStack(spacing: 4) {
                                Text("Requests")
                                    .font(.headline)
                                    .foregroundColor(selectedTab == .requests ? .primary : .gray)
                                
                                Rectangle()
                                    .fill(selectedTab == .requests ? Color.orange : Color.clear)
                                    .frame(height: 3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Search services...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    // Filter Bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            // View Mode Toggle
                            Button(action: {
                                viewMode = viewMode == .grid ? .list : .grid
                            }) {
                                Image(systemName: viewMode == .grid ? "square.grid.3x3" : "list.bullet")
                                    .foregroundColor(.blue)
                                    .padding(8)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            
                            // Category Filters
                            ForEach(ServiceCategory.allCases, id: \.self) { category in
                                Button(action: {
                                    selectedCategory = selectedCategory == category ? nil : category
                                }) {
                                    Text(category.displayName)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedCategory == category ? Color.blue : Color(.systemGray6))
                                        .foregroundColor(selectedCategory == category ? .white : .primary)
                                        .cornerRadius(15)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                    
                    // Main Content
                    ScrollView {
                        if filteredPosts.isEmpty {
                            EmptyStateView(
                                icon: "magnifyingglass",
                                title: "No Services Found",
                                message: selectedTab == .offers
                                    ? "Be the first to offer services!"
                                    : "No service requests yet.",
                                buttonTitle: selectedTab == .offers ? "Create Offer" : "Create Request",
                                action: {
                                    showingCreatePost = true
                                }
                            )
                            .padding(.top, 50)
                        } else {
                            if viewMode == .grid {
                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(filteredPosts) { post in
                                        NavigationLink(destination: PostDetailView(post: post)) {
                                            MinimalServiceCard(post: post, isRequest: post.isRequest)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .onAppear {
                                            // Load more when reaching the last item
                                            if post.id == filteredPosts.last?.id {
                                                Task {
                                                    if selectedTab == .offers && viewModel.offersHasMore {
                                                        await viewModel.loadMoreOffers()
                                                    } else if selectedTab == .requests && viewModel.requestsHasMore {
                                                        await viewModel.loadMoreRequests()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    
                                    // Loading indicator
                                    if (selectedTab == .offers && viewModel.isLoadingOffers) ||
                                       (selectedTab == .requests && viewModel.isLoadingRequests) {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                    }
                                }
                                .padding(.horizontal, 5)  // ← CHANGED: From .padding(.horizontal) to match Reels grid
                            } else {
                                // List View
                                LazyVStack(spacing: 12) {
                                    ForEach(filteredPosts) { post in
                                        NavigationLink(destination: PostDetailView(post: post)) {
                                            ServiceListCard(post: post, isRequest: post.isRequest)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .onAppear {
                                            if post.id == filteredPosts.last?.id {
                                                Task {
                                                    if selectedTab == .offers && viewModel.offersHasMore {
                                                        await viewModel.loadMoreOffers()
                                                    } else if selectedTab == .requests && viewModel.requestsHasMore {
                                                        await viewModel.loadMoreRequests()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    
                                    if (selectedTab == .offers && viewModel.isLoadingOffers) ||
                                       (selectedTab == .requests && viewModel.isLoadingRequests) {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                    }
                                }
                                .padding(.horizontal)  // ← KEEP AS IS for list view
                            }
                        }
                    }
                    .refreshable {
                        await viewModel.refresh(type: selectedTab == .offers ? .offers : .requests)
                    }
                }
                .navigationBarHidden(true)
    //            .sheet(isPresented: $showingFilters) {
    //                EnhancedFiltersView(
    //                    selectedCategory: $selectedCategory,
    //                    selectedTab: selectedTab
    //                )
    //            }
                .sheet(isPresented: $showingCreatePost) {
                    ServiceFormView(isRequest: selectedTab == .requests)
                }
            }
        }
    }


// MARK: - Minimal Service Card (for grid view)
struct MinimalServiceCard: View {
    let post: ServicePost
    let isRequest: Bool
    
    private var cardWidth: CGFloat {
        (UIScreen.main.bounds.width - 4) / 3  // Changed for tighter spacing
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Image Section (removed price overlay)
            ZStack {
                if !post.imageURLs.isEmpty, let firstImageURL = post.imageURLs.first {
                    AsyncImage(url: URL(string: firstImageURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth, height: cardWidth * 1.2)
                                .clipped()
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
                
                // NO MORE PRICE OVERLAY HERE
            }
            
            // Title and Category Section (kept, but removed price)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                Text(post.category.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // REMOVED PRICE TEXT HERE
            }
            .frame(width: cardWidth, alignment: .leading)
            .padding(4)
        }
        .background(Color(UIColor.systemBackground))
        // REMOVED .cornerRadius(10) - now square edges
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var imagePlaceholder: some View {
        Rectangle()  // No cornerRadius - square edges
            .fill(
                LinearGradient(
                    colors: isRequest ?
                        [Color.orange.opacity(0.3), Color.red.opacity(0.3)] :
                        [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: cardWidth, height: cardWidth * 1.2)
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: categoryIcon(for: post.category))
                        .font(.title2)
                        .foregroundColor(.white)
                    Text(isRequest ? "REQUEST" : "OFFER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            )
    }
    
    
}

// MARK: - Service List Card (for list view)
struct ServiceListCard: View {
    let post: ServicePost
    let isRequest: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Image or placeholder
            if !post.imageURLs.isEmpty, let firstImageURL = post.imageURLs.first {
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
                HStack {
                    Text(post.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(isRequest ? "REQUEST" : "OFFER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isRequest ? Color.orange : Color.blue)
                        .cornerRadius(12)
                }
                
                Text(post.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Label(post.category.displayName, systemImage: categoryIcon(for: post.category))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let price = post.price {
                        Text("$\(Int(price))")
                            .font(.headline)
                            .foregroundColor(isRequest ? .orange : .green)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: isRequest
                        ? [Color.orange.opacity(0.3), Color.red.opacity(0.3)]
                        : [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]
                    ),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: categoryIcon(for: post.category))
                    .font(.title2)
                    .foregroundColor(.white)
            )
    }
    
    
}
