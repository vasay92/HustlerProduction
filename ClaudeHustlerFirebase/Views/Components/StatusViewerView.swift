// StatusViewerView.swift
// This viewer handles multiple statuses per user like Instagram/WhatsApp
// FIXED: Removed X button, added swipe to dismiss, fixed tap areas

import SwiftUI
import FirebaseFirestore
import AVKit

struct StatusViewerView: View {
    let initialUserId: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    
    // Status management
    @State private var userStatuses: [Status] = []
    @State private var currentStatusIndex = 0
    @State private var isLoading = true
    
    // UI States
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var progress: CGFloat = 0
    @State private var timer: Timer?
    @State private var isPaused = false
    
    // Current status being viewed
    private var currentStatus: Status? {
        guard currentStatusIndex < userStatuses.count else { return nil }
        return userStatuses[currentStatusIndex]
    }
    
    private var isOwnStatus: Bool {
        initialUserId == firebase.currentUser?.id
    }
    
    private var userName: String {
        currentStatus?.userName ?? "User"
    }
    
    private var userProfileImage: String? {
        currentStatus?.userProfileImage
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if let status = currentStatus {
                // Status content
                statusContent(status)
                
                // Overlay UI
                VStack(spacing: 0) {
                    // Multi-segment progress bar at top
                    multiSegmentProgressBar
                        .padding(.top, 50)
                    
                    // User info header
                    statusHeader
                    
                    Spacer()
                    
                    // Caption at bottom
                    if let caption = status.caption, !caption.isEmpty {
                        Text(caption)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
                            .padding()
                    }
                }
                
                // Navigation tap areas - ONLY in the middle section
                HStack(spacing: 0) {
                    // Left side - Previous
                    Color.clear
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.3)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            moveToPreviousStatus()
                        }
                    
                    // Center area - no tap
                    Spacer()
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.4)
                    
                    // Right side - Next
                    Color.clear
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.3)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            moveToNextStatus()
                        }
                }
                .padding(.top, 120) // Start below header
                .padding(.bottom, 100) // End above caption
                
                // Long press to pause anywhere
                .gesture(
                    LongPressGesture(minimumDuration: 0.1)
                        .onChanged { _ in
                            if !isPaused {
                                pauseProgress()
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { _ in
                            if isPaused {
                                resumeProgress()
                            }
                        }
                )
            } else {
                VStack {
                    Text("No statuses available")
                        .foregroundColor(.white)
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            
            // Loading overlay when deleting
            if isDeleting {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                ProgressView("Deleting...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
            }
        }
        // Add swipe down gesture to dismiss
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    }
                }
        )
        .task {
            await loadUserStatuses()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .confirmationDialog("Delete Status?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteCurrentStatus()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove this status.")
        }
    }
    
    // MARK: - Multi-segment Progress Bar (like Instagram)
    @ViewBuilder
    private var multiSegmentProgressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<userStatuses.count, id: \.self) { index in
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .cornerRadius(2)
                        
                        // Progress
                        Rectangle()
                            .fill(Color.white)
                            .cornerRadius(2)
                            .frame(width: progressWidth(for: index, in: geometry))
                            .animation(.linear(duration: 0.05), value: progress)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal)
    }
    
    private func progressWidth(for index: Int, in geometry: GeometryProxy) -> CGFloat {
        if index < currentStatusIndex {
            // Completed segments
            return geometry.size.width
        } else if index == currentStatusIndex {
            // Current segment
            return geometry.size.width * progress
        } else {
            // Future segments
            return 0
        }
    }
    
    // MARK: - Status Header (FIXED: Removed X button, improved tap areas)
    @ViewBuilder
    private var statusHeader: some View {
        HStack {
            // Profile image
            AsyncImage(url: URL(string: userProfileImage ?? "")) { image in
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
                        Text(String(userName.first ?? "U"))
                            .foregroundColor(.white)
                    )
            }
            
            // Username and time
            VStack(alignment: .leading, spacing: 2) {
                Text(userName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                if let status = currentStatus {
                    Text(timeAgoString(from: status.createdAt))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            Spacer()
            
            // Status count indicator
            if userStatuses.count > 1 {
                Text("\(currentStatusIndex + 1) / \(userStatuses.count)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(10)
            }
            
            // Menu button with proper tap area
            Menu {
                if isOwnStatus {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete This Status", systemImage: "trash")
                    }
                } else {
                    Button {
                        reportStatus()
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44) // Proper tap area
                    .contentShape(Rectangle())
            }
            // REMOVED X button - use swipe down instead
        }
        .padding()
        .background(Color.clear) // Ensure header doesn't block taps
        .zIndex(1) // Ensure menu is above tap areas
    }
    
    // MARK: - Status Content
    @ViewBuilder
    private func statusContent(_ status: Status) -> some View {
        AsyncImage(url: URL(string: status.mediaURL)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure(_):
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                    Text("Failed to load image")
                        .foregroundColor(.white)
                }
            case .empty:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            @unknown default:
                EmptyView()
            }
        }
    }
    
    // MARK: - Navigation Methods
    
    private func moveToNextStatus() {
        timer?.invalidate()
        
        if currentStatusIndex < userStatuses.count - 1 {
            currentStatusIndex += 1
            progress = 0
            startProgress()
            markCurrentStatusAsViewed()
        } else {
            // All statuses viewed
            dismiss()
        }
    }
    
    private func moveToPreviousStatus() {
        timer?.invalidate()
        
        if currentStatusIndex > 0 {
            currentStatusIndex -= 1
            progress = 0
            startProgress()
        }
    }
    
    // MARK: - Timer Management
    
    private func startProgress() {
        progress = 0
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.linear(duration: 0.05)) {
                progress += 0.01 // 5 seconds per status
                
                if progress >= 1.0 {
                    moveToNextStatus()
                }
            }
        }
    }
    
    private func pauseProgress() {
        isPaused = true
        timer?.invalidate()
    }
    
    private func resumeProgress() {
        if isPaused {
            isPaused = false
            // Resume from current progress, don't restart
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                withAnimation(.linear(duration: 0.05)) {
                    progress += 0.01
                    
                    if progress >= 1.0 {
                        moveToNextStatus()
                    }
                }
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadUserStatuses() async {
        isLoading = true
        
        do {
            // Fetch ALL statuses for this user
            userStatuses = try await StatusRepository.shared.fetchAllUserStatuses(for: initialUserId)
            
            if !userStatuses.isEmpty {
                // Start viewing from first status
                currentStatusIndex = 0
                startProgress()
                markCurrentStatusAsViewed()
            }
        } catch {
            
            userStatuses = []
        }
        
        isLoading = false
    }
    
    // MARK: - Helper Methods
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
    
    private func markCurrentStatusAsViewed() {
        guard let status = currentStatus,
              let statusId = status.id,
              let currentUserId = firebase.currentUser?.id,
              !status.viewedBy.contains(currentUserId) else { return }
        
        Task {
            try? await StatusRepository.shared.markAsViewed(statusId, by: currentUserId)
        }
    }
    
    private func deleteCurrentStatus() {
        guard let status = currentStatus,
              let statusId = status.id,
              isOwnStatus else { return }
        
        isDeleting = true
        timer?.invalidate()
        
        Task {
            do {
                try await StatusRepository.shared.delete(statusId)
                
                // Remove from local array
                userStatuses.remove(at: currentStatusIndex)
                
                if userStatuses.isEmpty {
                    // No more statuses, dismiss
                    await MainActor.run {
                        dismiss()
                    }
                } else {
                    // Adjust index if needed
                    if currentStatusIndex >= userStatuses.count {
                        currentStatusIndex = userStatuses.count - 1
                    }
                    // Continue with remaining statuses
                    await MainActor.run {
                        isDeleting = false
                        progress = 0
                        startProgress()
                    }
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                   
                }
            }
        }
    }
    
    private func reportStatus() {
        
        // Implement reporting logic
    }
}

// MARK: - Convenience initializer for backward compatibility
extension StatusViewerView {
    init(status: Status) {
        self.init(initialUserId: status.userId)
    }
}
