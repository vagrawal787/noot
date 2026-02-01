import Foundation

extension FileManager {
    static func nootAppSupportDirectory() throws -> URL {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Noot", isDirectory: true)

        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }

        return appSupportURL
    }

    static func nootDatabaseURL() throws -> URL {
        try nootAppSupportDirectory().appendingPathComponent("noot.db")
    }

    static func nootAttachmentsDirectory() throws -> URL {
        let attachmentsURL = try nootAppSupportDirectory().appendingPathComponent("attachments", isDirectory: true)

        let fileManager = FileManager.default
        let subdirs = ["screenshots", "recordings", "audio"]

        for subdir in subdirs {
            let subdirURL = attachmentsURL.appendingPathComponent(subdir, isDirectory: true)
            if !fileManager.fileExists(atPath: subdirURL.path) {
                try fileManager.createDirectory(at: subdirURL, withIntermediateDirectories: true)
            }
        }

        return attachmentsURL
    }

    static func nootConfigURL() throws -> URL {
        try nootAppSupportDirectory().appendingPathComponent("config.json")
    }
}
