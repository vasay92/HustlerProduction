// HomeView.swift
// Path: ClaudeHustlerFirebase/Views/Home/HomeView.swift

import SwiftUI
import FirebaseFirestore

struct HomeView: View {
    @StateObject private var firebase = FirebaseService.shared
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var notificationsViewModel = NotificationsViewModel()
    @State private var showingMessages = false
    @State private var showingNotifications = false
    @State private var showingCategories = false
    @State private var showingCreatePost = false
    
    
    
            var body: some View {
                HomeMapView()
            }
}
