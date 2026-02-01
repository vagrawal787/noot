import SwiftUI
import AppKit

/// A view that renders note content with inline images
struct MarkdownNoteView: View {
    let content: String
    var font: Font = .body
    var monospaced: Bool = true
    var onNoteLinkTap: ((UUID) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseContent().enumerated()), id: \.offset) { _, element in
                switch element {
                case .text(let text):
                    Text(text)
                        .font(monospaced ? .system(.body, design: .monospaced) : font)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .image(let path):
                    InlineImageView(path: path)

                case .video(let path):
                    InlineVideoView(path: path)

                case .noteLink(let noteId, let displayText):
                    NoteLinkView(noteId: noteId, displayText: displayText, onTap: onNoteLinkTap)
                }
            }
        }
    }

    private func parseContent() -> [ContentElement] {
        var elements: [ContentElement] = []
        var currentText = ""
        var remaining = content

        // Combined pattern for images, video links, and note links
        // Images: ![alt](path)
        // Videos: 🎬 [Recording](path)
        // Note links: [[noteId|display text]]
        let imagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        let videoPattern = #"🎬\s*\[([^\]]*)\]\(([^)]+)\)"#
        let noteLinkPattern = #"\[\[([A-F0-9\-]{36})\|([^\]]+)\]\]"#

        guard let imageRegex = try? NSRegularExpression(pattern: imagePattern, options: []),
              let videoRegex = try? NSRegularExpression(pattern: videoPattern, options: []),
              let noteLinkRegex = try? NSRegularExpression(pattern: noteLinkPattern, options: [.caseInsensitive]) else {
            return [.text(content)]
        }

        enum MatchType {
            case image, video, noteLink
        }

        while !remaining.isEmpty {
            let range = NSRange(remaining.startIndex..., in: remaining)
            let imageMatch = imageRegex.firstMatch(in: remaining, options: [], range: range)
            let videoMatch = videoRegex.firstMatch(in: remaining, options: [], range: range)
            let noteLinkMatch = noteLinkRegex.firstMatch(in: remaining, options: [], range: range)

            // Find the earliest match
            var firstMatch: NSTextCheckingResult?
            var matchType: MatchType = .image

            let matches: [(NSTextCheckingResult?, MatchType)] = [
                (imageMatch, .image),
                (videoMatch, .video),
                (noteLinkMatch, .noteLink)
            ]

            for (match, type) in matches {
                guard let m = match else { continue }
                if firstMatch == nil || m.range.location < firstMatch!.range.location {
                    firstMatch = m
                    matchType = type
                }
            }

            if let match = firstMatch {
                // Get the text before the match
                if let beforeRange = Range(NSRange(location: 0, length: match.range.location), in: remaining) {
                    let beforeText = String(remaining[beforeRange])
                    if !beforeText.isEmpty {
                        currentText += beforeText
                    }
                }

                // Save accumulated text
                if !currentText.isEmpty {
                    elements.append(.text(currentText))
                    currentText = ""
                }

                switch matchType {
                case .image:
                    if let pathRange = Range(match.range(at: 2), in: remaining) {
                        var path = String(remaining[pathRange])
                        if path.hasPrefix("file://") {
                            path = String(path.dropFirst(7))
                        }
                        elements.append(.image(path))
                    }

                case .video:
                    if let pathRange = Range(match.range(at: 2), in: remaining) {
                        var path = String(remaining[pathRange])
                        if path.hasPrefix("file://") {
                            path = String(path.dropFirst(7))
                        }
                        elements.append(.video(path))
                    }

                case .noteLink:
                    if let idRange = Range(match.range(at: 1), in: remaining),
                       let textRange = Range(match.range(at: 2), in: remaining),
                       let noteId = UUID(uuidString: String(remaining[idRange])) {
                        let displayText = String(remaining[textRange])
                        elements.append(.noteLink(noteId, displayText))
                    }
                }

                // Move past this match
                if let matchRange = Range(match.range, in: remaining) {
                    remaining = String(remaining[matchRange.upperBound...])
                } else {
                    break
                }
            } else {
                // No more matches, add remaining text
                currentText += remaining
                break
            }
        }

        // Add any remaining text
        if !currentText.isEmpty {
            elements.append(.text(currentText))
        }

        return elements.isEmpty ? [.text(content)] : elements
    }

    enum ContentElement {
        case text(String)
        case image(String)
        case video(String)
        case noteLink(UUID, String) // noteId, display text
    }
}

struct NoteLinkView: View {
    let noteId: UUID
    let displayText: String
    var onTap: ((UUID) -> Void)?

    var body: some View {
        Button(action: { onTap?(noteId) }) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.caption2)
                Text(displayText)
                    .lineLimit(1)
            }
            .font(.callout)
            .foregroundColor(.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

struct InlineVideoView: View {
    let path: String
    @State private var showInFinder: Bool = false

    var body: some View {
        Button(action: openVideo) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 60, height: 45)

                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Recording")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 300)
    }

    private func openVideo() {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
}

struct InlineImageView: View {
    let path: String
    @State private var image: NSImage?
    @State private var showFullScreen: Bool = false

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .onTapGesture(count: 2) {
                        showFullScreen = true
                    }
                    .onTapGesture(count: 1) {
                        // Single tap does nothing but is needed to not block double tap
                    }
                    .help("Double-click to expand")
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 200, height: 150)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(.secondary)
                            Text("Image not found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
        .onAppear {
            loadImage()
        }
        .sheet(isPresented: $showFullScreen) {
            ImageExpandedView(image: image, path: path)
        }
    }

    private func loadImage() {
        // Try loading from the path
        if let nsImage = NSImage(contentsOfFile: path) {
            image = nsImage
        } else if let url = URL(string: path), let nsImage = NSImage(contentsOf: url) {
            image = nsImage
        }
    }
}

struct ImageExpandedView: View {
    let image: NSImage?
    let path: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Image Preview")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(.windowBackgroundColor))

            Divider()

            // Image - scaled to fit
            if let image = image {
                GeometryReader { geometry in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .padding()
            }

            Divider()

            // Footer with path
            HStack {
                Text(path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: openInFinder) {
                    Label("Show in Finder", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.windowBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 500)
        .frame(idealWidth: 900, idealHeight: 700)
    }

    private func openInFinder() {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

#Preview {
    MarkdownNoteView(content: """
    This is some text before the image.

    ![](file:///tmp/test.png)

    And this is text after the image.

    More text here.
    """)
    .padding()
    .frame(width: 500)
}
