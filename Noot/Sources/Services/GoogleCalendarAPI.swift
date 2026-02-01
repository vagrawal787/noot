import Foundation

final class GoogleCalendarAPI {
    static let shared = GoogleCalendarAPI()

    private let baseUrl = "https://www.googleapis.com/calendar/v3"
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private init() {}

    // MARK: - Fetch Events

    func fetchEvents(
        accessToken: String,
        from: Date,
        to: Date,
        calendarId: String = "primary"
    ) async throws -> [GoogleCalendarEventResponse] {
        var components = URLComponents(string: "\(baseUrl)/calendars/\(calendarId)/events")!

        components.queryItems = [
            URLQueryItem(name: "timeMin", value: dateFormatter.string(from: from)),
            URLQueryItem(name: "timeMax", value: dateFormatter.string(from: to)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250")
        ]

        guard let url = components.url else {
            throw CalendarAPIError.invalidUrl
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarAPIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw CalendarAPIError.unauthorized
        }

        guard httpResponse.statusCode == 200 else {
            throw CalendarAPIError.requestFailed(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with time
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // Try date-only format
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            if let date = dateOnlyFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
        }

        let eventsResponse = try decoder.decode(GoogleCalendarEventsResponse.self, from: data)
        return eventsResponse.items ?? []
    }

    // MARK: - Fetch Calendar List

    func fetchCalendarList(accessToken: String) async throws -> [GoogleCalendarInfo] {
        let url = URL(string: "\(baseUrl)/users/me/calendarList")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarAPIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw CalendarAPIError.unauthorized
        }

        guard httpResponse.statusCode == 200 else {
            throw CalendarAPIError.requestFailed(httpResponse.statusCode)
        }

        let listResponse = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)
        return listResponse.items ?? []
    }
}

// MARK: - API Response Types

struct GoogleCalendarEventsResponse: Codable {
    let kind: String?
    let summary: String?
    let items: [GoogleCalendarEventResponse]?
    let nextPageToken: String?
}

struct GoogleCalendarEventResponse: Codable {
    let id: String
    let recurringEventId: String?
    let summary: String?
    let description: String?
    let start: EventDateTime
    let end: EventDateTime
    let attendees: [Attendee]?
    let location: String?
    let hangoutLink: String?
    let htmlLink: String?
    let status: String?

    var title: String {
        summary ?? "(No title)"
    }

    var startDate: Date? {
        start.dateTime ?? start.date
    }

    var endDate: Date? {
        end.dateTime ?? end.date
    }

    var meetingLink: String? {
        hangoutLink
    }

    var attendeeEmails: [String] {
        attendees?.map { $0.email } ?? []
    }
}

struct EventDateTime: Codable {
    let dateTime: Date?
    let date: Date?
    let timeZone: String?
}

struct Attendee: Codable {
    let email: String
    let displayName: String?
    let responseStatus: String?
    let organizer: Bool?
    let `self`: Bool?
}

struct GoogleCalendarListResponse: Codable {
    let kind: String?
    let items: [GoogleCalendarInfo]?
}

struct GoogleCalendarInfo: Codable, Identifiable {
    let id: String
    let summary: String?
    let description: String?
    let primary: Bool?
    let accessRole: String?
    let backgroundColor: String?
    let foregroundColor: String?
}

// MARK: - Errors

enum CalendarAPIError: Error, LocalizedError {
    case invalidUrl
    case invalidResponse
    case unauthorized
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidUrl:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Access token expired or invalid"
        case .requestFailed(let code):
            return "API request failed with status code \(code)"
        }
    }
}
