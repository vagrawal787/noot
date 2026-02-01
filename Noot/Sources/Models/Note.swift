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
