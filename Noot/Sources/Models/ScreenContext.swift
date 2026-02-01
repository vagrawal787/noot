import Foundation
import GRDB

enum ScreenContextSourceType: String, Codable, Hashable {
    case browser
    case vscode
    case terminal
    case other
}

struct ScreenContext: Codable, Identifiable, Hashable {
    var id: UUID
    var noteId: UUID
    var sourceType: ScreenContextSourceType
    var appName: String?
    var url: String?
    var filePath: String?
    var lineStart: Int?
    var lineEnd: Int?
    var gitRepo: String?
    var gitBranch: String?
    var capturedAt: Date

    init(
        id: UUID = UUID(),
        noteId: UUID,
        sourceType: ScreenContextSourceType = .other,
        appName: String? = nil,
        url: String? = nil,
        filePath: String? = nil,
        lineStart: Int? = nil,
        lineEnd: Int? = nil,
        gitRepo: String? = nil,
        gitBranch: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.noteId = noteId
        self.sourceType = sourceType
        self.appName = appName
        self.url = url
        self.filePath = filePath
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.gitRepo = gitRepo
        self.gitBranch = gitBranch
        self.capturedAt = capturedAt
    }

    /// Human-readable summary of the context
    var displayString: String {
        switch sourceType {
        case .browser:
            if let url = url {
                return url
            }
            return appName ?? "Browser"

        case .vscode:
            var parts: [String] = []
            if let filePath = filePath {
                let fileName = (filePath as NSString).lastPathComponent
                parts.append(fileName)
            }
            if let lineStart = lineStart {
                if let lineEnd = lineEnd, lineEnd != lineStart {
                    parts.append(":\(lineStart)-\(lineEnd)")
                } else {
                    parts.append(":\(lineStart)")
                }
            }
            if parts.isEmpty {
                return "VS Code"
            }
            return parts.joined()

        case .terminal:
            return appName ?? "Terminal"

        case .other:
            return appName ?? "Unknown"
        }
    }
}

extension ScreenContext: FetchableRecord, PersistableRecord {
    static let databaseTableName = "screen_contexts"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let noteId = Column(CodingKeys.noteId)
        static let sourceType = Column(CodingKeys.sourceType)
        static let appName = Column(CodingKeys.appName)
        static let url = Column(CodingKeys.url)
        static let filePath = Column(CodingKeys.filePath)
        static let lineStart = Column(CodingKeys.lineStart)
        static let lineEnd = Column(CodingKeys.lineEnd)
        static let gitRepo = Column(CodingKeys.gitRepo)
        static let gitBranch = Column(CodingKeys.gitBranch)
        static let capturedAt = Column(CodingKeys.capturedAt)
    }

    static let note = belongsTo(Note.self)
}
