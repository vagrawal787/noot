import SwiftUI
import GRDB

struct MeetingCalendarLinkView: View {
    let meeting: Meeting
    let onDismiss: () -> Void

    @State private var searchText: String = ""
    @State private var events: [CalendarEvent] = []
    @State private var selectedEvent: CalendarEvent?
    @State private var applyToSeries: Bool = false
    @State private var selectedContexts: Set<UUID> = []
    @State private var availableContexts: [Context] = []
    @State private var showingContextPicker: Bool = false
    @State private var isLoading: Bool = true

    private var filteredEvents: [CalendarEvent] {
        if searchText.isEmpty {
            return events
        }
        return events.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Link to Calendar Event")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(NootTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(NootTheme.surface)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(NootTheme.textMuted)
                TextField("Search events...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(NootTheme.monoFont)
                    .foregroundColor(NootTheme.textPrimary)
            }
            .padding(10)
            .background(NootTheme.backgroundLight)
            .cornerRadius(8)
            .padding()

            // Event List
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Spacer()
            } else if filteredEvents.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(NootTheme.textMuted)
                    Text("No events found")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.textMuted)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredEvents) { event in
                            EventRow(
                                event: event,
                                isSelected: selectedEvent?.id == event.id,
                                onSelect: {
                                    selectedEvent = event
                                    loadSeriesContextRules(for: event)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }

            // Selected Event Details
            if let event = selectedEvent {
                Divider()
                    .background(NootTheme.textMuted)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected: \(event.title)")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.cyan)

                    if event.googleSeriesId != nil {
                        Toggle(isOn: $applyToSeries) {
                            VStack(alignment: .leading) {
                                Text("Apply context to entire series")
                                    .font(NootTheme.monoFontSmall)
                                    .foregroundColor(NootTheme.textPrimary)
                                Text("Future meetings in this series will auto-tag")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(NootTheme.textMuted)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: NootTheme.magenta))
                    }

                    // Context Selection
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Contexts:")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textSecondary)
                            Spacer()
                            Button(action: { showingContextPicker = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text("Add")
                                }
                                .font(NootTheme.monoFontSmall)
                            }
                            .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))
                        }

                        if selectedContexts.isEmpty {
                            Text("No contexts selected")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textMuted)
                                .italic()
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(availableContexts.filter { selectedContexts.contains($0.id) }) { context in
                                    NeonTag(context.name, icon: context.iconName, color: context.themeColor) {
                                        selectedContexts.remove(context.id)
                                    }
                                }
                            }
                        }
                    }

                    // Action Buttons
                    HStack {
                        Button("Cancel") {
                            onDismiss()
                        }
                        .buttonStyle(NeonButtonStyle(color: NootTheme.textMuted))

                        Spacer()

                        Button("Link Event") {
                            linkEvent()
                        }
                        .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))
                    }
                }
                .padding()
                .background(NootTheme.surface)
            }
        }
        .background(NootTheme.background)
        .onAppear {
            loadEvents()
            loadContexts()
        }
        .sheet(isPresented: $showingContextPicker) {
            CalendarContextPickerSheet(
                availableContexts: availableContexts,
                selectedContexts: $selectedContexts,
                onDismiss: { showingContextPicker = false }
            )
        }
    }

    private func loadEvents() {
        isLoading = true

        Task {
            do {
                let now = Date()
                let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
                let weekAhead = Calendar.current.date(byAdding: .day, value: 7, to: now)!

                let fetchedEvents = try Database.shared.read { db in
                    try CalendarEvent.inRange(from: weekAgo, to: weekAhead).fetchAll(db)
                }

                await MainActor.run {
                    events = fetchedEvents
                    isLoading = false
                }
            } catch {
                print("Failed to load events: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

    private func loadContexts() {
        do {
            availableContexts = try Database.shared.read { db in
                try Context.filter(Context.Columns.archived == false).fetchAll(db)
            }
        } catch {
            print("Failed to load contexts: \(error)")
        }
    }

    private func loadSeriesContextRules(for event: CalendarEvent) {
        guard let seriesId = event.googleSeriesId else {
            selectedContexts = []
            return
        }

        do {
            let rules = try CalendarSyncService.shared.getContextRules(for: seriesId)
            selectedContexts = Set(rules.map { $0.contextId })
        } catch {
            print("Failed to load context rules: \(error)")
        }
    }

    private func linkEvent() {
        guard let event = selectedEvent else { return }

        do {
            // Link meeting to calendar event
            try MeetingManager.shared.linkMeetingToCalendarEvent(meeting, event: event)

            // Apply contexts to meeting
            try Database.shared.write { db in
                for contextId in selectedContexts {
                    let meetingContext = MeetingContext(meetingId: meeting.id, contextId: contextId)
                    try? meetingContext.insert(db)
                }
            }

            // Apply series context rules if enabled
            if applyToSeries, let seriesId = event.googleSeriesId {
                for contextId in selectedContexts {
                    try? CalendarSyncService.shared.addContextRule(seriesId: seriesId, contextId: contextId)
                }
            }

            onDismiss()
        } catch {
            print("Failed to link event: \(error)")
        }
    }
}

// MARK: - Event Row

private struct EventRow: View {
    let event: CalendarEvent
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(NootTheme.monoFont)
                        .foregroundColor(isSelected ? NootTheme.cyan : NootTheme.textPrimary)
                        .lineLimit(1)

                    Text(formatEventTime())
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }

                Spacer()

                if event.googleSeriesId != nil {
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundColor(NootTheme.magenta)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(NootTheme.cyan)
                }
            }
            .padding(12)
            .background(isSelected ? NootTheme.surface : NootTheme.backgroundLight)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? NootTheme.cyan.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func formatEventTime() -> String {
        let dateFormatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(event.startTime) {
            dateFormatter.dateFormat = "'Today' h:mm a"
        } else if calendar.isDateInYesterday(event.startTime) {
            dateFormatter.dateFormat = "'Yesterday' h:mm a"
        } else if calendar.isDateInTomorrow(event.startTime) {
            dateFormatter.dateFormat = "'Tomorrow' h:mm a"
        } else {
            dateFormatter.dateFormat = "MMM d, h:mm a"
        }

        return dateFormatter.string(from: event.startTime)
    }
}

// MARK: - Context Picker Sheet

private struct CalendarContextPickerSheet: View {
    let availableContexts: [Context]
    @Binding var selectedContexts: Set<UUID>
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Contexts")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
                Spacer()
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(NeonButtonStyle())
            }
            .padding()
            .background(NootTheme.surface)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(availableContexts) { context in
                        Button(action: {
                            if selectedContexts.contains(context.id) {
                                selectedContexts.remove(context.id)
                            } else {
                                selectedContexts.insert(context.id)
                            }
                        }) {
                            HStack {
                                Image(systemName: context.iconName)
                                    .foregroundColor(context.themeColor)
                                Text(context.name)
                                    .font(NootTheme.monoFont)
                                    .foregroundColor(NootTheme.textPrimary)
                                Spacer()
                                if selectedContexts.contains(context.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(context.themeColor)
                                }
                            }
                            .padding(12)
                            .background(selectedContexts.contains(context.id) ? NootTheme.surface : NootTheme.backgroundLight)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .frame(width: 350, height: 400)
        .background(NootTheme.background)
    }
}

#Preview {
    MeetingCalendarLinkView(
        meeting: Meeting(title: "Test Meeting"),
        onDismiss: {}
    )
    .frame(width: 450, height: 600)
    .preferredColorScheme(.dark)
}
