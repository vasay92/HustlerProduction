// StatusViewerView.swift
// Path: ClaudeHustlerFirebase/Views/Components/StatusViewerView.swift
// FIXED: Use createdAt directly since it's not optional

import SwiftUI
import FirebaseFirestore
import AVKit

struct StatusViewerView: View {
    let status: Status
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    @State private var showingMenu = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var progress: CGFloat = 0
    @State private var timer: Timer?
    @State private var dragOffset: CGSize = .zero
    
    var isOwnStatus: Bool {
        status.userId == firebase.currentUser?.id
    }
    
    // Computed properties for drag effects
    private var dragScale: CGFloat {
        let height = abs(dragOffset.height)
        return 1.0 - (height / 1000.0)
    }
    
    private var dragOpacity: Double {
        let height = abs(dragOffset.height)
        return 1.0 - (height / 500.0)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Display content based on media type
            Group {
                if status.mediaType == .video {
                    // Video player for video statuses
                    if let url = URL(string: status.mediaURL) {
                        VideoPlayer(player: AVPlayer(url: url))
                            .ignoresSafeArea()
                    }
                } else {
                    // Image for photo statuses
                    AsyncImage(url: URL(string: status.mediaURL)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
            }
            .offset(y: dragOffset.height)
            .scaleEffect(dragScale)
            .opacity(dragOpacity)
            
            // Overlay with user info and controls
            VStack {
                // Top section with progress bar and user info
                VStack(spacing: 0) {
                    // Progress bar (WhatsApp style)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 3)
                            
                            // Progress
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: geometry.size.width * progress, height: 3)
                                .animation(.linear(duration: 0.1), value: progress)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 8)
                    .padding(.top, 50) // Account for safe area
                    
                    // User info bar
                    HStack(spacing: 12) {
                        // User profile image
                        AsyncImage(url: URL(string: status.userProfileImage ?? "")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } placeholder: {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(status.userName?.first ?? "U"))
                                        .foregroundColor(.white)
                                )
                        }
                        
                        // Username and time created
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.userName ?? "User")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            // FIXED: Use createdAt directly since it's not optional
                            Text(timeAgoString(from: status.createdAt))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        // Menu button (three dots)
                        Menu {
                            if isOwnStatus {
                                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                                    Label("Delete Status", systemImage: "trash")
                                }
                            } else {
                                Button(action: { reportStatus() }) {
                                    Label("Report", systemImage: "flag")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                }
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.8), Color.clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                Spacer()
                
                // Bottom caption if exists
                if let caption = status.caption, !caption.isEmpty {
                    HStack {
                        Text(caption)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(10)
                        
                        Spacer()
                    }
                    .padding()
                }
            }
            
            // Loading overlay when deleting
            if isDeleting {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                
                ProgressView("Deleting...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    // If dragged down more than 100 points, dismiss
                    if value.translation.height > 100 {
                        dismiss()
                    } else {
                        // Spring back to original position
                        withAnimation(.spring()) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onTapGesture {
            // Pause/resume progress on tap
            if timer != nil {
                pauseProgress()
            } else {
                resumeProgress()
            }
        }
        .onAppear {
            markStatusAsViewed()
            startProgress()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .alert("Delete Status?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteStatus()
            }
        } message: {
            Text("This will permanently remove your status. This action cannot be undone.")
        }
    }
    
    // MARK: - Helper Methods
    
    private func startProgress() {
        progress = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.linear(duration: 0.05)) {
                progress += 0.01 // 0.05 seconds * 20 = 1 second, so 0.01 * 100 = 1 in 5 seconds
                
                if progress >= 1.0 {
                    timer?.invalidate()
                    timer = nil
                    dismiss()
                }
            }
        }
    }
    
    private func pauseProgress() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resumeProgress() {
        if progress < 1.0 {
            startProgress()
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short  // Shows time like "5:05 PM"
        formatter.dateStyle = .none   // No date, just time
        return formatter.string(from: date)
    }
    
    private func markStatusAsViewed() {
        guard let statusId = status.id,
              let currentUserId = firebase.currentUser?.id,
              !status.viewedBy.contains(currentUserId) else { return }
        
        Task {
            do {
                try await StatusRepository.shared.markAsViewed(statusId, by: currentUserId)
            } catch {
                print("Error marking status as viewed: \(error)")
            }
        }
    }
    
    private func deleteStatus() {
        guard let statusId = status.id, isOwnStatus else { return }
        
        isDeleting = true
        timer?.invalidate()
        
        Task {
            do {
                // Delete using StatusRepository
                try await StatusRepository.shared.delete(statusId)
                
                // Dismiss the view after successful deletion
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    print("Error deleting status: \(error)")
                }
            }
        }
    }
    
    private func reportStatus() {
        // Implement reporting logic here
        // For now, just print
        print("Status reported: \(status.id ?? "")")
        // You could show an alert confirming the report was submitted
    }
}
