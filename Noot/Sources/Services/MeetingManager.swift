import Foundation
import Combine
import GRDB

final class MeetingManager: ObservableObject {
    static let shared = MeetingManager()

    @Published private(set) var currentMeeting: Meeting?
    @Published private(set) var isRecordingAudio: Bool = false

    private var audioRecordingURL: URL?

    private init() {}

    var isInMeeting: Bool {
        currentMeeting != nil
    }

    func startMeeting(title: String? = nil, recordAudio: Bool = false, audioSource: AudioSource = .microphone, calendarEvent: CalendarEvent? = nil) throws {
        guard currentMeeting == nil else {
            throw MeetingError.alreadyInMeeting
        }

        // Use calendar event title if available and no title provided
        let meetingTitle = title ?? calendarEvent?.title
        var meeting = Meeting(
            title: meetingTitle,
            calendarEventId: calendarEvent?.googleEventId
        )

        // Save meeting to database
        try Database.shared.write { db in
            try meeting.insert(db)

            // Auto-apply context rules for series if linked to calendar event
            if let seriesId = calendarEvent?.googleSeriesId {
                let rules = try CalendarSeriesContextRule.forSeries(seriesId).fetchAll(db)
                for rule in rules {
                    let meetingContext = MeetingContext(meetingId: meeting.id, contextId: rule.contextId)
                    try? meetingContext.insert(db)
                }
            }
        }

        currentMeeting = meeting

        // Start audio recording if requested
        if recordAudio && audioSource != .none {
            do {
                audioRecordingURL = try AudioRecorderService.shared.startRecording(source: audioSource)
                isRecordingAudio = true
            } catch {
                print("Failed to start audio recording: \(error)")
            }
        }
    }

    @discardableResult
    func endMeeting() throws -> Meeting {
        guard var meeting = currentMeeting else {
            throw MeetingError.notInMeeting
        }

        meeting.endedAt = Date()

        // Stop audio recording
        if isRecordingAudio {
            if let audioURL = AudioRecorderService.shared.stopRecording() {
                meeting.audioPath = audioURL.path
            }
            isRecordingAudio = false
        }

        // Update meeting in database
        try Database.shared.write { db in
            try meeting.update(db)

            // Get meeting's contexts for applying to notes
            let meetingContexts = try MeetingContext
                .filter(MeetingContext.Columns.meetingId == meeting.id)
                .fetchAll(db)

            // Get notes already associated with this meeting (respects user's opt-out choice)
            let associatedNoteIds = try NoteMeeting
                .filter(NoteMeeting.Columns.meetingId == meeting.id)
                .fetchAll(db)
                .map { $0.noteId }

            // Apply meeting's contexts to associated notes
            for noteId in associatedNoteIds {
                for meetingContext in meetingContexts {
                    let noteContext = NoteContext(noteId: noteId, contextId: meetingContext.contextId)
                    try? noteContext.insert(db) // Ignore if already exists
                }
            }
        }

        currentMeeting = nil
        return meeting
    }

    func toggleMeeting() throws {
        if isInMeeting {
            try endMeeting()
        } else {
            try startMeeting()
        }
    }

    func associateCurrentNote(_ noteId: UUID) throws {
        guard let meeting = currentMeeting else { return }

        try Database.shared.write { db in
            let noteMeeting = NoteMeeting(noteId: noteId, meetingId: meeting.id)
            try? noteMeeting.insert(db)
        }
    }

    // MARK: - Calendar Integration

    func startMeetingFromCalendarEvent(_ event: CalendarEvent, recordAudio: Bool = false, audioSource: AudioSource = .microphone) throws {
        guard currentMeeting == nil else {
            throw MeetingError.alreadyInMeeting
        }

        var meeting = Meeting(
            title: event.title,
            calendarEventId: event.googleEventId
        )

        // Save meeting to database
        try Database.shared.write { db in
            try meeting.insert(db)

            // Auto-apply context rules for series
            if let seriesId = event.googleSeriesId {
                let rules = try CalendarSeriesContextRule.forSeries(seriesId).fetchAll(db)
                for rule in rules {
                    let meetingContext = MeetingContext(meetingId: meeting.id, contextId: rule.contextId)
                    try? meetingContext.insert(db)
                }
            }
        }

        currentMeeting = meeting

        // Start audio recording if requested
        if recordAudio {
            do {
                audioRecordingURL = try AudioRecorderService.shared.startRecording(source: audioSource)
                isRecordingAudio = true
            } catch {
                print("Failed to start audio recording: \(error)")
            }
        }
    }

    func getCurrentMeetingCalendarEvent() -> CalendarEvent? {
        guard let meeting = currentMeeting,
              let eventId = meeting.calendarEventId else {
            return nil
        }

        return try? CalendarSyncService.shared.getEvent(by: eventId)
    }

    func linkMeetingToCalendarEvent(_ meeting: Meeting, event: CalendarEvent) throws {
        var updatedMeeting = meeting
        updatedMeeting.calendarEventId = event.googleEventId

        try Database.shared.write { db in
            try updatedMeeting.update(db)
        }

        // If this is the current meeting, update the reference
        if currentMeeting?.id == meeting.id {
            currentMeeting = updatedMeeting
        }
    }
}

enum MeetingError: Error {
    case alreadyInMeeting
    case notInMeeting
}
