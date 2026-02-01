import SwiftUI
import GRDB

struct MenuBarView: View {
    @State private var inboxCount: Int = 0
    @ObservedObject private var calendarService = CalendarSyncService.shared
    @ObservedObject private var meetingManager = MeetingManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Calendar event section
            if UserPreferences.shared.showCalendarInMenubar, !calendarService.activeEvents.isEmpty {
                ForEach(calendarService.activeEvents) { event in
                    CalendarEventMenuItem(event: event)
                }
                Divider()
            }

            MenuBarButton(title: "New Note", shortcut: "⌥Space") {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.newNote()
                }
            }

            MenuBarButton(title: "Continue Note", shortcut: "⌘⌥Space") {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.continueNote()
                }
            }

            Divider()

            MenuBarButton(title: meetingManager.isInMeeting ? "End Meeting" : "Start Meeting", shortcut: "⌘⌥M") {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.toggleMeeting()
                }
            }

            Divider()

            HStack {
                Text("Open Inbox")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textPrimary)
                Spacer()
                if inboxCount > 0 {
                    Text("\(inboxCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NootTheme.magenta)
                        .foregroundColor(NootTheme.textPrimary)
                        .clipShape(Capsule())
                }
                Text("⌘⌥I")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.openInbox()
                }
            }

            MenuBarButton(title: "Open Noot", shortcut: "⌘⌥O") {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.openMainWindow()
                }
            }

            Divider()

            MenuBarButton(title: "Preferences...", shortcut: "⌘,") {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.openPreferences()
                }
            }

            Divider()

            MenuBarButton(title: "Quit Noot", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 220)
        .background(NootTheme.background)
        .onAppear {
            loadInboxCount()
        }
    }

    private func loadInboxCount() {
        do {
            inboxCount = try Database.shared.read { db in
                try Note.ungrouped().fetchCount(db)
            }
        } catch {
            print("Failed to load inbox count: \(error)")
        }
    }
}

struct MenuBarButton: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textPrimary)
                Spacer()
                Text(shortcut)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Calendar Event Menu Item

struct CalendarEventMenuItem: View {
    let event: CalendarEvent
    @State private var isHovered: Bool = false

    private var isUpcoming: Bool {
        event.startTime > Date()
    }

    private var statusText: String {
        let now = Date()
        if event.startTime > now {
            // Event is upcoming (within 5 minutes)
            let remaining = event.startTime.timeIntervalSince(now)
            let minutes = Int(remaining / 60) + 1
            return "starts in \(minutes) min"
        } else {
            // Event is currently happening
            let remaining = event.endTime.timeIntervalSince(now)
            if remaining < 60 {
                return "ending soon"
            } else {
                return "until \(event.endTime.formatted(date: .omitted, time: .shortened))"
            }
        }
    }

    private var statusLabel: String {
        isUpcoming ? "Soon" : "Now"
    }

    private var accentColor: Color {
        isUpcoming ? Color.yellow : NootTheme.cyan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isUpcoming ? "clock.badge.exclamationmark" : "calendar.circle.fill")
                    .foregroundColor(accentColor)
                Text("\(statusLabel): \(event.title)")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textPrimary)
                    .lineLimit(1)
            }

            Text(statusText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(NootTheme.textMuted)
                .padding(.leading, 22)

            HStack(spacing: 8) {
                Button(action: startMeetingNotes) {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text.badge.plus")
                        Text("Start notes")
                    }
                    .font(.system(size: 10, design: .monospaced))
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))

                Button(action: ignoreEvent) {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.slash")
                        Text("Ignore")
                    }
                    .font(.system(size: 10, design: .monospaced))
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.textMuted))
            }
            .padding(.leading, 22)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(isHovered ? NootTheme.surfaceLight : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func startMeetingNotes() {
        do {
            try MeetingManager.shared.startMeetingFromCalendarEvent(event)
            NotificationCenter.default.post(name: .showCaptureWindow, object: nil)
        } catch {
            print("Failed to start meeting from calendar: \(error)")
        }
    }

    private func ignoreEvent() {
        do {
            try CalendarSyncService.shared.ignoreEvent(event)
        } catch {
            print("Failed to ignore event: \(error)")
        }
    }
}

#Preview {
    MenuBarView()
        .preferredColorScheme(.dark)
}
