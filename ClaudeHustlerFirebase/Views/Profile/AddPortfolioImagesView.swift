

// AddPortfolioImagesView.swift
import SwiftUI
import FirebaseFirestore

struct AddPortfolioImagesView: View {
    let images: [UIImage]
    let cardId: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var descriptions: [String]
    @State private var currentIndex = 0
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(images: [UIImage], cardId: String) {
        self.images = images
        self.cardId = cardId
        self._descriptions = State(initialValue: Array(repeating: "", count: images.count))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if images.isEmpty {
                    Text("No images selected")
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 0) {
                        // Image preview with description field
                        TabView(selection: $currentIndex) {
                            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                VStack(spacing: 20) {
                                    // Image preview
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 400)
                                        .cornerRadius(12)
                                        .shadow(radius: 4)
                                    
                                    // For now, skip description field since we'll add it properly later
                                    
                                    Spacer()
                                }
                                .tag(index)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle())
                        .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                        
                        // Page indicator
                        HStack {
                            Text("Photo \(currentIndex + 1) of \(images.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if currentIndex < images.count - 1 {
                                Text("Swipe for next →")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                    }
                }
                
                // Upload overlay
                if isUploading {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 20) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                
                                Text("Uploading \(Int(uploadProgress * 100))%")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .padding(30)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(12)
                        )
                }
            }
            .navigationTitle("Add Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isUploading)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Upload") {
                        Task {
                            await uploadImages()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isUploading || images.isEmpty)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .interactiveDismissDisabled(isUploading)
    }
    
    private func uploadImages() async {
        isUploading = true
        uploadProgress = 0
        
        do {
            guard let userId = firebase.currentUser?.id else {
                throw NSError(domain: "Upload", code: 0, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
            }
            
            // Upload images and get URLs
            var newURLs: [String] = []
            
            for (index, image) in images.enumerated() {
                let path = "portfolio/\(userId)/\(cardId)/\(UUID().uuidString)_\(index).jpg"
                let url = try await firebase.uploadImage(image, path: path)
                newURLs.append(url)
                
                uploadProgress = Double(index + 1) / Double(images.count)
            }
            
            // Get current card's mediaURLs and append new ones
            let cardDoc = try await Firestore.firestore()
                .collection("portfolioCards")
                .document(cardId)
                .getDocument()
            
            var currentURLs = cardDoc.data()?["mediaURLs"] as? [String] ?? []
            currentURLs.append(contentsOf: newURLs)
            
            // Update the card with new URLs
            try await Firestore.firestore()
                .collection("portfolioCards")
                .document(cardId)
                .updateData([
                    "mediaURLs": currentURLs,
                    "updatedAt": Date()
                ])
            
            dismiss()
            
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            isUploading = false
        }
    }
}
