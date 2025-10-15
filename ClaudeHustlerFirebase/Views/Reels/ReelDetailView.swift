// ReelDetailView.swift
// Path: ClaudeHustlerFirebase/Views/Reels/ReelDetailView.swift

import SwiftUI

struct ReelDetailView: View {
    let reelId: String
    @StateObject private var viewModel = ReelsViewModel()
    @State private var reel: Reel?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            if let reel = reel {
                ReelViewerView(reel: reel)
                    .ignoresSafeArea()
            } else {
                ProgressView("Loading reel...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
            }
        }
        .task {
            await loadReel()
        }
    }
    
    private func loadReel() async {
        do {
            reel = try await ReelRepository.shared.fetchById(reelId)
        } catch {
            
        }
    }
}
