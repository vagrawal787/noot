import Foundation
import GRDB
import Yams

// MARK: - Export Errors

enum ExportError: Error, LocalizedError {
    case databaseNotInitialized
    case failedToCreateDirectory(String)
    case failedToWriteFile(String)
    case failedToCopyAttachment(String)
    case invalidExportPath
    case contextNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .databaseNotInitialized:
            return "Database not initialized"
        case .failedToCreateDirectory(let path):
            return "Failed to create directory: \(path)"
        case .failedToWriteFile(let path):
            return "Failed to write file: \(path)"
        case .failedToCopyAttachment(let path):
            return "Failed to copy attachment: \(path)"
        case .invalidExportPath:
            return "Invalid export path"
        case .contextNotFound(let id):
            return "Context not found: \(id)"
        }
    }
}

// MARK: - Export Service

final class ExportService {
    static let shared = ExportService()

    private let fileManager = FileManager.default
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private init() {}

    // MARK: - App Support Directory

    private var appSupportURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Noot", isDirectory: true)
    }

    private var attachmentsURL: URL {
        appSupportURL.appendingPathComponent("attachments", isDirectory: true)
    }

    // MARK: - Full Export

    /// Export all Noot data to a directory
    func exportFull(to directory: URL, progress: @escaping (ExportProgress) -> Void) async throws -> URL {
        // Create timestamped export directory
        let dateString = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "T", with: "_")
            .prefix(19)
        let exportDir = directory.appendingPathComponent("noot-export-\(dateString)", isDirectory: true)

        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // Create notes subdirectory
        let notesDir = exportDir.appendingPathComponent("notes", isDirectory: true)
        try fileManager.createDirectory(at: notesDir, withIntermediateDirectories: true)

        // Fetch all data
        progress(ExportProgress(phase: "Reading database", current: 0, total: 1))

        let exportData = try Database.shared.read { db -> FullExportData in
            let notes = try Note.fetchAll(db)
            let contexts = try Context.fetchAll(db)
            let contextLinks = try ContextLink.fetchAll(db)
            let noteContexts = try NoteContext.fetchAll(db)
            let noteLinks = try NoteLink.fetchAll(db)
            let meetings = try Meeting.fetchAll(db)
            let noteMeetings = try NoteMeeting.fetchAll(db)
            let meetingContexts = try MeetingContext.fetchAll(db)
            let screenContexts = try ScreenContext.fetchAll(db)
            let attachments = try Attachment.fetchAll(db)
            let calendarAccounts = try CalendarAccount.fetchAll(db)
            let calendarEvents = try CalendarEvent.fetchAll(db)
            let calendarSeriesContextRules = try CalendarSeriesContextRule.fetchAll(db)
            let ignoredCalendarEvents = try IgnoredCalendarEvent.fetchAll(db)

            let manifest = ExportManifest(
                noteCount: notes.count,
                attachmentCount: attachments.count,
                contextCount: contexts.count,
                meetingCount: meetings.count,
                contextLinkCount: contextLinks.count,
                noteLinkCount: noteLinks.count,
                screenContextCount: screenContexts.count,
                calendarEventCount: calendarEvents.count,
                calendarAccountCount: calendarAccounts.count
            )

            return FullExportData(
                manifest: manifest,
                notes: notes,
                contexts: contexts,
                contextLinks: contextLinks,
                noteContexts: noteContexts,
                noteLinks: noteLinks,
                meetings: meetings,
                noteMeetings: noteMeetings,
                meetingContexts: meetingContexts,
                screenContexts: screenContexts,
                attachments: attachments,
                calendarAccounts: calendarAccounts,
                calendarEvents: calendarEvents,
                calendarSeriesContextRules: calendarSeriesContextRules,
                ignoredCalendarEvents: ignoredCalendarEvents
            )
        }

        // Write manifest
        progress(ExportProgress(phase: "Writing manifest", current: 1, total: 4))
        let manifestURL = exportDir.appendingPathComponent("manifest.json")
        try writeJSON(exportData.manifest, to: manifestURL)

        // Write contexts
        let contextsURL = exportDir.appendingPathComponent("contexts.json")
        try writeJSON(exportData.contexts, to: contextsURL)

        // Write context links
        let contextLinksURL = exportDir.appendingPathComponent("context-links.json")
        try writeJSON(exportData.contextLinks, to: contextLinksURL)

        // Write meetings
        let meetingsURL = exportDir.appendingPathComponent("meetings.json")
        try writeJSON(exportData.meetings, to: meetingsURL)

        // Write calendar data
        let calendarAccountsURL = exportDir.appendingPathComponent("calendar-accounts.json")
        try writeJSON(exportData.calendarAccounts, to: calendarAccountsURL)

        let calendarEventsURL = exportDir.appendingPathComponent("calendar-events.json")
        try writeJSON(exportData.calendarEvents, to: calendarEventsURL)

        let calendarRulesURL = exportDir.appendingPathComponent("calendar-rules.json")
        try writeJSON(exportData.calendarSeriesContextRules, to: calendarRulesURL)

        // Write config
        progress(ExportProgress(phase: "Writing config", current: 2, total: 4))
        let configSourceURL = appSupportURL.appendingPathComponent("config.json")
        if fileManager.fileExists(atPath: configSourceURL.path) {
            let configDestURL = exportDir.appendingPathComponent("config.json")
            try fileManager.copyItem(at: configSourceURL, to: configDestURL)
        }

        // Write notes as markdown with YAML frontmatter
        progress(ExportProgress(phase: "Exporting notes", current: 3, total: 4))
        let contextMap = Dictionary(uniqueKeysWithValues: exportData.contexts.map { ($0.id, $0) })

        for (index, note) in exportData.notes.enumerated() {
            if index % 50 == 0 {
                progress(ExportProgress(phase: "Exporting notes", current: index, total: exportData.notes.count))
            }

            let frontmatter = buildFrontmatter(
                for: note,
                noteContexts: exportData.noteContexts.filter { $0.noteId == note.id },
                noteLinks: exportData.noteLinks.filter { $0.sourceNoteId == note.id },
                noteMeetings: exportData.noteMeetings.filter { $0.noteId == note.id },
                screenContexts: exportData.screenContexts.filter { $0.noteId == note.id },
                attachments: exportData.attachments.filter { $0.noteId == note.id },
                contextMap: contextMap
            )

            let markdown = try buildMarkdownWithFrontmatter(frontmatter: frontmatter, content: note.content)
            let noteURL = notesDir.appendingPathComponent("\(note.id.uuidString).md")
            try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
        }

        // Copy attachments (only create directory if there are attachments)
        if !exportData.attachments.isEmpty {
            let attachmentsDir = exportDir.appendingPathComponent("attachments", isDirectory: true)
            try fileManager.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

            progress(ExportProgress(phase: "Copying attachments", current: 0, total: exportData.attachments.count))
            for (index, attachment) in exportData.attachments.enumerated() {
                if index % 10 == 0 {
                    progress(ExportProgress(phase: "Copying attachments", current: index, total: exportData.attachments.count))
                }

                // Handle both absolute and relative paths
                let sourcePath: URL
                if attachment.filePath.hasPrefix("/") {
                    // Absolute path - use directly
                    sourcePath = URL(fileURLWithPath: attachment.filePath)
                } else {
                    // Relative path - append to attachments directory
                    sourcePath = attachmentsURL.appendingPathComponent(attachment.filePath)
                }

                if fileManager.fileExists(atPath: sourcePath.path) {
                    let destPath = attachmentsDir.appendingPathComponent("\(attachment.id.uuidString)-\(attachment.type.rawValue).\(sourcePath.pathExtension)")
                    try? fileManager.copyItem(at: sourcePath, to: destPath)
                }
            }
        }

        progress(ExportProgress(phase: "Complete", current: 4, total: 4))
        return exportDir
    }

    // MARK: - Markdown Export

    /// Export notes as human-readable markdown files organized by context
    func exportMarkdown(to directory: URL, options: MarkdownExportOptions, progress: @escaping (ExportProgress) -> Void) async throws -> URL {
        let dateString = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .prefix(10)
        let exportDir = directory.appendingPathComponent("noot-markdown-\(dateString)", isDirectory: true)

        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // Fetch data
        progress(ExportProgress(phase: "Reading database", current: 0, total: 1))

        let (notes, contexts, noteContexts, attachments) = try Database.shared.read { db -> ([Note], [Context], [NoteContext], [Attachment]) in
            var notesQuery = Note.all()
            if !options.includeArchived {
                notesQuery = notesQuery.filter(Note.Columns.archived == false)
            }
            let notes = try notesQuery.fetchAll(db)
            let contexts = try Context.fetchAll(db)
            let noteContexts = try NoteContext.fetchAll(db)
            let attachments = try Attachment.fetchAll(db)
            return (notes, contexts, noteContexts, attachments)
        }

        let contextMap = Dictionary(uniqueKeysWithValues: contexts.map { ($0.id, $0) })
        let noteContextMap = Dictionary(grouping: noteContexts, by: { $0.noteId })
        let attachmentMap = Dictionary(grouping: attachments, by: { $0.noteId })

        // Create attachments directory only if needed
        var attachmentsDir: URL?
        if options.includeAttachments && !attachments.isEmpty {
            attachmentsDir = exportDir.appendingPathComponent("_attachments", isDirectory: true)
            try fileManager.createDirectory(at: attachmentsDir!, withIntermediateDirectories: true)
        }

        // Organize by option
        switch options.organizeBy {
        case .context:
            try await exportByContext(
                notes: notes,
                contextMap: contextMap,
                noteContextMap: noteContextMap,
                attachmentMap: attachmentMap,
                exportDir: exportDir,
                attachmentsDir: attachmentsDir,
                options: options,
                progress: progress
            )

        case .date:
            try await exportByDate(
                notes: notes,
                contextMap: contextMap,
                noteContextMap: noteContextMap,
                attachmentMap: attachmentMap,
                exportDir: exportDir,
                attachmentsDir: attachmentsDir,
                options: options,
                progress: progress
            )

        case .flat:
            try await exportFlat(
                notes: notes,
                contextMap: contextMap,
                noteContextMap: noteContextMap,
                attachmentMap: attachmentMap,
                exportDir: exportDir,
                attachmentsDir: attachmentsDir,
                options: options,
                progress: progress
            )
        }

        progress(ExportProgress(phase: "Complete", current: 1, total: 1))
        return exportDir
    }

    // MARK: - Context Export

    /// Export a single context with its notes
    func exportContext(_ contextId: UUID, to directory: URL, options: MarkdownExportOptions) async throws -> URL {
        let (context, notes, noteContexts, attachments) = try Database.shared.read { db -> (Context, [Note], [NoteContext], [Attachment]) in
            guard let context = try Context.fetchOne(db, key: contextId) else {
                throw ExportError.contextNotFound(contextId)
            }

            // Get note IDs in this context
            let noteContexts = try NoteContext
                .filter(NoteContext.Columns.contextId == contextId)
                .fetchAll(db)
            let noteIds = noteContexts.map { $0.noteId }

            // Get notes
            var notesQuery = Note.filter(keys: noteIds)
            if !options.includeArchived {
                notesQuery = notesQuery.filter(Note.Columns.archived == false)
            }
            let notes = try notesQuery.fetchAll(db)

            // Get attachments
            let attachments = try Attachment.filter(noteIds.contains(Attachment.Columns.noteId)).fetchAll(db)

            return (context, notes, noteContexts, attachments)
        }

        // Create export directory
        let safeContextName = context.name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let exportDir = directory.appendingPathComponent(safeContextName, isDirectory: true)
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // Create attachments directory if needed
        var attachmentsDir: URL?
        if options.includeAttachments && !attachments.isEmpty {
            attachmentsDir = exportDir.appendingPathComponent("_attachments", isDirectory: true)
            try fileManager.createDirectory(at: attachmentsDir!, withIntermediateDirectories: true)
        }

        let attachmentMap = Dictionary(grouping: attachments, by: { $0.noteId })

        // Export notes
        for note in notes {
            let filename = buildFilename(for: note)
            let noteURL = exportDir.appendingPathComponent(filename)

            let noteAttachments = attachmentMap[note.id] ?? []
            let markdown = buildReadableMarkdown(note: note, attachments: noteAttachments)
            try markdown.write(to: noteURL, atomically: true, encoding: .utf8)

            // Copy attachments
            if let attachmentsDir = attachmentsDir {
                for attachment in noteAttachments {
                    try copyAttachmentForMarkdown(attachment: attachment, to: attachmentsDir)
                }
            }
        }

        return exportDir
    }

    // MARK: - Private Helpers

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url)
    }

    private func buildFrontmatter(
        for note: Note,
        noteContexts: [NoteContext],
        noteLinks: [NoteLink],
        noteMeetings: [NoteMeeting],
        screenContexts: [ScreenContext],
        attachments: [Attachment],
        contextMap: [UUID: Context]
    ) -> NoteFrontmatter {
        let contextRefs: [NoteFrontmatter.ContextRef]? = noteContexts.isEmpty ? nil : noteContexts.compactMap { nc in
            guard let context = contextMap[nc.contextId] else { return nil }
            return NoteFrontmatter.ContextRef(id: nc.contextId.uuidString, name: context.name)
        }

        let linkRefs: [NoteFrontmatter.LinkRef]? = noteLinks.isEmpty ? nil : noteLinks.map { link in
            NoteFrontmatter.LinkRef(targetId: link.targetNoteId.uuidString, relationship: link.relationship.rawValue)
        }

        let screenContextRef: NoteFrontmatter.ScreenContextRef? = screenContexts.first.map { sc in
            NoteFrontmatter.ScreenContextRef(
                sourceType: sc.sourceType.rawValue,
                appName: sc.appName,
                url: sc.url,
                filePath: sc.filePath,
                lineStart: sc.lineStart,
                lineEnd: sc.lineEnd,
                gitRepo: sc.gitRepo,
                gitBranch: sc.gitBranch
            )
        }

        let attachmentRefs: [NoteFrontmatter.AttachmentRef]? = attachments.isEmpty ? nil : attachments.map { att in
            let ext = (att.filePath as NSString).pathExtension
            return NoteFrontmatter.AttachmentRef(
                id: att.id.uuidString,
                type: att.type.rawValue,
                filename: "\(att.id.uuidString)-\(att.type.rawValue).\(ext)",
                fileSize: att.fileSize,
                durationSeconds: att.durationSeconds
            )
        }

        return NoteFrontmatter(
            id: note.id.uuidString,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            closedAt: note.closedAt,
            archived: note.archived,
            contexts: contextRefs,
            links: linkRefs,
            meetingId: noteMeetings.first?.meetingId.uuidString,
            screenContext: screenContextRef,
            attachments: attachmentRefs
        )
    }

    private func buildMarkdownWithFrontmatter(frontmatter: NoteFrontmatter, content: String) throws -> String {
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(frontmatter)
        return "---\n\(yaml)---\n\n\(content)"
    }

    private func buildFilename(for note: Note) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: note.createdAt)

        // Extract title from first line or use snippet
        let firstLine = note.content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let title = firstLine.prefix(50)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)

        let slug = title.isEmpty ? String(note.id.uuidString.prefix(8)) : slugify(String(title))
        return "\(dateStr)-\(slug).md"
    }

    private func slugify(_ text: String) -> String {
        let result = text.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        return String(result.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func buildReadableMarkdown(note: Note, attachments: [Attachment]) -> String {
        var md = note.content

        // Add attachment references at the end if any
        if !attachments.isEmpty {
            md += "\n\n---\n\n## Attachments\n\n"
            for attachment in attachments {
                let ext = (attachment.filePath as NSString).pathExtension
                let filename = "\(attachment.id.uuidString).\(ext)"
                switch attachment.type {
                case .screenshot:
                    md += "![Screenshot](_attachments/\(filename))\n"
                case .screenRecording:
                    md += "- [Screen Recording](_attachments/\(filename))"
                    if let duration = attachment.formattedDuration {
                        md += " (\(duration))"
                    }
                    md += "\n"
                case .audio:
                    md += "- [Audio Recording](_attachments/\(filename))"
                    if let duration = attachment.formattedDuration {
                        md += " (\(duration))"
                    }
                    md += "\n"
                }
            }
        }

        return md
    }

    private func copyAttachmentForMarkdown(attachment: Attachment, to directory: URL) throws {
        // Handle both absolute and relative paths
        let sourcePath: URL
        if attachment.filePath.hasPrefix("/") {
            sourcePath = URL(fileURLWithPath: attachment.filePath)
        } else {
            sourcePath = attachmentsURL.appendingPathComponent(attachment.filePath)
        }

        if fileManager.fileExists(atPath: sourcePath.path) {
            let ext = sourcePath.pathExtension
            let destPath = directory.appendingPathComponent("\(attachment.id.uuidString).\(ext)")
            try? fileManager.copyItem(at: sourcePath, to: destPath)
        }
    }

    // MARK: - Export Organization Methods

    private func exportByContext(
        notes: [Note],
        contextMap: [UUID: Context],
        noteContextMap: [UUID: [NoteContext]],
        attachmentMap: [UUID: [Attachment]],
        exportDir: URL,
        attachmentsDir: URL?,
        options: MarkdownExportOptions,
        progress: @escaping (ExportProgress) -> Void
    ) async throws {
        // Create inbox for ungrouped notes
        let inboxDir = exportDir.appendingPathComponent("_inbox", isDirectory: true)
        try fileManager.createDirectory(at: inboxDir, withIntermediateDirectories: true)

        // Group notes by context
        var contextNotes: [UUID: [Note]] = [:]
        var inboxNotes: [Note] = []

        for note in notes {
            if let ncs = noteContextMap[note.id], let firstNC = ncs.first {
                contextNotes[firstNC.contextId, default: []].append(note)
            } else {
                inboxNotes.append(note)
            }
        }

        // Export inbox notes
        for note in inboxNotes {
            let filename = buildFilename(for: note)
            let noteURL = inboxDir.appendingPathComponent(filename)
            let noteAttachments = attachmentMap[note.id] ?? []
            let markdown = buildReadableMarkdown(note: note, attachments: noteAttachments)
            try markdown.write(to: noteURL, atomically: true, encoding: .utf8)

            if let attachmentsDir = attachmentsDir {
                for attachment in noteAttachments {
                    try copyAttachmentForMarkdown(attachment: attachment, to: attachmentsDir)
                }
            }
        }

        // Export context notes
        for (contextId, ctxNotes) in contextNotes {
            guard let context = contextMap[contextId] else { continue }

            let safeName = context.name.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let contextDir = exportDir.appendingPathComponent(safeName, isDirectory: true)
            try fileManager.createDirectory(at: contextDir, withIntermediateDirectories: true)

            for note in ctxNotes {
                let filename = buildFilename(for: note)
                let noteURL = contextDir.appendingPathComponent(filename)
                let noteAttachments = attachmentMap[note.id] ?? []
                let markdown = buildReadableMarkdown(note: note, attachments: noteAttachments)
                try markdown.write(to: noteURL, atomically: true, encoding: .utf8)

                if let attachmentsDir = attachmentsDir {
                    for attachment in noteAttachments {
                        try copyAttachmentForMarkdown(attachment: attachment, to: attachmentsDir)
                    }
                }
            }
        }
    }

    private func exportByDate(
        notes: [Note],
        contextMap: [UUID: Context],
        noteContextMap: [UUID: [NoteContext]],
        attachmentMap: [UUID: [Attachment]],
        exportDir: URL,
        attachmentsDir: URL?,
        options: MarkdownExportOptions,
        progress: @escaping (ExportProgress) -> Void
    ) async throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"

        // Group notes by month
        var monthNotes: [String: [Note]] = [:]
        for note in notes {
            let month = dateFormatter.string(from: note.createdAt)
            monthNotes[month, default: []].append(note)
        }

        // Export by month
        for (month, monthNoteList) in monthNotes.sorted(by: { $0.key > $1.key }) {
            let monthDir = exportDir.appendingPathComponent(month, isDirectory: true)
            try fileManager.createDirectory(at: monthDir, withIntermediateDirectories: true)

            for note in monthNoteList {
                let filename = buildFilename(for: note)
                let noteURL = monthDir.appendingPathComponent(filename)
                let noteAttachments = attachmentMap[note.id] ?? []
                let markdown = buildReadableMarkdown(note: note, attachments: noteAttachments)
                try markdown.write(to: noteURL, atomically: true, encoding: .utf8)

                if let attachmentsDir = attachmentsDir {
                    for attachment in noteAttachments {
                        try copyAttachmentForMarkdown(attachment: attachment, to: attachmentsDir)
                    }
                }
            }
        }
    }

    private func exportFlat(
        notes: [Note],
        contextMap: [UUID: Context],
        noteContextMap: [UUID: [NoteContext]],
        attachmentMap: [UUID: [Attachment]],
        exportDir: URL,
        attachmentsDir: URL?,
        options: MarkdownExportOptions,
        progress: @escaping (ExportProgress) -> Void
    ) async throws {
        for (index, note) in notes.enumerated() {
            if index % 50 == 0 {
                progress(ExportProgress(phase: "Exporting notes", current: index, total: notes.count))
            }

            let filename = buildFilename(for: note)
            let noteURL = exportDir.appendingPathComponent(filename)
            let noteAttachments = attachmentMap[note.id] ?? []
            let markdown = buildReadableMarkdown(note: note, attachments: noteAttachments)
            try markdown.write(to: noteURL, atomically: true, encoding: .utf8)

            if let attachmentsDir = attachmentsDir {
                for attachment in noteAttachments {
                    try copyAttachmentForMarkdown(attachment: attachment, to: attachmentsDir)
                }
            }
        }
    }
}
