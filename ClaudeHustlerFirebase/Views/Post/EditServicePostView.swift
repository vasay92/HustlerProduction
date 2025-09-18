// EditServicePostView.swift
// Path: ClaudeHustlerFirebase/Views/Post/EditServicePostView.swift

import SwiftUI
import PhotosUI

struct EditServicePostView: View {
    let post: ServicePost?  // Made optional to handle both create and edit
    @StateObject private var firebase = FirebaseService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var title: String
    @State private var description: String
    @State private var selectedCategory: ServiceCategory
    @State private var price: String
    @State private var location: String
    @State private var existingImageURLs: [String]
    @State private var newImages: [UIImage] = []
    @State private var showingImagePicker = false
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccessMessage = false
    @State private var isRequest: Bool  // Add this to track if it's a request or offer
    
    init(post: ServicePost? = nil, isRequest: Bool = false) {
        self.post = post
        // If editing, use post values; if creating, use defaults
        _title = State(initialValue: post?.title ?? "")
        _description = State(initialValue: post?.description ?? "")
        _selectedCategory = State(initialValue: post?.category ?? .other)
        _price = State(initialValue: post?.price != nil ? String(Int(post!.price!)) : "")
        _location = State(initialValue: post?.location ?? "")
        _existingImageURLs = State(initialValue: post?.imageURLs ?? [])
        _isRequest = State(initialValue: post?.isRequest ?? isRequest)
    }
    
    var isEditMode: Bool {
        post != nil
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Post Type Toggle (only show when creating new)
                if !isEditMode {
                    Section("Post Type") {
                        Picker("Type", selection: $isRequest) {
                            Text("Offering Service").tag(false)
                            Text("Requesting Service").tag(true)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(4...8)
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ServiceCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }
                
                Section("Pricing & Location") {
                    HStack {
                        Text("$")
                        TextField(isRequest ? "Budget" : "Price", text: $price)
                            .keyboardType(.numberPad)
                    }
                    TextField("Location", text: $location)
                }
                
                Section("Images") {
                    // Show existing images if editing
                    if !existingImageURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(existingImageURLs, id: \.self) { imageURL in
                                    AsyncImage(url: URL(string: imageURL)) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipped()
                                            .cornerRadius(10)
                                            .overlay(
                                                Button(action: {
                                                    existingImageURLs.removeAll(where: { $0 == imageURL })
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.white)
                                                        .background(Color.black.opacity(0.6))
                                                        .clipShape(Circle())
                                                }
                                                .padding(4),
                                                alignment: .topTrailing
                                            )
                                    } placeholder: {
                                        ProgressView()
                                            .frame(width: 100, height: 100)
                                            .background(Color.gray.opacity(0.2))
                                            .cornerRadius(10)
                                    }
                                }
                            }
                        }
                    }
                    
                    // New images to upload
                    if !newImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(newImages, id: \.self) { image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipped()
                                        .cornerRadius(10)
                                        .overlay(
                                            Button(action: {
                                                newImages.removeAll(where: { $0 == image })
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .background(Color.black.opacity(0.6))
                                                    .clipShape(Circle())
                                            }
                                            .padding(4),
                                            alignment: .topTrailing
                                        )
                                }
                            }
                        }
                    }
                    
                    Button(action: { showingImagePicker = true }) {
                        Label("Add Images", systemImage: "photo.on.rectangle.angled")
                    }
                }
                
                // Status section (only show if editing)
                if isEditMode, let postStatus = post?.status, postStatus != .active {
                    Section("Status") {
                        HStack {
                            Image(systemName: postStatus == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(postStatus == .completed ? .orange : .red)
                            Text(postStatus == .completed ? "Completed" : "Cancelled")
                                .foregroundColor(postStatus == .completed ? .orange : .red)
                            Spacer()
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        Task {
                            await savePost()
                        }
                    }) {
                        if isSaving {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text(isEditMode ? "Save Changes" : "Create Post")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(title.isEmpty || description.isEmpty || isSaving)
                }
            }
            .navigationTitle(isEditMode ? "Edit Post" : "Create Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            EditPostImagePicker(images: $newImages)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success!", isPresented: $showingSuccessMessage) {
            Button("OK") { dismiss() }
        } message: {
            Text(isEditMode ? "Your post has been updated successfully!" : "Your post has been created successfully!")
        }
    }
    
    private func savePost() async {
        isSaving = true
        
        do {
            // Upload new images
            var newImageURLs: [String] = []
            if !newImages.isEmpty {
                let userId = firebase.currentUser?.id ?? "unknown"
                for (index, image) in newImages.enumerated() {
                    let path = "services/\(userId)/\(UUID().uuidString)_\(index).jpg"
                    let url = try await firebase.uploadImage(image, path: path)
                    newImageURLs.append(url)
                }
            }
            
            let allImageURLs = existingImageURLs + newImageURLs
            let priceValue = Double(price) ?? 0
            
            if isEditMode {
                // Update existing post
                guard let postId = post?.id else { return }
                
                try await firebase.updatePost(
                    postId: postId,
                    title: title,
                    description: description,
                    category: selectedCategory,
                    price: priceValue > 0 ? priceValue : nil,
                    location: location.isEmpty ? nil : location,
                    imageURLs: allImageURLs
                )
            } else {
                // Create new post
                let newPost = ServicePost(
                    id: nil,
                    userId: firebase.currentUser?.id ?? "",
                    userName: firebase.currentUser?.name,
                    userProfileImage: firebase.currentUser?.profileImageURL,
                    title: title,
                    description: description,
                    category: selectedCategory,
                    price: priceValue > 0 ? priceValue : nil,
                    location: location.isEmpty ? nil : location,
                    imageURLs: allImageURLs,
                    isRequest: isRequest,
                    status: .active
                )
                
                try await firebase.saveServicePost(newPost)
            }
            
            showingSuccessMessage = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            isSaving = false
        }
    }
}

// Image Picker for Edit Post
struct EditPostImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 5
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: EditPostImagePicker
        
        init(_ parent: EditPostImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                        if let image = image as? UIImage {
                            DispatchQueue.main.async {
                                self.parent.images.append(image)
                            }
                        }
                    }
                }
            }
        }
    }
}
