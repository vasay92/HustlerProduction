// PortfolioGalleryView.swift
// Path: ClaudeHustlerFirebase/Views/Profile/PortfolioGalleryView.swift

import SwiftUI
import PhotosUI

struct PortfolioGalleryView: View {
    let card: PortfolioCard
    let isOwner: Bool
    @ObservedObject var profileViewModel: ProfileViewModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    
    @State private var showingImagePicker = false
    @State private var newImages: [UIImage] = []
    @State private var singleImage: UIImage? = nil
    @State private var isAddingImages = false
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var mediaURLs: [String] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title at the top
                    Text(card.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    // Show description if available (no "Description" label)
                    if let description = card.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                    }
                    
                    // Show date created (no "Created" label)
                    Text(card.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    // Images Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(Array(mediaURLs.enumerated()), id: \.offset) { index, url in
                            portfolioImageCell(url: url, index: index)
                        }
                        
                        if isOwner {
                            addImagesButton
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingEditSheet) {
                EditPortfolioDetailsView(card: card, profileViewModel: profileViewModel)
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(images: $newImages, singleImage: $singleImage)
                    .onDisappear {
                        if !newImages.isEmpty {
                            Task { await addMoreImages(newImages) }
                        }
                    }
            }
            .confirmationDialog("Delete Portfolio?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task { await deletePortfolioCard() }
                }
            }
        }
        .onAppear {
            mediaURLs = card.mediaURLs
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private func portfolioImageCell(url: String, index: Int) -> some View {
        NavigationLink(destination: ImageViewerView(
            imageURL: url,
            allImageURLs: mediaURLs,
            currentIndex: .constant(index)
        )) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: url)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .clipped()
                        .cornerRadius(12)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 180)
                        .cornerRadius(12)
                        .overlay(ProgressView())
                }
                
                if isOwner && isAddingImages {
                    deleteImageButton(url: url)
                }
            }
        }
    }
    
    @ViewBuilder
    private var addImagesButton: some View {
        Button(action: { showingImagePicker = true }) {
            Rectangle()
                .fill(Color.gray.opacity(0.1))
                .frame(height: 180)
                .cornerRadius(12)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                        Text("Add Images")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                )
        }
        .disabled(isAddingImages)
    }
    
    @ViewBuilder
    private func deleteImageButton(url: String) -> some View {
        Button(action: {
            withAnimation {
                deleteImage(url: url)
            }
        }) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundColor(.white)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
        }
        .padding(4)
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
                        showingDeleteConfirmation = true
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
    
    private func addMoreImages(_ images: [UIImage]) async {
        isAddingImages = true
        
        do {
            guard let userId = firebase.currentUser?.id,
                  let cardId = card.id else { return }
            
            var newURLs: [String] = []
            for (index, image) in images.enumerated() {
                let path = "portfolio/\(userId)/\(cardId)/\(UUID().uuidString)_\(index).jpg"
                let url = try await firebase.uploadImage(image, path: path)
                newURLs.append(url)
            }
            
            mediaURLs.append(contentsOf: newURLs)
            
            var updatedCard = card
            updatedCard.mediaURLs = mediaURLs
            
            try await profileViewModel.updatePortfolioCard(updatedCard)
            
            newImages = []
        } catch {
            print("Error adding images: \(error)")
        }
        
        isAddingImages = false
    }

    private func deleteImage(url: String) {
        mediaURLs.removeAll { $0 == url }
        
        Task {
            do {
                var updatedCard = card
                updatedCard.mediaURLs = mediaURLs
                
                try await profileViewModel.updatePortfolioCard(updatedCard)
            } catch {
                print("Error deleting image: \(error)")
            }
        }
    }
    
    private func deletePortfolioCard() async {
        guard let cardId = card.id else { return }
        
        await profileViewModel.deletePortfolioCard(cardId)
        dismiss()
    }
}

// MARK: - Simple Image Viewer
struct ImageViewerView: View {
    let imageURL: String
    let allImageURLs: [String]
    @Binding var currentIndex: Int
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $currentIndex) {
                ForEach(Array(allImageURLs.enumerated()), id: \.offset) { index, url in
                    AsyncImage(url: URL(string: url)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle())
            
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
                    
                    Text("\(currentIndex + 1) / \(allImageURLs.count)")
                        .foregroundColor(.white)
                        .padding()
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
    @ObservedObject var profileViewModel: ProfileViewModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var isSaving = false
    
    init(card: PortfolioCard, profileViewModel: ProfileViewModel) {
        self.card = card
        self.profileViewModel = profileViewModel
        _title = State(initialValue: card.title)
        _description = State(initialValue: card.description ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Title") {
                    TextField("Portfolio Title", text: $title)
                }
                
                Section("Description") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await saveChanges() }
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
    
    private func saveChanges() async {
        isSaving = true
        
        do {
            var updatedCard = card
            updatedCard.title = title
            updatedCard.description = description.isEmpty ? nil : description
            
            try await profileViewModel.updatePortfolioCard(updatedCard)
            dismiss()
        } catch {
            print("Error saving changes: \(error)")
        }
        
        isSaving = false
    }
}
