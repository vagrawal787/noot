import Foundation
import GRDB

// MARK: - Notion Sync Configuration

struct NotionSync: Codable, Identifiable, Hashable {
    var id: UUID
    var workspaceId: String
    var workspaceName: String?
    var databaseId: String
    var databaseName: String?
    var accessToken: String
    var connectedAt: Date
    var lastSyncAt: Date?
    var syncArchivedNotes: Bool

    init(
        id: UUID = UUID(),
        workspaceId: String,
        workspaceName: String? = nil,
        databaseId: String,
        databaseName: String? = nil,
        accessToken: String,
        connectedAt: Date = Date(),
        lastSyncAt: Date? = nil,
        syncArchivedNotes: Bool = false
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        self.databaseId = databaseId
        self.databaseName = databaseName
        self.accessToken = accessToken
        self.connectedAt = connectedAt
        self.lastSyncAt = lastSyncAt
        self.syncArchivedNotes = syncArchivedNotes
    }
}

extension NotionSync: FetchableRecord, PersistableRecord {
    static let databaseTableName = "notion_syncs"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let workspaceId = Column(CodingKeys.workspaceId)
        static let workspaceName = Column(CodingKeys.workspaceName)
        static let databaseId = Column(CodingKeys.databaseId)
        static let databaseName = Column(CodingKeys.databaseName)
        static let accessToken = Column(CodingKeys.accessToken)
        static let connectedAt = Column(CodingKeys.connectedAt)
        static let lastSyncAt = Column(CodingKeys.lastSyncAt)
        static let syncArchivedNotes = Column(CodingKeys.syncArchivedNotes)
    }
}

// MARK: - Note Sync State

/// Tracks sync state for individual notes
struct NoteSyncState: Codable, Identifiable, Hashable {
    var id: UUID
    var noteId: UUID
    var notionPageId: String
    var notionSyncId: UUID
    var lastSyncedAt: Date
    var syncHash: String  // Hash of content at last sync

    init(
        id: UUID = UUID(),
        noteId: UUID,
        notionPageId: String,
        notionSyncId: UUID,
        lastSyncedAt: Date = Date(),
        syncHash: String
    ) {
        self.id = id
        self.noteId = noteId
        self.notionPageId = notionPageId
        self.notionSyncId = notionSyncId
        self.lastSyncedAt = lastSyncedAt
        self.syncHash = syncHash
    }

    /// Compute hash for note content
    static func computeHash(for note: Note, meetingId: UUID? = nil) -> String {
        let meetingPart = meetingId?.uuidString ?? "none"
        let content = "\(note.content)|\(note.updatedAt.timeIntervalSince1970)|\(note.archived)|\(meetingPart)"
        return content.data(using: .utf8)?.base64EncodedString() ?? ""
    }
}

extension NoteSyncState: FetchableRecord, PersistableRecord {
    static let databaseTableName = "note_sync_states"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let noteId = Column(CodingKeys.noteId)
        static let notionPageId = Column(CodingKeys.notionPageId)
        static let notionSyncId = Column(CodingKeys.notionSyncId)
        static let lastSyncedAt = Column(CodingKeys.lastSyncedAt)
        static let syncHash = Column(CodingKeys.syncHash)
    }

    static let note = belongsTo(Note.self)
    static let notionSync = belongsTo(NotionSync.self)
}

// MARK: - Queries

extension NoteSyncState {
    static func forNote(_ noteId: UUID) -> QueryInterfaceRequest<NoteSyncState> {
        NoteSyncState.filter(Columns.noteId == noteId)
    }

    static func forSync(_ syncId: UUID) -> QueryInterfaceRequest<NoteSyncState> {
        NoteSyncState.filter(Columns.notionSyncId == syncId)
    }

    static func forNotionPage(_ pageId: String) -> QueryInterfaceRequest<NoteSyncState> {
        NoteSyncState.filter(Columns.notionPageId == pageId)
    }
}

// MARK: - Notion API Response Types

struct NotionOAuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let botId: String
    let workspaceId: String
    let workspaceName: String?
    let workspaceIcon: String?
    let duplicatedTemplateId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case botId = "bot_id"
        case workspaceId = "workspace_id"
        case workspaceName = "workspace_name"
        case workspaceIcon = "workspace_icon"
        case duplicatedTemplateId = "duplicated_template_id"
    }
}

struct NotionDatabase: Codable {
    let id: String
    let title: [NotionRichText]?
    let properties: [String: NotionPropertySchema]?

    var displayTitle: String {
        title?.first?.plainText ?? "Untitled"
    }
}

struct NotionPage: Codable {
    let id: String
    let url: String?
    let properties: [String: NotionPropertyValue]?
}

struct NotionRichText: Codable {
    let type: String?
    let text: NotionTextContent?
    let plainText: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case plainText = "plain_text"
    }
}

struct NotionTextContent: Codable {
    let content: String
    let link: NotionLink?
}

struct NotionLink: Codable {
    let url: String?
}

struct NotionPropertySchema: Codable {
    let id: String?
    let type: String?
    let name: String?
}

struct NotionPropertyValue: Codable {
    let id: String?
    let type: String?
    let title: [NotionRichText]?
    let richText: [NotionRichText]?
    let date: NotionDateValue?
    let checkbox: Bool?
    let select: NotionSelectValue?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case richText = "rich_text"
        case date
        case checkbox
        case select
    }
}

struct NotionDateValue: Codable {
    let start: String?
    let end: String?
}

struct NotionSelectValue: Codable {
    let id: String?
    let name: String?
    let color: String?
}

struct NotionError: Codable, Error {
    let status: Int?
    let code: String?
    let message: String?
}

// MARK: - Sync Progress

struct NotionSyncProgress {
    var phase: String
    var current: Int
    var total: Int
    var currentNote: String?

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

struct NotionSyncReport {
    var notesCreated: Int
    var notesUpdated: Int
    var notesFailed: Int
    var errors: [String]
}
