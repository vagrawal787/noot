import SwiftUI
import WebKit

struct MarkdownEditorView: NSViewRepresentable {
    typealias NSViewType = WKWebView

    @Binding var content: String
    var onContentChange: ((String) -> Void)?
    var onSave: (() -> Void)?

    func makeNSView(context: NSViewRepresentableContext<MarkdownEditorView>) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "contentChanged")
        contentController.add(context.coordinator, name: "save")
        contentController.add(context.coordinator, name: "editorReady")
        contentController.add(context.coordinator, name: "log")
        configuration.userContentController = contentController

        // Allow local file access for images
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")

        // Important: Allow the webview to be resized
        webView.autoresizingMask = [.width, .height]

        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif

        // Load from a file URL base to enable local file access
        let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: "/")

        webView.loadHTMLString(Self.editorHTML, baseURL: baseURL)

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: NSViewRepresentableContext<MarkdownEditorView>) {
        // Only update if content changed externally and editor is ready
        if context.coordinator.isReady && context.coordinator.lastContent != content {
            print("[MarkdownEditorView] updateNSView - content changed, updating editor")
            context.coordinator.setContent(content)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // Remove message handlers to prevent memory leaks
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "contentChanged")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "save")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "editorReady")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "log")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: MarkdownEditorView
        var webView: WKWebView?
        var isReady = false
        var lastContent: String = ""

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "log":
                // Suppress JS logs in production
                #if DEBUG
                if let msg = message.body as? String {
                    print("[Editor JS] \(msg)")
                }
                #endif

            case "editorReady":
                isReady = true
                let currentContent = parent.content
                setContent(currentContent)

            case "contentChanged":
                if let body = message.body as? [String: Any],
                   let html = body["html"] as? String {
                    lastContent = html
                    DispatchQueue.main.async {
                        self.parent.content = html
                        self.parent.onContentChange?(html)
                    }
                }

            case "save":
                DispatchQueue.main.async {
                    self.parent.onSave?()
                }

            default:
                break
            }
        }

        func setContent(_ content: String) {
            guard let webView = webView, isReady else { return }

            // Don't update if content is the same
            if content == lastContent { return }

            lastContent = content

            // Convert file:// URLs to data: URLs for images
            let processedContent = ImageHelper.convertFileURLsToDataURLs(content)

            // Escape for JavaScript template literal
            let escaped = processedContent
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\"", with: "\\\"")

            let js = "if(window.setEditorContent) { window.setEditorContent(`\(escaped)`); }"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - Embedded HTML

    static let editorHTML = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }

            :root {
                --background: #0d0d1a;
                --surface: #1a1a2e;
                --text-primary: #e0e0e0;
                --text-muted: #888888;
                --cyan: #00ffff;
                --magenta: #ff00ff;
            }

            html, body {
                height: 100%;
                width: 100%;
                margin: 0;
                padding: 0;
            }

            body {
                background: var(--background);
                color: var(--text-primary);
                font-family: -apple-system-ui-monospace, 'SF Mono', 'Menlo', 'Monaco', monospace;
                font-size: 14px;
                line-height: 1.6;
                padding: 16px;
                min-height: 100%;
                overflow-y: auto;
            }

            #editor {
                outline: none;
                min-height: calc(100% - 32px);
                white-space: pre-wrap;
                word-wrap: break-word;
                cursor: text;
            }

            #editor:empty:before {
                content: 'Start typing...';
                color: var(--text-muted);
                pointer-events: none;
            }

            #editor h1, #editor h2, #editor h3 {
                color: var(--cyan);
                margin-top: 0.5em;
                margin-bottom: 0.3em;
            }

            #editor h1 { font-size: 1.6em; }
            #editor h2 { font-size: 1.3em; }
            #editor h3 { font-size: 1.1em; }

            #editor code {
                background: var(--surface);
                padding: 2px 6px;
                border-radius: 4px;
                font-family: inherit;
                color: var(--magenta);
            }

            #editor pre {
                background: var(--surface);
                padding: 12px;
                border-radius: 8px;
                margin: 0.5em 0;
                overflow-x: auto;
                border: 1px solid rgba(0, 255, 255, 0.2);
            }

            #editor pre code {
                background: none;
                padding: 0;
                color: var(--text-primary);
            }

            #editor blockquote {
                border-left: 3px solid var(--cyan);
                padding-left: 1em;
                margin: 0.5em 0;
                color: var(--text-muted);
            }

            #editor ul, #editor ol {
                padding-left: 1.5em;
                margin: 0.5em 0;
            }

            #editor li {
                margin: 0.25em 0;
            }

            #editor hr {
                border: none;
                border-top: 1px solid rgba(0, 255, 255, 0.3);
                margin: 1em 0;
            }

            #editor a {
                color: var(--cyan);
                text-decoration: none;
            }

            #editor a:hover {
                text-decoration: underline;
            }

            #editor img {
                max-width: 100%;
                height: auto;
                border-radius: 8px;
                margin: 0.5em 0;
                display: block;
            }

            #editor strong, #editor b {
                color: var(--text-primary);
                font-weight: 600;
            }

            #editor em, #editor i {
                color: var(--text-muted);
                font-style: italic;
            }

            /* Task list styling */
            #editor .task-item {
                display: flex;
                align-items: flex-start;
                gap: 8px;
                list-style: none;
                margin-left: -1.5em;
            }

            #editor .task-item input[type="checkbox"] {
                appearance: none;
                -webkit-appearance: none;
                width: 16px;
                height: 16px;
                border: 2px solid var(--cyan);
                border-radius: 4px;
                background: transparent;
                cursor: pointer;
                margin-top: 3px;
                flex-shrink: 0;
            }

            #editor .task-item input[type="checkbox"]:checked {
                background: var(--cyan);
            }

            #editor .task-item.checked {
                text-decoration: line-through;
                color: var(--text-muted);
            }

            /* Selection */
            #editor ::selection {
                background: rgba(0, 255, 255, 0.3);
            }
        </style>
    </head>
    <body>
        <div id="editor" contenteditable="true" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false"></div>

        <script>
            (function() {
                'use strict';

                // Log helper - sends logs to Swift
                function log(msg) {
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.log) {
                            window.webkit.messageHandlers.log.postMessage(String(msg));
                        }
                        console.log('[Editor]', msg);
                    } catch (e) {
                        console.error('Log error:', e);
                    }
                }

                log('Script starting...');

                const editor = document.getElementById('editor');
                if (!editor) {
                    log('ERROR: Editor element not found!');
                    return;
                }

                log('Editor element found');
                let debounceTimer = null;

                // Set content from Swift
                window.setEditorContent = function(html) {
                    log('Setting content, length: ' + (html ? html.length : 0));
                    try {
                        editor.innerHTML = html || '';
                        log('Content set successfully');
                    } catch (e) {
                        log('Error setting content: ' + e.message);
                    }
                };

                // Get content
                window.getEditorContent = function() {
                    return editor.innerHTML;
                };

                // Handle input with longer debounce to reduce message frequency
                editor.addEventListener('input', function() {
                    clearTimeout(debounceTimer);
                    debounceTimer = setTimeout(function() {
                        try {
                            const html = editor.innerHTML;
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contentChanged) {
                                window.webkit.messageHandlers.contentChanged.postMessage({
                                    html: html,
                                    text: editor.innerText
                                });
                            }
                        } catch (e) {
                            log('Error sending content changed: ' + e.message);
                        }
                    }, 800); // Increased debounce to reduce WebKit message frequency
                });

                // Handle keyboard shortcuts
                document.addEventListener('keydown', function(e) {
                    // Cmd+S to save
                    if ((e.metaKey || e.ctrlKey) && e.key === 's') {
                        e.preventDefault();
                        try {
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.save) {
                                window.webkit.messageHandlers.save.postMessage({});
                            }
                        } catch (err) {
                            log('Error sending save: ' + err.message);
                        }
                    }

                    // Handle Enter in lists
                    if (e.key === 'Enter') {
                        const selection = window.getSelection();
                        const node = selection.anchorNode;
                        const li = node && node.parentElement ? node.parentElement.closest('li') : null;

                        if (li && li.innerText.trim() === '') {
                            // Empty list item - exit list
                            e.preventDefault();
                            const ul = li.parentElement;
                            const p = document.createElement('p');
                            p.innerHTML = '<br>';
                            ul.parentNode.insertBefore(p, ul.nextSibling);
                            li.remove();
                            if (ul.children.length === 0) ul.remove();

                            const range = document.createRange();
                            range.setStart(p, 0);
                            selection.removeAllRanges();
                            selection.addRange(range);
                        }
                    }

                    // Handle markdown shortcuts
                    if (e.key === ' ') {
                        const selection = window.getSelection();
                        const node = selection.anchorNode;
                        if (node && node.nodeType === 3) {
                            const text = node.textContent;
                            const offset = selection.anchorOffset;

                            // Check for list markers at start of line
                            const beforeCursor = text.substring(0, offset);

                            // Task list: - [ ] or - [x]
                            if (beforeCursor === '- [ ]' || beforeCursor === '- [x]') {
                                e.preventDefault();
                                const checked = beforeCursor === '- [x]';
                                const li = document.createElement('li');
                                li.className = 'task-item' + (checked ? ' checked' : '');
                                const checkbox = document.createElement('input');
                                checkbox.type = 'checkbox';
                                checkbox.checked = checked;
                                checkbox.addEventListener('change', function() {
                                    li.classList.toggle('checked', this.checked);
                                });
                                li.appendChild(checkbox);
                                const span = document.createElement('span');
                                span.innerHTML = '&nbsp;';
                                li.appendChild(span);

                                let ul = node.parentElement.querySelector('ul');
                                if (!ul) {
                                    ul = document.createElement('ul');
                                    node.parentNode.insertBefore(ul, node);
                                }
                                ul.appendChild(li);
                                node.textContent = text.substring(offset);

                                const range = document.createRange();
                                range.setStart(span, 0);
                                selection.removeAllRanges();
                                selection.addRange(range);
                            }
                            // Bullet list: -
                            else if (beforeCursor === '-') {
                                e.preventDefault();
                                const li = document.createElement('li');
                                li.innerHTML = '&nbsp;';

                                let ul = node.parentElement.querySelector('ul');
                                if (!ul) {
                                    ul = document.createElement('ul');
                                    node.parentNode.insertBefore(ul, node);
                                }
                                ul.appendChild(li);
                                node.textContent = text.substring(offset);

                                const range = document.createRange();
                                range.setStart(li, 0);
                                selection.removeAllRanges();
                                selection.addRange(range);
                            }
                            // Headers: #, ##, ###
                            else if (beforeCursor === '#' || beforeCursor === '##' || beforeCursor === '###') {
                                e.preventDefault();
                                const level = beforeCursor.length;
                                const h = document.createElement('h' + level);
                                h.innerHTML = '&nbsp;';

                                const parent = node.parentElement;
                                if (parent.tagName === 'P' || parent.tagName === 'DIV') {
                                    parent.replaceWith(h);
                                } else {
                                    node.parentNode.insertBefore(h, node);
                                    node.textContent = text.substring(offset);
                                }

                                const range = document.createRange();
                                range.setStart(h, 0);
                                selection.removeAllRanges();
                                selection.addRange(range);
                            }
                        }
                    }
                });

                // Focus editor on click anywhere
                document.body.addEventListener('click', function() {
                    editor.focus();
                });

                // Initial focus
                setTimeout(function() {
                    editor.focus();
                    log('Editor focused');
                }, 100);

                // Let Swift know we're ready
                log('Editor initialized, notifying Swift...');
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editorReady) {
                        window.webkit.messageHandlers.editorReady.postMessage({});
                        log('editorReady message sent');
                    } else {
                        log('WARNING: webkit.messageHandlers.editorReady not available');
                    }
                } catch (e) {
                    log('Error sending editorReady: ' + e.message);
                }
            })();
        </script>
    </body>
    </html>
    """
}

// MARK: - Image Helper

struct ImageHelper {
    /// Convert file:// URLs in HTML to base64 data URLs
    /// This is needed because WKWebView blocks local file access
    static func convertFileURLsToDataURLs(_ html: String) -> String {
        var result = html

        // Pattern to find img src with file:// URLs
        let pattern = #"<img\s+[^>]*src="(file://[^"]+)"[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return html
        }

        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))

        // Process matches in reverse to preserve string indices
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: html),
                  let urlRange = Range(match.range(at: 1), in: html) else {
                continue
            }

            let fullMatch = String(html[fullRange])
            let fileURLString = String(html[urlRange])

            // Extract the file path from the URL string
            var filePath: String
            if fileURLString.hasPrefix("file:///") {
                filePath = String(fileURLString.dropFirst(7))
            } else if fileURLString.hasPrefix("file://") {
                filePath = String(fileURLString.dropFirst(7))
            } else {
                continue
            }

            // Decode percent-encoded characters (spaces, etc.)
            if let decoded = filePath.removingPercentEncoding {
                filePath = decoded
            }

            var actualPath = filePath
            let fileManager = FileManager.default

            // Check if file exists, try alternate paths if not
            if !fileManager.fileExists(atPath: filePath) {
                // Fix missing underscore: "screenshot1234.jpg" → "screenshot_1234.jpg"
                let addUnderscorePattern = #"(screenshot|recording)(\d)"#
                let alternateWithUnderscore = filePath.replacingOccurrences(
                    of: addUnderscorePattern,
                    with: "$1_$2",
                    options: .regularExpression
                )

                if alternateWithUnderscore != filePath && fileManager.fileExists(atPath: alternateWithUnderscore) {
                    actualPath = alternateWithUnderscore
                } else {
                    continue
                }
            }

            let fileURL = URL(fileURLWithPath: actualPath)

            // Load the image and convert to base64
            guard let imageData = try? Data(contentsOf: fileURL) else { continue }

            let mimeType = mimeTypeForPath(actualPath)
            let base64 = imageData.base64EncodedString()
            let dataURL = "data:\(mimeType);base64,\(base64)"

            // Replace the file URL with data URL in the img tag
            let newImgTag = fullMatch.replacingOccurrences(of: fileURLString, with: dataURL)
            result = result.replacingCharacters(in: fullRange, with: newImgTag)
        }

        return result
    }

    private static func mimeTypeForPath(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        default: return "image/png"
        }
    }
}

// MARK: - Markdown to HTML Conversion Helper

struct MarkdownConverter {
    /// Convert simple markdown to HTML for the editor
    static func markdownToHTML(_ markdown: String) -> String {
        // Process line by line for multiline patterns
        let lines = markdown.components(separatedBy: "\n")
        var result: [String] = []

        for line in lines {
            var processed = line

            // Headers (must be at start of line)
            if processed.hasPrefix("### ") {
                processed = "<h3>\(String(processed.dropFirst(4)))</h3>"
            } else if processed.hasPrefix("## ") {
                processed = "<h2>\(String(processed.dropFirst(3)))</h2>"
            } else if processed.hasPrefix("# ") {
                processed = "<h1>\(String(processed.dropFirst(2)))</h1>"
            }
            // Task lists
            else if processed.hasPrefix("- [ ] ") {
                let content = String(processed.dropFirst(6))
                processed = "<li class=\"task-item\"><input type=\"checkbox\"><span>\(content)</span></li>"
            } else if processed.hasPrefix("- [x] ") || processed.hasPrefix("- [X] ") {
                let content = String(processed.dropFirst(6))
                processed = "<li class=\"task-item checked\"><input type=\"checkbox\" checked><span>\(content)</span></li>"
            }
            // Blockquotes
            else if processed.hasPrefix("> ") {
                processed = "<blockquote>\(String(processed.dropFirst(2)))</blockquote>"
            }
            // Unordered lists
            else if processed.hasPrefix("- ") {
                processed = "<li>\(String(processed.dropFirst(2)))</li>"
            }
            // Horizontal rule
            else if processed == "---" {
                processed = "<hr>"
            }

            result.append(processed)
        }

        var html = result.joined(separator: "\n")

        // Images: ![alt](url) -> <img src="url" alt="alt"><p><br></p>
        // Add paragraph after image so user can type below it
        html = html.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(([^)]+)\)"#,
            with: "<img src=\"$2\" alt=\"$1\"><p><br></p>",
            options: .regularExpression
        )

        // Links: [text](url) -> <a href="url">text</a>
        html = html.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )

        // Bold: **text** or __text__
        html = html.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"__([^_]+)__"#, with: "<strong>$1</strong>", options: .regularExpression)

        // Italic: *text* or _text_
        html = html.replacingOccurrences(of: #"(?<!\*)\*([^*]+)\*(?!\*)"#, with: "<em>$1</em>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?<!_)_([^_]+)_(?!_)"#, with: "<em>$1</em>", options: .regularExpression)

        // Inline code
        html = html.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)

        // Wrap consecutive list items in ul
        html = html.replacingOccurrences(of: #"(<li[^>]*>.*?</li>\n?)+"#, with: "<ul>$0</ul>", options: .regularExpression)

        // Wrap remaining plain lines in paragraphs
        let finalLines = html.components(separatedBy: "\n")
        var finalResult: [String] = []
        for line in finalLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                finalResult.append("<br>")
            } else if !trimmed.hasPrefix("<") {
                finalResult.append("<p>\(trimmed)</p>")
            } else {
                finalResult.append(line)
            }
        }

        return finalResult.joined(separator: "")
    }

    /// Convert HTML back to markdown
    static func htmlToMarkdown(_ html: String) -> String {
        var md = html

        // Handle line breaks first
        md = md.replacingOccurrences(of: "<br>", with: "\n")
        md = md.replacingOccurrences(of: "<br/>", with: "\n")
        md = md.replacingOccurrences(of: "<br />", with: "\n")

        // Images
        md = md.replacingOccurrences(
            of: #"<img[^>]*src="([^"]*)"[^>]*alt="([^"]*)"[^>]*/?>"#,
            with: "![$2]($1)",
            options: .regularExpression
        )
        md = md.replacingOccurrences(
            of: #"<img[^>]*src="([^"]*)"[^>]*/?>"#,
            with: "![]($1)",
            options: .regularExpression
        )

        // Links
        md = md.replacingOccurrences(
            of: #"<a[^>]*href="([^"]*)"[^>]*>([^<]*)</a>"#,
            with: "[$2]($1)",
            options: .regularExpression
        )

        // Task lists (checked)
        md = md.replacingOccurrences(
            of: #"<li[^>]*class="[^"]*task-item[^"]*checked[^"]*"[^>]*>.*?<span>([^<]*)</span></li>"#,
            with: "- [x] $1",
            options: .regularExpression
        )
        // Task lists (unchecked)
        md = md.replacingOccurrences(
            of: #"<li[^>]*class="[^"]*task-item[^"]*"[^>]*>.*?<span>([^<]*)</span></li>"#,
            with: "- [ ] $1",
            options: .regularExpression
        )

        // Headers
        md = md.replacingOccurrences(of: #"<h1[^>]*>([^<]*)</h1>"#, with: "# $1\n", options: .regularExpression)
        md = md.replacingOccurrences(of: #"<h2[^>]*>([^<]*)</h2>"#, with: "## $1\n", options: .regularExpression)
        md = md.replacingOccurrences(of: #"<h3[^>]*>([^<]*)</h3>"#, with: "### $1\n", options: .regularExpression)

        // Bold and italic
        md = md.replacingOccurrences(of: #"<strong>([^<]*)</strong>"#, with: "**$1**", options: .regularExpression)
        md = md.replacingOccurrences(of: #"<b>([^<]*)</b>"#, with: "**$1**", options: .regularExpression)
        md = md.replacingOccurrences(of: #"<em>([^<]*)</em>"#, with: "*$1*", options: .regularExpression)
        md = md.replacingOccurrences(of: #"<i>([^<]*)</i>"#, with: "*$1*", options: .regularExpression)

        // Code
        md = md.replacingOccurrences(of: #"<code>([^<]*)</code>"#, with: "`$1`", options: .regularExpression)
        md = md.replacingOccurrences(of: #"<pre><code>([^<]*)</code></pre>"#, with: "```\n$1\n```", options: .regularExpression)

        // Blockquotes
        md = md.replacingOccurrences(of: #"<blockquote>([^<]*)</blockquote>"#, with: "> $1\n", options: .regularExpression)

        // Lists
        md = md.replacingOccurrences(of: #"<li>([^<]*)</li>"#, with: "- $1\n", options: .regularExpression)
        md = md.replacingOccurrences(of: #"</?ul[^>]*>"#, with: "", options: .regularExpression)
        md = md.replacingOccurrences(of: #"</?ol[^>]*>"#, with: "", options: .regularExpression)

        // Horizontal rule
        md = md.replacingOccurrences(of: #"<hr[^>]*/?>"#, with: "---\n", options: .regularExpression)

        // Paragraphs - add newlines
        md = md.replacingOccurrences(of: #"<p>([^<]*)</p>"#, with: "$1\n", options: .regularExpression)

        // Divs
        md = md.replacingOccurrences(of: #"<div>([^<]*)</div>"#, with: "$1\n", options: .regularExpression)

        // Clean up remaining tags
        md = md.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        // Clean up entities
        md = md.replacingOccurrences(of: "&nbsp;", with: " ")
        md = md.replacingOccurrences(of: "&amp;", with: "&")
        md = md.replacingOccurrences(of: "&lt;", with: "<")
        md = md.replacingOccurrences(of: "&gt;", with: ">")
        md = md.replacingOccurrences(of: "&quot;", with: "\"")

        // Clean up extra whitespace
        md = md.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    MarkdownEditorView(content: .constant("<h1>Hello World</h1><p>This is a <strong>test</strong>.</p>"))
        .frame(width: 600, height: 400)
}
