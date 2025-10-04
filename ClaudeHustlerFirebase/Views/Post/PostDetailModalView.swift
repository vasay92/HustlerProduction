// PostDetailModalView.swift
// Path: ClaudeHustlerFirebase/Views/Post/PostDetailModalView.swift

import SwiftUI
import Firebase

struct PostDetailModalView: View {
    let post: ServicePost
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with close button
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .frame(width: 30, height: 30)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        Text(post.isRequest ? "REQUEST" : "OFFER")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(post.isRequest ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                            .foregroundColor(post.isRequest ? .orange : .blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Images if available
                    if !post.imageURLs.isEmpty {
                        TabView {
                            ForEach(Array(post.imageURLs.enumerated()), id: \.offset) { index, imageURL in
                                AsyncImage(url: URL(string: imageURL)) { image in
                                    image
                                        .resizable()
                                        .scaledToFit()
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .overlay(
                                            ProgressView()
                                        )
                                }
                                .frame(maxHeight: 350)
                            }
                        }
                        .frame(height: 350)
                        .tabViewStyle(PageTabViewStyle())
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Title
                        Text(post.title)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        // Price
                        if let price = post.price {
                            Text(post.isRequest ? "Budget: $\(Int(price))" : "$\(Int(price))")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(post.isRequest ? .orange : .green)
                        }
                        
                        // Category
                        HStack {
                            Image(systemName: categoryIcon(for: post.category))
                                .foregroundColor(.blue)
                            Text(post.category.displayName)
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(20)
                        
                        // Description
                        Text(post.description)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // Location if available
                        if let location = post.location {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.gray)
                                Text(location)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        // User info
                        HStack {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(post.userName?.first ?? "U"))
                                        .font(.caption)
                                        .foregroundColor(.white)
                                )
                            
                            VStack(alignment: .leading) {
                                Text(post.userName ?? "Unknown User")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Posted \(timeAgoString(from: post.updatedAt))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        
                        // Message button
                        if post.userId != firebase.currentUser?.id {
                            Button(action: {
                                dismiss()
                                // You can add message functionality here later
                            }) {
                                HStack {
                                    Image(systemName: "message.fill")
                                    Text("Send Message")
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 50)
                }
                .padding(.top)
            }
            .navigationBarHidden(true)
        }
    }
    
    
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
