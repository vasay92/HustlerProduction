// PostDetailModalView.swift
// Path: ClaudeHustlerFirebase/Views/Post/PostDetailModalView.swift

import SwiftUI
import Firebase
import MapKit

struct PostDetailModalView: View {
    let post: ServicePost
    @Environment(\.dismiss) var dismiss
    @State private var region: MKCoordinateRegion
    
    init(post: ServicePost) {
        self.post = post
        
        // Initialize map region
        if let coordinates = post.coordinates {
            let center = CLLocationCoordinate2D(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude
            )
            _region = State(initialValue: MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        } else {
            // Default to a general location if no coordinates
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            ))
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Map preview if coordinates available
                    if post.coordinates != nil {
                        Map(coordinateRegion: $region, annotationItems: [post]) { post in
                            MapAnnotation(coordinate: CLLocationCoordinate2D(
                                latitude: post.coordinates!.latitude,
                                longitude: post.coordinates!.longitude
                            )) {
                                VStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title)
                                        .foregroundColor(post.isRequest ? .orange : .blue)
                                    
                                    Text(post.title)
                                        .font(.caption)
                                        .padding(4)
                                        .background(Color.white)
                                        .cornerRadius(4)
                                        .shadow(radius: 2)
                                }
                            }
                        }
                        .frame(height: 200)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    
                    // Post details
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
                        
                        // UPDATED: Tags instead of category
                        if !post.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(post.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundColor(.blue)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                        }
                        
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
                                    .fontWeight(.semibold)
                                
                                Text("View Profile")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                        }
                        .padding(.top)
                    }
                    .padding(.horizontal)
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: {}) {
                            Label("Message", systemImage: "message")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "bookmark")
                                .frame(width: 50, height: 50)
                                .background(Color(.systemGray5))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .navigationTitle("Service Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

