// Create new file: ClaudeHustlerFirebase/Views/Components/HashtagTextView.swift

import SwiftUI

struct HashtagTextView: View {
    let text: String
    let onHashtagTap: (String) -> Void
    
    private var attributedText: [(String, Bool)] {
        parseHashtags(from: text)
    }
    
    var body: some View {
        FlowLayout(alignment: .leading, spacing: 4) {
            ForEach(Array(attributedText.enumerated()), id: \.offset) { index, item in
                if item.1 {
                    // It's a hashtag - make it clickable
                    Button(action: {
                        let hashtag = item.0.replacingOccurrences(of: "#", with: "")
                        onHashtagTap(hashtag)
                    }) {
                        Text(item.0)
                            .foregroundColor(.cyan)
                            .fontWeight(.medium)
                    }
                } else {
                    // Regular text
                    Text(item.0)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
    }
    
    private func parseHashtags(from text: String) -> [(String, Bool)] {
        var result: [(String, Bool)] = []
        let pattern = #"#\w+"#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let nsString = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            var lastIndex = 0
            
            for match in matches {
                // Add text before hashtag
                if match.range.location > lastIndex {
                    let range = NSRange(location: lastIndex, length: match.range.location - lastIndex)
                    let substring = nsString.substring(with: range)
                    if !substring.isEmpty {
                        result.append((substring, false))
                    }
                }
                
                // Add hashtag
                let hashtag = nsString.substring(with: match.range)
                result.append((hashtag, true))
                
                lastIndex = match.range.location + match.range.length
            }
            
            // Add remaining text
            if lastIndex < nsString.length {
                let substring = nsString.substring(from: lastIndex)
                if !substring.isEmpty {
                    result.append((substring, false))
                }
            }
            
            if result.isEmpty && !text.isEmpty {
                result.append((text, false))
            }
            
        } catch {
            result.append((text, false))
        }
        
        return result
    }
}

// Simple flow layout for text
struct FlowLayout: Layout {
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: result.positions[index].x + bounds.minX,
                                     y: result.positions[index].y + bounds.minY),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > width && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }
            
            self.size = CGSize(width: width, height: currentY + lineHeight)
        }
    }
}
