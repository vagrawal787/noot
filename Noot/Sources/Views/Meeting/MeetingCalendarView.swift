import SwiftUI
import GRDB

struct MeetingCalendarView: View {
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    @State private var eventsForSelectedDay: [CalendarEvent] = []
    @State private var meetingsForSelectedDay: [Meeting] = []
    @State private var daysWithMeetings: Set<DateComponents> = []
    @State private var selectedEvent: CalendarEvent? = nil
    @ObservedObject private var calendarService = CalendarSyncService.shared

    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            // LEFT COLUMN: Calendar + Events List
            VStack(spacing: 0) {
                // Mini Calendar
                VStack(spacing: 12) {
                    // Month Navigation
                    HStack {
                        Button(action: previousMonth) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(NootTheme.cyan)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(dateFormatter.string(from: currentMonth))
                            .font(NootTheme.monoFont)
                            .foregroundColor(NootTheme.textPrimary)

                        Spacer()

                        Button(action: nextMonth) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(NootTheme.cyan)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    // Day Headers
                    HStack(spacing: 0) {
                        ForEach(["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"], id: \.self) { day in
                            Text(day)
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textMuted)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Calendar Grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                        ForEach(Array(daysInMonth().enumerated()), id: \.offset) { index, date in
                            if let date = date {
                                DayCell(
                                    date: date,
                                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                    isToday: calendar.isDateInToday(date),
                                    hasMeetings: hasMeetings(on: date),
                                    hasEvents: hasEvents(on: date)
                                )
                                .onTapGesture {
                                    selectedDate = date
                                    selectedEvent = nil
                                    loadDataForSelectedDay()
                                }
                            } else {
                                Text("")
                                    .frame(height: 32)
                            }
                        }
                    }
                }
                .padding()
                .background(NootTheme.surface)

                Divider()
                    .background(NootTheme.textMuted)

                // Events List for Selected Day
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Selected Day Header
                        HStack {
                            Text(selectedDateHeader)
                                .font(NootTheme.monoFontLarge)
                                .foregroundColor(NootTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top)

                        // Calendar Events Section
                        if !eventsForSelectedDay.isEmpty {
                            ForEach(eventsForSelectedDay) { event in
                                CalendarEventRowClickable(
                                    event: event,
                                    isSelected: selectedEvent?.id == event.id
                                ) {
                                    withAnimation {
                                        selectedEvent = event
                                    }
                                }
                            }
                        }

                        // Unlinked Meetings Section
                        let unlinkedMeetings = meetingsForSelectedDay.filter { meeting in
                            !eventsForSelectedDay.contains { $0.googleEventId == meeting.calendarEventId }
                        }
                        if !unlinkedMeetings.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "person.2")
                                        .foregroundColor(NootTheme.magenta)
                                    Text("Other Meetings")
                                        .font(NootTheme.monoFontSmall)
                                        .foregroundColor(NootTheme.textSecondary)
                                }
                                .padding(.horizontal)

                                ForEach(unlinkedMeetings) { meeting in
                                    MeetingRowCompact(meeting: meeting)
                                }
                            }
                        }

                        // Empty State
                        if eventsForSelectedDay.isEmpty && meetingsForSelectedDay.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "calendar.badge.minus")
                                    .font(.system(size: 32))
                                    .foregroundColor(NootTheme.textMuted)
                                Text("No events or meetings")
                                    .font(NootTheme.monoFont)
                                    .foregroundColor(NootTheme.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(.bottom)
                }
            }
            .frame(minWidth: 280, maxWidth: 320)
            .background(NootTheme.background)

            // Divider between columns
            Rectangle()
                .fill(NootTheme.cyan.opacity(0.3))
                .frame(width: 1)

            // RIGHT COLUMN: Event Detail View
            if let event = selectedEvent {
                CalendarEventDetailView(event: event)
                    .id(event.id)  // Force view recreation when event changes
                    .frame(maxWidth: .infinity)
            } else {
                // Empty state for right column
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 40))
                        .foregroundColor(NootTheme.textMuted.opacity(0.5))
                    Text("SELECT AN EVENT")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.textMuted)
                    Text("Click on a calendar event to see\nlinked meetings and notes")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NootTheme.background)
            }
        }
        .background(NootTheme.background)
        .onAppear {
            loadDataForSelectedDay()
            loadDaysWithMeetings()
        }
        .onChange(of: currentMonth) { _ in
            loadDaysWithMeetings()
        }
    }

    // MARK: - Computed Properties

    private var selectedDateHeader: String {
        let formatter = DateFormatter()
        if calendar.isDateInToday(selectedDate) {
            formatter.dateFormat = "'Today,' EEEE"
        } else if calendar.isDateInYesterday(selectedDate) {
            formatter.dateFormat = "'Yesterday,' EEEE"
        } else if calendar.isDateInTomorrow(selectedDate) {
            formatter.dateFormat = "'Tomorrow,' EEEE"
        } else {
            formatter.dateFormat = "EEEE, MMMM d"
        }
        return formatter.string(from: selectedDate)
    }

    // MARK: - Calendar Helpers

    private func daysInMonth() -> [Date?] {
        let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonth)!.count

        var days: [Date?] = []

        // Add empty cells for days before the first day of the month
        for _ in 1..<firstWeekday {
            days.append(nil)
        }

        // Add all days of the month
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }

        return days
    }

    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    private func hasMeetings(on date: Date) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return daysWithMeetings.contains(components)
    }

    private func hasEvents(on date: Date) -> Bool {
        do {
            let events = try calendarService.getEvents(for: date)
            return !events.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Data Loading

    private func loadDataForSelectedDay() {
        do {
            eventsForSelectedDay = try calendarService.getEvents(for: selectedDate)

            let startOfDay = calendar.startOfDay(for: selectedDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

            meetingsForSelectedDay = try Database.shared.read { db in
                try Meeting
                    .filter(Meeting.Columns.startedAt >= startOfDay)
                    .filter(Meeting.Columns.startedAt < endOfDay)
                    .order(Meeting.Columns.startedAt)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to load data for selected day: \(error)")
        }
    }

    private func loadDaysWithMeetings() {
        do {
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

            let meetings = try Database.shared.read { db in
                try Meeting
                    .filter(Meeting.Columns.startedAt >= startOfMonth)
                    .filter(Meeting.Columns.startedAt < endOfMonth)
                    .fetchAll(db)
            }

            daysWithMeetings = Set(meetings.map { meeting in
                calendar.dateComponents([.year, .month, .day], from: meeting.startedAt)
            })
        } catch {
            print("Failed to load days with meetings: \(error)")
        }
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasMeetings: Bool
    let hasEvents: Bool

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            // Background
            if isSelected {
                Circle()
                    .fill(NootTheme.cyan.opacity(0.3))
            } else if isToday {
                Circle()
                    .stroke(NootTheme.cyan, lineWidth: 1)
            }

            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(isSelected ? NootTheme.cyan : (isToday ? NootTheme.cyan : NootTheme.textPrimary))

                // Indicators
                HStack(spacing: 2) {
                    if hasEvents {
                        Circle()
                            .fill(NootTheme.cyan)
                            .frame(width: 4, height: 4)
                    }
                    if hasMeetings {
                        Circle()
                            .fill(NootTheme.magenta)
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .frame(height: 32)
    }
}

// MARK: - Calendar Event Row

private struct CalendarEventRow: View {
    let event: CalendarEvent

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: event.startTime)) - \(formatter.string(from: event.endTime))"
    }

    var body: some View {
        HStack(alignment: .top) {
            Rectangle()
                .fill(NootTheme.cyan)
                .frame(width: 3)
                .cornerRadius(1.5)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(NootTheme.monoFont)
                    .foregroundColor(NootTheme.textPrimary)
                    .lineLimit(2)

                Text(timeText)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)

                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location")
                            .font(.system(size: 10))
                        Text(location)
                            .lineLimit(1)
                    }
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textSecondary)
                }

                if event.googleSeriesId != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.system(size: 10))
                        Text("Recurring")
                    }
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.magenta)
                }
            }

            Spacer()
        }
        .padding()
        .background(NootTheme.surface)
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Meeting Row

private struct MeetingRow: View {
    let meeting: Meeting

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var text = formatter.string(from: meeting.startedAt)
        if let endedAt = meeting.endedAt {
            text += " - \(formatter.string(from: endedAt))"
        } else {
            text += " - ongoing"
        }
        return text
    }

    private var durationText: String? {
        guard let duration = meeting.duration else { return nil }
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) hr"
            }
            return "\(hours) hr \(remainingMinutes) min"
        }
    }

    var body: some View {
        HStack(alignment: .top) {
            Rectangle()
                .fill(NootTheme.magenta)
                .frame(width: 3)
                .cornerRadius(1.5)

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title ?? "Untitled Meeting")
                    .font(NootTheme.monoFont)
                    .foregroundColor(NootTheme.textPrimary)

                Text(timeText)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)

                HStack(spacing: 12) {
                    if let duration = durationText {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(duration)
                        }
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textSecondary)
                    }

                    if meeting.audioPath != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.system(size: 10))
                            Text("Audio")
                        }
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.cyan)
                    }

                    if meeting.calendarEventId != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text("Linked")
                        }
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.cyan)
                    }
                }
            }

            Spacer()

            if meeting.isOngoing {
                NeonStatusIndicator(status: .recording, label: "LIVE")
            }
        }
        .padding()
        .background(NootTheme.surface)
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Clickable Calendar Event Row

private struct CalendarEventRowClickable: View {
    let event: CalendarEvent
    let isSelected: Bool
    let action: () -> Void

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: event.startTime)) - \(formatter.string(from: event.endTime))"
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                Rectangle()
                    .fill(isSelected ? NootTheme.cyan : NootTheme.cyan.opacity(0.6))
                    .frame(width: 3)
                    .cornerRadius(1.5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.textPrimary)
                        .lineLimit(2)

                    Text(timeText)
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)

                    if event.googleSeriesId != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                                .font(.system(size: 10))
                            Text("Recurring")
                        }
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.magenta)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(NootTheme.textMuted)
            }
            .padding()
            .background(isSelected ? NootTheme.cyan.opacity(0.1) : NootTheme.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? NootTheme.cyan.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Calendar Event Detail View

private struct CalendarEventDetailView: View {
    let event: CalendarEvent
    @State private var linkedMeetings: [Meeting] = []
    @State private var linkedNotes: [Note] = []
    @State private var linkedContexts: [Context] = []
    @State private var allContexts: [Context] = []
    @State private var showContextPicker: Bool = false

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: event.startTime)) - \(formatter.string(from: event.endTime))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Event Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "calendar.circle.fill")
                        .font(.title2)
                        .foregroundColor(NootTheme.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(NootTheme.monoFont)
                            .foregroundColor(NootTheme.textPrimary)
                        Text(timeText)
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textMuted)
                    }

                    Spacer()
                }

                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location")
                            .font(.caption)
                        Text(location)
                    }
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textSecondary)
                }

                if event.googleSeriesId != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.caption)
                        Text("Recurring event")
                    }
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.magenta)
                }
            }
            .padding()
            .background(NootTheme.surface)

            Divider()
                .background(NootTheme.textMuted)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Linked Meetings Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "person.2")
                                .foregroundColor(NootTheme.magenta)
                            Text("MEETINGS")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(NootTheme.textSecondary)
                            Spacer()
                            Text("\(linkedMeetings.count)")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(NootTheme.surface)
                                .cornerRadius(4)
                        }

                        if linkedMeetings.isEmpty {
                            Text("No meetings linked to this event")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textMuted)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(linkedMeetings) { meeting in
                                LinkedMeetingCard(meeting: meeting)
                            }
                        }
                    }

                    Divider()
                        .background(NootTheme.textMuted.opacity(0.5))

                    // Linked Notes Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "note.text")
                                .foregroundColor(NootTheme.cyan)
                            Text("NOTES")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(NootTheme.textSecondary)
                            Spacer()
                            Text("\(linkedNotes.count)")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(NootTheme.surface)
                                .cornerRadius(4)
                        }

                        if linkedNotes.isEmpty {
                            Text("No notes from meetings linked to this event")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textMuted)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(linkedNotes) { note in
                                LinkedNoteCard(note: note)
                            }
                        }
                    }

                    // Context Rules Section (only for recurring events)
                    if event.googleSeriesId != nil {
                        Divider()
                            .background(NootTheme.textMuted.opacity(0.5))

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(NootTheme.success)
                                Text("AUTO-ASSIGN CONTEXTS")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(NootTheme.textSecondary)
                                Spacer()
                            }

                            Text("Meetings created from this recurring event will automatically be assigned to these contexts:")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textMuted)

                            // Current linked contexts
                            if linkedContexts.isEmpty {
                                Text("No contexts assigned")
                                    .font(NootTheme.monoFontSmall)
                                    .foregroundColor(NootTheme.textMuted)
                                    .italic()
                                    .padding(.vertical, 4)
                            } else {
                                FlowLayout(spacing: 8) {
                                    ForEach(linkedContexts) { context in
                                        HStack(spacing: 4) {
                                            Image(systemName: context.iconName)
                                                .font(.system(size: 10))
                                            Text(context.name)
                                                .font(NootTheme.monoFontSmall)
                                            Button(action: { removeContext(context) }) {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 8, weight: .bold))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(context.themeColor.opacity(0.2))
                                        .foregroundColor(context.themeColor)
                                        .cornerRadius(6)
                                    }
                                }
                            }

                            // Add context button
                            Button(action: { showContextPicker = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text("Add Context")
                                }
                                .font(NootTheme.monoFontSmall)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(NeonButtonStyle(color: NootTheme.success))
                        }
                    }
                }
                .padding()
            }
        }
        .background(NootTheme.background)
        .sheet(isPresented: $showContextPicker) {
            if let seriesId = event.googleSeriesId {
                SeriesContextPickerSheet(
                    seriesId: seriesId,
                    onAdd: { context in
                        addContext(context)
                    }
                )
            }
        }
        .onAppear {
            loadLinkedContent()
        }
        .onChange(of: event.id) { _ in
            loadLinkedContent()
        }
    }

    private func loadLinkedContent() {
        print("[CalendarDetail] loadLinkedContent called for event: \(event.title), seriesId: \(event.googleSeriesId ?? "nil")")
        do {
            // Load meetings linked to this calendar event
            linkedMeetings = try Database.shared.read { db in
                try Meeting
                    .filter(Meeting.Columns.calendarEventId == event.googleEventId)
                    .order(Meeting.Columns.startedAt.desc)
                    .fetchAll(db)
            }

            // Load notes from those meetings
            if !linkedMeetings.isEmpty {
                let meetingIds = linkedMeetings.map { $0.id }
                linkedNotes = try Database.shared.read { db in
                    let noteMeetings = try NoteMeeting
                        .filter(meetingIds.contains(NoteMeeting.Columns.meetingId))
                        .fetchAll(db)
                    let noteIds = noteMeetings.map { $0.noteId }
                    return try Note
                        .filter(noteIds.contains(Note.Columns.id))
                        .order(Note.Columns.createdAt.desc)
                        .fetchAll(db)
                }
            } else {
                linkedNotes = []
            }

            // Load context rules for this series
            if let seriesId = event.googleSeriesId {
                linkedContexts = try Database.shared.read { db in
                    let rules = try CalendarSeriesContextRule
                        .filter(CalendarSeriesContextRule.Columns.googleSeriesId == seriesId)
                        .fetchAll(db)
                    let contextIds = rules.map { $0.contextId }
                    return try Context
                        .filter(contextIds.contains(Context.Columns.id))
                        .fetchAll(db)
                }
            } else {
                linkedContexts = []
            }

            // Load all available contexts
            allContexts = try Database.shared.read { db in
                let contexts = try Context
                    .filter(Context.Columns.archived == false)
                    .order(Context.Columns.name)
                    .fetchAll(db)
                print("[CalendarDetail] Loaded \(contexts.count) contexts: \(contexts.map { $0.name })")
                return contexts
            }
            print("[CalendarDetail] allContexts has \(allContexts.count) items, linkedContexts has \(linkedContexts.count) items")
        } catch {
            print("[CalendarDetail] Failed to load linked content: \(error)")
        }
    }

    private func addContext(_ context: Context) {
        guard let seriesId = event.googleSeriesId else { return }

        do {
            try CalendarSyncService.shared.addContextRule(seriesId: seriesId, contextId: context.id)
            loadLinkedContent()
        } catch {
            print("Failed to add context rule: \(error)")
        }
    }

    private func removeContext(_ context: Context) {
        guard let seriesId = event.googleSeriesId else { return }

        do {
            try CalendarSyncService.shared.removeContextRule(seriesId: seriesId, contextId: context.id)
            loadLinkedContent()
        } catch {
            print("Failed to remove context rule: \(error)")
        }
    }
}

// MARK: - Series Context Picker Sheet

private struct SeriesContextPickerSheet: View {
    let seriesId: String
    let onAdd: (Context) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var allContexts: [Context] = []
    @State private var linkedContexts: [Context] = []

    private var availableContexts: [Context] {
        let linkedIds = Set(linkedContexts.map { $0.id })
        return allContexts.filter { !linkedIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ADD CONTEXT")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(NootTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(NootTheme.surface)

            Divider()

            if allContexts.isEmpty {
                // No contexts exist at all
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(NootTheme.textMuted)
                    Text("No contexts created")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.textMuted)
                    Text("Create contexts in the sidebar\nto organize your meetings")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if availableContexts.isEmpty {
                // All contexts already assigned
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(NootTheme.success)
                    Text("All contexts assigned")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(availableContexts) { context in
                            Button(action: {
                                onAdd(context)
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: context.iconName)
                                        .foregroundColor(context.themeColor)
                                        .frame(width: 24)

                                    Text(context.name)
                                        .font(NootTheme.monoFont)
                                        .foregroundColor(NootTheme.textPrimary)

                                    Spacer()

                                    Text(context.type.rawValue)
                                        .font(NootTheme.monoFontSmall)
                                        .foregroundColor(NootTheme.textMuted)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(NootTheme.surface)
                                        .cornerRadius(4)

                                    Image(systemName: "plus.circle")
                                        .foregroundColor(NootTheme.success)
                                }
                                .padding()
                                .background(NootTheme.surface)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 350, height: 400)
        .background(NootTheme.background)
        .onAppear {
            loadData()
        }
    }

    private func loadData() {
        do {
            // Load all available contexts
            allContexts = try Database.shared.read { db in
                try Context
                    .filter(Context.Columns.archived == false)
                    .order(Context.Columns.name)
                    .fetchAll(db)
            }

            // Load already linked contexts for this series
            linkedContexts = try Database.shared.read { db in
                let rules = try CalendarSeriesContextRule
                    .filter(CalendarSeriesContextRule.Columns.googleSeriesId == seriesId)
                    .fetchAll(db)
                let contextIds = rules.map { $0.contextId }
                return try Context
                    .filter(contextIds.contains(Context.Columns.id))
                    .fetchAll(db)
            }

            print("[ContextPicker] Loaded \(allContexts.count) total contexts, \(linkedContexts.count) linked")
        } catch {
            print("[ContextPicker] Failed to load data: \(error)")
        }
    }
}

// MARK: - Meeting Row Compact (for left sidebar)

private struct MeetingRowCompact: View {
    let meeting: Meeting

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: meeting.startedAt)
    }

    var body: some View {
        HStack {
            Rectangle()
                .fill(NootTheme.magenta)
                .frame(width: 3)
                .cornerRadius(1.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title ?? "Untitled Meeting")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textPrimary)
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(NootTheme.textMuted)
            }

            Spacer()

            if meeting.audioPath != nil {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                    .foregroundColor(NootTheme.cyan)
            }
        }
        .padding(8)
        .background(NootTheme.surface)
        .cornerRadius(6)
        .padding(.horizontal)
    }
}

// MARK: - Linked Meeting Card

private struct LinkedMeetingCard: View {
    let meeting: Meeting

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var text = formatter.string(from: meeting.startedAt)
        if let endedAt = meeting.endedAt {
            text += " - \(formatter.string(from: endedAt))"
        }
        return text
    }

    private var durationText: String? {
        guard let duration = meeting.duration else { return nil }
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes == 0 ? "\(hours) hr" : "\(hours) hr \(remainingMinutes) min"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(NootTheme.magenta)

                Text(meeting.title ?? "Untitled Meeting")
                    .font(NootTheme.monoFont)
                    .foregroundColor(NootTheme.textPrimary)
                    .lineLimit(1)

                Spacer()

                if meeting.isOngoing {
                    NeonStatusIndicator(status: .recording, label: "LIVE")
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(timeText)
                }
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textMuted)

                if let duration = durationText {
                    Text("•")
                        .foregroundColor(NootTheme.textMuted)
                    Text(duration)
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }

                Spacer()

                if meeting.audioPath != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                        Text("Recording")
                    }
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.cyan)
                }
            }
        }
        .padding()
        .background(NootTheme.surface)
        .cornerRadius(8)
    }
}

// MARK: - Linked Note Card

private struct LinkedNoteCard: View {
    let note: Note

    private var previewText: String {
        let text = note.content.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]+\)"#, with: "[img]", options: .regularExpression)
        return String(text.prefix(150))
    }

    private var hasImages: Bool {
        note.content.contains("![")
    }

    var body: some View {
        Button(action: navigateToNote) {
            VStack(alignment: .leading, spacing: 8) {
                Text(previewText)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(note.createdAt, style: .relative)
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(NootTheme.textMuted)

                    if hasImages {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 10))
                            Text("Images")
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(NootTheme.magenta)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("Open")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(NootTheme.cyan)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NootTheme.surface)
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func navigateToNote() {
        NotificationCenter.default.post(
            name: .navigateToNote,
            object: nil,
            userInfo: ["noteId": note.id]
        )
    }
}

#Preview {
    MeetingCalendarView()
        .frame(width: 400, height: 600)
        .preferredColorScheme(.dark)
}
