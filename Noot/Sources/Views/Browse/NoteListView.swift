import SwiftUI
import GRDB

struct NoteListView: View {
    let sidebarItem: SidebarItem?
    @Binding var selectedNote: Note?
    @State private var notes: [Note] = []
    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header showing current view
            HStack {
                Text(sidebarItemTitle.uppercased())
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.cyan)
                Spacer()
                Text("\(notes.count)")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(NootTheme.surface)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NootTheme.backgroundLight)

            Rectangle()
                .fill(NootTheme.cyan.opacity(0.3))
                .frame(height: 1)

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(NootTheme.cyan.opacity(0.6))
                TextField("Search notes...", text: $searchText)
                    .font(NootTheme.monoFontSmall)
                    .textFieldStyle(.plain)
                    .foregroundColor(NootTheme.textPrimary)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(NootTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(NootTheme.surface.opacity(0.5))

            Rectangle()
                .fill(NootTheme.cyan.opacity(0.2))
                .frame(height: 1)

            // Notes list
            if notes.isEmpty {
                emptyState
            } else {
                List(selection: $selectedNote) {
                    ForEach(filteredNotes) { note in
                        NoteListRow(note: note, isSelected: selectedNote?.id == note.id)
                            .tag(note)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedNote = note
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(NootTheme.background)
            }
        }
        .background(NootTheme.background)
        .onAppear {
            loadNotes()
        }
        .onChange(of: sidebarItem) { _ in
            loadNotes()
            selectedNote = nil
        }
    }

    private var sidebarItemTitle: String {
        switch sidebarItem {
        case .inbox: return "Inbox"
        case .allNotes: return "All Notes"
        case .context(let ctx): return ctx.name
        case .meetings: return "Meetings"
        case .calendar: return "Calendar"
        case .archive: return "Archive"
        case .none: return "Notes"
        }
    }

    private var filteredNotes: [Note] {
        if searchText.isEmpty {
            return notes
        }
        return notes.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 36))
                .foregroundColor(NootTheme.cyan.opacity(0.5))
                .neonGlow(NootTheme.cyan, radius: 6)
            Text("NO NOTES")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NootTheme.background)
    }

    private func loadNotes() {
        do {
            notes = try Database.shared.read { db in
                switch sidebarItem {
                case .inbox:
                    return try Note.ungrouped().fetchAll(db)
                case .allNotes:
                    return try Note
                        .filter(Note.Columns.archived == false)
                        .order(Note.Columns.updatedAt.desc)
                        .fetchAll(db)
                case .context(let context):
                    let contextId = context.id
                    let noteContexts = try NoteContext
                        .filter(NoteContext.Columns.contextId == contextId)
                        .fetchAll(db)
                    let noteIds = noteContexts.map { $0.noteId }
                    return try Note
                        .filter(noteIds.contains(Note.Columns.id))
                        .filter(Note.Columns.archived == false)
                        .order(Note.Columns.updatedAt.desc)
                        .fetchAll(db)
                case .archive:
                    return try Note
                        .filter(Note.Columns.archived == true)
                        .order(Note.Columns.updatedAt.desc)
                        .fetchAll(db)
                case .meetings, .calendar, .none:
                    return []
                }
            }
        } catch {
            print("Failed to load notes: \(error)")
        }
    }
}

struct NoteListRow: View {
    let note: Note
    var isSelected: Bool = false

    // Check if note contains images
    private var hasImages: Bool {
        note.content.contains("![")
    }

    // Get text content without image markdown
    private var textContent: String {
        note.content.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]+\)"#, with: "[img]", options: .regularExpression)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(textContent.prefix(100))
                .lineLimit(2)
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textPrimary)

            HStack(spacing: 8) {
                Text(note.createdAt, style: .relative)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(NootTheme.textMuted)

                if hasImages {
                    Image(systemName: "photo")
                        .font(.system(size: 9))
                        .foregroundColor(NootTheme.magenta.opacity(0.7))
                }

                if note.isOpen {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(NootTheme.success)
                            .frame(width: 5, height: 5)
                        Text("OPEN")
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundColor(NootTheme.success)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(NootTheme.success.opacity(0.15))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .listRowBackground(isSelected ? NootTheme.cyan.opacity(0.15) : NootTheme.background)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }
}

#Preview {
    NoteListView(sidebarItem: .allNotes, selectedNote: .constant(nil))
        .frame(width: 300)
}
