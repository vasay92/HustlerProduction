// TagComponents.swift
// Reusable UI components for the tag system

import SwiftUI

// MARK: - Tag Input Field
struct TagInputField: View {
    @Binding var tags: [String]
    @State private var inputText = ""
    @State private var suggestions: [String] = []
    @State private var showingSuggestions = false
    @StateObject private var tagRepository = TagRepository.shared
    
    let maxTags: Int = 10
    let minTags: Int = 5
    let minTagLength: Int = 3
    let maxTagLength: Int = 30
    
    var tagsRemaining: Int {
        maxTags - tags.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tag input
            HStack {
                Image(systemName: "number")
                    .foregroundColor(.gray)
                
                TextField("Add tag (e.g. #plumbing)", text: $inputText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: inputText) { newValue in
                        handleInputChange(newValue)
                    }
                    .onSubmit {
                        addTag()
                    }
                
                if !inputText.isEmpty {
                    Button(action: addTag) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Current tags
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            TagChip(tag: tag) {
                                removeTag(tag)
                            }
                        }
                    }
                }
            }
            
            // Suggestions
            if showingSuggestions && !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggestions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(action: {
                                    selectSuggestion(suggestion)
                                }) {
                                    Text(suggestion)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(15)
                                }
                            }
                        }
                    }
                }
            }
            
            // Helper text
            HStack {
                Text("\(tags.count)/\(maxTags) tags")
                    .font(.caption)
                    .foregroundColor(tags.count < minTags ? .orange : .secondary)
                
                Spacer()
                
                if tags.count < minTags {
                    Text("Min \(minTags) required")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleInputChange(_ text: String) {
        // Auto-prepend # if not present
        if !text.isEmpty && !text.hasPrefix("#") {
            inputText = "#" + text
        }
        
        // Remove spaces
        inputText = inputText.replacingOccurrences(of: " ", with: "-")
        
        // Limit length
        if inputText.count > maxTagLength {
            inputText = String(inputText.prefix(maxTagLength))
        }
        
        // Fetch suggestions
        if inputText.count > 2 {
            Task {
                suggestions = await fetchSuggestions(for: inputText)
                showingSuggestions = true
            }
        } else {
            showingSuggestions = false
        }
    }
    
    private func addTag() {
        let tag = formatTag(inputText)
        
        guard validateTag(tag) else { return }
        
        if !tags.contains(tag) && tags.count < maxTags {
            withAnimation {
                tags.append(tag)
            }
            
            // Update tag analytics
            Task {
                await tagRepository.updateTagAnalytics([tag], type: "post")
            }
        }
        
        inputText = ""
        showingSuggestions = false
    }
    
    private func removeTag(_ tag: String) {
        withAnimation {
            tags.removeAll { $0 == tag }
        }
    }
    
    private func selectSuggestion(_ suggestion: String) {
        if !tags.contains(suggestion) && tags.count < maxTags {
            withAnimation {
                tags.append(suggestion)
            }
        }
        inputText = ""
        showingSuggestions = false
    }
    
    private func formatTag(_ text: String) -> String {
        var formatted = text.lowercased()
        
        // Ensure it starts with #
        if !formatted.hasPrefix("#") {
            formatted = "#" + formatted
        }
        
        // Replace spaces with hyphens
        formatted = formatted.replacingOccurrences(of: " ", with: "-")
        
        // Remove invalid characters
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "#-"))
        formatted = formatted.components(separatedBy: allowed.inverted).joined()
        
        return formatted
    }
    
    private func validateTag(_ tag: String) -> Bool {
        // Check length (excluding #)
        let tagWithoutHash = tag.replacingOccurrences(of: "#", with: "")
        
        if tagWithoutHash.count < minTagLength {
            return false
        }
        
        if tagWithoutHash.count > maxTagLength {
            return false
        }
        
        // Check if it's not just the hash symbol
        if tag == "#" {
            return false
        }
        
        return true
    }
    
    private func fetchSuggestions(for query: String) async -> [String] {
        // This will be implemented in TagRepository
        return await tagRepository.searchTags(query: query)
    }
}

// MARK: - Tag Chip
struct TagChip: View {
    let tag: String
    let onDelete: (() -> Void)?
    let isClickable: Bool
    let isSelected: Bool
    
    init(tag: String, isSelected: Bool = false, isClickable: Bool = true, onDelete: (() -> Void)? = nil) {
        self.tag = tag
        self.isSelected = isSelected
        self.isClickable = isClickable
        self.onDelete = onDelete
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
                .fontWeight(.medium)
            
            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, onDelete != nil ? 8 : 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .cornerRadius(15)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.blue
        } else if isClickable {
            return Color(.systemGray5)
        } else {
            return Color(.systemGray6)
        }
    }
    
    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else {
            return .primary
        }
    }
}

// MARK: - Tag List View
struct TagListView: View {
    let tags: [String]
    let maxDisplay: Int
    let onTagTap: ((String) -> Void)?
    
    init(tags: [String], maxDisplay: Int = 3, onTagTap: ((String) -> Void)? = nil) {
        self.tags = tags
        self.maxDisplay = maxDisplay
        self.onTagTap = onTagTap
    }
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tags.prefix(maxDisplay)), id: \.self) { tag in
                if let onTap = onTagTap {
                    Button(action: { onTap(tag) }) {
                        tagView(tag)
                    }
                } else {
                    tagView(tag)
                }
            }
            
            if tags.count > maxDisplay {
                Text("+\(tags.count - maxDisplay)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
        }
    }
    
    private func tagView(_ tag: String) -> some View {
        Text(tag)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .foregroundColor(.primary)
            .cornerRadius(12)
    }
}

// MARK: - Tag Filter View
struct TagFilterView: View {
    @Binding var selectedTags: [String]
    let availableTags: [String]
    let onClear: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Clear all button
                if !selectedTags.isEmpty {
                    Button(action: onClear) {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(15)
                    }
                }
                
                // Tag chips
                ForEach(availableTags, id: \.self) { tag in
                    TagChip(
                        tag: tag,
                        isSelected: selectedTags.contains(tag)
                    ) {
                        toggleTag(tag)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    private func toggleTag(_ tag: String) {
        withAnimation {
            if selectedTags.contains(tag) {
                selectedTags.removeAll { $0 == tag }
            } else {
                selectedTags.append(tag)
            }
        }
    }
}
