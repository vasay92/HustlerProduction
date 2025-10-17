// ServiceFormView.swift
// Updated to remove price field while keeping all other features

import SwiftUI
import PhotosUI
import FirebaseAuth
import MapKit
import CoreLocation
import FirebaseFirestore

struct ServiceFormView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    
    // Form Fields
    @State private var title = ""
    @State private var description = ""
    @State private var tags: [String] = []
    @State private var location = ""
    @State private var isRequest = false
    @State private var selectedImages: [UIImage] = []
    
    // Location properties
    @State private var locationInput = ""
    @State private var locationPrivacy: LocationPrivacyOption = .exact
    @State private var validatedCoordinates: CLLocationCoordinate2D?
    @State private var hasValidatedLocation = false
    @State private var isValidatingLocation = false
    @State private var locationError: String?
    @State private var displayLocation = ""
    @State private var approximateRadius: Double = 1000 // 1km default
    @StateObject private var locationService = LocationService.shared
    
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
        _tags = State(initialValue: post?.tags ?? [])
        _location = State(initialValue: post?.location ?? "")
        _locationInput = State(initialValue: post?.location ?? "")
        _isRequest = State(initialValue: post?.isRequest ?? isRequest)
        
        // Initialize location privacy from existing post
        if let post = post {
            _locationPrivacy = State(initialValue: LocationPrivacyOption(rawValue: post.locationPrivacy.rawValue) ?? .exact)
        }
    }
    
    var isEditMode: Bool { existingPost != nil }
    
    // Validations
    private var titleValidation: (isValid: Bool, message: String) {
        ValidationHelper.validatePostTitle(title)
    }
    
    private var descriptionValidation: (isValid: Bool, message: String) {
        ValidationHelper.validatePostDescription(description)
    }
    
    private var tagsValidation: (isValid: Bool, message: String) {
        if tags.count < 5 {
            return (false, "Please add at least 5 tags")
        }
        if tags.count > 10 {
            return (false, "Maximum 10 tags allowed")
        }
        return (true, "")
    }
    
    private var isFormValid: Bool {
        titleValidation.isValid &&
        descriptionValidation.isValid &&
        tagsValidation.isValid
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    typeToggleSection
                    titleSection
                    descriptionSection
                    tagSection
                    enhancedLocationSection
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
                ImagePickerView(selectedImages: $selectedImages, maxSelectionCount: 6)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - View Sections
    
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
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tags")
                    .font(.headline)
                Text("*")
                    .foregroundColor(.red)
                Text("(5-10 required)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Use the existing TagInputField component
            TagInputField(tags: $tags)
                .withValidation(tagsValidation, showError: $showValidationErrors)
            
            // Popular tags suggestions
            VStack(alignment: .leading, spacing: 8) {
                Text("Popular tags")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                PopularTagsView(selectedTags: $tags)
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    var enhancedLocationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Text("Location")
                    .font(.headline)
                Text("(Required)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            // Location Privacy Options
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy Setting")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ForEach(LocationPrivacyOption.allCases, id: \.self) { option in
                    LocationPrivacyRow(
                        option: option,
                        isSelected: locationPrivacy == option,
                        onSelect: { locationPrivacy = option }
                    )
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Location Input
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "location.circle.fill")
                        .foregroundColor(.blue)
                    
                    TextField("Enter address or area", text: $locationInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .onSubmit {
                            validateLocation()
                        }
                        .onChange(of: locationInput) { newValue in
                            // Cancel any pending validation
                            NSObject.cancelPreviousPerformRequests(withTarget: self)
                            
                            // Auto-validate after user stops typing for 1 second
                            if !newValue.isEmpty {
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                                    if locationInput == newValue { // Check if text hasn't changed
                                        validateLocation()
                                    }
                                }
                            } else {
                                // Clear validation if text is empty
                                hasValidatedLocation = false
                                validatedCoordinates = nil
                                locationError = nil
                            }
                        }
                    
                    if isValidatingLocation {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if hasValidatedLocation {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                if let error = locationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                // Show validated address
                if hasValidatedLocation && !displayLocation.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("✓ Valid address: \(displayLocation)")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            // Use Current Location Button
            Button(action: useCurrentLocation) {
                HStack {
                    Image(systemName: "location.fill")
                    Text("Use My Current Location")
                }
                .foregroundColor(.blue)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .disabled(locationService.authorizationStatus != .authorizedWhenInUse &&
                     locationService.authorizationStatus != .authorizedAlways)
            
            // Map Preview
            if let coordinates = validatedCoordinates {
                MapPreview(
                    coordinate: coordinates,
                    privacy: locationPrivacy,
                    approximateRadius: approximateRadius
                )
                .frame(height: 200)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
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
                "Add up to 6 images",
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
            
            if !tagsValidation.isValid {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                    Text(tagsValidation.message)
                        .font(.caption)
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Location Methods
    
    func validateLocation() {
        guard !locationInput.isEmpty else { return }
        
        isValidatingLocation = true
        locationError = nil
        
        Task {
            do {
                let coordinates = try await locationService.geocodeAddress(locationInput)
                validatedCoordinates = coordinates
                hasValidatedLocation = true
                
                // If city only, get the city name
                if locationPrivacy == .cityOnly {
                    displayLocation = try await locationService.reverseGeocode(coordinate: coordinates)
                } else {
                    displayLocation = locationInput
                }
            } catch {
                locationError = "Could not find this location. Please try again."
                hasValidatedLocation = false
            }
            
            isValidatingLocation = false
        }
    }
    
    func useCurrentLocation() {
        guard let userLocation = locationService.userLocation else {
            locationError = "Unable to get current location"
            return
        }
        
        isValidatingLocation = true
        
        Task {
            do {
                let address = try await locationService.reverseGeocode(coordinate: userLocation)
                locationInput = address
                validatedCoordinates = userLocation
                hasValidatedLocation = true
                displayLocation = address
            } catch {
                locationError = "Could not determine address for current location"
            }
            
            isValidatingLocation = false
        }
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
                    for (_, image) in selectedImages.enumerated() {
                        let imageName = "\(UUID().uuidString).jpg"
                        let imagePath = "posts/\(imageName)"
                        let url = try await firebase.uploadImage(image, path: imagePath)
                        imageURLs.append(url)
                    }
                }
                
                if isEditMode {
                    // UPDATE EXISTING POST
                    var updatedPost = existingPost!
                    updatedPost.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    updatedPost.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
                    updatedPost.tags = tags
                    updatedPost.price = nil // Always nil now
                    updatedPost.location = displayLocation.isEmpty ? location : displayLocation
                    updatedPost.imageURLs = imageURLs.isEmpty ? (existingPost?.imageURLs ?? []) : imageURLs
                    updatedPost.updatedAt = Date()
                    
                    // Add location data
                    if let coords = validatedCoordinates {
                        updatedPost.coordinates = GeoPoint(
                            latitude: coords.latitude,
                            longitude: coords.longitude
                        )
                        updatedPost.locationPrivacy = ServicePost.LocationPrivacy(
                            rawValue: locationPrivacy.rawValue
                        ) ?? .exact
                        updatedPost.approximateRadius = approximateRadius
                    }
                    
                    try await servicesViewModel.updatePost(updatedPost)
                    
                    // Update tag analytics
                    await TagRepository.shared.updateTagAnalytics(tags, type: "post")
                    
                    // Trigger refresh
                    await HomeViewModel.shared?.refresh()
                    await HomeMapViewModel.shared?.refresh()
                    await ServicesViewModel.shared?.refresh(type: updatedPost.isRequest ? .requests : .offers)
                    
                } else {
                    // CREATE NEW POST (without price)
                    let newPost = ServicePost(
                        id: nil,
                        userId: firebase.currentUser?.id ?? "",
                        userName: firebase.currentUser?.name,
                        userProfileImage: firebase.currentUser?.profileImageURL,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                        tags: tags,
                        price: nil, // Always nil now
                        location: displayLocation.isEmpty ? location : displayLocation,
                        imageURLs: imageURLs,
                        isRequest: isRequest,
                        status: .active,
                        updatedAt: Date(),
                        coordinates: validatedCoordinates != nil ? GeoPoint(
                            latitude: validatedCoordinates!.latitude,
                            longitude: validatedCoordinates!.longitude
                        ) : nil,
                        locationPrivacy: ServicePost.LocationPrivacy(
                            rawValue: locationPrivacy.rawValue
                        ) ?? .exact,
                        approximateRadius: approximateRadius
                    )
                    
                    _ = try await servicesViewModel.createPost(newPost)
                    
                    // Update tag analytics
                    await TagRepository.shared.updateTagAnalytics(tags, type: "post")
                    
                    // Trigger refresh in ViewModels
                    await HomeViewModel.shared?.refresh()
                    await HomeMapViewModel.shared?.refresh()
                    await ServicesViewModel.shared?.refresh(type: isRequest ? .requests : .offers)
                }
                
                dismiss()
            } catch {
                errorMessage = "Failed to save post: \(error.localizedDescription)"
                showingError = true
            }
            
            isSaving = false
        }
    }
}

// MARK: - Supporting Types and Views

enum LocationPrivacyOption: String, CaseIterable {
    case exact = "exact"
    case approximate = "approximate"
    case cityOnly = "city_only"
    
    var title: String {
        switch self {
        case .exact:
            return "Show Exact Location"
        case .approximate:
            return "Show Approximate Area"
        case .cityOnly:
            return "Show City Only"
        }
    }
    
    var description: String {
        switch self {
        case .exact:
            return "Your exact address will be visible on the map"
        case .approximate:
            return "Location will be shown within a 1km radius"
        case .cityOnly:
            return "Only your city name will be shown"
        }
    }
    
    var icon: String {
        switch self {
        case .exact:
            return "location.fill"
        case .approximate:
            return "location.circle"
        case .cityOnly:
            return "building.2.crop.circle"
        }
    }
}

struct LocationPrivacyRow: View {
    let option: LocationPrivacyOption
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: option.icon)
                    .foregroundColor(isSelected ? .blue : .gray)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(.primary)
                    
                    Text(option.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MapPreview: View {
    let coordinate: CLLocationCoordinate2D
    let privacy: LocationPrivacyOption
    let approximateRadius: Double
    
    @State private var cameraPosition: MapCameraPosition
    
    init(coordinate: CLLocationCoordinate2D, privacy: LocationPrivacyOption, approximateRadius: Double) {
        self.coordinate = coordinate
        self.privacy = privacy
        self.approximateRadius = approximateRadius
        
        let span = privacy == .exact ?
            MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01) :
            MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        
        self._cameraPosition = State(initialValue: .region(MKCoordinateRegion(center: coordinate, span: span)))
    }
    
    var body: some View {
        Map(position: $cameraPosition) {
            if privacy == .approximate {
                // Show radius circle for approximate location
                MapCircle(center: coordinate, radius: approximateRadius)
                    .foregroundStyle(Color.blue.opacity(0.2))
                    .stroke(Color.blue, lineWidth: 2)
            }
            
            Annotation("", coordinate: coordinate) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title)
            }
        }
        .disabled(true) // Make it non-interactive
        .overlay(
            VStack {
                HStack {
                    Spacer()
                    Label(
                        privacy == .exact ? "Exact Location" :
                        privacy == .approximate ? "Approximate Area" : "City Area",
                        systemImage: privacy == .exact ? "lock.open" : "lock"
                    )
                    .font(.caption)
                    .padding(6)
                    .background(Color(.systemBackground).opacity(0.9))
                    .cornerRadius(6)
                    .padding(8)
                }
                Spacer()
            }
        )
    }
}

// MARK: - Image Picker View
struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    let maxSelectionCount: Int
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = maxSelectionCount
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
        let parent: ImagePickerView
        
        init(_ parent: ImagePickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            // Clear previous selections
            parent.selectedImages = []
            
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
                self.parent.selectedImages = loadedImages
            }
        }
    }
}

// MARK: - Popular Tags View
struct PopularTagsView: View {
    @Binding var selectedTags: [String]
    @StateObject private var tagRepository = TagRepository.shared
    @State private var popularTags: [String] = []
    
    private let commonServiceTags = [
        "#plumbing", "#electrical", "#cleaning", "#painting", "#carpentry",
        "#landscaping", "#moving", "#tutoring", "#petcare", "#babysitting",
        "#repair", "#installation", "#maintenance", "#delivery", "#assembly"
    ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(commonServiceTags, id: \.self) { tag in
                    Button(action: {
                        if !selectedTags.contains(tag) && selectedTags.count < ValidationRules.maxTags {
                            selectedTags.append(tag)
                        }
                    }) {
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedTags.contains(tag) ?
                                Color.blue : Color(.systemGray5)
                            )
                            .foregroundColor(
                                selectedTags.contains(tag) ?
                                .white : .primary
                            )
                            .cornerRadius(15)
                    }
                    .disabled(selectedTags.contains(tag))
                }
            }
        }
    }
}
