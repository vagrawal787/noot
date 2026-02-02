import Foundation

// MARK: - Notion API Client

final class NotionAPI {
    private let baseURL = "https://api.notion.com/v1"
    private let notionVersion = "2022-06-28"
    private let accessToken: String

    init(accessToken: String) {
        self.accessToken = accessToken
    }

    // MARK: - Database Operations

    /// Search for databases the integration has access to
    func searchDatabases() async throws -> [NotionDatabase] {
        let url = URL(string: "\(baseURL)/search")!

        var request = makeRequest(url: url, method: "POST")
        let body: [String: Any] = [
            "filter": ["property": "object", "value": "database"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        let searchResponse = try JSONDecoder().decode(NotionSearchResponse.self, from: data)
        return searchResponse.results.compactMap { result -> NotionDatabase? in
            guard result.object == "database" else { return nil }
            return NotionDatabase(
                id: result.id,
                title: result.title,
                properties: result.properties
            )
        }
    }

    /// Create a new database in a parent page
    func createDatabase(in parentPageId: String, title: String) async throws -> String {
        let url = URL(string: "\(baseURL)/databases")!

        var request = makeRequest(url: url, method: "POST")
        let body: [String: Any] = [
            "parent": ["type": "page_id", "page_id": parentPageId],
            "title": [
                ["type": "text", "text": ["content": title]]
            ],
            "properties": [
                "Title": ["title": [:]],
                "Created": ["date": [:]],
                "Updated": ["date": [:]],
                "Archived": ["checkbox": [:]],
                "Contexts": ["rich_text": [:]]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        let database = try JSONDecoder().decode(NotionDatabaseResponse.self, from: data)
        return database.id
    }

    /// Get database info
    func getDatabase(id: String) async throws -> NotionDatabase {
        let url = URL(string: "\(baseURL)/databases/\(id)")!

        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        return try JSONDecoder().decode(NotionDatabase.self, from: data)
    }

    /// Ensure the database has the required properties for Noot sync
    func ensureDatabaseProperties(databaseId: String) async throws {
        let database = try await getDatabase(id: databaseId)
        let existingProperties = database.properties ?? [:]

        // Define the properties we need (excluding title, which always exists)
        var propertiesToAdd: [String: Any] = [:]

        // Check for Created date property
        if !existingProperties.keys.contains(where: { $0.lowercased() == "created" }) {
            propertiesToAdd["Created"] = ["date": [:]]
        }

        // Check for Updated date property
        if !existingProperties.keys.contains(where: { $0.lowercased() == "updated" }) {
            propertiesToAdd["Updated"] = ["date": [:]]
        }

        // Check for Archived checkbox property
        if !existingProperties.keys.contains(where: { $0.lowercased() == "archived" }) {
            propertiesToAdd["Archived"] = ["checkbox": [:]]
        }

        // Check for Contexts property
        if !existingProperties.keys.contains(where: { $0.lowercased() == "contexts" }) {
            propertiesToAdd["Contexts"] = ["rich_text": [:]]
        }

        // Check for Meeting property
        if !existingProperties.keys.contains(where: { $0.lowercased() == "meeting" }) {
            propertiesToAdd["Meeting"] = ["rich_text": [:]]
        }

        // Check for Meeting Date property
        if !existingProperties.keys.contains(where: { $0.lowercased() == "meeting date" }) {
            propertiesToAdd["Meeting Date"] = ["date": [:]]
        }

        // If we have properties to add, update the database
        if !propertiesToAdd.isEmpty {
            try await updateDatabaseProperties(databaseId: databaseId, properties: propertiesToAdd)
        }
    }

    /// Update database properties
    private func updateDatabaseProperties(databaseId: String, properties: [String: Any]) async throws {
        let url = URL(string: "\(baseURL)/databases/\(databaseId)")!

        var request = makeRequest(url: url, method: "PATCH")
        let body: [String: Any] = ["properties": properties]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
    }

    // MARK: - Page Operations

    /// Create a page (note) in a database
    func createPage(in databaseId: String, note: Note, contexts: [Context], meeting: Meeting? = nil) async throws -> NotionPage {
        // First, get the database to find property names
        let database = try await getDatabase(id: databaseId)
        let propertyNames = getPropertyNames(from: database)

        let url = URL(string: "\(baseURL)/pages")!

        var request = makeRequest(url: url, method: "POST")

        // Build properties
        let title = extractTitle(from: note.content)
        let contextNames = contexts.map { $0.name }.joined(separator: ", ")

        var properties: [String: Any] = [
            propertyNames.title: [
                "title": [
                    ["text": ["content": title]]
                ]
            ]
        ]

        // Add optional properties if they exist
        if let createdProp = propertyNames.created {
            properties[createdProp] = [
                "date": ["start": formatDate(note.createdAt)]
            ]
        }
        if let updatedProp = propertyNames.updated {
            properties[updatedProp] = [
                "date": ["start": formatDate(note.updatedAt)]
            ]
        }
        if let archivedProp = propertyNames.archived {
            properties[archivedProp] = [
                "checkbox": note.archived
            ]
        }
        if let contextsProp = propertyNames.contexts {
            properties[contextsProp] = [
                "rich_text": [
                    ["text": ["content": contextNames]]
                ]
            ]
        }

        // Add meeting properties if meeting exists
        if let meeting = meeting {
            if let meetingProp = propertyNames.meeting {
                properties[meetingProp] = [
                    "rich_text": [
                        ["text": ["content": meeting.title ?? "Untitled Meeting"]]
                    ]
                ]
            }
            if let meetingDateProp = propertyNames.meetingDate {
                properties[meetingDateProp] = [
                    "date": ["start": formatDate(meeting.startedAt)]
                ]
            }
        }

        // Build content blocks from markdown
        let blocks = convertMarkdownToBlocks(note.content)

        let body: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": properties,
            "children": blocks
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        return try JSONDecoder().decode(NotionPage.self, from: data)
    }

    /// Property names found in a database
    private struct DatabasePropertyNames {
        var title: String
        var created: String?
        var updated: String?
        var archived: String?
        var contexts: String?
        var meeting: String?
        var meetingDate: String?
    }

    /// Find property names in a database (case-insensitive matching)
    private func getPropertyNames(from database: NotionDatabase) -> DatabasePropertyNames {
        var names = DatabasePropertyNames(title: "Name")

        guard let properties = database.properties else { return names }

        for (name, schema) in properties {
            let lowercased = name.lowercased()

            if schema.type == "title" {
                names.title = name
            } else if lowercased == "created" && schema.type == "date" {
                names.created = name
            } else if lowercased == "updated" && schema.type == "date" {
                names.updated = name
            } else if lowercased == "archived" && schema.type == "checkbox" {
                names.archived = name
            } else if lowercased == "contexts" && schema.type == "rich_text" {
                names.contexts = name
            } else if lowercased == "meeting" && schema.type == "rich_text" {
                names.meeting = name
            } else if lowercased == "meeting date" && schema.type == "date" {
                names.meetingDate = name
            }
        }

        return names
    }

    /// Update an existing page
    func updatePage(pageId: String, note: Note, contexts: [Context], databaseId: String, meeting: Meeting? = nil) async throws -> NotionPage {
        // Get database to find property names
        let database = try await getDatabase(id: databaseId)
        let propertyNames = getPropertyNames(from: database)

        let url = URL(string: "\(baseURL)/pages/\(pageId)")!

        var request = makeRequest(url: url, method: "PATCH")

        let title = extractTitle(from: note.content)
        let contextNames = contexts.map { $0.name }.joined(separator: ", ")

        var properties: [String: Any] = [
            propertyNames.title: [
                "title": [
                    ["text": ["content": title]]
                ]
            ]
        ]

        // Add optional properties if they exist
        if let updatedProp = propertyNames.updated {
            properties[updatedProp] = [
                "date": ["start": formatDate(note.updatedAt)]
            ]
        }
        if let archivedProp = propertyNames.archived {
            properties[archivedProp] = [
                "checkbox": note.archived
            ]
        }
        if let contextsProp = propertyNames.contexts {
            properties[contextsProp] = [
                "rich_text": [
                    ["text": ["content": contextNames]]
                ]
            ]
        }

        // Add meeting properties if meeting exists
        if let meeting = meeting {
            if let meetingProp = propertyNames.meeting {
                properties[meetingProp] = [
                    "rich_text": [
                        ["text": ["content": meeting.title ?? "Untitled Meeting"]]
                    ]
                ]
            }
            if let meetingDateProp = propertyNames.meetingDate {
                properties[meetingDateProp] = [
                    "date": ["start": formatDate(meeting.startedAt)]
                ]
            }
        }

        let body: [String: Any] = [
            "properties": properties
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        // Also update the content blocks
        try await updatePageContent(pageId: pageId, content: note.content)

        return try JSONDecoder().decode(NotionPage.self, from: data)
    }

    /// Update page content by replacing all blocks
    func updatePageContent(pageId: String, content: String) async throws {
        // First, delete existing blocks
        let existingBlocks = try await getPageBlocks(pageId: pageId)
        for block in existingBlocks {
            try await deleteBlock(blockId: block.id)
        }

        // Then add new blocks
        let blocks = convertMarkdownToBlocks(content)
        if !blocks.isEmpty {
            try await appendBlocks(to: pageId, blocks: blocks)
        }
    }

    /// Get page info
    func getPage(id: String) async throws -> NotionPage {
        let url = URL(string: "\(baseURL)/pages/\(id)")!

        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        return try JSONDecoder().decode(NotionPage.self, from: data)
    }

    /// Archive a page
    func archivePage(pageId: String) async throws {
        let url = URL(string: "\(baseURL)/pages/\(pageId)")!

        var request = makeRequest(url: url, method: "PATCH")
        let body: [String: Any] = ["archived": true]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
    }

    // MARK: - Block Operations

    /// Get blocks (content) of a page
    func getPageBlocks(pageId: String) async throws -> [NotionBlock] {
        let url = URL(string: "\(baseURL)/blocks/\(pageId)/children")!

        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        let blocksResponse = try JSONDecoder().decode(NotionBlocksResponse.self, from: data)
        return blocksResponse.results
    }

    /// Append blocks to a page
    func appendBlocks(to pageId: String, blocks: [[String: Any]]) async throws {
        let url = URL(string: "\(baseURL)/blocks/\(pageId)/children")!

        var request = makeRequest(url: url, method: "PATCH")
        let body: [String: Any] = ["children": blocks]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
    }

    /// Delete a block
    func deleteBlock(blockId: String) async throws {
        let url = URL(string: "\(baseURL)/blocks/\(blockId)")!

        let request = makeRequest(url: url, method: "DELETE")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)
    }

    // MARK: - File Upload

    /// Upload a file (returns external URL - Notion file uploads require different handling)
    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> String {
        // Notion doesn't support direct file uploads via API
        // Files must be hosted externally and referenced by URL
        // For now, return a placeholder - actual implementation would need external storage
        throw NotionAPIError.fileUploadNotSupported
    }

    // MARK: - User Info

    /// Get current bot user info
    func getCurrentUser() async throws -> NotionUser {
        let url = URL(string: "\(baseURL)/users/me")!

        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data)

        return try JSONDecoder().decode(NotionUser.self, from: data)
    }

    // MARK: - Private Helpers

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let error = try? JSONDecoder().decode(NotionError.self, from: data) {
                throw NotionAPIError.apiError(httpResponse.statusCode, error.message ?? "Unknown error")
            }
            throw NotionAPIError.httpError(httpResponse.statusCode)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func extractTitle(from content: String) -> String {
        let firstLine = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? content
        let title = firstLine
            .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(title.prefix(100))
    }

    private func convertMarkdownToBlocks(_ markdown: String) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        let lines = markdown.components(separatedBy: "\n")

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Skip empty lines
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Headers
            if line.hasPrefix("### ") {
                blocks.append([
                    "object": "block",
                    "type": "heading_3",
                    "heading_3": [
                        "rich_text": [["type": "text", "text": ["content": String(line.dropFirst(4))]]]
                    ]
                ])
            } else if line.hasPrefix("## ") {
                blocks.append([
                    "object": "block",
                    "type": "heading_2",
                    "heading_2": [
                        "rich_text": [["type": "text", "text": ["content": String(line.dropFirst(3))]]]
                    ]
                ])
            } else if line.hasPrefix("# ") {
                blocks.append([
                    "object": "block",
                    "type": "heading_1",
                    "heading_1": [
                        "rich_text": [["type": "text", "text": ["content": String(line.dropFirst(2))]]]
                    ]
                ])
            }
            // Bullet lists
            else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append([
                    "object": "block",
                    "type": "bulleted_list_item",
                    "bulleted_list_item": [
                        "rich_text": [["type": "text", "text": ["content": String(line.dropFirst(2))]]]
                    ]
                ])
            }
            // Numbered lists
            else if line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                let content = line.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                blocks.append([
                    "object": "block",
                    "type": "numbered_list_item",
                    "numbered_list_item": [
                        "rich_text": [["type": "text", "text": ["content": content]]]
                    ]
                ])
            }
            // Checkboxes
            else if line.hasPrefix("- [ ] ") {
                blocks.append([
                    "object": "block",
                    "type": "to_do",
                    "to_do": [
                        "rich_text": [["type": "text", "text": ["content": String(line.dropFirst(6))]]],
                        "checked": false
                    ]
                ])
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                blocks.append([
                    "object": "block",
                    "type": "to_do",
                    "to_do": [
                        "rich_text": [["type": "text", "text": ["content": String(line.dropFirst(6))]]],
                        "checked": true
                    ]
                ])
            }
            // Code blocks
            else if line.hasPrefix("```") {
                var codeContent: [String] = []
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeContent.append(lines[i])
                    i += 1
                }
                blocks.append([
                    "object": "block",
                    "type": "code",
                    "code": [
                        "rich_text": [["type": "text", "text": ["content": codeContent.joined(separator: "\n")]]],
                        "language": language.isEmpty ? "plain text" : language
                    ]
                ])
            }
            // Blockquotes
            else if line.hasPrefix("> ") {
                blocks.append([
                    "object": "block",
                    "type": "quote",
                    "quote": [
                        "rich_text": [["type": "text", "text": ["content": String(line.dropFirst(2))]]]
                    ]
                ])
            }
            // Horizontal rule
            else if line == "---" || line == "***" || line == "___" {
                blocks.append([
                    "object": "block",
                    "type": "divider",
                    "divider": [:]
                ])
            }
            // Regular paragraph
            else {
                blocks.append([
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [["type": "text", "text": ["content": line]]]
                    ]
                ])
            }

            i += 1
        }

        return blocks
    }
}

// MARK: - Response Types

private struct NotionSearchResponse: Codable {
    let results: [NotionSearchResult]
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
    }
}

private struct NotionSearchResult: Codable {
    let object: String
    let id: String
    let title: [NotionRichText]?
    let properties: [String: NotionPropertySchema]?
}

private struct NotionDatabaseResponse: Codable {
    let id: String
}

struct NotionBlock: Codable {
    let id: String
    let object: String
    let type: String
}

private struct NotionBlocksResponse: Codable {
    let results: [NotionBlock]
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
    }
}

struct NotionUser: Codable {
    let id: String
    let object: String
    let type: String?
    let name: String?

    var isBot: Bool {
        type == "bot"
    }
}

// MARK: - Errors

enum NotionAPIError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case apiError(Int, String)
    case fileUploadNotSupported

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Notion API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let code, let message):
            return "Notion API error (\(code)): \(message)"
        case .fileUploadNotSupported:
            return "Direct file upload is not supported by Notion API. Files must be hosted externally."
        }
    }
}
