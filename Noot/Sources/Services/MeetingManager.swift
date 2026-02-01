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

    func startMeeting(title: String? = nil, recordAudio: Bool = false, audioSource: AudioSource = .microphone) throws {
        guard currentMeeting == nil else {
            throw MeetingError.alreadyInMeeting
        }

        let meeting = Meeting(title: title)

        // Save meeting to database
        try Database.shared.write { db in
            var record = meeting
            try record.insert(db)
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

            // Auto-associate notes created during the meeting
            let startedAt = meeting.startedAt
            let endedAt = meeting.endedAt!
            let notesInMeeting = try Note
                .filter(Note.Columns.createdAt >= startedAt)
                .filter(Note.Columns.createdAt <= endedAt)
                .fetchAll(db)

            for note in notesInMeeting {
                let noteMeeting = NoteMeeting(noteId: note.id, meetingId: meeting.id)
                try? noteMeeting.insert(db) // Ignore if already exists
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
}

enum MeetingError: Error {
    case alreadyInMeeting
    case notInMeeting
}
