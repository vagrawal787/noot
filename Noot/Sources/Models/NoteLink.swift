import Foundation
import GRDB

enum NoteLinkRelationship: String, Codable, Hashable {
    case continues
    case informedBy = "informed_by"
    case related
}

struct NoteLink: Codable, Identifiable, Hashable {
    var id: UUID
    var sourceNoteId: UUID
    var targetNoteId: UUID
    var relationship: NoteLinkRelationship
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sourceNoteId: UUID,
        targetNoteId: UUID,
        relationship: NoteLinkRelationship = .related,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceNoteId = sourceNoteId
        self.targetNoteId = targetNoteId
        self.relationship = relationship
        self.createdAt = createdAt
    }
}

extension NoteLink: FetchableRecord, PersistableRecord {
    static let databaseTableName = "note_links"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let sourceNoteId = Column(CodingKeys.sourceNoteId)
        static let targetNoteId = Column(CodingKeys.targetNoteId)
        static let relationship = Column(CodingKeys.relationship)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    static let sourceForeignKey = ForeignKey(["sourceNoteId"])
    static let targetForeignKey = ForeignKey(["targetNoteId"])

    static let sourceNote = belongsTo(Note.self, using: sourceForeignKey)
    static let targetNote = belongsTo(Note.self, using: targetForeignKey)
}
