// PortfolioGalleryView.swift
// Path: ClaudeHustlerFirebase/Views/Profile/PortfolioGalleryView.swift

import SwiftUI
import PhotosUI
import FirebaseFirestore

// MARK: - Identifiable Wrapper for String
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

struct PortfolioGalleryView: View {
    let card: PortfolioCard
    let isOwner: Bool
    @StateObject private var firebase = FirebaseService.shared
    @Environment(\.dismiss) var dismiss
    @State private var selectedImageIndex = 0
    @State private var showingImagePicker = false
    @State private var showingDeleteConfirmation = false
    @State private var showingEditSheet = false
    @State private var showingDescriptionView = false
    @State private var isAddingImages = false
    @State private var newImages: [UIImage] = []
    @State private var imageToDelete: String?
    @State private var mediaItems: [PortfolioMedia] = []
    @State private var selectedImageURL: IdentifiableString?
    
    var allMediaURLs: [String] {
        if !mediaItems.isEmpty {
            return mediaItems.map { $0.url }
        }
        return card.mediaURLs
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        imageGridSection
                    }
                    .padding(.vertical)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    toolbarContent
                }
                
                // Floating Add Button
                if isOwner {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { showingImagePicker = true }) {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                    .shadow(radius: 4)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(images: $newImages, singleImage: nil)
        }
        .sheet(isPresented: $showingDescriptionView) {
            AddPortfolioImagesView(images: newImages, cardId: card.id ?? "")
                .onDisappear {
                    newImages = []
                    Task {
                        await reloadCardData()
                    }
                }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditPortfolioDetailsView(card: card)
        }
        .fullScreenCover(item: $selectedImageURL) { identifiableURL in
            ImageViewerView(
                card: card,
                mediaItems: mediaItems,
                currentURL: identifiableURL.value
            )
        }
        .alert("Delete Photo?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let urlToDelete = imageToDelete {
                    deleteImage(url: urlToDelete)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .onChange(of: newImages) { _, images in
            if !images.isEmpty {
                showingDescriptionView = true
            }
        }
        .onAppear {
            loadMediaItems()
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let description = card.description, !description.isEmpty {
                Text("DESCRIPTION")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            Text("Created \(card.createdAt, style: .date)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var imageGridSection: some View {
        if allMediaURLs.isEmpty {
            emptyStateView
        } else {
            imageGrid
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No photos yet")
                .font(.headline)
                .foregroundColor(.gray)
            
            if isOwner {
                Text("Tap + to add photos")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
    
    @ViewBuilder
    private var imageGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2)
        ], spacing: 2) {
            ForEach(Array(allMediaURLs.enumerated()), id: \.offset) { index, url in
                gridImageItem(at: index, url: url)
            }
        }
        .padding(.horizontal, 2)
    }
    
    @ViewBuilder
    private func gridImageItem(at index: Int, url: String) -> some View {
        let imageSize = UIScreen.main.bounds.width / 3 - 2
        
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: imageSize, height: imageSize)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedImageIndex = index
                            selectedImageURL = IdentifiableString(value: url)
                        }
                case .failure(_):
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: imageSize, height: imageSize)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: imageSize, height: imageSize)
                        .overlay(ProgressView())
                @unknown default:
                    EmptyView()
                }
            }
            
            if isOwner {
                Button(action: {
                    imageToDelete = url
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .padding(4)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Done") { dismiss() }
        }
        
        if isOwner {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingEditSheet = true }) {
                        Label("Edit Title", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive, action: {
                        Task {
                            await deletePortfolioCard()
                        }
                    }) {
                        Label("Delete Portfolio", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadMediaItems() {
        // Load media items from card
        if !card.mediaItems.isEmpty {
            mediaItems = card.mediaItems
        } else {
            // Fallback for old data structure
            mediaItems = card.mediaURLs.map { PortfolioMedia(url: $0, description: "") }
        }
    }
    
    private func reloadCardData() async {
        guard let cardId = card.id else { return }
        
        do {
            let doc = try await Firestore.firestore()
                .collection("portfolioCards")
                .document(cardId)
                .getDocument()
            
            if let updatedCard = try? doc.data(as: PortfolioCard.self) {
                if !updatedCard.mediaItems.isEmpty {
                    mediaItems = updatedCard.mediaItems
                } else {
                    mediaItems = updatedCard.mediaURLs.map { PortfolioMedia(url: $0, description: "") }
                }
            }
        } catch {
            print("Error reloading card: \(error)")
        }
    }
    
    private func deleteImage(url: String) {
        guard let cardId = card.id else { return }
        
        // Remove from local array
        mediaItems.removeAll { $0.url == url }
        
        Task {
            do {
                // Update in Firestore
                let updateData: [String: Any] = [
                    "mediaItems": mediaItems.map { ["url": $0.url, "description": $0.description] },
                    "mediaURLs": mediaItems.map { $0.url },
                    "updatedAt": Date()
                ]
                
                try await Firestore.firestore()
                    .collection("portfolioCards")
                    .document(cardId)
                    .updateData(updateData)
            } catch {
                print("Error deleting image: \(error)")
            }
        }
    }
    
    private func deletePortfolioCard() async {
        guard let cardId = card.id else { return }
        
        do {
            try await Firestore.firestore()
                .collection("portfolioCards")
                .document(cardId)
                .delete()
            
            dismiss()
        } catch {
            print("Error deleting portfolio card: \(error)")
        }
    }
}

// MARK: - Image Viewer for full screen viewing
struct ImageViewerView: View {
    let card: PortfolioCard
    let mediaItems: [PortfolioMedia]
    let currentURL: String
    @Environment(\.dismiss) var dismiss
    @State private var currentIndex: Int = 0
    
    init(card: PortfolioCard, mediaItems: [PortfolioMedia], currentURL: String) {
        self.card = card
        self.mediaItems = mediaItems
        self.currentURL = currentURL
        
        // Set initial index
        if let index = mediaItems.firstIndex(where: { $0.url == currentURL }) {
            self._currentIndex = State(initialValue: index)
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $currentIndex) {
                ForEach(Array(mediaItems.enumerated()), id: \.offset) { index, item in
                    ZStack(alignment: .bottom) {
                        AsyncImage(url: URL(string: item.url)) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        
                        // Description overlay (like Reels)
                        if !item.description.isEmpty {
                            VStack {
                                Spacer()
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.description)
                                            .font(.body)
                                            .foregroundColor(.white)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.black.opacity(0.8),
                                            Color.black.opacity(0.5),
                                            Color.clear
                                        ]),
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                    .edgesIgnoringSafeArea(.bottom)
                                )
                            }
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle())
            
            // Top controls
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
                    
                    Spacer()
                    
                    Text("\(currentIndex + 1) / \(mediaItems.count)")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(20)
                    
                    Spacer()
                    
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding()
                
                Spacer()
            }
        }
    }
}

// MARK: - Edit Portfolio Details View
struct EditPortfolioDetailsView: View {
    let card: PortfolioCard
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var isSaving = false
    
    init(card: PortfolioCard) {
        self.card = card
        _title = State(initialValue: card.title)
        _description = State(initialValue: card.description ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Portfolio Title") {
                    TextField("Enter title", text: $title)
                }
                
                Section("Description") {
                    TextField("Describe your work", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section {
                    Text("Created: \(card.createdAt, style: .date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Last updated: \(card.updatedAt, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await updateDetails()
                        }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay(ProgressView())
                }
            }
        }
    }
    
    private func updateDetails() async {
        guard let cardId = card.id else { return }
        
        isSaving = true
        
        do {
            try await firebase.updatePortfolioCard(
                cardId,
                title: title,
                description: description
            )
            dismiss()
        } catch {
            print("Error updating details: \(error)")
        }
        
        isSaving = false
    }
}
