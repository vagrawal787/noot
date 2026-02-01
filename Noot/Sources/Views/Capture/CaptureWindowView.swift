import SwiftUI
import GRDB
import AppKit

struct CaptureWindowView: View {
    @State private var noteContent: String = ""
    @State private var screenContext: ScreenContext?
    @State private var recentContexts: [Context] = []
    @State private var selectedContexts: Set<UUID> = []
    @State private var editingNoteId: UUID?
    @State private var isCapturing: Bool = false
    @State private var isRecording: Bool = false
    @State private var showNoteLinkPicker: Bool = false
    @State private var showNewContextSheet: Bool = false
    @State private var showFileSizeWarning: Bool = false
    @State private var recordingFileSize: Int = 0
    @FocusState private var isTextFieldFocused: Bool

    // Check if content has images
    private var hasImages: Bool {
        noteContent.contains("![")
    }

    // Dynamic height calculations - expands vertically based on newlines
    private var maxWindowHeight: CGFloat {
        guard let screen = NSScreen.main else { return 500 }
        return screen.visibleFrame.height * 0.7
    }

    private var lineCount: Int {
        noteContent.components(separatedBy: .newlines).count
    }

    private var calculatedHeight: CGFloat {
        // Base height includes: header space, bottom toolbar, and whitespace buffer
        let baseHeight: CGFloat = 120
        // Extra space per line (line height + some breathing room)
        let heightPerLine: CGFloat = 22
        // Always show room for at least 3 more lines (whitespace at bottom)
        let whitespaceBuffer: CGFloat = 66

        let textHeight = CGFloat(lineCount) * heightPerLine + whitespaceBuffer

        if hasImages {
            // More space when images are present
            return min(max(textHeight + baseHeight + 200, 350), maxWindowHeight)
        }

        return min(max(textHeight + baseHeight, 250), maxWindowHeight)
    }

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Recording indicator
                if isRecording {
                    VStack(spacing: 4) {
                        HStack {
                            Circle()
                                .fill(NootTheme.recording)
                                .frame(width: 8, height: 8)
                                .neonGlow(NootTheme.recording, radius: 6)
                            Text("REC")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.recording)
                            Spacer()
                            Button("STOP") {
                                toggleScreenRecording()
                            }
                            .buttonStyle(NeonButtonStyle(color: NootTheme.recording))
                        }

                        if showFileSizeWarning {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(NootTheme.warning)
                                    .font(.caption)
                                Text("Large file: \(ByteCountFormatter.string(fromByteCount: Int64(recordingFileSize), countStyle: .file))")
                                    .font(NootTheme.monoFontSmall)
                                    .foregroundColor(NootTheme.warning)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(NootTheme.recording.opacity(0.1))
                }

                // Meeting indicator
                if MeetingManager.shared.isInMeeting {
                    HStack {
                        Circle()
                            .fill(NootTheme.magenta)
                            .frame(width: 8, height: 8)
                            .neonGlow(NootTheme.magenta, radius: 4)
                        Text("IN MEETING")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.magenta)
                        if let meeting = MeetingManager.shared.currentMeeting {
                            Text("// \(meeting.title ?? "Untitled")")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(NootTheme.magenta.opacity(0.1))
                }

                // Screen context indicator
                if let context = screenContext {
                    HStack {
                        Image(systemName: iconForSourceType(context.sourceType))
                            .font(.caption)
                            .foregroundColor(NootTheme.cyan)
                        Text(context.displayString)
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }

                // Text editor - always visible, fills available space
                TextEditor(text: $noteContent)
                    .font(NootTheme.monoFont)
                    .foregroundColor(NootTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .focused($isTextFieldFocused)
                    .frame(minHeight: 60, maxHeight: .infinity)

                // Image preview section - only when images exist
                if hasImages {
                    Rectangle()
                        .fill(NootTheme.cyan.opacity(0.3))
                        .frame(height: 1)
                        .neonGlow(NootTheme.cyan, radius: 2)

                    ScrollView {
                        MarkdownNoteView(content: noteContent)
                            .padding(12)
                    }
                    .frame(minHeight: 150, maxHeight: 250)
                    .background(NootTheme.surface.opacity(0.5))
                }

                Rectangle()
                    .fill(NootTheme.cyan.opacity(0.3))
                    .frame(height: 1)

                // Context tags and actions
                HStack(spacing: 8) {
                    // Recent context tags
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(recentContexts) { context in
                                CyberContextTag(
                                    context: context,
                                    isSelected: selectedContexts.contains(context.id)
                                ) {
                                    toggleContext(context.id)
                                }
                            }

                            // Add context button
                            Button(action: { showNewContextSheet = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.caption2)
                                    Text("ADD")
                                        .font(NootTheme.monoFontSmall)
                                }
                                .foregroundColor(NootTheme.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(NootTheme.textMuted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
                                )
                            }
                            .buttonStyle(.plain)
                            .help("New Context")
                        }
                    }

                    Spacer()

                    // Action buttons
                    HStack(spacing: 8) {
                        Button(action: captureScreenshot) {
                            Image(systemName: "camera")
                                .font(.caption)
                                .foregroundColor(NootTheme.cyan)
                        }
                        .buttonStyle(.plain)
                        .disabled(isCapturing)
                        .help("Capture Screenshot")

                        Button(action: toggleScreenRecording) {
                            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                                .font(.caption)
                                .foregroundColor(isRecording ? NootTheme.recording : NootTheme.magenta)
                        }
                        .buttonStyle(.plain)
                        .help(isRecording ? "Stop Recording" : "Start Screen Recording")

                        Button(action: { showNoteLinkPicker = true }) {
                            Image(systemName: "link")
                                .font(.caption)
                                .foregroundColor(NootTheme.purple)
                        }
                        .buttonStyle(.plain)
                        .help("Link to Note")
                    }

                    // Save button
                    Button("SAVE") {
                        saveNote()
                    }
                    .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            // Scan lines overlay
            ScanLines(spacing: 3, opacity: 0.03)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                NootTheme.background
                // Subtle gradient
                LinearGradient(
                    colors: [NootTheme.cyan.opacity(0.03), NootTheme.magenta.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [NootTheme.cyan.opacity(0.5), NootTheme.magenta.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: NootTheme.cyan.opacity(0.2), radius: 20, x: 0, y: 0)
        .shadow(color: NootTheme.magenta.opacity(0.1), radius: 30, x: 0, y: 10)
        .animation(.easeInOut(duration: 0.2), value: hasImages)
        .onChange(of: lineCount) { _ in
            // Notify window to resize when lines change
            NotificationCenter.default.post(name: .captureWindowNeedsResize, object: nil, userInfo: ["height": calculatedHeight])
        }
        .onAppear {
            loadRecentContexts()
            detectScreenContext()
            // Delay focus to ensure window is fully ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .loadNoteIntoCapture)) { notification in
            if let noteId = notification.userInfo?["noteId"] as? UUID {
                loadNoteForEditing(noteId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerCaptureSave)) { _ in
            saveAndDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addMediaToCapture)) { notification in
            if let url = notification.userInfo?["url"] as? URL,
               let type = notification.userInfo?["type"] as? String {
                addMedia(url: url, type: type)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenRecordingStarted)) { _ in
            isRecording = true
            showFileSizeWarning = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingFileSizeWarning)) { notification in
            if let fileSize = notification.userInfo?["fileSize"] as? Int {
                recordingFileSize = fileSize
                showFileSizeWarning = true
            }
        }
        .background(
            Button("") { saveAndDismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
        )
        .sheet(isPresented: $showNoteLinkPicker) {
            InlineNoteLinkPicker(
                currentNoteId: editingNoteId,
                onSelect: { note in
                    insertNoteLink(note)
                    showNoteLinkPicker = false
                },
                onCancel: {
                    showNoteLinkPicker = false
                }
            )
        }
        .sheet(isPresented: $showNewContextSheet) {
            CaptureContextCreateSheet(onCreated: { newContext in
                recentContexts.insert(newContext, at: 0)
                selectedContexts.insert(newContext.id)
            })
        }
    }

    private func iconForSourceType(_ type: ScreenContextSourceType) -> String {
        switch type {
        case .browser: return "globe"
        case .vscode: return "chevron.left.forwardslash.chevron.right"
        case .terminal: return "terminal"
        case .other: return "app"
        }
    }

    private func toggleContext(_ id: UUID) {
        if selectedContexts.contains(id) {
            selectedContexts.remove(id)
        } else {
            selectedContexts.insert(id)
        }
    }

    private func loadRecentContexts() {
        do {
            recentContexts = try Database.shared.read { db in
                try Context.active().limit(5).fetchAll(db)
            }
        } catch {
            print("Failed to load contexts: \(error)")
        }
    }

    private func detectScreenContext() {
        // TODO: Implement screen context detection
        // For now, create a placeholder
        Task {
            if let context = await ScreenContextDetector.shared.detectCurrentContext() {
                await MainActor.run {
                    self.screenContext = context
                }
            }
        }
    }

    private func loadNoteForEditing(_ noteId: UUID) {
        do {
            if let note = try Database.shared.read({ db in
                try Note.fetchOne(db, key: noteId)
            }) {
                editingNoteId = note.id
                noteContent = note.content

                // Load existing contexts for this note
                let contextIds = try Database.shared.read { db in
                    try NoteContext
                        .filter(NoteContext.Columns.noteId == noteId)
                        .fetchAll(db)
                        .map { $0.contextId }
                }
                selectedContexts = Set(contextIds)

                // Focus the text editor
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isTextFieldFocused = true
                }
            }
        } catch {
            print("Failed to load note for editing: \(error)")
        }
    }

    private func captureScreenshot() {
        guard !isCapturing else { return }
        isCapturing = true

        // Hide window temporarily for clean screenshot
        NotificationCenter.default.post(name: .hideCaptureWindow, object: nil)

        Task {
            // Small delay to let window hide
            try? await Task.sleep(nanoseconds: 200_000_000)

            do {
                let url = try await ScreenCaptureService.shared.captureScreenshotToFile()

                await MainActor.run {
                    // Insert markdown image syntax at the end of content
                    // Add newline before if content exists, and newline after for continued typing
                    let imageMarkdown: String
                    if noteContent.isEmpty {
                        imageMarkdown = "![](file://\(url.path))\n"
                    } else if noteContent.hasSuffix("\n") {
                        imageMarkdown = "![](file://\(url.path))\n"
                    } else {
                        imageMarkdown = "\n![](file://\(url.path))\n"
                    }

                    noteContent += imageMarkdown
                    isCapturing = false

                    // Re-show capture window, stay in edit mode so user can continue typing
                    NotificationCenter.default.post(name: .showCaptureWindow, object: nil)
                    // Re-focus the text editor
                    isTextFieldFocused = true
                }
            } catch {
                print("Screenshot failed: \(error)")
                await MainActor.run {
                    isCapturing = false
                    NotificationCenter.default.post(name: .showCaptureWindow, object: nil)
                }
            }
        }
    }

    private func toggleScreenRecording() {
        Task {
            if isRecording {
                // Stop recording
                do {
                    if let url = try await ScreenCaptureService.shared.stopRecording() {
                        await MainActor.run {
                            // Insert video reference in markdown format
                            let videoMarkdown: String
                            if noteContent.isEmpty {
                                videoMarkdown = "🎬 [Recording](file://\(url.path))\n"
                            } else if noteContent.hasSuffix("\n") {
                                videoMarkdown = "🎬 [Recording](file://\(url.path))\n"
                            } else {
                                videoMarkdown = "\n🎬 [Recording](file://\(url.path))\n"
                            }
                            noteContent += videoMarkdown
                            isRecording = false
                        }
                    }
                } catch {
                    print("Failed to stop recording: \(error)")
                    await MainActor.run {
                        isRecording = false
                    }
                }
            } else {
                // Start recording - hide window first
                NotificationCenter.default.post(name: .hideCaptureWindow, object: nil)

                try? await Task.sleep(nanoseconds: 200_000_000)

                do {
                    try await ScreenCaptureService.shared.startRecording()
                    await MainActor.run {
                        isRecording = true
                        // Show window again with recording indicator
                        NotificationCenter.default.post(name: .showCaptureWindow, object: nil)
                    }
                } catch {
                    print("Failed to start recording: \(error)")
                    await MainActor.run {
                        NotificationCenter.default.post(name: .showCaptureWindow, object: nil)
                    }
                }
            }
        }
    }

    private func saveNote() {
        guard !noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            dismissWindow()
            return
        }

        do {
            try Database.shared.write { db in
                let savedNoteId: UUID

                if let existingId = editingNoteId {
                    // Update existing note
                    if var existingNote = try Note.fetchOne(db, key: existingId) {
                        existingNote.content = noteContent
                        existingNote.updatedAt = Date()
                        existingNote.closedAt = nil // Reopen the note
                        try existingNote.update(db)
                        savedNoteId = existingId
                    } else {
                        // Note was deleted, create new
                        var newNote = Note(content: noteContent)
                        try newNote.insert(db)
                        savedNoteId = newNote.id
                    }
                } else {
                    // Create new note
                    var newNote = Note(content: noteContent)
                    try newNote.insert(db)
                    savedNoteId = newNote.id

                    // Save screen context only for new notes
                    if var context = screenContext {
                        context.noteId = savedNoteId
                        try context.insert(db)
                    }
                }

                // Update context associations
                // First, remove existing associations if editing
                if editingNoteId != nil {
                    try NoteContext
                        .filter(NoteContext.Columns.noteId == savedNoteId)
                        .deleteAll(db)
                }

                // Save new context associations
                for contextId in selectedContexts {
                    let noteContext = NoteContext(noteId: savedNoteId, contextId: contextId)
                    try noteContext.insert(db)
                }

                // Extract and save note links
                let linkedNoteIds = extractLinkedNoteIds(from: noteContent)

                // Remove existing outgoing links if editing
                if editingNoteId != nil {
                    try NoteLink
                        .filter(NoteLink.Columns.sourceNoteId == savedNoteId)
                        .deleteAll(db)
                }

                // Create new links
                for targetId in linkedNoteIds {
                    // Don't link to self
                    guard targetId != savedNoteId else { continue }
                    // Verify target exists
                    guard try Note.fetchOne(db, key: targetId) != nil else { continue }

                    let link = NoteLink(
                        sourceNoteId: savedNoteId,
                        targetNoteId: targetId,
                        relationship: .related
                    )
                    try link.insert(db)
                }

                // Associate with current meeting if one is active
                if let meeting = MeetingManager.shared.currentMeeting {
                    let noteMeeting = NoteMeeting(noteId: savedNoteId, meetingId: meeting.id)
                    try? noteMeeting.insert(db) // Ignore if already exists
                }

                // Extract and save attachments
                // Remove existing attachments if editing
                if editingNoteId != nil {
                    try Attachment
                        .filter(Attachment.Columns.noteId == savedNoteId)
                        .deleteAll(db)
                }

                // Create attachment records for media files
                let mediaFiles = extractMediaFiles(from: noteContent)
                for (url, type) in mediaFiles {
                    if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
                        let attachment = Attachment(
                            noteId: savedNoteId,
                            type: type,
                            filePath: url.path,
                            fileSize: fileSize
                        )
                        try attachment.insert(db)
                    }
                }
            }
        } catch {
            print("Failed to save note: \(error)")
        }

        dismissWindow()
    }

    private func extractMediaFiles(from content: String) -> [(URL, AttachmentType)] {
        var results: [(URL, AttachmentType)] = []

        // Extract screenshot images: ![...](file://path)
        let imagePattern = #"!\[[^\]]*\]\(file://([^)]+)\)"#
        if let regex = try? NSRegularExpression(pattern: imagePattern, options: []) {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, options: [], range: range)
            for match in matches {
                if let pathRange = Range(match.range(at: 1), in: content) {
                    let path = String(content[pathRange])
                    let url = URL(fileURLWithPath: path)
                    results.append((url, .screenshot))
                }
            }
        }

        // Extract recordings: 🎬 [Recording](file://path)
        let recordingPattern = #"🎬\s*\[[^\]]*\]\(file://([^)]+)\)"#
        if let regex = try? NSRegularExpression(pattern: recordingPattern, options: []) {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, options: [], range: range)
            for match in matches {
                if let pathRange = Range(match.range(at: 1), in: content) {
                    let path = String(content[pathRange])
                    let url = URL(fileURLWithPath: path)
                    results.append((url, .screenRecording))
                }
            }
        }

        return results
    }

    private func extractLinkedNoteIds(from content: String) -> [UUID] {
        // Pattern: [[UUID|display text]]
        let pattern = #"\[\[([A-F0-9\-]{36})\|[^\]]+\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        return matches.compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: content) else { return nil }
            return UUID(uuidString: String(content[idRange]))
        }
    }

    private func saveAndDismiss() {
        // Auto-save if there's content, otherwise just dismiss
        if !noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveNote()
        } else {
            dismissWindow()
        }
    }

    private func addMedia(url: URL, type: String) {
        let markdown: String
        if type == "screenshot" {
            if noteContent.isEmpty {
                markdown = "![](file://\(url.path))\n"
            } else if noteContent.hasSuffix("\n") {
                markdown = "![](file://\(url.path))\n"
            } else {
                markdown = "\n![](file://\(url.path))\n"
            }
        } else {
            // Recording
            if noteContent.isEmpty {
                markdown = "🎬 [Recording](file://\(url.path))\n"
            } else if noteContent.hasSuffix("\n") {
                markdown = "🎬 [Recording](file://\(url.path))\n"
            } else {
                markdown = "\n🎬 [Recording](file://\(url.path))\n"
            }
        }
        noteContent += markdown
        isTextFieldFocused = true
    }

    private func insertNoteLink(_ note: Note) {
        // Get a preview of the linked note (first line or first 30 chars)
        let preview = note.content
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(30) ?? "Note"

        // Format: [[noteId|display text]]
        let linkMarkdown = "[[\(note.id.uuidString)|\(preview)]]"

        // Insert at cursor position (for now, append)
        if noteContent.isEmpty {
            noteContent = linkMarkdown
        } else if noteContent.hasSuffix(" ") || noteContent.hasSuffix("\n") {
            noteContent += linkMarkdown
        } else {
            noteContent += " " + linkMarkdown
        }

        isTextFieldFocused = true
    }

    private func dismissWindow() {
        noteContent = ""
        selectedContexts = []
        screenContext = nil
        editingNoteId = nil

        // Post notification to hide the capture window
        NotificationCenter.default.post(name: .hideCaptureWindow, object: nil)
    }
}

struct CyberContextTag: View {
    let context: Context
    let isSelected: Bool
    let action: () -> Void

    private var tagColor: Color {
        context.type == .domain ? NootTheme.cyan : NootTheme.magenta
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: context.type == .domain ? "folder" : "arrow.triangle.branch")
                    .font(.system(size: 9))
                Text(context.name)
                    .font(NootTheme.monoFontSmall)
            }
            .foregroundColor(isSelected ? tagColor : NootTheme.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? tagColor.opacity(0.2) : NootTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? tagColor.opacity(0.8) : tagColor.opacity(0.3), lineWidth: 0.5)
            )
            .neonGlow(isSelected ? tagColor : .clear, radius: isSelected ? 4 : 0)
        }
        .buttonStyle(.plain)
    }
}

struct InlineNoteLinkPicker: View {
    let currentNoteId: UUID?
    let onSelect: (Note) -> Void
    let onCancel: () -> Void

    @State private var searchText: String = ""
    @State private var notes: [Note] = []

    private var filteredNotes: [Note] {
        var result = notes.filter { $0.id != currentNoteId }
        if !searchText.isEmpty {
            result = result.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
        return Array(result.prefix(15))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Link to Note")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search notes...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Notes list
            if filteredNotes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text(notes.isEmpty ? "No notes available" : "No matching notes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredNotes) { note in
                            InlineNoteLinkRow(note: note) {
                                onSelect(note)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 400, height: 350)
        .onAppear {
            loadNotes()
        }
    }

    private func loadNotes() {
        do {
            notes = try Database.shared.read { db in
                try Note
                    .filter(Note.Columns.archived == false)
                    .order(Note.Columns.updatedAt.desc)
                    .limit(50)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to load notes for linking: \(error)")
        }
    }
}

struct InlineNoteLinkRow: View {
    let note: Note
    let action: () -> Void

    private var preview: String {
        // Remove image/video markdown for clean preview
        let cleaned = note.content
            .replacingOccurrences(of: #"!\[[^\]]*\]\([^)]+\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"🎬\s*\[[^\]]*\]\([^)]+\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[\[[^\]]+\]\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(80))
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview)
                        .lineLimit(2)
                        .font(.callout)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(note.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Image(systemName: "link.circle")
                    .foregroundColor(.accentColor)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CaptureContextCreateSheet: View {
    let onCreated: (Context) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var type: ContextType = .domain
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("NEW CONTEXT")
                .font(NootTheme.monoFontLarge)
                .foregroundColor(NootTheme.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                Text("NAME")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
                TextField("e.g., payments-service", text: $name)
                    .font(NootTheme.monoFont)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(NootTheme.surface)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(NootTheme.cyan.opacity(0.4), lineWidth: 1)
                    )
                    .focused($isNameFocused)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("TYPE")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
                HStack(spacing: 8) {
                    CaptureTypePill(label: "DOMAIN", isSelected: type == .domain, color: NootTheme.cyan) {
                        type = .domain
                    }
                    CaptureTypePill(label: "WORKSTREAM", isSelected: type == .workstream, color: NootTheme.magenta) {
                        type = .workstream
                    }
                }
            }

            HStack {
                Button("CANCEL") {
                    dismiss()
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.textMuted))

                Button("CREATE") {
                    createContext()
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(NootTheme.background)
        .onAppear {
            isNameFocused = true
        }
    }

    private func createContext() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        do {
            var newContext = Context(name: trimmedName, type: type)
            try Database.shared.write { db in
                try newContext.insert(db)
            }
            onCreated(newContext)
            NotificationCenter.default.post(name: .contextsDidChange, object: nil)
            dismiss()
        } catch {
            print("Failed to create context: \(error)")
        }
    }
}

struct CaptureTypePill: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(NootTheme.monoFontSmall)
                .foregroundColor(isSelected ? color : NootTheme.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? color.opacity(0.2) : NootTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? color.opacity(0.6) : NootTheme.textMuted.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CaptureWindowView()
        .frame(width: 500, height: 200)
}
