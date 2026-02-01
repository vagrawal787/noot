import SwiftUI
import GRDB

struct MainWindowView: View {
    @State private var selectedSidebarItem: SidebarItem? = .allNotes
    @State private var selectedNote: Note?
    @State private var selectedMeeting: Meeting?

    var body: some View {
        Group {
            if selectedSidebarItem == .calendar {
                // Two-column layout for calendar (sidebar + calendar view)
                NavigationSplitView {
                    SidebarView(selection: $selectedSidebarItem)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
                } detail: {
                    MeetingCalendarView()
                        .id("calendar")
                }
            } else {
                // Three-column layout for everything else
                NavigationSplitView {
                    SidebarView(selection: $selectedSidebarItem)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
                } content: {
                    if selectedSidebarItem == .meetings {
                        MeetingListView(selectedMeeting: $selectedMeeting)
                            .id("meetings")
                            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
                    } else {
                        NoteListView(sidebarItem: selectedSidebarItem, selectedNote: $selectedNote)
                            .id(sidebarItemId)
                            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
                    }
                } detail: {
                    if selectedSidebarItem == .meetings {
                        if let meeting = selectedMeeting {
                            MeetingView(meeting: meeting)
                                .id(meeting.id)
                        } else {
                            CyberEmptyState(
                                icon: "person.2",
                                title: "SELECT MEETING",
                                subtitle: "Choose a meeting from the list"
                            )
                        }
                    } else if let note = selectedNote {
                        NoteDetailView(note: note)
                            .id(note.id)
                    } else {
                        CyberEmptyState(
                            icon: "note.text",
                            title: "SELECT NOTE",
                            subtitle: "Choose a note to view contents"
                        )
                    }
                }
            }
        }
        .background(NootTheme.background)
        .frame(minWidth: 800, minHeight: 500)
        .onChange(of: selectedSidebarItem) { _ in
            // Clear selections when switching sidebar items
            selectedNote = nil
            selectedMeeting = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToNote)) { notification in
            if let noteId = notification.userInfo?["noteId"] as? UUID {
                navigateToNote(noteId)
            }
        }
    }

    private func navigateToNote(_ noteId: UUID) {
        do {
            if let note = try Database.shared.read({ db in
                try Note.fetchOne(db, key: noteId)
            }) {
                // Switch to All Notes to ensure the note is visible
                selectedSidebarItem = .allNotes
                // Small delay to let the view update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    selectedNote = note
                }
            }
        } catch {
            print("Failed to navigate to note: \(error)")
        }
    }

    // Generate a unique ID for each sidebar item to force view refresh
    private var sidebarItemId: String {
        switch selectedSidebarItem {
        case .inbox: return "inbox"
        case .allNotes: return "allNotes"
        case .context(let ctx): return "context-\(ctx.id.uuidString)"
        case .meetings: return "meetings"
        case .calendar: return "calendar"
        case .archive: return "archive"
        case .none: return "none"
        }
    }
}

// MARK: - Cyber Empty State

struct CyberEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(NootTheme.cyan.opacity(0.6))
                .neonGlow(NootTheme.cyan, radius: 8)

            Text(title)
                .font(NootTheme.monoFontLarge)
                .foregroundColor(NootTheme.textPrimary)

            Text(subtitle)
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NootTheme.background)
    }
}

#Preview {
    MainWindowView()
}
