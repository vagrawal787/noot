import Foundation
import Combine
import GRDB

final class CalendarSyncService: ObservableObject {
    static let shared = CalendarSyncService()

    /// Events that are currently active or starting within 5 minutes
    @Published private(set) var activeEvents: [CalendarEvent] = []
    @Published private(set) var upcomingEvents: [CalendarEvent] = []
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastError: Error?

    /// Minutes before an event starts to show it as "active"
    let preEventMinutes: Int = 5

    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Check initial connection status synchronously
        isConnected = getConnectedAccount() != nil
    }

    // MARK: - Lifecycle

    func start() {
        // Re-check connection status
        isConnected = getConnectedAccount() != nil

        guard isConnected else {
            print("[CalendarSync] Not connected, skipping start")
            return
        }

        print("[CalendarSync] Starting sync service...")

        // Stop any existing timers
        stop()

        // Initial sync and check
        Task {
            await syncEvents()
        }

        // Poll timer: sync from Google Calendar AND check for active events
        let pollInterval = TimeInterval(UserPreferences.shared.calendarPollIntervalSeconds)
        DispatchQueue.main.async { [weak self] in
            self?.pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
                print("[CalendarSync] Poll timer fired, syncing and checking events")
                Task {
                    await self?.syncEvents()
                }
            }
            // Add to common run loop mode so it fires even during UI interactions
            if let timer = self?.pollTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Connection Management

    func connectAccount() async throws {
        let result = try await GoogleOAuthService.shared.startOAuthFlow()

        // Create calendar account record
        let account = CalendarAccount(email: result.email)

        try Database.shared.write { db in
            var record = account
            try record.insert(db)
        }

        await MainActor.run {
            isConnected = true
        }

        // Start syncing
        start()

        // Post notification for UI updates
        NotificationCenter.default.post(name: .calendarAccountConnected, object: nil)
    }

    func disconnectAccount() throws {
        guard let account = getConnectedAccount() else { return }

        // Delete tokens from Keychain
        try KeychainService.shared.deleteAllTokens(for: account.email)

        // Delete account and all related data from database
        try Database.shared.write { db in
            try CalendarEvent.filter(CalendarEvent.Columns.calendarAccountId == account.id).deleteAll(db)
            try CalendarAccount.filter(CalendarAccount.Columns.id == account.id).deleteAll(db)
        }

        stop()

        DispatchQueue.main.async {
            self.isConnected = false
            self.activeEvents = []
            self.upcomingEvents = []
        }

        NotificationCenter.default.post(name: .calendarAccountDisconnected, object: nil)
    }

    func getConnectedAccount() -> CalendarAccount? {
        do {
            return try Database.shared.read { db in
                try CalendarAccount.fetchOne(db)
            }
        } catch {
            print("Failed to fetch calendar account: \(error)")
            return nil
        }
    }

    private func checkConnectionStatus() async {
        let connected = getConnectedAccount() != nil
        await MainActor.run {
            isConnected = connected
        }
    }

    // MARK: - Event Sync

    func syncEvents() async {
        guard let account = getConnectedAccount() else { return }

        await MainActor.run {
            isSyncing = true
            lastError = nil
        }

        defer {
            DispatchQueue.main.async {
                self.isSyncing = false
            }
        }

        do {
            let accessToken = try await GoogleOAuthService.shared.getValidAccessToken(for: account.email)

            let now = Date()
            let daysAhead = UserPreferences.shared.calendarSyncDaysAhead
            let endDate = Calendar.current.date(byAdding: .day, value: daysAhead, to: now)!

            let events = try await GoogleCalendarAPI.shared.fetchEvents(
                accessToken: accessToken,
                from: now,
                to: endDate
            )

            // Cache events to database
            try cacheEvents(events, for: account)

            // Update last sync time
            try Database.shared.write { db in
                var updatedAccount = account
                updatedAccount.lastSyncAt = Date()
                try updatedAccount.update(db)
            }

            // Update current and upcoming events
            checkCurrentEvent()
            await updateUpcomingEvents()

        } catch CalendarAPIError.unauthorized {
            // Token expired, try to refresh
            do {
                _ = try await GoogleOAuthService.shared.refreshAccessToken(for: account.email)
                await syncEvents()  // Retry
            } catch {
                await MainActor.run {
                    lastError = error
                }
            }
        } catch {
            await MainActor.run {
                lastError = error
            }
            print("Calendar sync failed: \(error)")
        }
    }

    private func cacheEvents(_ events: [GoogleCalendarEventResponse], for account: CalendarAccount) throws {
        let now = Date()

        try Database.shared.write { db in
            // Only delete future events (preserve historical events)
            // This way past events remain in the database for history
            try CalendarEvent
                .filter(CalendarEvent.Columns.calendarAccountId == account.id)
                .filter(CalendarEvent.Columns.startTime >= now)
                .deleteAll(db)

            // Insert/update events from API
            for event in events {
                guard let startDate = event.startDate,
                      let endDate = event.endDate,
                      event.status != "cancelled" else {
                    continue
                }

                // Encode attendees as JSON
                var attendeesJson: String? = nil
                if let attendees = event.attendees {
                    let emails = attendees.map { $0.email }
                    if let data = try? JSONEncoder().encode(emails) {
                        attendeesJson = String(data: data, encoding: .utf8)
                    }
                }

                // Check if event already exists (might be an update to an existing event)
                let existingEvent = try CalendarEvent
                    .filter(CalendarEvent.Columns.googleEventId == event.id)
                    .fetchOne(db)

                if var existing = existingEvent {
                    // Update existing event
                    existing.title = event.title
                    existing.startTime = startDate
                    existing.endTime = endDate
                    existing.attendees = attendeesJson
                    existing.location = event.location
                    existing.meetingLink = event.meetingLink
                    existing.cachedAt = Date()
                    try existing.update(db)
                } else {
                    // Insert new event
                    var calendarEvent = CalendarEvent(
                        googleEventId: event.id,
                        googleSeriesId: event.recurringEventId,
                        calendarAccountId: account.id,
                        title: event.title,
                        startTime: startDate,
                        endTime: endDate,
                        attendees: attendeesJson,
                        location: event.location,
                        meetingLink: event.meetingLink
                    )
                    try calendarEvent.insert(db)
                }
            }
        }
    }

    // MARK: - Current Event Detection

    func checkCurrentEvent() {
        do {
            let now = Date()
            let preEventThreshold = Calendar.current.date(byAdding: .minute, value: preEventMinutes, to: now)!

            let events = try Database.shared.read { db -> [CalendarEvent] in
                // Get events that are:
                // 1. Currently happening (started and not ended), OR
                // 2. Starting within the next 5 minutes
                let allCandidates = try CalendarEvent
                    .filter(
                        // Currently active: started before now and ends after now
                        (CalendarEvent.Columns.startTime <= now && CalendarEvent.Columns.endTime > now) ||
                        // Starting soon: starts between now and 5 minutes from now
                        (CalendarEvent.Columns.startTime > now && CalendarEvent.Columns.startTime <= preEventThreshold)
                    )
                    .order(CalendarEvent.Columns.startTime)
                    .fetchAll(db)

                // Filter out ignored events
                var filteredEvents: [CalendarEvent] = []
                for event in allCandidates {
                    // Check if event is ignored
                    let isIgnored = try IgnoredCalendarEvent
                        .filter(IgnoredCalendarEvent.Columns.googleEventId == event.googleEventId)
                        .fetchCount(db) > 0

                    if isIgnored {
                        print("[CalendarSync] Event '\(event.title)' is ignored")
                        continue
                    }

                    // Check if series is ignored
                    if let seriesId = event.googleSeriesId {
                        let seriesIgnored = try IgnoredCalendarEvent
                            .filter(IgnoredCalendarEvent.Columns.googleSeriesId == seriesId)
                            .fetchCount(db) > 0
                        if seriesIgnored {
                            print("[CalendarSync] Series '\(seriesId)' is ignored")
                            continue
                        }
                    }

                    filteredEvents.append(event)
                }

                return filteredEvents
            }

            if events.isEmpty {
                // Debug: check what events exist
                let allEvents = try Database.shared.read { db in
                    try CalendarEvent.fetchAll(db)
                }
                print("[CalendarSync] No active events found. Total events in DB: \(allEvents.count)")
                print("[CalendarSync] Current time: \(now)")
                print("[CalendarSync] Pre-event threshold (now + 5min): \(preEventThreshold)")
                for event in allEvents {
                    let isActive = event.startTime <= now && event.endTime > now
                    let isUpcoming = event.startTime > now && event.startTime <= preEventThreshold
                    print("[CalendarSync] Event '\(event.title)': start=\(event.startTime), end=\(event.endTime), isActive=\(isActive), isUpcoming=\(isUpcoming)")
                }
            } else {
                print("[CalendarSync] Found \(events.count) active event(s): \(events.map { $0.title }.joined(separator: ", "))")
            }

            DispatchQueue.main.async {
                let previousEventIds = Set(self.activeEvents.map { $0.id })
                let newEventIds = Set(events.map { $0.id })
                self.activeEvents = events

                print("[CalendarSync] Updated activeEvents to \(events.count) event(s)")

                // Post notification for any new events
                let addedEventIds = newEventIds.subtracting(previousEventIds)
                if !addedEventIds.isEmpty {
                    let newEvents = events.filter { addedEventIds.contains($0.id) }
                    NotificationCenter.default.post(
                        name: .calendarEventBecameActive,
                        object: nil,
                        userInfo: ["events": newEvents]
                    )
                }
            }
        } catch {
            print("[CalendarSync] Failed to check current event: \(error)")
        }
    }

    private func updateUpcomingEvents() async {
        do {
            let events = try Database.shared.read { db in
                try CalendarEvent.upcoming(limit: 5).fetchAll(db)
            }

            await MainActor.run {
                upcomingEvents = events
            }
        } catch {
            print("Failed to fetch upcoming events: \(error)")
        }
    }

    // MARK: - Ignore Events

    func ignoreEvent(_ event: CalendarEvent) throws {
        let ignored = IgnoredCalendarEvent(googleEventId: event.googleEventId)

        try Database.shared.write { db in
            var record = ignored
            try record.insert(db)
        }

        // Re-check current event
        checkCurrentEvent()
    }

    func ignoreSeries(_ seriesId: String) throws {
        let ignored = IgnoredCalendarEvent(googleSeriesId: seriesId)

        try Database.shared.write { db in
            var record = ignored
            try record.insert(db)
        }

        // Re-check current event
        checkCurrentEvent()
    }

    func unignoreEvent(_ eventId: String) throws {
        try Database.shared.write { db in
            try IgnoredCalendarEvent
                .filter(IgnoredCalendarEvent.Columns.googleEventId == eventId)
                .deleteAll(db)
        }
    }

    func unignoreSeries(_ seriesId: String) throws {
        try Database.shared.write { db in
            try IgnoredCalendarEvent
                .filter(IgnoredCalendarEvent.Columns.googleSeriesId == seriesId)
                .deleteAll(db)
        }
    }

    func getIgnoredEvents() throws -> [IgnoredCalendarEvent] {
        try Database.shared.read { db in
            try IgnoredCalendarEvent.fetchAll(db)
        }
    }

    func clearAllIgnoredEvents() throws {
        try Database.shared.write { db in
            try IgnoredCalendarEvent.deleteAll(db)
        }
        // Re-check current event
        checkCurrentEvent()
    }

    // MARK: - Context Rules

    func getContextRules(for seriesId: String) throws -> [CalendarSeriesContextRule] {
        try Database.shared.read { db in
            try CalendarSeriesContextRule.forSeries(seriesId).fetchAll(db)
        }
    }

    func addContextRule(seriesId: String, contextId: UUID) throws {
        let rule = CalendarSeriesContextRule(googleSeriesId: seriesId, contextId: contextId)

        try Database.shared.write { db in
            var record = rule
            try record.insert(db)
        }
    }

    func removeContextRule(seriesId: String, contextId: UUID) throws {
        try Database.shared.write { db in
            try CalendarSeriesContextRule
                .filter(CalendarSeriesContextRule.Columns.googleSeriesId == seriesId)
                .filter(CalendarSeriesContextRule.Columns.contextId == contextId)
                .deleteAll(db)
        }
    }

    // MARK: - Event Queries

    func getEvents(for date: Date) throws -> [CalendarEvent] {
        try Database.shared.read { db in
            try CalendarEvent.forDay(date).fetchAll(db)
        }
    }

    func getEvent(by googleEventId: String) throws -> CalendarEvent? {
        try Database.shared.read { db in
            try CalendarEvent
                .filter(CalendarEvent.Columns.googleEventId == googleEventId)
                .fetchOne(db)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let calendarAccountConnected = Notification.Name("calendarAccountConnected")
    static let calendarAccountDisconnected = Notification.Name("calendarAccountDisconnected")
    static let calendarEventBecameActive = Notification.Name("calendarEventBecameActive")
    static let calendarEventsUpdated = Notification.Name("calendarEventsUpdated")
}
