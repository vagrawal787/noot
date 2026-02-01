import Foundation
import GRDB

final class Database {
    static let shared = Database()

    private var dbPool: DatabasePool?

    private init() {}

    var reader: DatabaseReader {
        guard let dbPool = dbPool else {
            fatalError("Database not initialized. Call initialize() first.")
        }
        return dbPool
    }

    var writer: DatabaseWriter {
        guard let dbPool = dbPool else {
            fatalError("Database not initialized. Call initialize() first.")
        }
        return dbPool
    }

    func initialize() throws {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Noot", isDirectory: true)

        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        // Create attachments directories
        let attachmentsURL = appSupportURL.appendingPathComponent("attachments", isDirectory: true)
        try fileManager.createDirectory(at: attachmentsURL.appendingPathComponent("screenshots"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: attachmentsURL.appendingPathComponent("recordings"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: attachmentsURL.appendingPathComponent("audio"), withIntermediateDirectories: true)

        let dbURL = appSupportURL.appendingPathComponent("noot.db")

        var config = Configuration()
        config.foreignKeysEnabled = true

        dbPool = try DatabasePool(path: dbURL.path, configuration: config)

        try migrator.migrate(dbPool!)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_initial") { db in
            // Notes table
            try db.create(table: "notes") { t in
                t.column("id", .text).primaryKey()
                t.column("content", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("closedAt", .datetime)
                t.column("archived", .boolean).notNull().defaults(to: false)
            }

            // Contexts table
            try db.create(table: "contexts") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }

            // Context links (parent-child relationships)
            try db.create(table: "context_links") { t in
                t.column("id", .text).primaryKey()
                t.column("parentContextId", .text).notNull().references("contexts", onDelete: .cascade)
                t.column("childContextId", .text).notNull().references("contexts", onDelete: .cascade)
                t.column("createdAt", .datetime).notNull()

                t.uniqueKey(["parentContextId", "childContextId"])
            }

            // Note-Context join table
            try db.create(table: "note_contexts") { t in
                t.column("noteId", .text).notNull().references("notes", onDelete: .cascade)
                t.column("contextId", .text).notNull().references("contexts", onDelete: .cascade)
                t.column("assignedAt", .datetime).notNull()

                t.primaryKey(["noteId", "contextId"])
            }

            // Note links
            try db.create(table: "note_links") { t in
                t.column("id", .text).primaryKey()
                t.column("sourceNoteId", .text).notNull().references("notes", onDelete: .cascade)
                t.column("targetNoteId", .text).notNull().references("notes", onDelete: .cascade)
                t.column("relationship", .text).notNull()
                t.column("createdAt", .datetime).notNull()

                t.uniqueKey(["sourceNoteId", "targetNoteId"])
            }

            // Meetings table
            try db.create(table: "meetings") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text)
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("audioPath", .text)
                t.column("calendarEventId", .text)
            }

            // Note-Meeting join table
            try db.create(table: "note_meetings") { t in
                t.column("noteId", .text).notNull().references("notes", onDelete: .cascade)
                t.column("meetingId", .text).notNull().references("meetings", onDelete: .cascade)

                t.primaryKey(["noteId", "meetingId"])
            }

            // Screen contexts table
            try db.create(table: "screen_contexts") { t in
                t.column("id", .text).primaryKey()
                t.column("noteId", .text).notNull().references("notes", onDelete: .cascade)
                t.column("sourceType", .text).notNull()
                t.column("appName", .text)
                t.column("url", .text)
                t.column("filePath", .text)
                t.column("lineStart", .integer)
                t.column("lineEnd", .integer)
                t.column("gitRepo", .text)
                t.column("gitBranch", .text)
                t.column("capturedAt", .datetime).notNull()
            }

            // Attachments table
            try db.create(table: "attachments") { t in
                t.column("id", .text).primaryKey()
                t.column("noteId", .text).notNull().references("notes", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("filePath", .text).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("originalSize", .integer)
                t.column("durationSeconds", .double)
                t.column("createdAt", .datetime).notNull()
            }

            // Meeting-Context join table
            try db.create(table: "meeting_contexts") { t in
                t.column("meetingId", .text).notNull().references("meetings", onDelete: .cascade)
                t.column("contextId", .text).notNull().references("contexts", onDelete: .cascade)
                t.column("assignedAt", .datetime).notNull()

                t.primaryKey(["meetingId", "contextId"])
            }

            // Indexes for common queries
            try db.create(index: "notes_createdAt", on: "notes", columns: ["createdAt"])
            try db.create(index: "notes_archived", on: "notes", columns: ["archived"])
            try db.create(index: "contexts_type", on: "contexts", columns: ["type"])
            try db.create(index: "contexts_archived", on: "contexts", columns: ["archived"])
            try db.create(index: "screen_contexts_noteId", on: "screen_contexts", columns: ["noteId"])
            try db.create(index: "attachments_noteId", on: "attachments", columns: ["noteId"])
            try db.create(index: "meeting_contexts_meetingId", on: "meeting_contexts", columns: ["meetingId"])
        }

        return migrator
    }
}

// MARK: - Convenience Methods
extension Database {
    func read<T>(_ block: (GRDB.Database) throws -> T) throws -> T {
        try reader.read(block)
    }

    func write<T>(_ block: (GRDB.Database) throws -> T) throws -> T {
        try writer.write(block)
    }
}
