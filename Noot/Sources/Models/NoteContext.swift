import Foundation
import GRDB

struct NoteContext: Codable {
    var noteId: UUID
    var contextId: UUID
    var assignedAt: Date

    init(
        noteId: UUID,
        contextId: UUID,
        assignedAt: Date = Date()
    ) {
        self.noteId = noteId
        self.contextId = contextId
        self.assignedAt = assignedAt
    }
}

extension NoteContext: FetchableRecord, PersistableRecord {
    static let databaseTableName = "note_contexts"

    enum Columns {
        static let noteId = Column(CodingKeys.noteId)
        static let contextId = Column(CodingKeys.contextId)
        static let assignedAt = Column(CodingKeys.assignedAt)
    }

    static let note = belongsTo(Note.self)
    static let context = belongsTo(Context.self)
}
