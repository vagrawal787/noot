import Foundation
import GRDB
import Yams

// MARK: - Import Errors

enum ImportError: Error, LocalizedError {
    case invalidImportPath
    case manifestNotFound
    case invalidManifest
    case unsupportedSchemaVersion(Int)
    case corruptedData(String)
    case databaseWriteFailed(String)
    case attachmentNotFound(String)
    case frontmatterParseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidImportPath:
            return "Invalid import path"
        case .manifestNotFound:
            return "Export manifest not found"
        case .invalidManifest:
            return "Invalid export manifest"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported schema version: \(version)"
        case .corruptedData(let detail):
            return "Corrupted data: \(detail)"
        case .databaseWriteFailed(let detail):
            return "Database write failed: \(detail)"
        case .attachmentNotFound(let path):
            return "Attachment not found: \(path)"
        case .frontmatterParseError(let detail):
            return "Failed to parse frontmatter: \(detail)"
        }
    }
}

// MARK: - Import Types

struct ImportPreview {
    var isValid: Bool
    var schemaVersion: Int
    var noteCount: Int
    var contextCount: Int
    var meetingCount: Int
    var attachmentCount: Int
    var warnings: [String]
    var manifest: ExportManifest?
}

enum ImportMode {
    case merge      // Keep both on conflict (imported items get new UUIDs)
    case replace    // Backup first, then replace entire database
}

struct MarkdownImportOptions {
    var createContextsFromFolders: Bool = true
    var parseFrontmatter: Bool = true
    var importImages: Bool = true
    var targetContext: UUID?
}

struct ImportReport {
    var notesImported: Int
    var contextsImported: Int
    var meetingsImported: Int
    var attachmentsImported: Int
    var skipped: [SkippedItem]
    var warnings: [String]

    struct SkippedItem {
        var type: String
        var name: String
        var reason: String
    }
}

struct ImportProgress {
    var phase: String
    var current: Int
    var total: Int

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

// MARK: - Import Service

final class ImportService {
    static let shared = ImportService()

    private let fileManager = FileManager.default

    private init() {}

    // MARK: - App Support Directory

    private var appSupportURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Noot", isDirectory: true)
    }

    private var attachmentsURL: URL {
        appSupportURL.appendingPathComponent("attachments", isDirectory: true)
    }

    // MARK: - Validation

    /// Validate an export directory and return a preview of its contents
    func validateExport(at url: URL) throws -> ImportPreview {
        var warnings: [String] = []

        // Check if directory exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return ImportPreview(
                isValid: false,
                schemaVersion: 0,
                noteCount: 0,
                contextCount: 0,
                meetingCount: 0,
                attachmentCount: 0,
                warnings: ["Not a valid directory"],
                manifest: nil
            )
        }

        // Look for manifest.json
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return ImportPreview(
                isValid: false,
                schemaVersion: 0,
                noteCount: 0,
                contextCount: 0,
                meetingCount: 0,
                attachmentCount: 0,
                warnings: ["manifest.json not found"],
                manifest: nil
            )
        }

        // Parse manifest
        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifest: ExportManifest
        do {
            manifest = try decoder.decode(ExportManifest.self, from: manifestData)
        } catch {
            return ImportPreview(
                isValid: false,
                schemaVersion: 0,
                noteCount: 0,
                contextCount: 0,
                meetingCount: 0,
                attachmentCount: 0,
                warnings: ["Invalid manifest: \(error.localizedDescription)"],
                manifest: nil
            )
        }

        // Check schema version compatibility
        if manifest.schemaVersion > currentExportSchemaVersion {
            warnings.append("Export was created with a newer version of Noot. Some data may not import correctly.")
        }

        // Verify notes directory
        let notesDir = url.appendingPathComponent("notes")
        if !fileManager.fileExists(atPath: notesDir.path) {
            warnings.append("Notes directory not found")
        }

        // Verify attachments directory
        let attachmentsDir = url.appendingPathComponent("attachments")
        if manifest.attachmentCount > 0 && !fileManager.fileExists(atPath: attachmentsDir.path) {
            warnings.append("Attachments directory not found but \(manifest.attachmentCount) attachments expected")
        }

        return ImportPreview(
            isValid: true,
            schemaVersion: manifest.schemaVersion,
            noteCount: manifest.noteCount,
            contextCount: manifest.contextCount,
            meetingCount: manifest.meetingCount,
            attachmentCount: manifest.attachmentCount,
            warnings: warnings,
            manifest: manifest
        )
    }

    // MARK: - Full Import

    /// Import a full Noot export
    func importFull(from url: URL, mode: ImportMode, progress: @escaping (ImportProgress) -> Void) async throws -> ImportReport {
        var report = ImportReport(
            notesImported: 0,
            contextsImported: 0,
            meetingsImported: 0,
            attachmentsImported: 0,
            skipped: [],
            warnings: []
        )

        // Validate first
        let preview = try validateExport(at: url)
        guard preview.isValid else {
            throw ImportError.invalidImportPath
        }
        report.warnings.append(contentsOf: preview.warnings)

        progress(ImportProgress(phase: "Reading export data", current: 0, total: 5))

        // Read all JSON files
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Read contexts
        let contextsURL = url.appendingPathComponent("contexts.json")
        let contexts: [Context] = try readJSON(from: contextsURL, decoder: decoder) ?? []

        // Read context links
        let contextLinksURL = url.appendingPathComponent("context-links.json")
        let contextLinks: [ContextLink] = try readJSON(from: contextLinksURL, decoder: decoder) ?? []

        // Read meetings
        let meetingsURL = url.appendingPathComponent("meetings.json")
        let meetings: [Meeting] = try readJSON(from: meetingsURL, decoder: decoder) ?? []

        // Read calendar data
        let calendarAccountsURL = url.appendingPathComponent("calendar-accounts.json")
        let calendarAccounts: [CalendarAccount] = try readJSON(from: calendarAccountsURL, decoder: decoder) ?? []

        let calendarEventsURL = url.appendingPathComponent("calendar-events.json")
        let calendarEvents: [CalendarEvent] = try readJSON(from: calendarEventsURL, decoder: decoder) ?? []

        let calendarRulesURL = url.appendingPathComponent("calendar-rules.json")
        let calendarRules: [CalendarSeriesContextRule] = try readJSON(from: calendarRulesURL, decoder: decoder) ?? []

        // Read notes from markdown files
        progress(ImportProgress(phase: "Reading notes", current: 1, total: 5))
        let notesDir = url.appendingPathComponent("notes")
        var notes: [Note] = []
        var noteContexts: [NoteContext] = []
        var noteLinks: [NoteLink] = []
        var noteMeetings: [NoteMeeting] = []
        var screenContexts: [ScreenContext] = []
        var attachmentRefs: [(noteId: UUID, ref: NoteFrontmatter.AttachmentRef)] = []

        if fileManager.fileExists(atPath: notesDir.path) {
            let noteFiles = try fileManager.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "md" }

            for noteFile in noteFiles {
                let markdown = try String(contentsOf: noteFile, encoding: .utf8)
                let (frontmatter, content) = try parseMarkdownWithFrontmatter(markdown)

                guard let frontmatter = frontmatter else {
                    report.skipped.append(ImportReport.SkippedItem(
                        type: "note",
                        name: noteFile.lastPathComponent,
                        reason: "No frontmatter"
                    ))
                    continue
                }

                guard let noteId = UUID(uuidString: frontmatter.id) else {
                    report.skipped.append(ImportReport.SkippedItem(
                        type: "note",
                        name: noteFile.lastPathComponent,
                        reason: "Invalid note ID"
                    ))
                    continue
                }

                let note = Note(
                    id: noteId,
                    content: content,
                    createdAt: frontmatter.createdAt,
                    updatedAt: frontmatter.updatedAt,
                    closedAt: frontmatter.closedAt,
                    archived: frontmatter.archived
                )
                notes.append(note)

                // Parse contexts
                if let contextRefs = frontmatter.contexts {
                    for ctxRef in contextRefs {
                        if let contextId = UUID(uuidString: ctxRef.id) {
                            noteContexts.append(NoteContext(noteId: noteId, contextId: contextId))
                        }
                    }
                }

                // Parse links
                if let linkRefs = frontmatter.links {
                    for linkRef in linkRefs {
                        if let targetId = UUID(uuidString: linkRef.targetId),
                           let relationship = NoteLinkRelationship(rawValue: linkRef.relationship) {
                            noteLinks.append(NoteLink(
                                sourceNoteId: noteId,
                                targetNoteId: targetId,
                                relationship: relationship
                            ))
                        }
                    }
                }

                // Parse meeting reference
                if let meetingIdStr = frontmatter.meetingId,
                   let meetingId = UUID(uuidString: meetingIdStr) {
                    noteMeetings.append(NoteMeeting(noteId: noteId, meetingId: meetingId))
                }

                // Parse screen context
                if let scRef = frontmatter.screenContext {
                    if let sourceType = ScreenContextSourceType(rawValue: scRef.sourceType) {
                        screenContexts.append(ScreenContext(
                            noteId: noteId,
                            sourceType: sourceType,
                            appName: scRef.appName,
                            url: scRef.url,
                            filePath: scRef.filePath,
                            lineStart: scRef.lineStart,
                            lineEnd: scRef.lineEnd,
                            gitRepo: scRef.gitRepo,
                            gitBranch: scRef.gitBranch
                        ))
                    }
                }

                // Parse attachments
                if let attRefs = frontmatter.attachments {
                    for attRef in attRefs {
                        attachmentRefs.append((noteId: noteId, ref: attRef))
                    }
                }
            }
        }

        // Handle import mode
        progress(ImportProgress(phase: "Importing data", current: 2, total: 5))

        switch mode {
        case .replace:
            // Create backup first
            try await createBackup()

            // Clear existing data and import
            try Database.shared.write { db in
                // Delete all existing data (order matters for foreign keys)
                try db.execute(sql: "DELETE FROM note_meetings")
                try db.execute(sql: "DELETE FROM note_contexts")
                try db.execute(sql: "DELETE FROM note_links")
                try db.execute(sql: "DELETE FROM screen_contexts")
                try db.execute(sql: "DELETE FROM attachments")
                try db.execute(sql: "DELETE FROM meeting_contexts")
                try db.execute(sql: "DELETE FROM context_links")
                try db.execute(sql: "DELETE FROM calendar_series_context_rules")
                try db.execute(sql: "DELETE FROM calendar_events")
                try db.execute(sql: "DELETE FROM calendar_accounts")
                try db.execute(sql: "DELETE FROM ignored_calendar_events")
                try db.execute(sql: "DELETE FROM meetings")
                try db.execute(sql: "DELETE FROM contexts")
                try db.execute(sql: "DELETE FROM notes")

                // Insert imported data
                for context in contexts {
                    try context.insert(db)
                    report.contextsImported += 1
                }

                for contextLink in contextLinks {
                    try contextLink.insert(db)
                }

                for meeting in meetings {
                    try meeting.insert(db)
                    report.meetingsImported += 1
                }

                for note in notes {
                    try note.insert(db)
                    report.notesImported += 1
                }

                for noteContext in noteContexts {
                    try? noteContext.insert(db)
                }

                for noteLink in noteLinks {
                    try? noteLink.insert(db)
                }

                for noteMeeting in noteMeetings {
                    try? noteMeeting.insert(db)
                }

                for screenContext in screenContexts {
                    try screenContext.insert(db)
                }

                for calendarAccount in calendarAccounts {
                    try calendarAccount.insert(db)
                }

                for calendarEvent in calendarEvents {
                    try calendarEvent.insert(db)
                }

                for calendarRule in calendarRules {
                    try calendarRule.insert(db)
                }
            }

        case .merge:
            // Import with conflict handling - skip existing IDs
            try Database.shared.write { db in
                for context in contexts {
                    if try Context.fetchOne(db, key: context.id) == nil {
                        try context.insert(db)
                        report.contextsImported += 1
                    } else {
                        report.skipped.append(ImportReport.SkippedItem(
                            type: "context",
                            name: context.name,
                            reason: "Already exists"
                        ))
                    }
                }

                for contextLink in contextLinks {
                    try? contextLink.insert(db)
                }

                for meeting in meetings {
                    if try Meeting.fetchOne(db, key: meeting.id) == nil {
                        try meeting.insert(db)
                        report.meetingsImported += 1
                    } else {
                        report.skipped.append(ImportReport.SkippedItem(
                            type: "meeting",
                            name: meeting.title ?? "Untitled",
                            reason: "Already exists"
                        ))
                    }
                }

                for note in notes {
                    if try Note.fetchOne(db, key: note.id) == nil {
                        try note.insert(db)
                        report.notesImported += 1
                    } else {
                        report.skipped.append(ImportReport.SkippedItem(
                            type: "note",
                            name: String(note.content.prefix(50)),
                            reason: "Already exists"
                        ))
                    }
                }

                for noteContext in noteContexts {
                    try? noteContext.insert(db)
                }

                for noteLink in noteLinks {
                    try? noteLink.insert(db)
                }

                for noteMeeting in noteMeetings {
                    try? noteMeeting.insert(db)
                }

                for screenContext in screenContexts {
                    if try ScreenContext.fetchOne(db, key: screenContext.id) == nil {
                        try screenContext.insert(db)
                    }
                }

                for calendarAccount in calendarAccounts {
                    if try CalendarAccount.fetchOne(db, key: calendarAccount.id) == nil {
                        try calendarAccount.insert(db)
                    }
                }

                for calendarEvent in calendarEvents {
                    if try CalendarEvent.fetchOne(db, key: calendarEvent.id) == nil {
                        try calendarEvent.insert(db)
                    }
                }

                for calendarRule in calendarRules {
                    if try CalendarSeriesContextRule.fetchOne(db, key: calendarRule.id) == nil {
                        try calendarRule.insert(db)
                    }
                }
            }
        }

        // Copy attachments
        progress(ImportProgress(phase: "Copying attachments", current: 3, total: 5))
        let sourceAttachmentsDir = url.appendingPathComponent("attachments")
        if fileManager.fileExists(atPath: sourceAttachmentsDir.path) {
            for (noteId, attRef) in attachmentRefs {
                guard let attId = UUID(uuidString: attRef.id),
                      let attType = AttachmentType(rawValue: attRef.type) else {
                    continue
                }

                let sourceFile = sourceAttachmentsDir.appendingPathComponent(attRef.filename)
                if fileManager.fileExists(atPath: sourceFile.path) {
                    // Determine destination subdirectory
                    let subdir: String
                    switch attType {
                    case .screenshot: subdir = "screenshots"
                    case .screenRecording: subdir = "recordings"
                    case .audio: subdir = "audio"
                    }

                    let destDir = attachmentsURL.appendingPathComponent(subdir)
                    try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)

                    let destFilename = "\(attId.uuidString).\(sourceFile.pathExtension)"
                    let destPath = destDir.appendingPathComponent(destFilename)

                    if !fileManager.fileExists(atPath: destPath.path) {
                        try fileManager.copyItem(at: sourceFile, to: destPath)

                        // Create attachment record
                        let fileSize = try fileManager.attributesOfItem(atPath: destPath.path)[.size] as? Int ?? 0
                        let attachment = Attachment(
                            id: attId,
                            noteId: noteId,
                            type: attType,
                            filePath: "\(subdir)/\(destFilename)",
                            fileSize: fileSize,
                            durationSeconds: attRef.durationSeconds
                        )

                        try? Database.shared.write { db in
                            try attachment.insert(db)
                        }
                        report.attachmentsImported += 1
                    }
                }
            }
        }

        // Copy config if replacing
        progress(ImportProgress(phase: "Finalizing", current: 4, total: 5))
        if mode == .replace {
            let sourceConfig = url.appendingPathComponent("config.json")
            if fileManager.fileExists(atPath: sourceConfig.path) {
                let destConfig = appSupportURL.appendingPathComponent("config.json")
                try? fileManager.removeItem(at: destConfig)
                try? fileManager.copyItem(at: sourceConfig, to: destConfig)
                UserPreferences.shared.reload()
            }
        }

        progress(ImportProgress(phase: "Complete", current: 5, total: 5))
        return report
    }

    // MARK: - Markdown Import

    /// Import markdown files from a folder
    func importMarkdown(from url: URL, options: MarkdownImportOptions, progress: @escaping (ImportProgress) -> Void) async throws -> ImportReport {
        var report = ImportReport(
            notesImported: 0,
            contextsImported: 0,
            meetingsImported: 0,
            attachmentsImported: 0,
            skipped: [],
            warnings: []
        )

        // Collect all markdown files
        progress(ImportProgress(phase: "Scanning files", current: 0, total: 1))

        var mdFiles: [(url: URL, contextName: String?)] = []
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey])

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "md" else { continue }

            // Determine context from folder name
            var contextName: String?
            if options.createContextsFromFolders {
                let relativePath = fileURL.deletingLastPathComponent().path
                    .replacingOccurrences(of: url.path, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !relativePath.isEmpty && !relativePath.hasPrefix("_") {
                    contextName = relativePath.components(separatedBy: "/").first
                }
            }

            mdFiles.append((url: fileURL, contextName: contextName))
        }

        // Create contexts from folder names
        var contextMap: [String: UUID] = [:]
        if options.createContextsFromFolders {
            let folderNames = Set(mdFiles.compactMap { $0.contextName })
            for folderName in folderNames {
                // Check if context exists
                let existingContext = try Database.shared.read { db in
                    try Context.filter(Context.Columns.name == folderName).fetchOne(db)
                }

                if let existing = existingContext {
                    contextMap[folderName] = existing.id
                } else {
                    let newContext = Context(name: folderName, type: .workstream)
                    try Database.shared.write { db in
                        try newContext.insert(db)
                    }
                    contextMap[folderName] = newContext.id
                    report.contextsImported += 1
                }
            }
        }

        // Import notes
        progress(ImportProgress(phase: "Importing notes", current: 0, total: mdFiles.count))

        for (index, mdFile) in mdFiles.enumerated() {
            if index % 20 == 0 {
                progress(ImportProgress(phase: "Importing notes", current: index, total: mdFiles.count))
            }

            let markdown = try String(contentsOf: mdFile.url, encoding: .utf8)

            let noteId = UUID()
            var content: String
            var createdAt = Date()
            var updatedAt = Date()

            // Try to parse frontmatter
            if options.parseFrontmatter {
                let (frontmatter, parsedContent) = try parseMarkdownWithFrontmatter(markdown)
                content = parsedContent

                if let fm = frontmatter {
                    createdAt = fm.createdAt
                    updatedAt = fm.updatedAt
                }
            } else {
                content = markdown
            }

            // Create note
            let note = Note(
                id: noteId,
                content: content,
                createdAt: createdAt,
                updatedAt: updatedAt
            )

            try Database.shared.write { db in
                try note.insert(db)

                // Assign to context
                if let contextName = mdFile.contextName,
                   let contextId = contextMap[contextName] {
                    let noteContext = NoteContext(noteId: noteId, contextId: contextId)
                    try noteContext.insert(db)
                } else if let targetContext = options.targetContext {
                    let noteContext = NoteContext(noteId: noteId, contextId: targetContext)
                    try noteContext.insert(db)
                }
            }

            report.notesImported += 1

            // Import images if requested
            if options.importImages {
                let imagesImported = try importImagesFromMarkdown(
                    content: content,
                    noteId: noteId,
                    baseURL: mdFile.url.deletingLastPathComponent()
                )
                report.attachmentsImported += imagesImported
            }
        }

        progress(ImportProgress(phase: "Complete", current: mdFiles.count, total: mdFiles.count))
        return report
    }

    // MARK: - Private Helpers

    private func readJSON<T: Decodable>(from url: URL, decoder: JSONDecoder) throws -> T? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    private func parseMarkdownWithFrontmatter(_ markdown: String) throws -> (NoteFrontmatter?, String) {
        let lines = markdown.components(separatedBy: "\n")

        guard lines.first == "---" else {
            return (nil, markdown)
        }

        // Find closing ---
        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i] == "---" {
                endIndex = i
                break
            }
        }

        guard let end = endIndex else {
            return (nil, markdown)
        }

        let yamlContent = lines[1..<end].joined(separator: "\n")
        let content = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let decoder = YAMLDecoder()
        let frontmatter = try? decoder.decode(NoteFrontmatter.self, from: yamlContent)

        return (frontmatter, content)
    }

    private func createBackup() async throws {
        let backupDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Noot Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        _ = try await ExportService.shared.exportFull(to: backupDir) { _ in }
    }

    private func importImagesFromMarkdown(content: String, noteId: UUID, baseURL: URL) throws -> Int {
        var count = 0

        // Find markdown image references: ![alt](path)
        let pattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(content.startIndex..<content.endIndex, in: content)

        for match in regex.matches(in: content, range: range) {
            guard let pathRange = Range(match.range(at: 2), in: content) else { continue }
            let imagePath = String(content[pathRange])

            // Skip URLs
            if imagePath.hasPrefix("http://") || imagePath.hasPrefix("https://") {
                continue
            }

            // Resolve path
            let imageURL = baseURL.appendingPathComponent(imagePath)
            guard fileManager.fileExists(atPath: imageURL.path) else { continue }

            // Copy to attachments
            let attachmentId = UUID()
            let ext = imageURL.pathExtension
            let destFilename = "\(attachmentId.uuidString).\(ext)"
            let destPath = attachmentsURL.appendingPathComponent("screenshots/\(destFilename)")

            do {
                try fileManager.copyItem(at: imageURL, to: destPath)

                let fileSize = try fileManager.attributesOfItem(atPath: destPath.path)[.size] as? Int ?? 0
                let attachment = Attachment(
                    id: attachmentId,
                    noteId: noteId,
                    type: .screenshot,
                    filePath: "screenshots/\(destFilename)",
                    fileSize: fileSize
                )

                try Database.shared.write { db in
                    try attachment.insert(db)
                }
                count += 1
            } catch {
                // Skip failed imports
            }
        }

        return count
    }
}
