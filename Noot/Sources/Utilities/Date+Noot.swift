import Foundation

extension Date {
    /// Returns true if this date is within the same calendar day as the given date
    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// Returns true if this date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Returns true if this date is yesterday
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    /// Returns true if this date is within the last N hours
    func isWithinLast(hours: Int) -> Bool {
        let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
        return self >= cutoff
    }

    /// Returns the start of the day for this date
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// Formats the date for display in the UI
    func formatted(style: DateFormattingStyle) -> String {
        switch style {
        case .relative:
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: self, relativeTo: Date())

        case .time:
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: self)

        case .dateTime:
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: self)

        case .full:
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .short
            return formatter.string(from: self)

        case .compact:
            if isToday {
                return formatted(style: .time)
            } else if isYesterday {
                return "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                return formatter.string(from: self)
            }
        }
    }
}

enum DateFormattingStyle {
    case relative    // "2 min ago"
    case time        // "3:45 PM"
    case dateTime    // "1/31/26, 3:45 PM"
    case full        // "Friday, January 31, 2026 at 3:45 PM"
    case compact     // "3:45 PM" for today, "Yesterday" for yesterday, "Jan 31" otherwise
}
