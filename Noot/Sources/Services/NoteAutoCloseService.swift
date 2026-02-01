import Foundation
import GRDB

final class NoteAutoCloseService {
    static let shared = NoteAutoCloseService()

    private var timer: Timer?

    private init() {}

    func start() {
        guard UserPreferences.shared.autoCloseNotes else { return }

        // Check every minute
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.closeStaleNotes()
        }

        // Also run immediately
        closeStaleNotes()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func restart() {
        stop()
        start()
    }

    private func closeStaleNotes() {
        guard UserPreferences.shared.autoCloseNotes else { return }

        let delayMinutes = UserPreferences.shared.autoCloseDelayMinutes
        let cutoff = Date().addingTimeInterval(-Double(delayMinutes * 60))

        do {
            try Database.shared.write { db in
                // Find open notes that haven't been updated since the cutoff
                let staleNotes = try Note
                    .filter(Note.Columns.closedAt == nil)
                    .filter(Note.Columns.archived == false)
                    .filter(Note.Columns.updatedAt < cutoff)
                    .fetchAll(db)

                let now = Date()
                for var note in staleNotes {
                    note.closedAt = now
                    try note.update(db)
                    print("Auto-closed note: \(note.id)")
                }

                if !staleNotes.isEmpty {
                    print("Auto-closed \(staleNotes.count) stale notes")
                }
            }
        } catch {
            print("Failed to auto-close stale notes: \(error)")
        }
    }
}
