import Foundation
import GRDB

struct Note: Codable, Identifiable, Hashable {
    var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var closedAt: Date?
    var archived: Bool

    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        closedAt: Date? = nil,
        archived: Bool = false
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.archived = archived
    }

    var isOpen: Bool {
        closedAt == nil
    }
}

extension Note: FetchableRecord, PersistableRecord {
    static let databaseTableName = "notes"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let content = Column(CodingKeys.content)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
        static let closedAt = Column(CodingKeys.closedAt)
        static let archived = Column(CodingKeys.archived)
    }

    // Associations
    static let contexts = hasMany(NoteContext.self)
    static let attachments = hasMany(Attachment.self)
    static let screenContexts = hasMany(ScreenContext.self)
    static let meetings = hasMany(NoteMeeting.self)

    // Links where this note is the source
    static let outgoingLinks = hasMany(NoteLink.self, using: NoteLink.sourceForeignKey)
    // Links where this note is the target
    static let incomingLinks = hasMany(NoteLink.self, using: NoteLink.targetForeignKey)
}

// MARK: - Lightweight List Item (for memory-efficient list views)

/// A lightweight version of Note for list views - only loads preview text, not full content
struct NoteListItem: Codable, Identifiable, Hashable, FetchableRecord {
    var id: UUID
    var contentPreview: String  // First 150 chars only
    var createdAt: Date
    var updatedAt: Date
    var closedAt: Date?
    var archived: Bool
    var hasImages: Bool

    var isOpen: Bool {
        closedAt == nil
    }

    /// Fetch lightweight list items with pagination
    static func fetch(
        db: GRDB.Database,
        filter: NoteListFilter,
        limit: Int = 50,
        offset: Int = 0
    ) throws -> [NoteListItem] {
        let baseQuery: String
        var arguments: StatementArguments = []

        switch filter {
        case .all:
            baseQuery = """
                SELECT id, SUBSTR(content, 1, 150) as contentPreview, createdAt, updatedAt, closedAt, archived,
                       (content LIKE '%![%' ) as hasImages
                FROM notes
                WHERE archived = 0
                ORDER BY updatedAt DESC
                LIMIT ? OFFSET ?
                """
            arguments = [limit, offset]

        case .inbox:
            baseQuery = """
                SELECT id, SUBSTR(content, 1, 150) as contentPreview, createdAt, updatedAt, closedAt, archived,
                       (content LIKE '%![%') as hasImages
                FROM notes
                WHERE archived = 0 AND id NOT IN (SELECT noteId FROM note_contexts)
                ORDER BY createdAt DESC
                LIMIT ? OFFSET ?
                """
            arguments = [limit, offset]

        case .archived:
            baseQuery = """
                SELECT id, SUBSTR(content, 1, 150) as contentPreview, createdAt, updatedAt, closedAt, archived,
                       (content LIKE '%![%') as hasImages
                FROM notes
                WHERE archived = 1
                ORDER BY updatedAt DESC
                LIMIT ? OFFSET ?
                """
            arguments = [limit, offset]

        case .context(let contextId):
            baseQuery = """
                SELECT n.id, SUBSTR(n.content, 1, 150) as contentPreview, n.createdAt, n.updatedAt, n.closedAt, n.archived,
                       (n.content LIKE '%![%') as hasImages
                FROM notes n
                INNER JOIN note_contexts nc ON nc.noteId = n.id
                WHERE nc.contextId = ? AND n.archived = 0
                ORDER BY n.updatedAt DESC
                LIMIT ? OFFSET ?
                """
            arguments = [contextId.uuidString, limit, offset]
        }

        return try NoteListItem.fetchAll(db, sql: baseQuery, arguments: arguments)
    }
}

enum NoteListFilter {
    case all
    case inbox
    case archived
    case context(UUID)
}

// MARK: - Queries
extension Note {
    static func ungrouped() -> QueryInterfaceRequest<Note> {
        Note
            .filter(Columns.archived == false)
            .filter(sql: """
                id NOT IN (SELECT noteId FROM note_contexts)
            """)
            .order(Columns.createdAt.desc)
    }

    static func open() -> QueryInterfaceRequest<Note> {
        Note
            .filter(Columns.closedAt == nil)
            .filter(Columns.archived == false)
            .order(Columns.updatedAt.desc)
    }

    static func recentFromSession(hours: Int = 8) -> QueryInterfaceRequest<Note> {
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
        return Note
            .filter(Columns.createdAt >= cutoff)
            .filter(Columns.archived == false)
            .order(Columns.updatedAt.desc)
    }

    static func today() -> QueryInterfaceRequest<Note> {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return Note
            .filter(Columns.createdAt >= startOfDay)
            .filter(Columns.archived == false)
            .order(Columns.updatedAt.desc)
    }
}
