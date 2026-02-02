import Foundation

// MARK: - Schema Migration

/// Handles migration of imported data from older export schema versions
struct SchemaMigration {

    /// Migrate export data from an older schema version to the current version
    /// - Parameters:
    ///   - data: The raw JSON data from the export
    ///   - fromVersion: The schema version of the export
    /// - Returns: Migrated JSON data compatible with current schema
    static func migrateIfNeeded(_ data: Data, fromVersion: Int) throws -> Data {
        guard fromVersion < currentExportSchemaVersion else {
            return data
        }

        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // Apply migrations in sequence
        for version in fromVersion..<currentExportSchemaVersion {
            json = try migrate(json, from: version, to: version + 1)
        }

        return try JSONSerialization.data(withJSONObject: json)
    }

    private static func migrate(_ json: [String: Any], from: Int, to: Int) throws -> [String: Any] {
        var result = json

        switch (from, to) {
        case (0, 1):
            // Migration from hypothetical v0 to v1
            // This is a placeholder for future migrations
            // Example: rename fields, add default values, restructure data
            result = migrateV0ToV1(result)

        default:
            // Unknown migration path - return as-is
            break
        }

        return result
    }

    // MARK: - Migration Functions

    /// Placeholder migration from v0 to v1
    private static func migrateV0ToV1(_ json: [String: Any]) -> [String: Any] {
        var result = json

        // Example migrations that might be needed in the future:

        // 1. Add missing fields with defaults
        if result["contextLinkCount"] == nil {
            result["contextLinkCount"] = 0
        }

        // 2. Rename fields
        // if let oldValue = result["oldFieldName"] {
        //     result["newFieldName"] = oldValue
        //     result.removeValue(forKey: "oldFieldName")
        // }

        // 3. Transform data structures
        // if var notes = result["notes"] as? [[String: Any]] {
        //     notes = notes.map { note in
        //         var transformed = note
        //         // Apply transformations
        //         return transformed
        //     }
        //     result["notes"] = notes
        // }

        return result
    }
}

// MARK: - Schema Version Compatibility

extension SchemaMigration {

    /// Check if a schema version is compatible for import
    static func isCompatible(version: Int) -> Bool {
        // We can import from older versions (with migration)
        // We cannot import from future versions
        return version <= currentExportSchemaVersion
    }

    /// Get a description of what migration will be performed
    static func migrationDescription(fromVersion: Int) -> String? {
        guard fromVersion < currentExportSchemaVersion else {
            return nil
        }

        switch fromVersion {
        case 0:
            return "Legacy export format will be upgraded to current version"
        default:
            return "Export from version \(fromVersion) will be migrated to version \(currentExportSchemaVersion)"
        }
    }

    /// Get warnings for importing from a specific version
    static func migrationWarnings(fromVersion: Int) -> [String] {
        var warnings: [String] = []

        if fromVersion > currentExportSchemaVersion {
            warnings.append("This export was created with a newer version of Noot. Some data may not be imported correctly.")
        }

        // Add version-specific warnings
        switch fromVersion {
        case 0:
            warnings.append("This is a legacy export. Some metadata may be missing.")
        default:
            break
        }

        return warnings
    }
}

// MARK: - Frontmatter Migration

extension SchemaMigration {

    /// Migrate frontmatter from older versions
    static func migrateFrontmatter(_ yaml: [String: Any], fromVersion: Int) -> [String: Any] {
        var result = yaml

        // Handle missing fields that were added in later versions
        if result["archived"] == nil {
            result["archived"] = false
        }

        // Handle renamed fields
        // if let oldValue = result["old_field"], result["new_field"] == nil {
        //     result["new_field"] = oldValue
        // }

        return result
    }
}

// MARK: - Data Validation

extension SchemaMigration {

    /// Validate imported data structure
    static func validate(_ data: FullExportData) -> [String] {
        var errors: [String] = []

        // Validate note references
        let noteIds = Set(data.notes.map { $0.id })

        for noteContext in data.noteContexts {
            if !noteIds.contains(noteContext.noteId) {
                errors.append("NoteContext references non-existent note: \(noteContext.noteId)")
            }
        }

        for noteLink in data.noteLinks {
            if !noteIds.contains(noteLink.sourceNoteId) {
                errors.append("NoteLink references non-existent source note: \(noteLink.sourceNoteId)")
            }
            if !noteIds.contains(noteLink.targetNoteId) {
                errors.append("NoteLink references non-existent target note: \(noteLink.targetNoteId)")
            }
        }

        // Validate context references
        let contextIds = Set(data.contexts.map { $0.id })

        for noteContext in data.noteContexts {
            if !contextIds.contains(noteContext.contextId) {
                errors.append("NoteContext references non-existent context: \(noteContext.contextId)")
            }
        }

        for contextLink in data.contextLinks {
            if !contextIds.contains(contextLink.parentContextId) {
                errors.append("ContextLink references non-existent parent context: \(contextLink.parentContextId)")
            }
            if !contextIds.contains(contextLink.childContextId) {
                errors.append("ContextLink references non-existent child context: \(contextLink.childContextId)")
            }
        }

        // Validate meeting references
        let meetingIds = Set(data.meetings.map { $0.id })

        for noteMeeting in data.noteMeetings {
            if !noteIds.contains(noteMeeting.noteId) {
                errors.append("NoteMeeting references non-existent note: \(noteMeeting.noteId)")
            }
            if !meetingIds.contains(noteMeeting.meetingId) {
                errors.append("NoteMeeting references non-existent meeting: \(noteMeeting.meetingId)")
            }
        }

        return errors
    }
}
