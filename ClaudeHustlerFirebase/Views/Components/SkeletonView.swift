

// SkeletonView.swift
// Path: ClaudeHustlerFirebase/Views/Components/SkeletonView.swift

import SwiftUI

struct SkeletonView: View {
    @State private var isAnimating = false
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.2),
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.2)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .offset(x: isAnimating ? 200 : -200)
            .animation(
                Animation.linear(duration: 1.5)
                    .repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// Skeleton for a service card
struct ServiceCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonView()
                .frame(height: 150)
                .cornerRadius(10)
            
            SkeletonView()
                .frame(height: 20)
                .cornerRadius(4)
            
            SkeletonView()
                .frame(height: 16)
                .frame(maxWidth: 200)
                .cornerRadius(4)
            
            HStack {
                SkeletonView()
                    .frame(width: 60, height: 24)
                    .cornerRadius(12)
                
                Spacer()
                
                SkeletonView()
                    .frame(width: 80, height: 24)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
}

// Skeleton for list items
struct ListItemSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonView()
                .frame(width: 80, height: 80)
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 8) {
                SkeletonView()
                    .frame(height: 18)
                    .cornerRadius(4)
                
                SkeletonView()
                    .frame(height: 14)
                    .frame(maxWidth: 150)
                    .cornerRadius(4)
                
                HStack {
                    SkeletonView()
                        .frame(width: 60, height: 20)
                        .cornerRadius(10)
                    
                    SkeletonView()
                        .frame(width: 40, height: 20)
                        .cornerRadius(10)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
