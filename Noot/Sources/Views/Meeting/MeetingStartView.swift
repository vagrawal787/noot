import SwiftUI

struct MeetingStartView: View {
    let activeCalendarEvents: [CalendarEvent]
    let onStart: (AudioSource, CalendarEvent?) -> Void
    let onCancel: () -> Void

    @State private var selectedSource: AudioSource = .both
    @State private var selectedEventId: String? = nil  // nil means "No calendar event"

    init(activeCalendarEvents: [CalendarEvent] = [], onStart: @escaping (AudioSource, CalendarEvent?) -> Void, onCancel: @escaping () -> Void) {
        self.activeCalendarEvents = activeCalendarEvents
        self.onStart = onStart
        self.onCancel = onCancel
        // Pre-select the first event if there's only one
        if activeCalendarEvents.count == 1 {
            _selectedEventId = State(initialValue: activeCalendarEvents.first?.googleEventId)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(NootTheme.cyan)
                .neonGlow(NootTheme.cyan, radius: 8)

            Text("START MEETING")
                .font(NootTheme.monoFontLarge)
                .foregroundColor(NootTheme.textPrimary)

            // Calendar Event Selection (if there are active events)
            if !activeCalendarEvents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LINK TO CALENDAR EVENT")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)

                    // "No calendar event" option
                    CalendarEventSelectionRow(
                        title: "No calendar event",
                        subtitle: "Start an unlinked meeting",
                        icon: "calendar.badge.minus",
                        isSelected: selectedEventId == nil
                    ) {
                        selectedEventId = nil
                    }

                    ForEach(activeCalendarEvents) { event in
                        CalendarEventSelectionRow(
                            title: event.title,
                            subtitle: formatEventTime(event),
                            icon: "calendar",
                            isSelected: selectedEventId == event.googleEventId
                        ) {
                            selectedEventId = event.googleEventId
                        }
                    }
                }
                .padding()
                .background(NootTheme.surface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(NootTheme.cyan.opacity(0.3), lineWidth: 1)
                )
            }

            // Audio Recording Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("AUDIO RECORDING")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)

                ForEach(AudioSource.allCases, id: \.self) { source in
                    AudioSourceRow(
                        source: source,
                        isSelected: selectedSource == source
                    ) {
                        selectedSource = source
                    }
                }
            }
            .padding()
            .background(NootTheme.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(NootTheme.cyan.opacity(0.3), lineWidth: 1)
            )

            Text(audioSourceDescription)
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textMuted)
                .multilineTextAlignment(.center)
                .frame(height: 32)

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .font(NootTheme.monoFont)
                .foregroundColor(NootTheme.textMuted)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(NootTheme.surface)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(NootTheme.textMuted.opacity(0.3), lineWidth: 1)
                )
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                Button("Start Meeting") {
                    let selectedEvent = activeCalendarEvents.first { $0.googleEventId == selectedEventId }
                    onStart(selectedSource, selectedEvent)
                }
                .font(NootTheme.monoFont)
                .foregroundColor(NootTheme.background)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(NootTheme.cyan)
                .cornerRadius(4)
                .neonGlow(NootTheme.cyan, radius: 4)
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(24)
        .frame(width: 340)
        .background(NootTheme.background)
    }

    private func formatEventTime(_ event: CalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: event.startTime)) - \(formatter.string(from: event.endTime))"
    }

    private var audioSourceDescription: String {
        switch selectedSource {
        case .microphone:
            return "Records your voice only."
        case .system:
            return "Records computer audio only."
        case .both:
            return "Records both voice and computer audio."
        case .none:
            return "No audio recording."
        }
    }
}

struct CalendarEventSelectionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? NootTheme.cyan : NootTheme.textMuted)

                Image(systemName: icon)
                    .foregroundColor(NootTheme.cyan)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? NootTheme.cyan.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AudioSourceRow: View {
    let source: AudioSource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? NootTheme.cyan : NootTheme.textMuted)

                Image(systemName: iconForSource)
                    .foregroundColor(NootTheme.textMuted)
                    .frame(width: 20)

                Text(source.rawValue)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textPrimary)

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? NootTheme.cyan.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconForSource: String {
        switch source {
        case .microphone:
            return "mic"
        case .system:
            return "speaker.wave.2"
        case .both:
            return "mic.and.signal.meter"
        case .none:
            return "mic.slash"
        }
    }
}

// MARK: - Calendar Meeting Start View

struct CalendarMeetingStartView: View {
    let eventTitle: String
    let onStart: (AudioSource) -> Void
    let onCancel: () -> Void

    @State private var selectedSource: AudioSource = .none

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(NootTheme.cyan)
                .neonGlow(NootTheme.cyan, radius: 8)

            VStack(spacing: 4) {
                Text("START MEETING NOTES")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)

                Text(eventTitle)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("AUDIO RECORDING")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)

                ForEach(AudioSource.allCases, id: \.self) { source in
                    AudioSourceRow(
                        source: source,
                        isSelected: selectedSource == source
                    ) {
                        selectedSource = source
                    }
                }
            }
            .padding()
            .background(NootTheme.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(NootTheme.cyan.opacity(0.3), lineWidth: 1)
            )

            Text(audioSourceDescription)
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textMuted)
                .multilineTextAlignment(.center)
                .frame(height: 40)

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .font(NootTheme.monoFont)
                .foregroundColor(NootTheme.textMuted)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(NootTheme.surface)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(NootTheme.textMuted.opacity(0.3), lineWidth: 1)
                )
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                Button("Start") {
                    onStart(selectedSource)
                }
                .font(NootTheme.monoFont)
                .foregroundColor(NootTheme.background)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(NootTheme.cyan)
                .cornerRadius(4)
                .neonGlow(NootTheme.cyan, radius: 4)
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(NootTheme.background)
    }

    private var audioSourceDescription: String {
        switch selectedSource {
        case .microphone:
            return "Records your voice only. Use when you want to capture your own notes."
        case .system:
            return "Records computer audio only. Captures what you hear from other participants."
        case .both:
            return "Records both your voice and computer audio. Best for full meeting capture."
        case .none:
            return "No audio will be recorded. You can still take notes during the meeting."
        }
    }
}

#Preview {
    MeetingStartView(
        onStart: { _, _ in },
        onCancel: {}
    )
}

#Preview("With Calendar Events") {
    MeetingStartView(
        activeCalendarEvents: [
            CalendarEvent(
                googleEventId: "test1",
                calendarAccountId: UUID(),
                title: "Weekly Team Standup",
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600)
            )
        ],
        onStart: { _, _ in },
        onCancel: {}
    )
}

#Preview("Calendar Meeting Start") {
    CalendarMeetingStartView(
        eventTitle: "Weekly Team Standup",
        onStart: { _ in },
        onCancel: {}
    )
}
