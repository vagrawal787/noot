import Foundation
import GRDB

// MARK: - Calendar Account

struct CalendarAccount: Codable, Identifiable, Hashable {
    var id: UUID
    var email: String
    var connectedAt: Date
    var lastSyncAt: Date?

    init(
        id: UUID = UUID(),
        email: String,
        connectedAt: Date = Date(),
        lastSyncAt: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.connectedAt = connectedAt
        self.lastSyncAt = lastSyncAt
    }
}

extension CalendarAccount: FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendar_accounts"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let email = Column(CodingKeys.email)
        static let connectedAt = Column(CodingKeys.connectedAt)
        static let lastSyncAt = Column(CodingKeys.lastSyncAt)
    }

    static let calendarEvents = hasMany(CalendarEvent.self)
}

// MARK: - Calendar Event

struct CalendarEvent: Codable, Identifiable, Hashable {
    var id: UUID
    var googleEventId: String
    var googleSeriesId: String?
    var calendarAccountId: UUID
    var title: String
    var startTime: Date
    var endTime: Date
    var attendees: String?  // JSON array of attendee emails
    var location: String?
    var meetingLink: String?
    var cachedAt: Date

    init(
        id: UUID = UUID(),
        googleEventId: String,
        googleSeriesId: String? = nil,
        calendarAccountId: UUID,
        title: String,
        startTime: Date,
        endTime: Date,
        attendees: String? = nil,
        location: String? = nil,
        meetingLink: String? = nil,
        cachedAt: Date = Date()
    ) {
        self.id = id
        self.googleEventId = googleEventId
        self.googleSeriesId = googleSeriesId
        self.calendarAccountId = calendarAccountId
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.attendees = attendees
        self.location = location
        self.meetingLink = meetingLink
        self.cachedAt = cachedAt
    }

    var isActive: Bool {
        let now = Date()
        return startTime <= now && endTime > now
    }

    var attendeeList: [String] {
        guard let attendees = attendees,
              let data = attendees.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return list
    }
}

extension CalendarEvent: FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendar_events"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let googleEventId = Column(CodingKeys.googleEventId)
        static let googleSeriesId = Column(CodingKeys.googleSeriesId)
        static let calendarAccountId = Column(CodingKeys.calendarAccountId)
        static let title = Column(CodingKeys.title)
        static let startTime = Column(CodingKeys.startTime)
        static let endTime = Column(CodingKeys.endTime)
        static let attendees = Column(CodingKeys.attendees)
        static let location = Column(CodingKeys.location)
        static let meetingLink = Column(CodingKeys.meetingLink)
        static let cachedAt = Column(CodingKeys.cachedAt)
    }

    static let calendarAccount = belongsTo(CalendarAccount.self)
}

// MARK: - Calendar Event Queries

extension CalendarEvent {
    static func current() -> QueryInterfaceRequest<CalendarEvent> {
        let now = Date()
        return CalendarEvent
            .filter(Columns.startTime <= now)
            .filter(Columns.endTime > now)
            .order(Columns.startTime)
    }

    static func upcoming(limit: Int = 10) -> QueryInterfaceRequest<CalendarEvent> {
        let now = Date()
        return CalendarEvent
            .filter(Columns.startTime > now)
            .order(Columns.startTime)
            .limit(limit)
    }

    static func inRange(from: Date, to: Date) -> QueryInterfaceRequest<CalendarEvent> {
        return CalendarEvent
            .filter(Columns.endTime > from)
            .filter(Columns.startTime < to)
            .order(Columns.startTime)
    }

    static func forDay(_ date: Date) -> QueryInterfaceRequest<CalendarEvent> {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return inRange(from: startOfDay, to: endOfDay)
    }

    static func bySeries(_ seriesId: String) -> QueryInterfaceRequest<CalendarEvent> {
        return CalendarEvent
            .filter(Columns.googleSeriesId == seriesId)
            .order(Columns.startTime)
    }
}

// MARK: - Calendar Series Context Rule

struct CalendarSeriesContextRule: Codable, Identifiable, Hashable {
    var id: UUID
    var googleSeriesId: String
    var contextId: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        googleSeriesId: String,
        contextId: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.googleSeriesId = googleSeriesId
        self.contextId = contextId
        self.createdAt = createdAt
    }
}

extension CalendarSeriesContextRule: FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendar_series_context_rules"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let googleSeriesId = Column(CodingKeys.googleSeriesId)
        static let contextId = Column(CodingKeys.contextId)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    static let context = belongsTo(Context.self)
}

// MARK: - Calendar Series Context Rule Queries

extension CalendarSeriesContextRule {
    static func forSeries(_ seriesId: String) -> QueryInterfaceRequest<CalendarSeriesContextRule> {
        return CalendarSeriesContextRule
            .filter(Columns.googleSeriesId == seriesId)
    }
}

// MARK: - Ignored Calendar Event

struct IgnoredCalendarEvent: Codable, Identifiable, Hashable {
    var id: UUID
    var googleEventId: String?
    var googleSeriesId: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        googleEventId: String? = nil,
        googleSeriesId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.googleEventId = googleEventId
        self.googleSeriesId = googleSeriesId
        self.createdAt = createdAt
    }
}

extension IgnoredCalendarEvent: FetchableRecord, PersistableRecord {
    static let databaseTableName = "ignored_calendar_events"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let googleEventId = Column(CodingKeys.googleEventId)
        static let googleSeriesId = Column(CodingKeys.googleSeriesId)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}

// MARK: - Ignored Calendar Event Queries

extension IgnoredCalendarEvent {
    static func isIgnored(eventId: String?, seriesId: String?) -> QueryInterfaceRequest<IgnoredCalendarEvent> {
        var request = IgnoredCalendarEvent.all()
        if let eventId = eventId {
            request = request.filter(Columns.googleEventId == eventId)
        }
        if let seriesId = seriesId {
            request = IgnoredCalendarEvent.filter(Columns.googleSeriesId == seriesId)
        }
        return request
    }
}
