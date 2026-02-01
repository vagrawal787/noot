import Foundation

struct UserPreferencesData: Codable {
    var lastUsedContextIds: [UUID]
    var defaultCaptureMode: CaptureMode
    var compressionLevel: CompressionLevel
    var autoCloseNotes: Bool
    var autoCloseDelayMinutes: Int
    var largeFileWarningMB: Int
    var hotkeys: HotkeyPreferences

    // Calendar settings
    var calendarPollIntervalSeconds: Int
    var calendarSyncDaysAhead: Int
    var showCalendarInMenubar: Bool
    var autoStartMeetingNotes: Bool
    var googleOAuthCredentials: GoogleOAuthCredentials

    init() {
        self.lastUsedContextIds = []
        self.defaultCaptureMode = .note
        self.compressionLevel = .medium
        self.autoCloseNotes = true
        self.autoCloseDelayMinutes = 30
        self.largeFileWarningMB = 100
        self.hotkeys = HotkeyPreferences()

        // Calendar defaults
        self.calendarPollIntervalSeconds = 60
        self.calendarSyncDaysAhead = 7
        self.showCalendarInMenubar = true
        self.autoStartMeetingNotes = false
        self.googleOAuthCredentials = GoogleOAuthCredentials()
    }
}

struct GoogleOAuthCredentials: Codable {
    var clientId: String?
    var clientSecret: String?

    init(clientId: String? = nil, clientSecret: String? = nil) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
}

enum CaptureMode: String, Codable {
    case note
    case screenshot
    case recording
}

enum CompressionLevel: String, Codable {
    case none
    case low
    case medium
    case high
}

struct HotkeyPreferences: Codable {
    var newNote: String
    var continueNote: String
    var screenshot: String
    var screenRecording: String
    var meeting: String
    var inbox: String
    var openNoot: String
    var closeNote: String

    init() {
        self.newNote = "Option+Space"
        self.continueNote = "Cmd+Option+Space"
        self.screenshot = "Cmd+Option+2"
        self.screenRecording = "Cmd+Option+3"
        self.meeting = "Cmd+Option+M"
        self.inbox = "Cmd+Option+I"
        self.openNoot = "Cmd+Option+O"
        self.closeNote = "Escape"
    }
}

final class UserPreferences {
    static let shared = UserPreferences()

    private var preferences: UserPreferencesData
    private let configURL: URL

    private init() {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Noot", isDirectory: true)
        configURL = appSupportURL.appendingPathComponent("config.json")

        // Load or create preferences
        if FileManager.default.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let loaded = try? JSONDecoder().decode(UserPreferencesData.self, from: data) {
            preferences = loaded
        } else {
            preferences = UserPreferencesData()
            save()
        }
    }

    // MARK: - Accessors

    var lastUsedContextIds: [UUID] {
        get { preferences.lastUsedContextIds }
        set {
            preferences.lastUsedContextIds = Array(newValue.prefix(10)) // Keep last 10
            save()
        }
    }

    var defaultCaptureMode: CaptureMode {
        get { preferences.defaultCaptureMode }
        set {
            preferences.defaultCaptureMode = newValue
            save()
        }
    }

    var compressionLevel: CompressionLevel {
        get { preferences.compressionLevel }
        set {
            preferences.compressionLevel = newValue
            save()
        }
    }

    var autoCloseNotes: Bool {
        get { preferences.autoCloseNotes }
        set {
            preferences.autoCloseNotes = newValue
            save()
        }
    }

    var autoCloseDelayMinutes: Int {
        get { preferences.autoCloseDelayMinutes }
        set {
            preferences.autoCloseDelayMinutes = newValue
            save()
        }
    }

    var largeFileWarningMB: Int {
        get { preferences.largeFileWarningMB }
        set {
            preferences.largeFileWarningMB = newValue
            save()
        }
    }

    var hotkeys: HotkeyPreferences {
        get { preferences.hotkeys }
        set {
            preferences.hotkeys = newValue
            save()
        }
    }

    // MARK: - Calendar Settings

    var calendarPollIntervalSeconds: Int {
        get { preferences.calendarPollIntervalSeconds }
        set {
            preferences.calendarPollIntervalSeconds = newValue
            save()
        }
    }

    var calendarSyncDaysAhead: Int {
        get { preferences.calendarSyncDaysAhead }
        set {
            preferences.calendarSyncDaysAhead = newValue
            save()
        }
    }

    var showCalendarInMenubar: Bool {
        get { preferences.showCalendarInMenubar }
        set {
            preferences.showCalendarInMenubar = newValue
            save()
        }
    }

    var autoStartMeetingNotes: Bool {
        get { preferences.autoStartMeetingNotes }
        set {
            preferences.autoStartMeetingNotes = newValue
            save()
        }
    }

    var googleOAuthCredentials: GoogleOAuthCredentials {
        get { preferences.googleOAuthCredentials }
        set {
            preferences.googleOAuthCredentials = newValue
            save()
        }
    }

    // MARK: - Context Usage

    func markContextUsed(_ contextId: UUID) {
        var ids = preferences.lastUsedContextIds.filter { $0 != contextId }
        ids.insert(contextId, at: 0)
        preferences.lastUsedContextIds = Array(ids.prefix(10))
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(preferences)
            try data.write(to: configURL)
        } catch {
            print("Failed to save preferences: \(error)")
        }
    }

    func reload() {
        if let data = try? Data(contentsOf: configURL),
           let loaded = try? JSONDecoder().decode(UserPreferencesData.self, from: data) {
            preferences = loaded
        }
    }
}
