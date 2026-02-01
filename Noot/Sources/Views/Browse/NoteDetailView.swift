import SwiftUI
import GRDB

struct NoteDetailView: View {
    let note: Note
    @State private var currentNote: Note?
    @State private var content: String = ""
    @State private var contexts: [Context] = []
    @State private var attachments: [Attachment] = []
    @State private var screenContext: ScreenContext?
    @State private var linkedNotes: [(NoteLink, Note)] = []
    @State private var showPreview: Bool = false
    @State private var saveStatus: SaveStatus = .saved
    @State private var lastSavedContent: String = ""
    @State private var saveTask: DispatchWorkItem?
    @State private var lastRefreshed: Date = Date()
    @State private var showContextPicker: Bool = false
    @State private var availableContexts: [Context] = []

    enum SaveStatus {
        case saved
        case saving
        case unsaved
    }

    private var displayNote: Note {
        currentNote ?? note
    }

    var body: some View {
        HSplitView {
            // Editor pane
            VStack(spacing: 0) {
                // Header
                header
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Rectangle()
                    .fill(NootTheme.cyan.opacity(0.3))
                    .frame(height: 1)

                // Screen context
                if let screenContext = screenContext {
                    screenContextView(screenContext)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Editable content
                TextEditor(text: $content)
                    .font(NootTheme.monoFont)
                    .foregroundColor(NootTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(NootTheme.background)
                    .onChange(of: content) { newContent in
                        guard newContent != lastSavedContent else { return }
                        saveStatus = .unsaved

                        // Cancel previous save task
                        saveTask?.cancel()

                        // Schedule new save after delay
                        let noteId = note.id
                        let task = DispatchWorkItem {
                            saveContent(noteId: noteId, newContent: newContent)
                        }
                        saveTask = task
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
                    }

                Rectangle()
                    .fill(NootTheme.cyan.opacity(0.3))
                    .frame(height: 1)

                // Bottom bar with contexts and actions
                bottomBar
                    .padding(8)
            }

            // Preview pane (optional)
            if showPreview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        MarkdownNoteView(content: content, onNoteLinkTap: { noteId in
                            NotificationCenter.default.post(
                                name: .navigateToNote,
                                object: nil,
                                userInfo: ["noteId": noteId]
                            )
                        })
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if !linkedNotes.isEmpty {
                            linkedNotesView
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 300)
                .background(NootTheme.surface.opacity(0.5))
            }
        }
        .background(NootTheme.background)
        .onAppear {
            loadNoteDetails()
            loadAvailableContexts()
        }
        .onChange(of: note.id) { _ in
            loadNoteDetails()
        }
        .sheet(isPresented: $showContextPicker) {
            NoteContextPickerSheet(
                availableContexts: availableContexts,
                selectedContexts: contexts,
                onAdd: { context in
                    addContext(context)
                    showContextPicker = false
                },
                onCancel: {
                    showContextPicker = false
                }
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("UPDATED \(displayNote.updatedAt, style: .relative)")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)

                    if displayNote.isOpen {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(NootTheme.success)
                                .frame(width: 5, height: 5)
                                .neonGlow(NootTheme.success, radius: 2)
                            Text("OPEN")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundColor(NootTheme.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(NootTheme.success.opacity(0.15))
                        )
                    }

                    // Save status indicator
                    switch saveStatus {
                    case .saved:
                        HStack(spacing: 3) {
                            Circle()
                                .fill(NootTheme.success)
                                .frame(width: 5, height: 5)
                            Text("SAVED")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundColor(NootTheme.success)
                    case .saving:
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                            Text("SAVING...")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(NootTheme.textMuted)
                        }
                    case .unsaved:
                        HStack(spacing: 3) {
                            Circle()
                                .fill(NootTheme.warning)
                                .frame(width: 5, height: 5)
                                .neonGlow(NootTheme.warning, radius: 2)
                            Text("UNSAVED")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundColor(NootTheme.warning)
                    }
                }

                // Last refreshed
                Text("LOADED \(lastRefreshed, style: .relative)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(NootTheme.textMuted.opacity(0.7))
            }

            Spacer()

            HStack(spacing: 12) {
                // Refresh button
                CyberIconButton(icon: "arrow.clockwise", color: NootTheme.cyan, action: refreshNote)
                    .help("Refresh from database")

                // Toggle preview
                CyberIconButton(icon: showPreview ? "eye.fill" : "eye", color: NootTheme.magenta, action: { showPreview.toggle() })
                    .help(showPreview ? "Hide Preview" : "Show Preview")

                // Continue in capture window
                CyberIconButton(icon: "square.and.pencil", color: NootTheme.purple, action: continueInCapture)
                    .help("Continue in Capture Window")

                // Archive
                CyberIconButton(icon: "archivebox", color: NootTheme.warning, action: archiveNote)
                    .help("Archive Note")
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            // Contexts - editable
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(contexts) { context in
                        HStack(spacing: 4) {
                            Image(systemName: context.iconName)
                                .font(.system(size: 9))
                            Text(context.name)
                                .font(NootTheme.monoFontSmall)

                            // Remove button
                            Button(action: { removeContext(context) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(NootTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundColor(context.themeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(context.themeColor.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(context.themeColor.opacity(0.4), lineWidth: 0.5)
                        )
                    }

                    // Add context button
                    Button(action: { showContextPicker = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9))
                            Text("ADD")
                                .font(NootTheme.monoFontSmall)
                        }
                        .foregroundColor(NootTheme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(NootTheme.textMuted.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3]))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Attachments count
            if !attachments.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "paperclip")
                        .font(.caption)
                    Text("\(attachments.count)")
                        .font(NootTheme.monoFontSmall)
                }
                .foregroundColor(NootTheme.textMuted)
            }
        }
    }

    @ViewBuilder
    private func screenContextView(_ context: ScreenContext) -> some View {
        HStack {
            Image(systemName: iconForSourceType(context.sourceType))
                .font(.caption)
                .foregroundColor(NootTheme.purple)
            Text(context.displayString)
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textSecondary)
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(NootTheme.purple.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(NootTheme.purple.opacity(0.3), lineWidth: 0.5)
        )
    }

    private func iconForSourceType(_ type: ScreenContextSourceType) -> String {
        switch type {
        case .browser: return "globe"
        case .vscode: return "chevron.left.forwardslash.chevron.right"
        case .terminal: return "terminal"
        case .other: return "app"
        }
    }

    private var linkedNotesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LINKED NOTES")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.cyan)

            ForEach(linkedNotes, id: \.0.id) { link, linkedNote in
                HStack {
                    Image(systemName: iconForRelationship(link.relationship))
                        .font(.caption)
                        .foregroundColor(NootTheme.purple)
                    Text(linkedNote.content.prefix(50))
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(link.relationship.rawValue.uppercased())
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(NootTheme.textMuted)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(NootTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(NootTheme.purple.opacity(0.3), lineWidth: 0.5)
                )
            }
        }
    }

    private func iconForRelationship(_ relationship: NoteLinkRelationship) -> String {
        switch relationship {
        case .continues: return "arrow.right"
        case .informedBy: return "lightbulb"
        case .related: return "link"
        }
    }

    private func loadNoteDetails() {
        let noteId = note.id

        do {
            try Database.shared.read { db in
                // Fetch fresh note from database
                if let freshNote = try Note.fetchOne(db, key: noteId) {
                    currentNote = freshNote
                    content = freshNote.content
                    lastSavedContent = freshNote.content
                    lastRefreshed = Date()
                    saveStatus = .saved
                } else {
                    // Fallback to passed note
                    content = note.content
                    lastSavedContent = note.content
                }
                // Load contexts via join table
                let noteContexts = try NoteContext
                    .filter(NoteContext.Columns.noteId == noteId)
                    .fetchAll(db)
                let contextIds = noteContexts.map { $0.contextId }
                contexts = try Context
                    .filter(contextIds.contains(Context.Columns.id))
                    .fetchAll(db)

                // Load attachments
                attachments = try Attachment
                    .filter(Attachment.Columns.noteId == noteId)
                    .order(Attachment.Columns.createdAt)
                    .fetchAll(db)

                // Load screen context
                screenContext = try ScreenContext
                    .filter(ScreenContext.Columns.noteId == noteId)
                    .fetchOne(db)

                // Load linked notes (outgoing)
                let outgoingLinks = try NoteLink
                    .filter(NoteLink.Columns.sourceNoteId == noteId)
                    .fetchAll(db)

                linkedNotes = try outgoingLinks.compactMap { link -> (NoteLink, Note)? in
                    guard let linkedNote = try Note.fetchOne(db, key: link.targetNoteId) else {
                        return nil
                    }
                    return (link, linkedNote)
                }
            }
        } catch {
            print("Failed to load note details: \(error)")
        }
    }

    private func saveContent(noteId: UUID, newContent: String) {
        saveStatus = .saving

        do {
            var savedNote: Note?
            try Database.shared.write { db in
                // Fetch fresh from database to avoid stale data issues
                if var freshNote = try Note.fetchOne(db, key: noteId) {
                    freshNote.content = newContent
                    freshNote.updatedAt = Date()
                    freshNote.closedAt = nil // Reopen on edit
                    try freshNote.update(db)
                    savedNote = freshNote
                    print("Note saved: \(noteId)")
                }
            }
            // Update local state with saved note
            if let saved = savedNote {
                currentNote = saved
                lastSavedContent = newContent
                lastRefreshed = Date()
            }
            saveStatus = .saved
        } catch {
            print("Failed to save note: \(error)")
            saveStatus = .unsaved
        }
    }

    private func refreshNote() {
        let noteId = note.id
        do {
            if let freshNote = try Database.shared.read({ db in
                try Note.fetchOne(db, key: noteId)
            }) {
                currentNote = freshNote
                content = freshNote.content
                lastSavedContent = freshNote.content
                lastRefreshed = Date()
                saveStatus = .saved
            }
        } catch {
            print("Failed to refresh note: \(error)")
        }
    }

    private func continueInCapture() {
        NotificationCenter.default.post(
            name: .continueWithNote,
            object: nil,
            userInfo: ["noteId": note.id]
        )
    }

    private func archiveNote() {
        var updatedNote = note
        updatedNote.archived = true
        updatedNote.updatedAt = Date()

        do {
            try Database.shared.write { db in
                try updatedNote.update(db)
            }
        } catch {
            print("Failed to archive note: \(error)")
        }
    }

    private func loadAvailableContexts() {
        do {
            availableContexts = try Database.shared.read { db in
                try Context.active().fetchAll(db)
            }
        } catch {
            print("Failed to load available contexts: \(error)")
        }
    }

    private func addContext(_ context: Context) {
        let noteId = note.id
        do {
            try Database.shared.write { db in
                let noteContext = NoteContext(noteId: noteId, contextId: context.id)
                try noteContext.insert(db)
            }
            // Update local state
            if !contexts.contains(where: { $0.id == context.id }) {
                contexts.append(context)
            }
        } catch {
            print("Failed to add context: \(error)")
        }
    }

    private func removeContext(_ context: Context) {
        let noteId = note.id
        do {
            try Database.shared.write { db in
                try NoteContext
                    .filter(NoteContext.Columns.noteId == noteId)
                    .filter(NoteContext.Columns.contextId == context.id)
                    .deleteAll(db)
            }
            // Update local state
            contexts.removeAll { $0.id == context.id }
        } catch {
            print("Failed to remove context: \(error)")
        }
    }
}

// MARK: - Cyber Icon Button

struct CyberIconButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(color.opacity(0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Context Picker Sheet

struct NoteContextPickerSheet: View {
    let availableContexts: [Context]
    let selectedContexts: [Context]
    let onAdd: (Context) -> Void
    let onCancel: () -> Void

    @State private var searchText: String = ""

    private var filteredContexts: [Context] {
        let unselected = availableContexts.filter { context in
            !selectedContexts.contains { $0.id == context.id }
        }
        if searchText.isEmpty {
            return unselected
        }
        return unselected.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ADD CONTEXT")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(NootTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Rectangle()
                .fill(NootTheme.cyan.opacity(0.3))
                .frame(height: 1)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(NootTheme.cyan.opacity(0.6))
                TextField("Search contexts...", text: $searchText)
                    .font(NootTheme.monoFontSmall)
                    .textFieldStyle(.plain)
                    .foregroundColor(NootTheme.textPrimary)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(NootTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(NootTheme.surface.opacity(0.5))

            Rectangle()
                .fill(NootTheme.cyan.opacity(0.2))
                .frame(height: 1)

            // Context list
            if filteredContexts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.title)
                        .foregroundColor(NootTheme.cyan.opacity(0.5))
                        .neonGlow(NootTheme.cyan, radius: 6)
                    Text(availableContexts.isEmpty ? "NO CONTEXTS AVAILABLE" : "NO MATCHING CONTEXTS")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NootTheme.background)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredContexts) { context in
                            Button(action: { onAdd(context) }) {
                                HStack {
                                    Image(systemName: context.iconName)
                                        .foregroundColor(context.themeColor)
                                        .font(.caption)
                                    Text(context.name)
                                        .font(NootTheme.monoFontSmall)
                                        .foregroundColor(NootTheme.textPrimary)
                                    Spacer()
                                    Text(context.type.rawValue.uppercased())
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(NootTheme.textMuted)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(NootTheme.surface.opacity(0.5))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(context.themeColor.opacity(0.2), lineWidth: 0.5)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .background(NootTheme.background)
            }
        }
        .frame(width: 350, height: 400)
        .background(NootTheme.background)
    }
}

struct AttachmentThumbnail: View {
    let attachment: Attachment

    var body: some View {
        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))

                Image(systemName: iconForType)
                    .font(.title)
                    .foregroundColor(.secondary)
            }
            .frame(height: 80)

            Text(attachment.formattedFileSize)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var iconForType: String {
        switch attachment.type {
        case .screenshot: return "photo"
        case .screenRecording: return "video"
        case .audio: return "waveform"
        }
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

#Preview {
    NoteDetailView(note: Note(content: "# Sample Note\n\nThis is a sample note with some content."))
        .frame(width: 500, height: 600)
}
