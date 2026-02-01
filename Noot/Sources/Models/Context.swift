import Foundation
import GRDB

enum ContextType: String, Codable, Hashable {
    case domain
    case workstream
}

struct Context: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var type: ContextType
    var pinned: Bool
    var archived: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: ContextType,
        pinned: Bool = false,
        archived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.pinned = pinned
        self.archived = archived
        self.createdAt = createdAt
    }
}

extension Context: FetchableRecord, PersistableRecord {
    static let databaseTableName = "contexts"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let type = Column(CodingKeys.type)
        static let pinned = Column(CodingKeys.pinned)
        static let archived = Column(CodingKeys.archived)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    // Associations
    static let noteContexts = hasMany(NoteContext.self)
    static let notes = hasMany(Note.self, through: noteContexts, using: NoteContext.note)

    // Parent/child relationships
    static let parentLinks = hasMany(ContextLink.self, using: ContextLink.childForeignKey)
    static let childLinks = hasMany(ContextLink.self, using: ContextLink.parentForeignKey)
}

// MARK: - Queries
extension Context {
    static func active() -> QueryInterfaceRequest<Context> {
        Context
            .filter(Columns.archived == false)
            .order(Columns.pinned.desc, Columns.name)
    }

    static func pinned() -> QueryInterfaceRequest<Context> {
        Context
            .filter(Columns.pinned == true)
            .filter(Columns.archived == false)
            .order(Columns.name)
    }

    static func domains() -> QueryInterfaceRequest<Context> {
        Context
            .filter(Columns.type == ContextType.domain.rawValue)
            .filter(Columns.archived == false)
            .order(Columns.pinned.desc, Columns.name)
    }

    static func workstreams() -> QueryInterfaceRequest<Context> {
        Context
            .filter(Columns.type == ContextType.workstream.rawValue)
            .filter(Columns.archived == false)
            .order(Columns.pinned.desc, Columns.name)
    }
}

// MARK: - Context Links (Parent-Child Relationships)
struct ContextLink: Codable, Identifiable, Hashable {
    var id: UUID
    var parentContextId: UUID
    var childContextId: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        parentContextId: UUID,
        childContextId: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.parentContextId = parentContextId
        self.childContextId = childContextId
        self.createdAt = createdAt
    }
}

extension ContextLink: FetchableRecord, PersistableRecord {
    static let databaseTableName = "context_links"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let parentContextId = Column(CodingKeys.parentContextId)
        static let childContextId = Column(CodingKeys.childContextId)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    static let parentForeignKey = ForeignKey(["parentContextId"])
    static let childForeignKey = ForeignKey(["childContextId"])

    static let parentContext = belongsTo(Context.self, using: parentForeignKey)
    static let childContext = belongsTo(Context.self, using: childForeignKey)
}
