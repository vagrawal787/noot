import Foundation
import GRDB

struct Meeting: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String?
    var startedAt: Date
    var endedAt: Date?
    var audioPath: String?
    var calendarEventId: String?

    init(
        id: UUID = UUID(),
        title: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        audioPath: String? = nil,
        calendarEventId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.audioPath = audioPath
        self.calendarEventId = calendarEventId
    }

    var isOngoing: Bool {
        endedAt == nil
    }

    var duration: TimeInterval? {
        guard let endedAt = endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}

extension Meeting: FetchableRecord, PersistableRecord {
    static let databaseTableName = "meetings"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let startedAt = Column(CodingKeys.startedAt)
        static let endedAt = Column(CodingKeys.endedAt)
        static let audioPath = Column(CodingKeys.audioPath)
        static let calendarEventId = Column(CodingKeys.calendarEventId)
    }

    static let noteMeetings = hasMany(NoteMeeting.self)
    static let notes = hasMany(Note.self, through: noteMeetings, using: NoteMeeting.note)
    static let meetingContexts = hasMany(MeetingContext.self)
    static let contexts = hasMany(Context.self, through: meetingContexts, using: MeetingContext.context)
}

// MARK: - Queries
extension Meeting {
    static func ongoing() -> QueryInterfaceRequest<Meeting> {
        Meeting
            .filter(Columns.endedAt == nil)
            .order(Columns.startedAt.desc)
    }

    static func recent(limit: Int = 10) -> QueryInterfaceRequest<Meeting> {
        Meeting
            .order(Columns.startedAt.desc)
            .limit(limit)
    }
}

// MARK: - Note-Meeting Join Table
struct NoteMeeting: Codable {
    var noteId: UUID
    var meetingId: UUID

    init(noteId: UUID, meetingId: UUID) {
        self.noteId = noteId
        self.meetingId = meetingId
    }
}

extension NoteMeeting: FetchableRecord, PersistableRecord {
    static let databaseTableName = "note_meetings"

    enum Columns {
        static let noteId = Column(CodingKeys.noteId)
        static let meetingId = Column(CodingKeys.meetingId)
    }

    static let note = belongsTo(Note.self)
    static let meeting = belongsTo(Meeting.self)
}

// MARK: - Meeting-Context Join Table

struct MeetingContext: Codable {
    var meetingId: UUID
    var contextId: UUID
    var assignedAt: Date

    init(meetingId: UUID, contextId: UUID, assignedAt: Date = Date()) {
        self.meetingId = meetingId
        self.contextId = contextId
        self.assignedAt = assignedAt
    }
}

extension MeetingContext: FetchableRecord, PersistableRecord {
    static let databaseTableName = "meeting_contexts"

    enum Columns {
        static let meetingId = Column(CodingKeys.meetingId)
        static let contextId = Column(CodingKeys.contextId)
        static let assignedAt = Column(CodingKeys.assignedAt)
    }

    static let meeting = belongsTo(Meeting.self)
    static let context = belongsTo(Context.self)
}
