import SwiftUI

struct MarkdownRenderer: View {
    let content: String

    var body: some View {
        // For v1, use basic Text with markdown support
        // Future versions can use a more sophisticated renderer
        // with syntax highlighting for code blocks
        Text(try! AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            .textSelection(.enabled)
    }
}

// Code syntax highlighting support (placeholder for future implementation)
struct CodeBlockView: View {
    let code: String
    let language: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }
}

#Preview {
    MarkdownRenderer(content: """
    # Hello World

    This is a **bold** and *italic* text.

    - List item 1
    - List item 2

    `inline code`
    """)
    .padding()
}
