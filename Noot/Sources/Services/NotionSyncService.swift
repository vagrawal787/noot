import Foundation
import GRDB
import Combine

// MARK: - Notion Sync Service

final class NotionSyncService: ObservableObject {
    static let shared = NotionSyncService()

    @Published var isConnected: Bool = false
    @Published var isSyncing: Bool = false
    @Published var lastSync: Date?
    @Published var lastError: Error?
    @Published var syncProgress: NotionSyncProgress?

    private var syncTimer: Timer?
    private var currentSync: NotionSync?

    private init() {
        loadConnectionState()
    }

    // MARK: - Connection State

    private func loadConnectionState() {
        do {
            currentSync = try Database.shared.read { db in
                try NotionSync.fetchOne(db)
            }
            isConnected = currentSync != nil
            lastSync = currentSync?.lastSyncAt
        } catch {
            print("Failed to load Notion connection state: \(error)")
        }
    }

    func getConnectedSync() -> NotionSync? {
        return currentSync
    }

    // MARK: - Connect

    /// Connect using an internal integration token
    func connectWithToken(_ token: String) async throws {
        // Validate token format (Notion uses "secret_" or "ntn_" prefixes)
        guard token.hasPrefix("secret_") || token.hasPrefix("ntn_") else {
            throw NotionSyncError.invalidToken
        }

        // Create API client
        let api = NotionAPI(accessToken: token)

        // Get bot info to verify token works
        let user = try await api.getCurrentUser()

        // Search for databases the integration has access to
        let databases = try await api.searchDatabases()

        let databaseId: String
        let databaseName: String

        if let nootDb = databases.first(where: { $0.displayTitle.lowercased().contains("noot") }) {
            databaseId = nootDb.id
            databaseName = nootDb.displayTitle
        } else if let firstDb = databases.first {
            databaseId = firstDb.id
            databaseName = firstDb.displayTitle
        } else {
            throw NotionSyncError.noDatabaseAccess
        }

        // Ensure the database has the required properties
        try await api.ensureDatabaseProperties(databaseId: databaseId)

        // Save connection
        let sync = NotionSync(
            workspaceId: user.id,
            workspaceName: user.name,
            databaseId: databaseId,
            databaseName: databaseName,
            accessToken: token,
            syncArchivedNotes: UserPreferences.shared.notionSyncArchivedNotes
        )

        try Database.shared.write { db in
            try NotionSync.deleteAll(db)
            try sync.insert(db)
        }

        await MainActor.run {
            self.currentSync = sync
            self.isConnected = true
            self.lastError = nil
        }

        if UserPreferences.shared.notionAutoSyncEnabled {
            startAutoSync()
        }
    }

    func disconnect() throws {
        // Stop auto-sync
        stopAutoSync()

        // Delete sync configuration and all sync states
        try Database.shared.write { db in
            try NoteSyncState.deleteAll(db)
            try NotionSync.deleteAll(db)
        }

        currentSync = nil
        isConnected = false
        lastSync = nil
        lastError = nil
    }

    // MARK: - Sync Operations

    func syncAll(progress: @escaping (NotionSyncProgress) -> Void) async throws -> NotionSyncReport {
        guard let sync = currentSync else {
            throw NotionSyncError.notConnected
        }

        await MainActor.run {
            self.isSyncing = true
            self.lastError = nil
        }

        defer {
            Task { @MainActor in
                self.isSyncing = false
            }
        }

        var report = NotionSyncReport(
            notesCreated: 0,
            notesUpdated: 0,
            notesFailed: 0,
            errors: []
        )

        let api = NotionAPI(accessToken: sync.accessToken)

        // Ensure database has required properties
        try await api.ensureDatabaseProperties(databaseId: sync.databaseId)

        // Fetch notes to sync
        let notes = try Database.shared.read { db -> [Note] in
            var query = Note.all()
            if !sync.syncArchivedNotes {
                query = query.filter(Note.Columns.archived == false)
            }
            return try query.fetchAll(db)
        }

        progress(NotionSyncProgress(phase: "Preparing", current: 0, total: notes.count))

        // Get existing sync states
        let existingSyncStates = try Database.shared.read { db in
            try NoteSyncState.filter(NoteSyncState.Columns.notionSyncId == sync.id).fetchAll(db)
        }
        let syncStateMap = Dictionary(uniqueKeysWithValues: existingSyncStates.map { ($0.noteId, $0) })

        // Sync each note
        for (index, note) in notes.enumerated() {
            let noteTitle = String(note.content.prefix(50))
            progress(NotionSyncProgress(
                phase: "Syncing notes",
                current: index + 1,
                total: notes.count,
                currentNote: noteTitle
            ))

            do {
                // Get contexts for this note
                let contexts = try Database.shared.read { db -> [Context] in
                    let noteContexts = try NoteContext.filter(NoteContext.Columns.noteId == note.id).fetchAll(db)
                    let contextIds = noteContexts.map { $0.contextId }
                    return try Context.filter(keys: contextIds).fetchAll(db)
                }

                // Get meeting for this note (if any)
                let meeting = try Database.shared.read { db -> Meeting? in
                    guard let noteMeeting = try NoteMeeting.filter(NoteMeeting.Columns.noteId == note.id).fetchOne(db) else {
                        return nil
                    }
                    return try Meeting.fetchOne(db, key: noteMeeting.meetingId)
                }

                let currentHash = NoteSyncState.computeHash(for: note, meetingId: meeting?.id)

                if let existingState = syncStateMap[note.id] {
                    // Check if note has changed
                    if existingState.syncHash != currentHash {
                        // Update existing page
                        _ = try await api.updatePage(
                            pageId: existingState.notionPageId,
                            note: note,
                            contexts: contexts,
                            databaseId: sync.databaseId,
                            meeting: meeting
                        )

                        // Update sync state
                        var updatedState = existingState
                        updatedState.lastSyncedAt = Date()
                        updatedState.syncHash = currentHash

                        try Database.shared.write { db in
                            try updatedState.update(db)
                        }

                        report.notesUpdated += 1
                    }
                } else {
                    // Create new page
                    let page = try await api.createPage(
                        in: sync.databaseId,
                        note: note,
                        contexts: contexts,
                        meeting: meeting
                    )

                    // Create sync state
                    let syncState = NoteSyncState(
                        noteId: note.id,
                        notionPageId: page.id,
                        notionSyncId: sync.id,
                        syncHash: currentHash
                    )

                    try Database.shared.write { db in
                        try syncState.insert(db)
                    }

                    report.notesCreated += 1
                }
            } catch {
                report.notesFailed += 1
                report.errors.append("Failed to sync note: \(error.localizedDescription)")
            }
        }

        // Update last sync time
        var updatedSync = sync
        updatedSync.lastSyncAt = Date()
        try Database.shared.write { db in
            try updatedSync.update(db)
        }

        await MainActor.run {
            self.currentSync = updatedSync
            self.lastSync = updatedSync.lastSyncAt
        }

        progress(NotionSyncProgress(phase: "Complete", current: notes.count, total: notes.count))

        return report
    }

    func syncNote(_ noteId: UUID) async throws {
        guard let sync = currentSync else {
            throw NotionSyncError.notConnected
        }

        let api = NotionAPI(accessToken: sync.accessToken)

        // Fetch note, contexts, and meeting
        let (note, contexts, meeting) = try Database.shared.read { db -> (Note, [Context], Meeting?) in
            guard let note = try Note.fetchOne(db, key: noteId) else {
                throw NotionSyncError.noteNotFound
            }

            let noteContexts = try NoteContext.filter(NoteContext.Columns.noteId == noteId).fetchAll(db)
            let contextIds = noteContexts.map { $0.contextId }
            let contexts = try Context.filter(keys: contextIds).fetchAll(db)

            // Get meeting if any
            var meeting: Meeting? = nil
            if let noteMeeting = try NoteMeeting.filter(NoteMeeting.Columns.noteId == noteId).fetchOne(db) {
                meeting = try Meeting.fetchOne(db, key: noteMeeting.meetingId)
            }

            return (note, contexts, meeting)
        }

        let currentHash = NoteSyncState.computeHash(for: note, meetingId: meeting?.id)

        // Check for existing sync state
        let existingState = try Database.shared.read { db in
            try NoteSyncState.filter(NoteSyncState.Columns.noteId == noteId)
                .filter(NoteSyncState.Columns.notionSyncId == sync.id)
                .fetchOne(db)
        }

        if let existingState = existingState {
            // Update existing page
            _ = try await api.updatePage(
                pageId: existingState.notionPageId,
                note: note,
                contexts: contexts,
                databaseId: sync.databaseId,
                meeting: meeting
            )

            var updatedState = existingState
            updatedState.lastSyncedAt = Date()
            updatedState.syncHash = currentHash

            try Database.shared.write { db in
                try updatedState.update(db)
            }
        } else {
            // Create new page
            let page = try await api.createPage(
                in: sync.databaseId,
                note: note,
                contexts: contexts,
                meeting: meeting
            )

            let syncState = NoteSyncState(
                noteId: note.id,
                notionPageId: page.id,
                notionSyncId: sync.id,
                syncHash: currentHash
            )

            try Database.shared.write { db in
                try syncState.insert(db)
            }
        }
    }

    // MARK: - Auto-Sync

    func startAutoSync() {
        stopAutoSync()

        let interval = TimeInterval(UserPreferences.shared.notionAutoSyncIntervalMinutes * 60)

        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                do {
                    _ = try await self?.syncAll { _ in }
                } catch {
                    await MainActor.run {
                        self?.lastError = error
                    }
                }
            }
        }
    }

    func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Force Resync

    /// Clear all sync states to force a full resync
    func clearSyncStates() throws {
        guard let sync = currentSync else { return }

        try Database.shared.write { db in
            try NoteSyncState.filter(NoteSyncState.Columns.notionSyncId == sync.id).deleteAll(db)
        }
    }

    // MARK: - Settings

    func updateSyncSettings(syncArchived: Bool) throws {
        guard var sync = currentSync else { return }

        sync.syncArchivedNotes = syncArchived

        try Database.shared.write { db in
            try sync.update(db)
        }

        currentSync = sync
    }

    // MARK: - Helpers

    func getNotionPageURL(for noteId: UUID) -> URL? {
        guard let sync = currentSync else { return nil }

        do {
            let syncState = try Database.shared.read { db in
                try NoteSyncState.filter(NoteSyncState.Columns.noteId == noteId)
                    .filter(NoteSyncState.Columns.notionSyncId == sync.id)
                    .fetchOne(db)
            }

            if let pageId = syncState?.notionPageId {
                // Convert page ID to URL format (remove hyphens)
                let cleanId = pageId.replacingOccurrences(of: "-", with: "")
                return URL(string: "https://notion.so/\(cleanId)")
            }
        } catch {
            print("Failed to get Notion page URL: \(error)")
        }

        return nil
    }

    func isSynced(noteId: UUID) -> Bool {
        guard let sync = currentSync else { return false }

        do {
            let syncState = try Database.shared.read { db in
                try NoteSyncState.filter(NoteSyncState.Columns.noteId == noteId)
                    .filter(NoteSyncState.Columns.notionSyncId == sync.id)
                    .fetchOne(db)
            }
            return syncState != nil
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum NotionSyncError: Error, LocalizedError {
    case notConnected
    case noDatabaseAccess
    case noteNotFound
    case invalidToken
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to Notion. Please connect first."
        case .noDatabaseAccess:
            return "No database found. Please share a database with your Notion integration."
        case .noteNotFound:
            return "Note not found"
        case .invalidToken:
            return "Invalid token. Please use an internal integration secret starting with 'secret_' or 'ntn_'."
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        }
    }
}
