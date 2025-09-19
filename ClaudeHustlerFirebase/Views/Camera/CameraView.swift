

// CameraView.swift
// Path: ClaudeHustlerFirebase/Views/Camera/CameraView.swift

import SwiftUI
import PhotosUI
import AVKit
import FirebaseStorage
import FirebaseFirestore

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
        .onAppear {
            if mode == .status {
                showingImagePicker = true
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(
                images: .constant([]),
                singleImage: $capturedImage,
                sourceType: .camera
            )
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
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        
                        Text("Uploading... \(Int(uploadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.white)
                        
                        ProgressView(value: uploadProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .white))
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    HStack(spacing: 16) {
                        // Retake button
                        Button(action: retakeContent) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Retake")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.6))
                            .cornerRadius(25)
                        }
                        
                        // Post button
                        Button(action: { Task { await postContent() } }) {
                            HStack {
                                Image(systemName: mode == .status ? "circle.dashed" : "play.rectangle.fill")
                                Text(mode == .status ? "Share Story" : "Post Reel")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: mode == .status ? [Color.orange, Color.red] : [Color.purple, Color.blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(25)
                        }
                        .disabled(mode == .reel && (title.isEmpty || description.isEmpty))
                    }
                    .padding()
                }
            }
            .background(Color.black.opacity(0.8))
        }
    }
    
    @ViewBuilder
    private var cameraSelectionView: some View {
        VStack(spacing: 32) {
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
                
                // Photo option
                Button(action: { showingImagePicker = true }) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text(mode == .status ? "Take Photo" : "Use Photo")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(mode == .status ? Color.orange : Color.blue)
                    .cornerRadius(12)
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
            // Show confirmation if content is captured
            capturedImage = nil
            capturedVideoURL = nil
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
        // This would open a photo library picker
        // For now, using the image picker with photo library source
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
        guard let image = capturedImage else { return }
        
        do {
            // Upload image
            uploadProgress = 0.3
            let imageURL = try await uploadImage(image)
            
            uploadProgress = 0.6
            
            // Create status
            let statusData: [String: Any] = [
                "userId": firebase.currentUser?.id ?? "",
                "userName": firebase.currentUser?.name ?? "User",
                "userProfileImage": firebase.currentUser?.profileImageURL ?? "",
                "mediaURL": imageURL,
                "caption": caption.isEmpty ? nil : caption,
                "mediaType": "image",
                "createdAt": Date(),
                "expiresAt": Calendar.current.date(byAdding: .hour, value: 24, to: Date()) ?? Date(),
                "viewedBy": [],
                "isActive": true
            ]
            
            let ref = try await Firestore.firestore()
                .collection("statuses")
                .addDocument(data: statusData)
            
            uploadProgress = 1.0
            
            print("✅ Created status with ID: \(ref.documentID)")
            
            // Refresh statuses
            await firebase.loadStatusesFromFollowing()
        } catch {
            throw error
        }
    }
    
    private func postReel() async throws {
        do {
            var mediaURL = ""
            var thumbnailURL = ""
            
            uploadProgress = 0.2
            
            if let image = capturedImage {
                // Upload image as both media and thumbnail
                mediaURL = try await uploadImage(image)
                thumbnailURL = mediaURL
            } else if let videoURL = capturedVideoURL {
                // Upload video and generate thumbnail
                mediaURL = try await uploadVideo(videoURL)
                if let thumbnail = generateVideoThumbnail(from: videoURL) {
                    thumbnailURL = try await uploadImage(thumbnail)
                }
            }
            
            uploadProgress = 0.6
            
            // Create reel
            let reelData: [String: Any] = [
                "userId": firebase.currentUser?.id ?? "",
                "userName": firebase.currentUser?.name ?? "User",
                "userProfileImage": firebase.currentUser?.profileImageURL ?? "",
                "videoURL": mediaURL,
                "thumbnailURL": thumbnailURL,
                "title": title,
                "description": description,
                "category": selectedCategory.rawValue,
                "hashtags": extractHashtags(from: description),
                "createdAt": Date(),
                "likes": [],
                "comments": 0,
                "shares": 0,
                "views": 0,
                "isPromoted": false
            ]
            
            uploadProgress = 0.8
            
            let ref = try await Firestore.firestore()
                .collection("reels")
                .addDocument(data: reelData)
            
            uploadProgress = 1.0
            
            print("✅ Created reel with ID: \(ref.documentID)")
            
            // Refresh reels
            await firebase.loadReels()
        } catch {
            throw error
        }
    }
    
    private func uploadImage(_ image: UIImage) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "CameraView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to process image"])
        }
        
        let fileName = "\(UUID().uuidString).jpg"
        let storageRef = Storage.storage().reference()
            .child(mode == .status ? "statuses" : "reels")
            .child(fileName)
        
        let _ = try await storageRef.putDataAsync(imageData)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    private func uploadVideo(_ url: URL) async throws -> String {
        let videoData = try Data(contentsOf: url)
        
        let fileName = "\(UUID().uuidString).mp4"
        let storageRef = Storage.storage().reference()
            .child("reels")
            .child(fileName)
        
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

// Note: ImagePicker should already exist in your project
// If not, here's a basic implementation:
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Binding var singleImage: UIImage?
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController,
                                 didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.singleImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
