// ServicesView.swift
// Path: ClaudeHustlerFirebase/Views/Services/ServicesView.swift

// ServicesView.swift
// Path: ClaudeHustlerFirebase/Views/Services/ServicesView.swift

import SwiftUI

// ONLY REPLACE THIS STRUCT - Keep everything else below it!
struct ServicesView: View {
    @StateObject private var viewModel = ServicesViewModel()  // NEW: Using ViewModel
    @State private var selectedTab: ServiceTab = .offers
    @State private var selectedCategory: ServiceCategory? = nil
    @State private var searchText = ""
    @State private var showingFilters = false
    @State private var viewMode: ViewMode = .grid
    
    enum ServiceTab {
        case offers, requests
    }
    
    enum ViewMode {
        case grid, list
    }
    
    var currentPosts: [ServicePost] {
        selectedTab == .offers ? viewModel.offers : viewModel.requests  // CHANGED: From firebase.offers
    }
    
    var filteredPosts: [ServicePost] {
        var posts = currentPosts
        
        if let category = selectedCategory {
            posts = posts.filter { $0.category == category }
        }
        
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
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Selector for Offers/Requests - Now at the very top
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
                                .fill(selectedTab == .requests ? Color.blue : Color.clear)
                                .frame(height: 3)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 10)
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search \(selectedTab == .offers ? "offers" : "requests")...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.vertical, 5)
                
                // Filter Bar
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            // View Mode Toggle
                            Button(action: { viewMode = viewMode == .grid ? .list : .grid }) {
                                Image(systemName: viewMode == .grid ? "square.grid.3x3" : "list.bullet")
                                    .foregroundColor(.primary)
                            }
                            
                            // Category Filter
                            if let category = selectedCategory {
                                Button(action: { selectedCategory = nil }) {
                                    HStack {
                                        Text(category.displayName)
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(15)
                                }
                            }
                            
                            // Filter Button
                            Button(action: { showingFilters = true }) {
                                HStack {
                                    Image(systemName: "slider.horizontal.3")
                                    Text("Filters")
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.gray.opacity(0.1))
                                .foregroundColor(.primary)
                                .cornerRadius(15)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 5)
                
                // Content
                ScrollView {
                    if filteredPosts.isEmpty && !viewModel.isLoadingOffers && !viewModel.isLoadingRequests {
                        ServicesEmptyStateView(isRequest: selectedTab == .requests)
                            .padding(.top, 50)
                    } else {
                        if viewMode == .grid {
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(filteredPosts) { post in
                                    NavigationLink(destination: PostDetailView(post: post)) {
                                        MinimalServiceCard(post: post, isRequest: post.isRequest)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .onAppear {
                                        // NEW: Load more when reaching the last item
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
                                
                                // NEW: Loading indicator at bottom
                                if (selectedTab == .offers && viewModel.isLoadingOffers) ||
                                   (selectedTab == .requests && viewModel.isLoadingRequests) {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            // List View
                            LazyVStack(spacing: 12) {
                                ForEach(filteredPosts) { post in
                                    NavigationLink(destination: PostDetailView(post: post)) {
                                        ServiceListCard(post: post, isRequest: post.isRequest)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .onAppear {
                                        // NEW: Load more when reaching the last item
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
                                
                                // NEW: Loading indicator
                                if (selectedTab == .offers && viewModel.isLoadingOffers) ||
                                   (selectedTab == .requests && viewModel.isLoadingRequests) {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .refreshable {
                    // NEW: Using ViewModel refresh
                    await viewModel.refresh(type: selectedTab == .offers ? .offers : .requests)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingFilters) {
                EnhancedFiltersView(
                    selectedCategory: $selectedCategory,
                    selectedTab: selectedTab
                )
            }
        }
    }
}



// MARK: - Minimal Service Card (3 per row)
struct MinimalServiceCard: View {
    let post: ServicePost
    let isRequest: Bool
    
    // Calculate card width based on screen size
    private var cardWidth: CGFloat {
        // Screen width minus padding (20) and spacing between cards (20 total for 2 gaps)
        return (UIScreen.main.bounds.width - 40) / 3
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Image Section with Price Overlay - 80% of card
            ZStack(alignment: .bottomTrailing) {
                // Image or Placeholder
                if !post.imageURLs.isEmpty, let firstImageURL = post.imageURLs.first {
                    AsyncImage(url: URL(string: firstImageURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth, height: cardWidth * 1.2) // 80% of total height
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
                
                // Price Overlay on Image
                HStack {
                    if let price = post.price {
                        Text("$\(Int(price))")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(isRequest ? Color.orange : Color.green)
                            )
                    } else {
                        Text(isRequest ? "Flexible" : "Contact")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                            )
                    }
                }
                .padding(6)
            }
            .frame(width: cardWidth, height: cardWidth * 1.2)
            .clipped()
            
            // Title Section - 20% of card
            Text(post.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(.primary)
                .frame(width: cardWidth - 12, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(height: cardWidth * 0.3) // 20% of total height
        }
        .frame(width: cardWidth, height: cardWidth * 1.5) // Total height with aspect ratio
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
    
    var imagePlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: isRequest
                        ? [Color.orange.opacity(0.3), Color.red.opacity(0.3)]
                        : [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
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
    
    func categoryIcon(for category: ServiceCategory) -> String {
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
                    
                    // Request/Offer Badge
                    Text(isRequest ? "REQUEST" : "OFFER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isRequest ? Color.orange : Color.blue)
                        .cornerRadius(4)
                }
                
                Text(post.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    if let price = post.price {
                        Text(isRequest ? "Budget: $\(Int(price))" : "$\(Int(price))")
                            .font(.headline)
                            .foregroundColor(isRequest ? .orange : .green)
                    }
                    
                    Spacer()
                    
                    Text(post.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    var imagePlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: isRequest
                        ? [Color.orange.opacity(0.3), Color.red.opacity(0.3)]
                        : [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 80, height: 80)
            .cornerRadius(10)
            .overlay(
                Image(systemName: "briefcase.fill")
                    .foregroundColor(.white)
            )
    }
}

// MARK: - Enhanced Filters View
struct EnhancedFiltersView: View {
    @Binding var selectedCategory: ServiceCategory?
    let selectedTab: ServicesView.ServiceTab
    @Environment(\.dismiss) private var dismiss
    @State private var priceRange = 0...500.0
    @State private var sortBy = "Newest"
    
    let sortOptions = ["Newest", "Price: Low to High", "Price: High to Low", "Most Popular"]
    
    var body: some View {
        NavigationView {
            Form {
                // Category Section
                Section("Category") {
                    ForEach([nil] + ServiceCategory.allCases.map { $0 as ServiceCategory? }, id: \.self) { category in
                        HStack {
                            Text(category?.displayName ?? "All Categories")
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedCategory == category {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCategory = category
                        }
                    }
                }
                
                Section("Sort By") {
                    Picker("Sort By", selection: $sortBy) {
                        ForEach(sortOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section("Price Range") {
                    VStack {
                        HStack {
                            Text("$\(Int(priceRange.lowerBound))")
                            Spacer()
                            Text("$\(Int(priceRange.upperBound))+")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("Apply Filters") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button("Clear All") {
                        selectedCategory = nil
                        priceRange = 0...500.0
                        sortBy = "Newest"
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Empty State
struct ServicesEmptyStateView: View {
    let isRequest: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isRequest ? "person.fill.questionmark" : "briefcase")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text(isRequest ? "No requests found" : "No services offered")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(isRequest
                ? "Be the first to request a service"
                : "Be the first to offer your services")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
