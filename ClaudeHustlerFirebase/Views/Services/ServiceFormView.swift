

// ServiceFormView.swift
// Path: ClaudeHustlerFirebase/Views/Services/ServiceFormView.swift

import SwiftUI
import PhotosUI
import FirebaseAuth


struct ServiceFormView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    
    // Form Fields
    @State private var title = ""
    @State private var description = ""
    @State private var selectedCategory: ServiceCategory = .other
    @State private var price = ""
    @State private var location = ""
    @State private var isRequest = false
    @State private var selectedImages: [UIImage] = []
    
    // UI State
    @State private var showingImagePicker = false
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showValidationErrors = false
    @StateObject private var servicesViewModel = ServicesViewModel()
    
    // For Edit Mode
    let existingPost: ServicePost?
    
    init(post: ServicePost? = nil, isRequest: Bool = false) {
        self.existingPost = post
        _title = State(initialValue: post?.title ?? "")
        _description = State(initialValue: post?.description ?? "")
        _selectedCategory = State(initialValue: post?.category ?? .other)
        _price = State(initialValue: post?.price != nil ? String(Int(post!.price!)) : "")
        _location = State(initialValue: post?.location ?? "")
        _isRequest = State(initialValue: post?.isRequest ?? isRequest)
    }
    
    var isEditMode: Bool { existingPost != nil }
    
    // Validations
    private var titleValidation: (isValid: Bool, message: String) {
        ValidationHelper.validatePostTitle(title)
    }
    
    private var descriptionValidation: (isValid: Bool, message: String) {
        ValidationHelper.validatePostDescription(description)
    }
    
    private var priceValidation: (isValid: Bool, price: Double?, message: String) {
        ValidationHelper.validatePostPrice(price)
    }
    
    private var isFormValid: Bool {
        titleValidation.isValid &&
        descriptionValidation.isValid &&
        priceValidation.isValid
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    typeToggleSection
                    titleSection
                    descriptionSection
                    categorySection
                    priceSection
                    locationSection
                    imagesSection
                    submitSection
                }
            }
            .navigationTitle(isEditMode ? "Edit Post" : "Create Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                MultiImagePicker(images: $selectedImages)  // Use the new picker
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - View Sections (Breaking up complex view)
    
    @ViewBuilder
    private var typeToggleSection: some View {
        if !isEditMode {
            VStack(alignment: .leading, spacing: 8) {
                Text("What would you like to do?")
                    .font(.headline)
                
                Picker("Type", selection: $isRequest) {
                    Text("Offer a Service").tag(false)
                    Text("Request a Service").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Title")
                    .font(.headline)
                Text("*")
                    .foregroundColor(.red)
                Spacer()
                CharacterCounterView(
                    current: title.count,
                    min: ValidationRules.postTitleMin,
                    max: ValidationRules.postTitleMax
                )
            }
            
            TextField("Enter a descriptive title", text: $title)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .withValidation(titleValidation, showError: $showValidationErrors)
            
            RequirementHintView(requirements: [
                "Between \(ValidationRules.postTitleMin)-\(ValidationRules.postTitleMax) characters",
                "Be specific about your service"
            ])
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description")
                    .font(.headline)
                Text("*")
                    .foregroundColor(.red)
                Spacer()
                CharacterCounterView(
                    current: description.count,
                    min: ValidationRules.postDescriptionMin,
                    max: ValidationRules.postDescriptionMax
                )
            }
            
            TextEditor(text: $description)
                .frame(minHeight: 100)
                .padding(4)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .withValidation(descriptionValidation, showError: $showValidationErrors)
            
            RequirementHintView(requirements: [
                "Minimum \(ValidationRules.postDescriptionMin) characters required",
                "Describe what you're offering or what you need",
                "Include relevant details about timeline, skills, etc."
            ])
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Category")
                    .font(.headline)
                Text("*")
                    .foregroundColor(.red)
            }
            
            Picker("Category", selection: $selectedCategory) {
                ForEach(ServiceCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Price")
                    .font(.headline)
                Text("(Optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("$")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                TextField(isRequest ? "Your budget" : "Your price", text: $price)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .withValidation(
                (priceValidation.isValid, priceValidation.message),
                showError: $showValidationErrors
            )
            
            RequirementHintView(requirements: [
                "Leave empty for negotiable pricing",
                "Maximum: $\(Int(ValidationRules.postPriceMax))"
            ])
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Location")
                    .font(.headline)
                Text("(Optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            TextField("City or area", text: $location)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            RequirementHintView(requirements: [
                "Add if location is relevant to your service"
            ])
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Images")
                    .font(.headline)
                Text("(Optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                            imagePreview(image: image, index: index)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            Button(action: { showingImagePicker = true }) {
                HStack {
                    Image(systemName: "photo.badge.plus")
                    Text("Add Images")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            RequirementHintView(requirements: [
                "Add up to 5 images",
                "Images help attract more attention"
            ])
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func imagePreview(image: UIImage, index: Int) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 100, height: 100)
            .clipped()
            .cornerRadius(8)
            .overlay(
                Button(action: {
                    selectedImages.remove(at: index)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .padding(4),
                alignment: .topTrailing
            )
    }
    
    @ViewBuilder
    private var submitSection: some View {
        VStack(spacing: 12) {
            submitButton
            
            if showValidationErrors && !isFormValid {
                validationSummary
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
    
    @ViewBuilder
    private var submitButton: some View {
        Button(action: { savePost() }) {
            if isSaving {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Text(isEditMode ? "Update Post" : "Create Post")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .background(
            isFormValid ?
            (isRequest ? Color.orange : Color.blue) :
            Color.gray
        )
        .cornerRadius(12)
        .disabled(!isFormValid || isSaving)
    }
    
    @ViewBuilder
    private var validationSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !titleValidation.isValid {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                    Text(titleValidation.message)
                        .font(.caption)
                }
                .foregroundColor(.red)
            }
            
            if !descriptionValidation.isValid {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                    Text(descriptionValidation.message)
                        .font(.caption)
                }
                .foregroundColor(.red)
            }
            
            if !priceValidation.isValid {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                    Text(priceValidation.message)
                        .font(.caption)
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Actions
    
    private func savePost() {
        
        showValidationErrors = true
        
        guard isFormValid else {
            return
        }
        
        Task {
            isSaving = true
            
            do {
                var imageURLs: [String] = []
                if !selectedImages.isEmpty {
                    
                    for (index, image) in selectedImages.enumerated() {
                        let imageName = "\(UUID().uuidString).jpg"
                        let imagePath = "posts/\(imageName)"
                        
                        
                        let url = try await firebase.uploadImage(image, path: imagePath)
                        
                        imageURLs.append(url)
                    }
                }
                
                if isEditMode {
                    var updatedPost = existingPost!
                        updatedPost.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updatedPost.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
                        updatedPost.category = selectedCategory
                        updatedPost.price = priceValidation.price
                        updatedPost.location = location.isEmpty ? nil : location
                        // Only update images if new ones were selected, otherwise keep existing
                        updatedPost.imageURLs = imageURLs.isEmpty ? (existingPost?.imageURLs ?? []) : imageURLs  // ✅ Preserves existing images!
                    try await servicesViewModel.updatePost(updatedPost)
                    // Trigger refresh
                    await HomeViewModel.shared?.refresh()
                    await ServicesViewModel.shared?.refresh(type: updatedPost.isRequest ? .requests : .offers)
                    
                } else {
                    // CREATE NEW POST using PostRepository
                    let newPost = ServicePost(
                        id: nil,
                        userId: firebase.currentUser?.id ?? "",
                        userName: firebase.currentUser?.name,
                        userProfileImage: firebase.currentUser?.profileImageURL,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                        category: selectedCategory,
                        price: priceValidation.price,
                        location: location.isEmpty ? nil : location,
                        imageURLs: imageURLs,
                        isRequest: isRequest,
                        status: .active,
                        updatedAt: Date()
                    )
                    _ = try await servicesViewModel.createPost(newPost)
                    
                    // Trigger refresh in ViewModels
                    await HomeViewModel.shared?.refresh()
                    await ServicesViewModel.shared?.refresh(type: isRequest ? .requests : .offers)
                }
                
                dismiss()
            } catch {
                errorMessage = "Update failed: \(error.localizedDescription)"
                showingError = true
                print("❌ Update Error: \(error)")  // This will help debug
            }
            
            isSaving = false
        }
    }
}

#Preview {
    ServiceFormView()
}

// Add this ENTIRE struct at the BOTTOM of ServiceFormView.swift
struct MultiImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 5  // Allow up to 5 images
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MultiImagePicker
        
        init(_ parent: MultiImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            parent.images = []  // Clear previous selections
            
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
