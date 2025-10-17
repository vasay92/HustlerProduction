// PortfolioGalleryView.swift - FIXED with proper multi-image selection
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
    @State private var isAddingImages = false
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var mediaURLs: [String] = []
    
    // Grid configuration for uniform squares like iPhone Photos
    private let columns = 3
    private let spacing: CGFloat = 2
    private var gridItemSize: CGFloat {
        let totalSpacing = spacing * CGFloat(columns - 1)
        let width = UIScreen.main.bounds.width - totalSpacing
        return width / CGFloat(columns)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title at the top
                        Text(card.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        // Show description if available
                        if let description = card.description, !description.isEmpty {
                            Text(description)
                                .font(.body)
                                .foregroundColor(.primary)
                                .padding(.horizontal)
                        }
                        
                        // Show date created
                        Text(card.createdAt, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        // Images Grid - 3 columns with uniform squares
                        LazyVGrid(columns: [
                            GridItem(.fixed(gridItemSize), spacing: spacing),
                            GridItem(.fixed(gridItemSize), spacing: spacing),
                            GridItem(.fixed(gridItemSize), spacing: spacing)
                        ], spacing: spacing) {
                            ForEach(Array(mediaURLs.enumerated()), id: \.offset) { index, url in
                                portfolioImageCell(url: url, index: index)
                            }
                        }
                        .padding(.horizontal, 0)
                        .padding(.bottom, isOwner ? 80 : 20) // Extra padding if FAB is shown
                    }
                }
                
                // Floating Action Button (bottom right corner)
                if isOwner {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { showingImagePicker = true }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 60, height: 60)
                                    
                                    Image(systemName: "plus")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                            }
                            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingEditSheet) {
                EditPortfolioDetailsView(card: card, profileViewModel: profileViewModel)
            }
            .sheet(isPresented: $showingImagePicker) {
                MultiImagePickerForPortfolio(images: $newImages)
                    .onDisappear {
                        if !newImages.isEmpty {
                            Task {
                                await addMoreImages(newImages)
                            }
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
            // Initialize mediaURLs from card
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
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: gridItemSize, height: gridItemSize)
                            .clipped()
                            
                    case .failure(_):
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: gridItemSize, height: gridItemSize)
                            .overlay(
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.gray)
                            )
                            
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: gridItemSize, height: gridItemSize)
                            .overlay(ProgressView())
                            
                    @unknown default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: gridItemSize, height: gridItemSize)
                    }
                }
                
                // Show delete button when in edit mode
                if isOwner && isAddingImages {
                    Button(action: {
                        withAnimation {
                            deleteImage(url: url)
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .padding(4)
                }
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
                        Label("Edit Details", systemImage: "pencil")
                    }
                    
                    Button(action: {
                        withAnimation {
                            isAddingImages.toggle()
                        }
                    }) {
                        Label(isAddingImages ? "Done Editing" : "Edit Photos", systemImage: "square.and.pencil")
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
        guard !images.isEmpty else { return }
        
        // Show loading state
        isAddingImages = true
        
        do {
            guard let userId = firebase.currentUser?.id,
                  let cardId = card.id else {
                isAddingImages = false
                return
            }
            
            
            var newURLs: [String] = []
            
            for (index, image) in images.enumerated() {
                let path = "portfolio/\(userId)/\(cardId)/\(UUID().uuidString)_\(index).jpg"
                
                let url = try await firebase.uploadImage(image, path: path)
                newURLs.append(url)
            }
            
            
            // Update local state immediately
            await MainActor.run {
                mediaURLs.append(contentsOf: newURLs)
            }
            
            // Update the card in Firestore
            var updatedCard = card
            updatedCard.mediaURLs = mediaURLs
            
            try await profileViewModel.updatePortfolioCard(updatedCard)
            
            // Clear the selected images
            newImages = []
            
        } catch {
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
                
            }
        }
    }
    
    private func deletePortfolioCard() async {
        guard let cardId = card.id else { return }
        
        await profileViewModel.deletePortfolioCard(cardId)
        dismiss()
    }
}

// MARK: - Custom Multi-Image Picker for Portfolio
struct MultiImagePickerForPortfolio: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 10  // Allow up to 10 images at once
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MultiImagePickerForPortfolio
        
        init(_ parent: MultiImagePickerForPortfolio) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            // Clear previous selections
            parent.images = []
            
            // Handle empty selection
            guard !results.isEmpty else { return }
            
            // Process all selected images
            let group = DispatchGroup()
            var loadedImages: [UIImage] = []
            
            for result in results {
                group.enter()
                
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                        if let image = image as? UIImage {
                            loadedImages.append(image)
                        }
                        group.leave()
                    }
                } else {
                    group.leave()
                }
            }
            
            // Wait for all images to load, then update
            group.notify(queue: .main) {
                self.parent.images = loadedImages
               
            }
        }
    }
}

// MARK: - Image Viewer (unchanged)
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

// MARK: - Edit Portfolio Details View (unchanged)
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
            
        }
        
        isSaving = false
    }
}
