

// EditProfileView.swift
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
    @State private var isServiceProvider = false
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init() {
        // Initialize with current user data
    }
    
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
                            } else if let imageURL = firebase.currentUser?.profileImageURL {
                                AsyncImage(url: URL(string: imageURL)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                } placeholder: {
                                    profileImagePlaceholder
                                }
                            } else {
                                profileImagePlaceholder
                            }
                            
                            // Camera Button
                            Button(action: { showingImagePicker = true }) {
                                Image(systemName: "camera.fill")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
                
                // Profile Info
                Section("Profile Information") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                    
                    TextField("Location", text: $location)
                        .textContentType(.location)
                }
                
                // Service Provider Toggle
                Section("Account Type") {
                    Toggle("Service Provider", isOn: $isServiceProvider)
                    
                    if isServiceProvider {
                        Text("Enable this to offer services to other users")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await saveProfile()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty || isSaving)
                }
            }
            .onAppear {
                loadCurrentUserData()
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(images: .constant([]), singleImage: $profileImage)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 15) {
                                ProgressView()
                                Text("Saving Profile...")
                                    .font(.caption)
                            }
                            .padding(20)
                            .background(Color.white)
                            .cornerRadius(10)
                        )
                }
            }
        }
    }
    
    private var profileImagePlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 100, height: 100)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.gray)
            )
    }
    
    private func loadCurrentUserData() {
        guard let user = firebase.currentUser else { return }
        
        name = user.name
        bio = user.bio
        location = user.location
        isServiceProvider = user.isServiceProvider
    }
    
    private func saveProfile() async {
        isSaving = true
        
        do {
            guard let userId = firebase.currentUser?.id else {
                throw NSError(domain: "EditProfile", code: 0, userInfo: [NSLocalizedDescriptionKey: "No user ID"])
            }
            
            // Upload profile image if changed
            var profileImageURL = firebase.currentUser?.profileImageURL
            
            if let image = profileImage {
                let path = "profiles/\(userId)/profile.jpg"
                profileImageURL = try await firebase.uploadImage(image, path: path)
            }
            
            // Use the existing updateUserProfile method which handles the refresh internally
            try await firebase.updateUserProfile(
                name: name,
                bio: bio,
                location: location,
                profileImageURL: profileImageURL,
                isServiceProvider: isServiceProvider
            )
            
            dismiss()
            
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            isSaving = false
        }
    }
}
