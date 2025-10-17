// EditProfileView.swift
// Path: ClaudeHustlerFirebase/Views/Profile/EditProfileView.swift

import SwiftUI
import PhotosUI
import FirebaseFirestore

struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var name: String = ""
    @State private var bio: String = ""
    @State private var location: String = ""
    @State private var profileImage: UIImage?
    @State private var showingImagePicker = false
    @State private var isServiceProvider = false  // Keep in state for database compatibility
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUpdatingProfileImage = false
    
    var body: some View {
        NavigationView {
            Form {
                // Profile Photo Section
                Section {
                    HStack {
                        Spacer()
                        
                        ZStack(alignment: .bottomTrailing) {
                            // Profile Image
                            if let profileImage = profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                UserAvatar(
                                    imageURL: firebase.currentUser?.profileImageURL,
                                    userName: firebase.currentUser?.name,
                                    size: 100
                                )
                            }
                            
                            // Camera button
                            PhotosPicker(selection: $selectedItem,
                                       matching: .images,
                                       photoLibrary: .shared()) {
                                Image(systemName: "camera.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.blue)
                                    .background(Circle().fill(Color.white))
                            }
                            .offset(x: -5, y: -5)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
                
                // Name Section
                Section(header: Text("Name")) {
                    TextField("Enter your name", text: $name)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                }
                
                // Bio Section
                Section(header: Text("Bio")) {
                    TextEditor(text: $bio)
                        .frame(minHeight: 100)
                        .overlay(
                            Group {
                                if bio.isEmpty {
                                    Text("Tell us about yourself...")
                                        .foregroundColor(Color(.placeholderText))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                }
                
                // Location Section
                Section(header: Text("Location")) {
                    TextField("City or area", text: $location)
                        .autocapitalization(.words)
                }
                
                // REMOVED: Service Provider Toggle Section
                // This section has been removed as requested
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving || isUpdatingProfileImage)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await saveProfile()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving || isUpdatingProfileImage || name.isEmpty)
                }
            }
            .onAppear {
                loadCurrentUserData()
            }
            .onChange(of: selectedItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        if let uiImage = UIImage(data: data) {
                            profileImage = uiImage
                        }
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .overlay {
                if isSaving || isUpdatingProfileImage {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 15) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                                
                                if isUpdatingProfileImage {
                                    Text("Updating profile image everywhere...")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                } else {
                                    Text("Saving Profile...")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(25)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(15)
                        )
                }
            }
        }
    }
    
    private func loadCurrentUserData() {
        guard let user = firebase.currentUser else { return }
        
        name = user.name
        bio = user.bio
        location = user.location
        isServiceProvider = user.isServiceProvider  // Load from database but don't show UI
    }
    
    private func saveProfile() async {
        isSaving = true
        
        do {
            guard let userId = firebase.currentUser?.id else {
                throw NSError(domain: "EditProfile", code: 0, userInfo: [NSLocalizedDescriptionKey: "No user ID found"])
            }
            
            var profileImageURL = firebase.currentUser?.profileImageURL
            
            // Upload and update profile image if changed
            if let image = profileImage {
                isUpdatingProfileImage = true
                
                // Upload image to storage
                let path = "profiles/\(userId)/profile_\(Date().timeIntervalSince1970).jpg"
                profileImageURL = try await firebase.uploadImage(image, path: path)
                
                // Update profile image across all content
                if let newImageURL = profileImageURL {
                    try await UserRepository.shared.updateProfileImage(newImageURL, for: userId)
                }
                
                isUpdatingProfileImage = false
            }
            
            // Update other profile fields (keep existing isServiceProvider value)
            try await firebase.updateUserProfile(
                name: name,
                bio: bio,
                location: location,
                profileImageURL: profileImageURL,
                isServiceProvider: isServiceProvider  // Keep existing value from database
            )
            
            // Refresh current user data
            await firebase.refreshCurrentUser()
            
            dismiss()
            
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            isSaving = false
            isUpdatingProfileImage = false
        }
    }
}

#Preview {
    EditProfileView()
}
