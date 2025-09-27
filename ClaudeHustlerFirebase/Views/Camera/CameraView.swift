// CameraView.swift
// Path: ClaudeHustlerFirebase/Views/Camera/CameraView.swift

import SwiftUI
import PhotosUI
import AVKit
import FirebaseStorage
import FirebaseFirestore

// MARK: - ImagePicker (Works with both single and multiple selection)
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Binding var singleImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        // If singleImage is being used, limit to 1, otherwise unlimited
        config.selectionLimit = images.isEmpty ? 1 : 0
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Handle empty selection
            guard !results.isEmpty else {
                parent.dismiss()
                return
            }
            
            // Check if we're doing single or multiple selection based on bindings
            let isSingleSelection = parent.images.isEmpty
            
            if isSingleSelection && results.count == 1 {
                // Single image selection
                let result = results[0]
                result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                    DispatchQueue.main.async {
                        if let image = image as? UIImage {
                            // Set the single image binding if available
                            self.parent.singleImage = image
                            print("✅ Single image loaded and set")
                        }
                        // Dismiss after setting the image
                        self.parent.dismiss()
                    }
                }
            } else {
                // Multiple image selection
                let group = DispatchGroup()
                var loadedImages: [UIImage] = []
                
                for result in results {
                    group.enter()
                    result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                        if let image = image as? UIImage {
                            loadedImages.append(image)
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    self.parent.images = loadedImages
                    print("✅ Loaded \(loadedImages.count) images")
                    self.parent.dismiss()
                }
            }
        }
    }
}

// MARK: - CameraView
struct CameraView: View {
    let mode: CameraMode
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    
    // Image/Video capture states
    @State private var capturedImage: UIImage?
    @State private var capturedVideoURL: URL?
    @State private var showingImagePicker = false
    @State private var showingVideoPicker = false
    
    // Content creation states
    @State private var caption = ""
    @State private var title = ""
    @State private var description = ""
    @State private var selectedCategory: ServiceCategory = .other
    @State private var isPosting = false
    @State private var uploadProgress: Double = 0
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if capturedImage != nil || capturedVideoURL != nil {
                    // Preview and posting interface
                    contentPreviewView
                } else {
                    // Camera selection interface
                    cameraSelectionView
                }
                
                // Close button overlay
                closeButtonOverlay
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(images: .constant([]), singleImage: $capturedImage)
        }
        .sheet(isPresented: $showingVideoPicker) {
            VideoPicker(videoURL: $capturedVideoURL)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var contentPreviewView: some View {
        VStack(spacing: 0) {
            // Preview area
            ScrollView {
                VStack {
                    if let image = capturedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                            .cornerRadius(10)
                    } else if let videoURL = capturedVideoURL {
                        VideoPlayer(player: AVPlayer(url: videoURL))
                            .frame(height: UIScreen.main.bounds.height * 0.5)
                            .cornerRadius(10)
                    }
                    
                    // Input fields based on mode
                    VStack(spacing: 16) {
                        if mode == .status {
                            // Status caption
                            TextField("Add a caption (optional)", text: $caption, axis: .vertical)
                                .lineLimit(3...5)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.horizontal)
                        } else {
                            // Reel details
                            VStack(spacing: 12) {
                                TextField("Title", text: $title)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                TextField("Description", text: $description, axis: .vertical)
                                    .lineLimit(3...5)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                // Category picker
                                Picker("Category", selection: $selectedCategory) {
                                    ForEach(ServiceCategory.allCases, id: \.self) { category in
                                        Text(category.displayName).tag(category)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            
            // Post button at bottom
            VStack {
                if isPosting {
                    // Upload progress
                    VStack(spacing: 8) {
                        ProgressView(value: uploadProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .white))
                            .padding(.horizontal)
                        
                        Text("Uploading... \(Int(uploadProgress * 100))%")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                    .padding()
                } else {
                    // Action buttons
                    HStack(spacing: 16) {
                        // Retake button
                        Button(action: retakeContent) {
                            Text("Retake")
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.6))
                                .cornerRadius(12)
                        }
                        
                        // Post button
                        Button(action: {
                            Task {
                                await postContent()
                            }
                        }) {
                            Text(mode == .status ? "Share Story" : "Post Reel")
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
    }
    
    @ViewBuilder
    private var cameraSelectionView: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Icon
            Image(systemName: mode == .status ? "circle.dashed" : "play.rectangle")
                .font(.system(size: 80))
                .foregroundColor(.white)
            
            // Title
            VStack(spacing: 8) {
                Text(mode == .status ? "Create Your Story" : "Create a Reel")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(mode == .status ?
                     "Share what you're working on (24 hours)" :
                     "Showcase your skills to potential clients")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            // Action buttons
            VStack(spacing: 16) {
                if mode == .reel {
                    // Video option for reels
                    Button(action: { showingVideoPicker = true }) {
                        HStack {
                            Image(systemName: "video.fill")
                            Text("Record Video")
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(12)
                    }
                }
                
                // Gallery option
                Button(action: openGallery) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("Choose from Gallery")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.6))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var closeButtonOverlay: some View {
        VStack {
            HStack {
                if !isPosting {
                    Button(action: handleClose) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .padding()
                }
                Spacer()
            }
            Spacer()
        }
    }
    
    // MARK: - Methods
    
    private func handleClose() {
        if capturedImage != nil || capturedVideoURL != nil {
            // Reset and go back to selection
            capturedImage = nil
            capturedVideoURL = nil
            caption = ""
            title = ""
            description = ""
        } else {
            dismiss()
        }
    }
    
    private func retakeContent() {
        capturedImage = nil
        capturedVideoURL = nil
        caption = ""
        title = ""
        description = ""
    }
    
    private func openGallery() {
        showingImagePicker = true
    }
    
    private func postContent() async {
        isPosting = true
        uploadProgress = 0
        
        do {
            if mode == .status {
                try await postStatus()
            } else {
                try await postReel()
            }
            
            // Success - dismiss
            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
                isPosting = false
            }
        }
    }
    
    private func postStatus() async throws {
        guard let image = capturedImage else {
            throw NSError(domain: "CameraView", code: 0, userInfo: [NSLocalizedDescriptionKey: "No image selected"])
        }
        
        uploadProgress = 0.5
        
        // Use StatusRepository's createStatus method directly
        let statusId = try await StatusRepository.shared.createStatus(
            image: image,
            caption: caption.isEmpty ? nil : caption
        )
        
        uploadProgress = 1.0
        
        print("✅ Created status with ID: \(statusId)")
        
        // Refresh statuses in ReelsViewModel
        if let reelsVM = ReelsViewModel.shared {
            await reelsVM.loadStatuses()
        }
    }
    
    private func postReel() async throws {
        var mediaURL = ""
        var thumbnailURL = ""
        
        uploadProgress = 0.2
        
        // Get userId first
        guard let userId = firebase.currentUser?.id else {
            throw NSError(domain: "CameraView", code: 0, userInfo: [NSLocalizedDescriptionKey: "No user ID"])
        }
        
        if let image = capturedImage {
            // Upload image as both media and thumbnail
            let imagePath = "reels/\(userId)/\(UUID().uuidString).jpg"
            mediaURL = try await firebase.uploadImage(image, path: imagePath)
            thumbnailURL = mediaURL
        } else if let videoURL = capturedVideoURL {
            // Upload video and generate thumbnail
            let videoPath = "reels/\(userId)/\(UUID().uuidString).mp4"
            mediaURL = try await uploadVideo(videoURL, path: videoPath)
            if let thumbnail = generateVideoThumbnail(from: videoURL) {
                let thumbPath = "reels/\(userId)/thumbnails/\(UUID().uuidString).jpg"
                thumbnailURL = try await firebase.uploadImage(thumbnail, path: thumbPath)
            }
        } else {
            throw NSError(domain: "CameraView", code: 0, userInfo: [NSLocalizedDescriptionKey: "No media selected"])
        }
        
        uploadProgress = 0.6
        
        // Ensure title has a value
        let reelTitle = title.isEmpty ? "Untitled Reel" : title
        let reelDescription = description.isEmpty ? "" : description
        
        uploadProgress = 0.8
        
        // Create Reel object
        let reel = Reel(
            userId: userId,
            userName: firebase.currentUser?.name ?? "Unknown",
            userProfileImage: firebase.currentUser?.profileImageURL ?? "",
            videoURL: mediaURL,
            thumbnailURL: thumbnailURL.isEmpty ? mediaURL : thumbnailURL,
            title: reelTitle,
            description: reelDescription,
            category: selectedCategory,
            hashtags: extractHashtags(from: reelDescription),
            likes: [],
            comments: 0,
            shares: 0,
            views: 0,
            isPromoted: false
        )
        
        // Use ReelRepository to create the reel
        let reelId = try await ReelRepository.shared.create(reel)
        
        uploadProgress = 1.0
        
        print("✅ Created reel with ID: \(reelId)")
        
        // Refresh reels in view model
        if let reelsVM = ReelsViewModel.shared {
            await reelsVM.loadInitialReels()
        }
    }
    
    private func uploadVideo(_ url: URL, path: String? = nil) async throws -> String {
        guard let userId = firebase.currentUser?.id else {
            throw NSError(domain: "CameraView", code: 0, userInfo: [NSLocalizedDescriptionKey: "No user ID"])
        }
        
        let videoData = try Data(contentsOf: url)
        
        let finalPath = path ?? "reels/\(userId)/\(UUID().uuidString).mp4"
        
        let storageRef = Storage.storage().reference().child(finalPath)
        
        let _ = try await storageRef.putDataAsync(videoData)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    private func generateVideoThumbnail(from url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 1, preferredTimescale: 60)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("Error generating thumbnail: \(error)")
            return nil
        }
    }
    
    private func extractHashtags(from text: String) -> [String] {
        let pattern = "#\\w+"
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        return matches?.compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        } ?? []
    }
}

// MARK: - Video Picker
struct VideoPicker: UIViewControllerRepresentable {
    @Binding var videoURL: URL?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.videoMaximumDuration = 60 // 1 minute max
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoPicker
        
        init(_ parent: VideoPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController,
                                 didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.videoURL = url
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
