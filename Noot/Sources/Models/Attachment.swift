import Foundation
import GRDB

enum AttachmentType: String, Codable, Hashable {
    case screenshot
    case screenRecording = "screen_recording"
    case audio
}

struct Attachment: Codable, Identifiable, Hashable {
    var id: UUID
    var noteId: UUID
    var type: AttachmentType
    var filePath: String
    var fileSize: Int
    var originalSize: Int?
    var durationSeconds: Double?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        noteId: UUID,
        type: AttachmentType,
        filePath: String,
        fileSize: Int,
        originalSize: Int? = nil,
        durationSeconds: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.noteId = noteId
        self.type = type
        self.filePath = filePath
        self.fileSize = fileSize
        self.originalSize = originalSize
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
    }

    /// Compression ratio as a percentage (e.g., 0.75 means 75% smaller)
    var compressionRatio: Double? {
        guard let originalSize = originalSize, originalSize > 0 else { return nil }
        return 1.0 - (Double(fileSize) / Double(originalSize))
    }

    /// Human-readable file size
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    /// Human-readable duration for recordings
    var formattedDuration: String? {
        guard let duration = durationSeconds else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration)
    }
}

extension Attachment: FetchableRecord, PersistableRecord {
    static let databaseTableName = "attachments"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let noteId = Column(CodingKeys.noteId)
        static let type = Column(CodingKeys.type)
        static let filePath = Column(CodingKeys.filePath)
        static let fileSize = Column(CodingKeys.fileSize)
        static let originalSize = Column(CodingKeys.originalSize)
        static let durationSeconds = Column(CodingKeys.durationSeconds)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    static let note = belongsTo(Note.self)
}

// MARK: - Queries
extension Attachment {
    static func forNote(_ noteId: UUID) -> QueryInterfaceRequest<Attachment> {
        Attachment
            .filter(Columns.noteId == noteId)
            .order(Columns.createdAt)
    }

    static func screenshots() -> QueryInterfaceRequest<Attachment> {
        Attachment
            .filter(Columns.type == AttachmentType.screenshot.rawValue)
            .order(Columns.createdAt.desc)
    }

    static func recordings() -> QueryInterfaceRequest<Attachment> {
        Attachment
            .filter(Columns.type == AttachmentType.screenRecording.rawValue)
            .order(Columns.createdAt.desc)
    }
}
