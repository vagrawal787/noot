import Foundation

// MARK: - Export Schema Version

/// Current export schema version. Increment when making breaking changes to export format.
let currentExportSchemaVersion = 1

// MARK: - Export Manifest

/// Metadata about the export for validation and compatibility checking
struct ExportManifest: Codable {
    var nootVersion: String
    var schemaVersion: Int
    var exportedAt: Date
    var noteCount: Int
    var attachmentCount: Int
    var contextCount: Int
    var meetingCount: Int
    var contextLinkCount: Int
    var noteLinkCount: Int
    var screenContextCount: Int
    var calendarEventCount: Int
    var calendarAccountCount: Int

    init(
        nootVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
        schemaVersion: Int = currentExportSchemaVersion,
        exportedAt: Date = Date(),
        noteCount: Int = 0,
        attachmentCount: Int = 0,
        contextCount: Int = 0,
        meetingCount: Int = 0,
        contextLinkCount: Int = 0,
        noteLinkCount: Int = 0,
        screenContextCount: Int = 0,
        calendarEventCount: Int = 0,
        calendarAccountCount: Int = 0
    ) {
        self.nootVersion = nootVersion
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.noteCount = noteCount
        self.attachmentCount = attachmentCount
        self.contextCount = contextCount
        self.meetingCount = meetingCount
        self.contextLinkCount = contextLinkCount
        self.noteLinkCount = noteLinkCount
        self.screenContextCount = screenContextCount
        self.calendarEventCount = calendarEventCount
        self.calendarAccountCount = calendarAccountCount
    }
}

// MARK: - Note Frontmatter (YAML)

/// YAML frontmatter structure for note markdown files
struct NoteFrontmatter: Codable {
    var id: String
    var createdAt: Date
    var updatedAt: Date
    var closedAt: Date?
    var archived: Bool
    var contexts: [ContextRef]?
    var links: [LinkRef]?
    var meetingId: String?
    var screenContext: ScreenContextRef?
    var attachments: [AttachmentRef]?

    struct ContextRef: Codable {
        var id: String
        var name: String
    }

    struct LinkRef: Codable {
        var targetId: String
        var relationship: String
    }

    struct ScreenContextRef: Codable {
        var sourceType: String
        var appName: String?
        var url: String?
        var filePath: String?
        var lineStart: Int?
        var lineEnd: Int?
        var gitRepo: String?
        var gitBranch: String?
    }

    struct AttachmentRef: Codable {
        var id: String
        var type: String
        var filename: String
        var fileSize: Int?
        var durationSeconds: Double?
    }
}

// MARK: - Export Options

/// Options for markdown export
struct MarkdownExportOptions {
    var includeAttachments: Bool = true
    var includeArchived: Bool = false
    var organizeBy: OrganizeBy = .context

    enum OrganizeBy: String, CaseIterable, Codable {
        case context
        case date
        case flat

        var displayName: String {
            switch self {
            case .context: return "Context"
            case .date: return "Date"
            case .flat: return "Flat"
            }
        }
    }
}

// MARK: - Export Progress

/// Progress reporting for export operations
struct ExportProgress {
    var phase: String
    var current: Int
    var total: Int

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    var description: String {
        "\(phase) (\(current)/\(total))"
    }
}

// MARK: - Full Export Data

/// Complete export of all Noot data (for JSON serialization)
struct FullExportData: Codable {
    var manifest: ExportManifest
    var notes: [Note]
    var contexts: [Context]
    var contextLinks: [ContextLink]
    var noteContexts: [NoteContext]
    var noteLinks: [NoteLink]
    var meetings: [Meeting]
    var noteMeetings: [NoteMeeting]
    var meetingContexts: [MeetingContext]
    var screenContexts: [ScreenContext]
    var attachments: [Attachment]
    var calendarAccounts: [CalendarAccount]
    var calendarEvents: [CalendarEvent]
    var calendarSeriesContextRules: [CalendarSeriesContextRule]
    var ignoredCalendarEvents: [IgnoredCalendarEvent]
}

// MARK: - Context Export Data

/// Export data for a single context (for context-specific export)
struct ContextExportData: Codable {
    var context: Context
    var notes: [Note]
    var noteContexts: [NoteContext]
    var noteLinks: [NoteLink]
    var screenContexts: [ScreenContext]
    var attachments: [Attachment]
    var meetings: [Meeting]
    var noteMeetings: [NoteMeeting]
}
