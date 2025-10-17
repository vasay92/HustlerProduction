// ProfileSupportingViews.swift
import SwiftUI
import PhotosUI
import FirebaseFirestore
import Foundation
import FirebaseAuth

// MARK: - Portfolio Card View (with square edges - no cornerRadius)
struct PortfolioCardView: View {
    let card: PortfolioCard
    let isOwner: Bool
    @ObservedObject var profileViewModel: ProfileViewModel
    @State private var showingGallery = false
    @State private var showingMenu = false
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        Button(action: { showingGallery = true }) {
            VStack(alignment: .leading, spacing: 0) {
                // Cover Image - No rounded corners
                GeometryReader { geometry in
                    if let coverURL = card.coverImageURL, !coverURL.isEmpty {
                        AsyncImage(url: URL(string: coverURL)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.width * 1.33)
                                .clipped()
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: geometry.size.width, height: geometry.size.width * 1.33)
                                .overlay(ProgressView())
                        }
                    } else if let firstImage = card.mediaURLs.first {
                        AsyncImage(url: URL(string: firstImage)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.width * 1.33)
                                .clipped()
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: geometry.size.width, height: geometry.size.width * 1.33)
                                .overlay(ProgressView())
                        }
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: geometry.size.width, height: geometry.size.width * 1.33)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                    }
                }
                .aspectRatio(3/4, contentMode: .fit)
                
                // Title bar with slight padding
                Text(card.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
            }
        }
        .fullScreenCover(isPresented: $showingGallery) {
            PortfolioGalleryView(card: card, isOwner: isOwner, profileViewModel: profileViewModel)
        }
        .contextMenu {
            if isOwner {
                Button(action: { showingGallery = true }) {
                    Label("View", systemImage: "eye")
                }
                Button(action: { showingGallery = true }) {
                    Label("Edit", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive, action: {
                    Task {
                        await deletePortfolio()
                    }
                }) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    private func deletePortfolio() async {
        guard let cardId = card.id else { return }
        
        do {
            try await PortfolioRepository.shared.deletePortfolioCard(cardId)
            await profileViewModel.loadPortfolioCards()
        } catch {
        }
    }
}

// ProfileSupportingViews.swift - UPDATED ReviewCard
// Replace the existing ReviewCard struct with this updated version:

// MARK: - Review Card
struct ReviewCard: View {
    let review: Review
    let isProfileOwner: Bool
    @State private var showingReplyForm = false
    @State private var showingEditForm = false
    @State private var helpfulCount: Int
    @State private var isHelpful: Bool
    @State private var isUpdating = false
    @State private var selectedImageURL: String? = nil  // CHANGED from selectedImageIndex
    @StateObject private var firebase = FirebaseService.shared
    
    init(review: Review, isProfileOwner: Bool) {
        self.review = review
        self.isProfileOwner = isProfileOwner
        _helpfulCount = State(initialValue: review.helpfulVotes.count)
        _isHelpful = State(initialValue: false)
    }
    
    var isOwnReview: Bool {
        review.reviewerId == firebase.currentUser?.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Reviewer Info
            reviewerSection
            
            // Review Text
            reviewTextSection
            
            // Review Images
            if !review.mediaURLs.isEmpty {
                reviewImagesSection
            }
            
            // Reply if exists
            if let reply = review.reply {
                replySection(reply: reply)
            }
            
            // Action Buttons
            actionButtonsSection
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .opacity(isUpdating ? 0.6 : 1.0)
        .sheet(isPresented: $showingReplyForm) {
            ReplyToReviewView(reviewId: review.id ?? "")
        }
        .sheet(isPresented: $showingEditForm) {
            EditReviewView(review: review)
        }
        // CHANGED: Using sheet with item binding instead of fullScreenCover
        .sheet(item: $selectedImageURL) { imageURL in
            SimpleImageViewer(
                imageURL: imageURL,
                allImageURLs: review.mediaURLs
            )
        }
        .onAppear {
            isHelpful = review.helpfulVotes.contains(firebase.currentUser?.id ?? "")
        }
    }
    
    @ViewBuilder
    private var reviewerSection: some View {
        HStack {
            // Wrap reviewer info in NavigationLink to their profile
            NavigationLink(destination: EnhancedProfileView(userId: review.reviewerId)) {
                HStack {
                    // Profile Image
                    if let profileImageURL = review.reviewerProfileImage,
                       !profileImageURL.isEmpty,
                       let url = URL(string: profileImageURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.5)
                                )
                        }
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(String(review.reviewerName?.first ?? "U"))
                                    .foregroundColor(.white)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(review.reviewerName ?? "Anonymous")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 2) {
                            ForEach(0..<5) { index in
                                Image(systemName: index < review.rating ? "star.fill" : "star")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                            }
                            
                            Text("• \(review.createdAt, style: .date)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Menu for own reviews
            if isOwnReview {
                Menu {
                    Button("Edit", action: { showingEditForm = true })
                    Button("Delete", role: .destructive, action: deleteReview)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var reviewTextSection: some View {
        Text(review.text)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
        
        if review.isEdited {
            Text("(edited)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // CHANGED: Simplified image section with direct URL tap
    @ViewBuilder
    private var reviewImagesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(review.mediaURLs, id: \.self) { urlString in
                    if let url = URL(string: urlString) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(8)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 80, height: 80)
                                .cornerRadius(8)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.7)
                                )
                        }
                        .onTapGesture {
                            selectedImageURL = urlString
                        }
                        .overlay(
                            // Photo count indicator for first image
                            Group {
                                if review.mediaURLs.first == urlString && review.mediaURLs.count > 1 {
                                    VStack {
                                        HStack {
                                            Spacer()
                                            HStack(spacing: 2) {
                                                Image(systemName: "photo")
                                                    .font(.caption2)
                                                Text("\(review.mediaURLs.count)")
                                                    .font(.caption2)
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(4)
                                            .padding(4)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
    }
    
    private func replySection(reply: ReviewReply) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Owner's Reply")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            Text(reply.text)
                .font(.subheadline)
                .padding(8)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        HStack {
            // Helpful button
            Button(action: toggleHelpful) {
                HStack(spacing: 4) {
                    Image(systemName: isHelpful ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.caption)
                    Text("Helpful")
                        .font(.caption)
                    if helpfulCount > 0 {
                        Text("(\(helpfulCount))")
                            .font(.caption)
                    }
                }
                .foregroundColor(isHelpful ? .blue : .secondary)
            }
            .disabled(isOwnReview || isUpdating)
            
            Spacer()
            
            // Reply button (for profile owner only)
            if isProfileOwner && review.reply == nil && !isOwnReview {
                Button("Reply", action: { showingReplyForm = true })
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }
    
    private func toggleHelpful() {
        guard !isOwnReview else { return }
        
        isUpdating = true
        Task {
            do {
                let (isVoted, count) = try await ReviewRepository.shared.toggleHelpfulVote(for: review.id ?? "")
                await MainActor.run {
                    isHelpful = isVoted
                    helpfulCount = count
                    isUpdating = false
                }
            } catch {
                isUpdating = false
            }
        }
    }
    
    private func deleteReview() {
        Task {
            do {
                try await ReviewRepository.shared.delete(review.id ?? "")
            } catch {
            }
        }
    }
}

// Add this extension to make String Identifiable for sheet(item:)
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// Add this simple image viewer that actually works
struct SimpleImageViewer: View {
    let imageURL: String
    let allImageURLs: [String]
    @State private var currentImageURL: String
    @Environment(\.dismiss) var dismiss
    
    init(imageURL: String, allImageURLs: [String]) {
        self.imageURL = imageURL
        self.allImageURLs = allImageURLs
        _currentImageURL = State(initialValue: imageURL)
    }
    
    var currentIndex: Int {
        allImageURLs.firstIndex(of: currentImageURL) ?? 0
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    // Image display
                    if let url = URL(string: currentImageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            case .failure(_):
                                VStack(spacing: 16) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 60))
                                        .foregroundColor(.yellow)
                                    
                                    Text("Failed to load image")
                                        .foregroundColor(.white)
                                        .font(.headline)
                                }
                            case .empty:
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(2)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    
                    // Navigation controls if multiple images
                    if allImageURLs.count > 1 {
                        HStack(spacing: 40) {
                            Button(action: previousImage) {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                            }
                            .disabled(currentIndex == 0)
                            .opacity(currentIndex == 0 ? 0.3 : 1)
                            
                            Text("\(currentIndex + 1) / \(allImageURLs.count)")
                                .foregroundColor(.white)
                                .font(.headline)
                            
                            Button(action: nextImage) {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                            }
                            .disabled(currentIndex == allImageURLs.count - 1)
                            .opacity(currentIndex == allImageURLs.count - 1 ? 0.3 : 1)
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func previousImage() {
        if currentIndex > 0 {
            currentImageURL = allImageURLs[currentIndex - 1]
        }
    }
    
    private func nextImage() {
        if currentIndex < allImageURLs.count - 1 {
            currentImageURL = allImageURLs[currentIndex + 1]
        }
    }
}

// ReviewImageViewer_Fixed.swift
// Replace the ReviewImageViewer struct in ProfileSupportingViews.swift with this fixed version

struct ReviewImageViewer: View {
    let imageURLs: [String]
    let selectedIndex: Int
    
    @State private var currentIndex: Int
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastStoredOffset: CGSize = .zero
    @Environment(\.dismiss) var dismiss
    
    init(imageURLs: [String], selectedIndex: Int) {
        self.imageURLs = imageURLs
        self.selectedIndex = selectedIndex
        _currentIndex = State(initialValue: selectedIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .padding()
                }
                Spacer()
            }
            .zIndex(1)
            
            // Image viewer
            TabView(selection: $currentIndex) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                    GeometryReader { geometry in
                        AsyncImage(url: URL(string: url)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .scaleEffect(scale)
                                    .offset(offset)
                                    .gesture(
                                        MagnificationGesture()
                                            .onChanged { value in
                                                scale = value * lastScale
                                            }
                                            .onEnded { value in
                                                if scale < 1 {
                                                    withAnimation(.spring()) {
                                                        scale = 1
                                                        lastScale = 1
                                                    }
                                                } else {
                                                    lastScale = scale
                                                }
                                            }
                                    )
                                    .simultaneousGesture(
                                        DragGesture()
                                            .onChanged { value in
                                                if scale > 1 {
                                                    offset = CGSize(
                                                        width: lastStoredOffset.width + value.translation.width,
                                                        height: lastStoredOffset.height + value.translation.height
                                                    )
                                                }
                                            }
                                            .onEnded { value in
                                                if scale > 1 {
                                                    lastStoredOffset = offset
                                                } else {
                                                    withAnimation(.spring()) {
                                                        offset = .zero
                                                        lastStoredOffset = .zero
                                                    }
                                                }
                                            }
                                    )
                                    .onTapGesture(count: 2) {
                                        withAnimation(.spring()) {
                                            if scale > 1 {
                                                scale = 1
                                                lastScale = 1
                                                offset = .zero
                                                lastStoredOffset = .zero
                                            } else {
                                                scale = 2
                                                lastScale = 2
                                            }
                                        }
                                    }
                            case .failure(let error):
                                VStack(spacing: 16) {
                                    Image(systemName: "photo.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                    
                                    Text("Failed to load image")
                                        .foregroundColor(.white)
                                        .font(.headline)
                                    
                                    Text(error.localizedDescription)
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                    
                                    Button("Try Again") {
                                        // Force refresh by changing the URL slightly
                                        currentIndex = -1
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            currentIndex = index
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            case .empty:
                                VStack {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(1.5)
                                    Text("Loading...")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .padding(.top, 8)
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
            
            // Image counter
            if imageURLs.count > 1 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(currentIndex + 1) / \(imageURLs.count)")
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(20)
                            .padding()
                    }
                }
            }
        }
        .onAppear {
            // Reset any zoom when appearing
            scale = 1.0
            offset = .zero
            lastStoredOffset = .zero
        }
    }
}

// Alternative simpler version if the above still has issues:
struct SimpleReviewImageViewer: View {
    let imageURLs: [String]
    let selectedIndex: Int
    @Environment(\.dismiss) var dismiss
    @State private var currentIndex: Int
    
    init(imageURLs: [String], selectedIndex: Int) {
        self.imageURLs = imageURLs
        self.selectedIndex = selectedIndex
        _currentIndex = State(initialValue: selectedIndex)
    }
    
    var body: some View {
        NavigationView {
            TabView(selection: $currentIndex) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, urlString in
                    ZStack {
                        Color.black.ignoresSafeArea()
                        
                        if let url = URL(string: urlString) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                            } placeholder: {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(2)
                            }
                        } else {
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.yellow)
                                Text("Invalid image URL")
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle())
            .navigationBarHidden(false)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
    }
}


// CreateReviewView_Fixed.swift
// Replace the CreateReviewView struct in ProfileSupportingViews.swift with this fixed version

struct CreateReviewView: View {
    let userId: String
    @Environment(\.dismiss) var dismiss
    @State private var rating = 5
    @State private var reviewText = ""
    @State private var reviewImages: [UIImage] = []
    @State private var showingImagePicker = false
    @State private var isSubmitting = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var submitProgress: Double = 0
    
    var body: some View {
        NavigationView {
            Form {
                Section("Rating") {
                    HStack {
                        ForEach(1...5, id: \.self) { index in
                            Image(systemName: index <= rating ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundColor(index <= rating ? .yellow : .gray)
                                .onTapGesture {
                                    rating = index
                                }
                        }
                        Spacer()
                        Text(ratingText(for: rating))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Review") {
                    TextEditor(text: $reviewText)
                        .frame(minHeight: 100)
                }
                
                Section("Photos (Optional)") {
                    if !reviewImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Array(reviewImages.enumerated()), id: \.offset) { index, image in
                                    photoThumbnail(image: image, index: index)
                                }
                                
                                if reviewImages.count < 5 {
                                    addMorePhotosButton
                                }
                            }
                        }
                    } else {
                        addPhotosButton
                    }
                }
            }
            .navigationTitle("Write a Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Submit") {
                        Task {
                            await submitReview()
                        }
                    }
                    .disabled(reviewText.isEmpty || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 16) {
                                ProgressView(value: submitProgress)
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(1.5)
                                Text("Submitting review...")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(radius: 4)
                        )
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                // Use MultiImagePicker for reviews instead
                MultiImagePickerForReviews(images: $reviewImages)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // ... rest of the methods remain the same ...
    
    @ViewBuilder
    private func photoThumbnail(image: UIImage, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .cornerRadius(8)
            
            Button(action: {
                withAnimation {
                    var updatedImages = reviewImages
                    updatedImages.remove(at: index)
                    reviewImages = updatedImages
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
    }
    
    @ViewBuilder
    private var addMorePhotosButton: some View {
        Button(action: { showingImagePicker = true }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.title2)
                    Text("Add")
                        .font(.caption)
                }
                .foregroundColor(.gray)
            }
        }
    }
    
    @ViewBuilder
    private var addPhotosButton: some View {
        Button(action: { showingImagePicker = true }) {
            HStack {
                Image(systemName: "camera.fill")
                Text("Add Photos")
                Spacer()
                Text("Optional")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func ratingText(for rating: Int) -> String {
        switch rating {
        case 1: return "Poor"
        case 2: return "Fair"
        case 3: return "Good"
        case 4: return "Very Good"
        case 5: return "Excellent"
        default: return ""
        }
    }
    
    private func submitReview() async {
        isSubmitting = true
        submitProgress = 0.2
        
        
        do {
            // Add a small delay for UI feedback
            try await Task.sleep(nanoseconds: 200_000_000)
            submitProgress = 0.5
            
            // Debug: Check if we have images
            if !reviewImages.isEmpty {
                for (index, image) in reviewImages.enumerated() {
                    let size = image.size
                }
            } else {
            }
            
            // Create the review with images
            let createdReview = try await ReviewRepository.shared.createReview(
                for: userId,
                rating: rating,
                text: reviewText,
                images: reviewImages
            )
            
            if !createdReview.mediaURLs.isEmpty {
                for (index, url) in createdReview.mediaURLs.enumerated() {
                }
            }
            
            submitProgress = 1.0
            try await Task.sleep(nanoseconds: 300_000_000)
            
            dismiss()
        } catch {
            
            errorMessage = "Failed to submit review: \(error.localizedDescription)"
            showingError = true
            isSubmitting = false
            submitProgress = 0
        }
    }
}

// Add this new MultiImagePicker specifically for reviews
struct MultiImagePickerForReviews: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 5  // Allow up to 5 images for reviews
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MultiImagePickerForReviews
        private var loadCount = 0
        
        init(_ parent: MultiImagePickerForReviews) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            // Clear previous selections
            parent.images = []
            loadCount = 0
            
            // If no results, just return
            guard !results.isEmpty else { return }
            
            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                        if let image = image as? UIImage {
                            DispatchQueue.main.async {
                                self.parent.images.append(image)
                                self.loadCount += 1
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Other supporting views

struct ReplyToReviewView: View {
    let reviewId: String
    @Environment(\.dismiss) var dismiss
    @State private var replyText = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Your Reply") {
                    TextEditor(text: $replyText)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Reply to Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Submit") {
                        // Submit logic
                        dismiss()
                    }
                    .disabled(replyText.isEmpty)
                }
            }
        }
    }
}

struct EditReviewView: View {
    let review: Review
    @Environment(\.dismiss) var dismiss
    @State private var reviewText: String
    
    init(review: Review) {
        self.review = review
        _reviewText = State(initialValue: review.text)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Edit Review") {
                    TextEditor(text: $reviewText)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Edit Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // Save logic
                        dismiss()
                    }
                    .disabled(reviewText.isEmpty)
                }
            }
        }
    }
}

// MARK: - Followers/Following List Views
struct FollowersListView: View {
    let userId: String
    @Environment(\.dismiss) var dismiss
    @State private var followers: [User] = []
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        NavigationView {
            List(followers) { follower in
                NavigationLink(destination: EnhancedProfileView(userId: follower.id ?? "")) {
                    HStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(String(follower.name.first ?? "U"))
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading) {
                            Text(follower.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(follower.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Followers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                followers = (try? await UserRepository.shared.fetchFollowers(for: userId)) ?? []
            }
        }
    }
}

struct FollowingListView: View {
    let userId: String
    @Environment(\.dismiss) var dismiss
    @State private var following: [User] = []
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        NavigationView {
            List(following) { user in
                NavigationLink(destination: EnhancedProfileView(userId: user.id ?? "")) {
                    HStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(String(user.name.first ?? "U"))
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading) {
                            Text(user.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(user.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Following")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                following = (try? await UserRepository.shared.fetchFollowing(for: userId)) ?? []
            }
        }
    }
}

// MARK: - Saved Content Views

struct SavedPostCard: View {
    let post: ServicePost
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(post.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    if let price = post.price {
                        Text("$\(Int(price))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    Text(post.isRequest ? "REQUEST" : "OFFER")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(post.isRequest ? .orange : .blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            (post.isRequest ? Color.orange : Color.blue).opacity(0.1)
                        )
                        .cornerRadius(4)
                }
            }
            
            if let imageURL = post.imageURLs.first {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipped()
                        .cornerRadius(8)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct SavedReelThumbnail: View {
    let reel: Reel
    
    var body: some View {
        NavigationLink(destination: ReelViewerView(reel: reel)) {
            AsyncImage(url: URL(string: reel.thumbnailURL ?? reel.videoURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
                    .clipped()
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: UIScreen.main.bounds.width / 3 - 2, height: 180)
                    .overlay(
                        Image(systemName: "play.rectangle")
                            .foregroundColor(.gray)
                    )
            }
        }
    }
}

// MARK: - Create Portfolio Card View
struct CreatePortfolioCardView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var title = ""
    @State private var description = ""
    @State private var coverImage: UIImage?
    @State private var mediaImages: [UIImage] = []
    @State private var showingCoverPicker = false
    @State private var showingMediaPicker = false
    @State private var isCreating = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Portfolio Title") {
                    TextField("Enter title", text: $title)
                }
                
                Section("Description") {
                    TextField("Describe your work", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Cover Image (Optional)") {
                    if let cover = coverImage {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                            .clipped()  // No cornerRadius for square edges
                    }
                    
                    Button(action: { showingCoverPicker = true }) {
                        Label(coverImage == nil ? "Select Cover" : "Change Cover",
                              systemImage: coverImage == nil ? "photo" : "photo.badge.plus")
                    }
                }
                
                Section("Portfolio Images") {
                    Text("Selected: \(mediaImages.count) images")
                        .foregroundColor(.blue)
                    if !mediaImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Array(mediaImages.enumerated()), id: \.offset) { _, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipped()  // No cornerRadius for square edges
                                }
                            }
                        }
                    }
                    
                    Button(action: { showingMediaPicker = true }) {
                        Label("Add Images", systemImage: "photo.on.rectangle.angled")
                    }
                }
            }
            .navigationTitle("Create Portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        Task {
                            await createCard()
                        }
                    }
                    .disabled(title.isEmpty || isCreating)
                }
            }
        }
        .sheet(isPresented: $showingCoverPicker) {
            ImagePicker(images: .constant([]), singleImage: $coverImage)
        }
        .sheet(isPresented: $showingMediaPicker) {
            ImagePicker(images: $mediaImages, singleImage: .constant(nil))
        }
    }
    
    private func createCard() async {
        isCreating = true
        
        do {
            guard let userId = firebase.currentUser?.id else {
                return
            }
            
            var coverURL: String?
            var mediaURLs: [String] = []
            
            // Upload cover image if exists
            if let cover = coverImage {
                let path = "portfolio/\(userId)/\(UUID().uuidString)_cover.jpg"
                coverURL = try await firebase.uploadImage(cover, path: path)
            }
            
            // Upload media images
            for (index, image) in mediaImages.enumerated() {
                let path = "portfolio/\(userId)/\(UUID().uuidString)_\(index).jpg"
                let url = try await firebase.uploadImage(image, path: path)
                mediaURLs.append(url)
            }
            
            // Get existing cards for display order
            let existingCards = try await PortfolioRepository.shared.fetchPortfolioCards(for: userId)
            
            // Create portfolio card
            let newCard = PortfolioCard(
                userId: userId,
                title: title,
                coverImageURL: coverURL ?? "",
                mediaURLs: mediaURLs,
                description: description.isEmpty ? nil : description,
                displayOrder: existingCards.count
            )
            
            _ = try await PortfolioRepository.shared.createPortfolioCard(newCard)
            
            dismiss()
        } catch {
        }
        
        isCreating = false
    }
}

// Note: ImagePicker is imported from CameraView.swift - no need to duplicate it here
