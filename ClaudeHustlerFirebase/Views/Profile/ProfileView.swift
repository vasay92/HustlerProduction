// ProfileView.swift
// Path: ClaudeHustlerFirebase/Views/Profile/ProfileView.swift

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// This is now a wrapper that redirects to EnhancedProfileView for the current user
struct ProfileView: View {
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        // Show the new EnhancedProfileView with current user's ID
        if let userId = firebase.currentUser?.id {
            EnhancedProfileView(userId: userId)
        } else {
            // Fallback if no user is logged in
            VStack {
                Image(systemName: "person.circle")
                    .font(.system(size: 80))
                    .foregroundColor(.gray)
                
                Text("Please log in to view your profile")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }
}

// Keep the SettingsView here since it's still being used
// SettingsView.swift
// Path: ClaudeHustlerFirebase/Views/Profile/ProfileView.swift
// UPDATED: Complete rewrite with Privacy Policy, Terms of Service, Contact Form, and Functional Change Password
// REMOVED: Language, Help Center, Notifications, Report Problem, Privacy
// CONTACT EMAIL: contactus.hustler@gmail.com



struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    
    var body: some View {
        NavigationView {
            List {
                // MARK: - Account Section
                Section("Account") {
                    NavigationLink("Edit Profile") {
                        EditProfileView()
                    }
                    
                    NavigationLink("Change Password") {
                        ChangePasswordView()
                    }
                }
                
                // MARK: - Legal Section
                Section("Legal") {
                    NavigationLink("Terms of Service") {
                        TermsOfServiceView()
                    }
                    
                    NavigationLink("Privacy Policy") {
                        PrivacyPolicyView()
                    }
                }
                
                // MARK: - Support Section
                Section("Support") {
                    NavigationLink("Contact Us") {
                        ContactSupportView()
                    }
                }
                
                // MARK: - Sign Out
                Section {
                    Button(action: {
                        try? firebase.signOut()
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.square")
                            Text("Sign Out")
                        }
                        .foregroundColor(.red)
                    }
                }
                
                // MARK: - App Version
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Change Password View
struct ChangePasswordView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isChanging = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    
    var body: some View {
        Form {
            Section {
                SecureField("Enter current password", text: $currentPassword)
                    .textContentType(.password)
                    .autocapitalization(.none)
            } header: {
                Text("Current Password")
            }
            
            Section {
                SecureField("Enter new password", text: $newPassword)
                    .textContentType(.newPassword)
                    .autocapitalization(.none)
                
                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .autocapitalization(.none)
            } header: {
                Text("New Password")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password must contain:")
                        .font(.caption)
                    Text("• At least 8 characters")
                        .font(.caption2)
                    Text("• Upper & lowercase letters")
                        .font(.caption2)
                    Text("• At least one number")
                        .font(.caption2)
                    Text("• At least one special character")
                        .font(.caption2)
                }
            }
            
            Section {
                Button(action: { changePassword() }) {
                    if isChanging {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        HStack {
                            Spacer()
                            Text("Change Password")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
                .disabled(!isFormValid || isChanging)
            }
        }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showingSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your password has been changed successfully")
        }
    }
    
    private var isFormValid: Bool {
        !currentPassword.isEmpty &&
        !newPassword.isEmpty &&
        !confirmPassword.isEmpty &&
        newPassword == confirmPassword &&
        newPassword.count >= 8
    }
    
    private func changePassword() {
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match"
            showingError = true
            return
        }
        
        let passwordValidation = SecurityService.validatePassword(newPassword)
        guard passwordValidation.isValid else {
            errorMessage = passwordValidation.errors.joined(separator: "\n")
            showingError = true
            return
        }
        
        isChanging = true
        
        Task {
            do {
                guard let user = firebase.auth.currentUser,
                      let email = user.email else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not found"])
                }
                
                let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
                try await user.reauthenticate(with: credential)
                try await user.updatePassword(to: newPassword)
                
                await MainActor.run {
                    isChanging = false
                    showingSuccess = true
                }
            } catch {
                await MainActor.run {
                    isChanging = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

// MARK: - Contact Support View
struct ContactSupportView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var firebase = FirebaseService.shared
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                VStack(spacing: 10) {
                    Image(systemName: "envelope.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Contact Support")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("We typically respond within 24 hours")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("First Name")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("Enter your first name", text: $firstName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.words)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Name")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("Enter your last name", text: $lastName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.words)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextEditor(text: $message)
                            .frame(minHeight: 150)
                            .padding(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                            .overlay(
                                Group {
                                    if message.isEmpty {
                                        Text("How can we help you?")
                                            .foregroundColor(Color(.placeholderText))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 16)
                                            .allowsHitTesting(false)
                                    }
                                },
                                alignment: .topLeading
                            )
                    }
                    
                    Button(action: { sendMessage() }) {
                        if isSending {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Sending...")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        } else {
                            Text("Send Message")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isFormValid ? Color.blue : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .disabled(!isFormValid || isSending)
                }
                .padding(.horizontal)
                
                Spacer(minLength: 40)
            }
        }
        .navigationTitle("Contact Us")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Success!", isPresented: $showingSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your message has been sent successfully. We'll get back to you soon!")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        message.count >= 10
    }
    
    private func sendMessage() {
        guard isFormValid else { return }
        
        isSending = true
        
        Task {
            do {
                let userEmail = firebase.currentUser?.email ?? "No email"
                let userId = firebase.currentUser?.id ?? "No ID"
                
                let emailSubject = "Support Request from \(firstName) \(lastName)"
                let emailBody = """
                Support Request Details:
                
                Name: \(firstName) \(lastName)
                User Email: \(userEmail)
                User ID: \(userId)
                
                Message:
                \(message)
                
                ---
                Sent from ClaudeHustler App
                """
                
                let email = "contactus.hustler@gmail.com"
                let subject = emailSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let body = emailBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                
                if let url = URL(string: "mailto:\(email)?subject=\(subject)&body=\(body)") {
                    await MainActor.run {
                        if UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                isSending = false
                                showingSuccess = true
                            }
                        } else {
                            isSending = false
                            errorMessage = "Unable to open mail app. Please email us directly at contactus.hustler@gmail.com"
                            showingError = true
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Failed to send message. Please try again."
                    showingError = true
                }
            }
        }
    }
}

// MARK: - Terms of Service View (FROM YOUR WEBSITE)
struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Terms of Service")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Text("Last Updated: October 17, 2025")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Effective Date: October 17, 2025")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // Introduction
                Text("Introduction")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Welcome to Hustler. These Terms of Service govern your access to and use of the Hustler mobile application and services.")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Text("IMPORTANT: By accessing or using Hustler, you agree to be bound by these Terms. If you do not agree to these Terms, do not use the App.")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                
                // 1. Acceptance of Terms
                SectionView(
                    title: "1. Acceptance of Terms",
                    content: "By creating an account, accessing, or using the Hustler App, you agree to these Terms of Service, our Privacy Policy, and any additional guidelines we may post in the App.\n\nWe reserve the right to modify these Terms at any time. Your continued use of the App after changes constitutes acceptance of the modified Terms.\n\nTo use Hustler, you must be at least 13 years old (or 16 in Europe), have the legal capacity to enter into a binding agreement, and comply with all applicable laws."
                )
                
                // 2. Account Registration
                SectionView(
                    title: "2. Account Registration and Security",
                    content: "You must provide accurate, current, and complete information when creating your account. You are responsible for maintaining the confidentiality of your login credentials and all activities that occur under your account.\n\nYou may only create one account per person. We reserve the right to suspend or terminate your account if you violate these Terms, engage in fraudulent activity, or harm other users."
                )
                
                // 3. User Conduct
                SectionView(
                    title: "3. User Conduct and Content",
                    content: "You agree NOT to: violate any laws, harass or bully others, spam or use bots, post inappropriate content, engage in fraudulent behavior, or impersonate others.\n\nYou are solely responsible for all content you create, upload, or share. By posting content, you grant us a non-exclusive, worldwide, royalty-free license to use, reproduce, modify, and display your content for operating and improving the App.\n\nWe reserve the right to monitor, review, or remove any content that violates these Terms."
                )
                
                // 4. Service Posts
                SectionView(
                    title: "4. Service Posts (Offers and Requests)",
                    content: "When creating service posts, you must provide accurate and truthful information. Hustler is a platform to connect users - we are NOT responsible for the quality, safety, or legality of services, transactions between users, or any disputes that arise.\n\nExercise caution when engaging with other users. Verify information independently, meet in public places, and report suspicious activity immediately."
                )
                
                // 5. Reels and Media
                SectionView(
                    title: "5. Reels, Status, and Media Content",
                    content: "When posting reels, status updates, or photos, you must own the rights to all media content. Content must comply with our guidelines - no copyrighted material, explicit content, or inappropriate content.\n\nStatus updates automatically delete after 24 hours. We are not responsible for saving or backing up status content."
                )
                
                // 6. Messages
                SectionView(
                    title: "6. Messages and Communications",
                    content: "Messages are intended for legitimate service-related communication. Do not send spam, harassment, or unsolicited commercial messages.\n\nMessages are private between sender and recipient, but we may monitor messages for safety purposes and may access messages if required by law."
                )
                
                // 7. Reviews
                SectionView(
                    title: "7. Reviews and Ratings",
                    content: "Base reviews on genuine personal experience and provide honest feedback. Do not post fake, fraudulent, or paid reviews. Do not use reviews to harass or defame others.\n\nWe may remove reviews that violate these Terms, contain false statements, or are spam. You may respond to reviews on your profile respectfully and professionally."
                )
                
                // 8. Intellectual Property
                SectionView(
                    title: "8. Intellectual Property Rights",
                    content: "The App and all content, features, and functionality are owned by us and protected by copyright and trademark laws. We grant you a limited license to access and use the App for personal, non-commercial purposes.\n\nYou may NOT copy, modify, distribute, reverse engineer, or remove copyright notices from the App."
                )
                
                // 9. Privacy
                SectionView(
                    title: "9. Privacy and Data",
                    content: "Your privacy is important to us. Please review our Privacy Policy to understand what information we collect and how we use it.\n\nBy using location features, you consent to collection of location data. By using camera features, you consent to camera and photo library access. You can disable these permissions in your device settings."
                )
                
                // 10. Third-Party Services
                SectionView(
                    title: "10. Third-Party Services",
                    content: "The App may contain links to third-party websites or services. We are not responsible for the content or practices of third-party sites.\n\nWe use Google Firebase for authentication, database hosting, file storage, and analytics. Your use of Firebase is subject to Google's Terms of Service and Privacy Policy."
                )
                
                // 11. Disclaimers
                SectionView(
                    title: "11. Disclaimers and Limitations of Liability",
                    content: "THE APP IS PROVIDED \"AS IS\" WITHOUT WARRANTIES OF ANY KIND. We do not guarantee uninterrupted or error-free operation, and we are NOT responsible for actions of users, quality of services, or disputes between users.\n\nTO THE MAXIMUM EXTENT PERMITTED BY LAW, WE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, OR CONSEQUENTIAL DAMAGES. Our total liability shall not exceed $100."
                )
                
                // 12. Indemnification
                SectionView(
                    title: "12. Indemnification",
                    content: "You agree to indemnify and hold us harmless from any claims, damages, losses, and expenses arising from your use of the App, your violation of these Terms, or your interactions with other users."
                )
                
                // 13. Dispute Resolution
                SectionView(
                    title: "13. Dispute Resolution",
                    content: "These Terms are governed by the laws of the United States. You agree that any disputes will be resolved through binding arbitration, NOT in court. BY AGREEING TO THESE TERMS, YOU WAIVE YOUR RIGHT TO A JURY TRIAL AND CLASS ACTION.\n\nYou may opt out of arbitration within 30 days by sending written notice to contactus.hustler@gmail.com."
                )
                
                // 14. Termination
                SectionView(
                    title: "14. Termination",
                    content: "You may terminate your account at any time through the Delete Account feature. We may suspend or terminate your account immediately if you violate these Terms.\n\nUpon termination, your access ceases and your data will be deleted within 30 days (subject to legal requirements)."
                )
                
                // Contact
                SectionView(
                    title: "15. Contact Us",
                    content: "If you have questions about these Terms of Service, please contact us at:\n\nEmail: contactus.hustler@gmail.com"
                )
                
                // Acknowledgment
                Text("ACKNOWLEDGMENT")
                    .font(.headline)
                    .fontWeight(.bold)
                    .padding(.top, 10)
                
                Text("BY USING HUSTLER, YOU ACKNOWLEDGE THAT:\n\n• You have read and understood these Terms\n• You agree to be bound by these Terms\n• You are at least 13 years old (or 16 in Europe)\n• You will comply with all applicable laws\n• You understand the risks of interacting with other users online")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Privacy Policy View (FROM YOUR WEBSITE)
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Text("Last Updated: October 17, 2025")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Effective Date: October 17, 2025")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // Introduction
                Text("Introduction")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Welcome to Hustler. We respect your privacy and are committed to protecting your personal information. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application.")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                // 1. Information We Collect
                SectionView(
                    title: "1. Information We Collect",
                    content: "We collect information you provide directly:\n\n• Account Information: Name, email, profile photo, bio, location, service provider status\n• Content You Create: Service posts, photos, videos, reels, status updates, portfolio items, comments, reviews, messages\n• Automatically Collected: Device information, usage data, location information (with permission), camera and photo library access (with permission)\n\nLocation is used to show nearby services on the map. Camera access is used to create posts, reels, and update your profile. You can disable these permissions in your device settings."
                )
                
                // 2. How We Use Your Information
                SectionView(
                    title: "2. How We Use Your Information",
                    content: "We use collected information to:\n\n• Provide and maintain the service (create accounts, enable posts, facilitate messaging, display maps)\n• Improve our service (analyze usage, fix bugs, develop features)\n• Communicate with you (notifications, support, announcements)\n• Ensure safety and security (detect fraud, enforce Terms, monitor for abuse)\n• For analytics (understand user demographics and preferences)"
                )
                
                // 3. How We Share Your Information
                SectionView(
                    title: "3. How We Share Your Information",
                    content: "Public Information visible to all users: Your name, profile photo, bio, location (if provided), service posts, reels, status updates, portfolio items, comments, and reviews.\n\nWe share information with:\n• Other Users: When you message them or interact with their content\n• Firebase (Google): For authentication, database, storage, and analytics\n• Legal Requirements: When required by law or to protect our rights\n\nWe do NOT sell your personal information to third parties."
                )
                
                // 4. Data Security
                SectionView(
                    title: "4. Data Security",
                    content: "We implement security measures including Firebase Authentication, encrypted data transmission (HTTPS/TLS), secure cloud storage, access controls, and regular security monitoring.\n\nHowever, no method of transmission over the internet is 100% secure. You are responsible for keeping your login credentials secure."
                )
                
                // 5. Your Privacy Rights
                SectionView(
                    title: "5. Your Privacy Rights and Choices",
                    content: "You have the right to:\n\n• Access: View your information in settings\n• Update: Edit your profile and posts anytime\n• Delete: Remove posts or your entire account\n• Export: Request a copy of your data\n• Control Permissions: Manage location, camera, and notification access in device settings\n\nTo delete your account: Profile → Settings → Delete Account\nYour data will be permanently deleted within 30 days."
                )
                
                // 6. Children's Privacy
                SectionView(
                    title: "6. Children's Privacy",
                    content: "Hustler is not intended for children under 13 years of age. We do not knowingly collect information from children under 13. If we learn we have collected such information, we will promptly delete it.\n\nYou must be at least 13 years old to use this App."
                )
                
                // 7. International Users
                SectionView(
                    title: "7. International Users",
                    content: "If you are accessing the App from outside the United States, your information may be transferred to and processed in the United States. By using the App, you consent to this transfer.\n\nFor European Union users, you have additional rights under GDPR including data portability, right to object to processing, and right to lodge complaints with supervisory authorities."
                )
                
                // 8. Data Retention
                SectionView(
                    title: "8. Data Retention",
                    content: "We retain your information as long as your account is active or as needed to provide services.\n\nUpon account deletion:\n• Most data is deleted within 30 days\n• Some information may be retained in backups for up to 90 days\n• Certain data may be retained longer if required by law"
                )
                
                // 9. Third-Party Services
                SectionView(
                    title: "9. Third-Party Services",
                    content: "We use Firebase (by Google) for authentication, database hosting, file storage, and analytics. Firebase's Privacy Policy applies to their services.\n\nIf you share content to social media platforms, those services' privacy policies apply to the shared content."
                )
                
                // 10. California Privacy Rights
                SectionView(
                    title: "10. California Privacy Rights (CCPA)",
                    content: "If you are a California resident, you have the right to:\n\n• Know what personal information we collect\n• Know whether we sell or share your information (we do not)\n• Access your personal information\n• Delete your personal information\n• Non-discrimination for exercising your rights\n\nContact contactus.hustler@gmail.com to exercise these rights."
                )
                
                // 11. Changes to Privacy Policy
                SectionView(
                    title: "11. Changes to This Privacy Policy",
                    content: "We may update this Privacy Policy from time to time. We will notify you of significant changes by posting the new Privacy Policy in the App and sending an in-app notification or email.\n\nYour continued use after changes constitutes acceptance of the updated policy."
                )
                
                // Contact
                SectionView(
                    title: "12. Contact Us",
                    content: "If you have questions or concerns about this Privacy Policy, please contact us at:\n\nEmail: contactus.hustler@gmail.com"
                )
                
                // Consent
                Text("CONSENT")
                    .font(.headline)
                    .fontWeight(.bold)
                    .padding(.top, 10)
                
                Text("By using Hustler, you acknowledge that you have read and understood this Privacy Policy and agree to its terms.")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                // Quick Summary
                Text("Quick Summary")
                    .font(.headline)
                    .fontWeight(.bold)
                    .padding(.top, 10)
                
                Text("What we collect: Account info, content you create, location (with permission), photos/videos (what you choose), usage data\n\nHow we use it: To provide the service, improve the App, keep the platform safe\n\nWho sees it: Your profile and posts are public. Messages are private. We use Firebase (Google) to store data. We never sell your data.\n\nYour rights: Update or delete your info anytime. Delete your account anytime. Control permissions. Request a copy of your data.\n\nQuestions? Email: contactus.hustler@gmail.com")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Supporting View
struct SectionView: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
