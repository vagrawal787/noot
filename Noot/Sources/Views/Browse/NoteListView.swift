import SwiftUI
import GRDB

struct NoteListView: View {
    let sidebarItem: SidebarItem?
    @Binding var selectedNote: Note?
    @State private var noteItems: [NoteListItem] = []
    @State private var searchText: String = ""
    @State private var isLoadingMore: Bool = false
    @State private var hasMoreNotes: Bool = true
    @State private var currentOffset: Int = 0
    private let pageSize: Int = 50

    var body: some View {
        VStack(spacing: 0) {
            // Header showing current view
            HStack {
                Text(sidebarItemTitle.uppercased())
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.cyan)
                Spacer()
                Text("\(noteItems.count)\(hasMoreNotes ? "+" : "")")
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
            if noteItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredNotes) { item in
                            NoteListRow(item: item, isSelected: selectedNote?.id == item.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    loadFullNote(id: item.id)
                                }
                                .onAppear {
                                    // Load more when approaching the end
                                    if item.id == filteredNotes.last?.id && hasMoreNotes && !isLoadingMore {
                                        loadMoreNotes()
                                    }
                                }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding()
                        }
                    }
                }
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

    private var filteredNotes: [NoteListItem] {
        if searchText.isEmpty {
            return noteItems
        }
        return noteItems.filter { $0.contentPreview.localizedCaseInsensitiveContains(searchText) }
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
        currentOffset = 0
        hasMoreNotes = true

        do {
            let filter = noteListFilter
            let items = try Database.shared.read { db in
                try NoteListItem.fetch(db: db, filter: filter, limit: pageSize, offset: 0)
            }
            noteItems = items
            hasMoreNotes = items.count == pageSize
        } catch {
            print("Failed to load notes: \(error)")
        }
    }

    private func loadMoreNotes() {
        guard hasMoreNotes, !isLoadingMore else { return }
        isLoadingMore = true
        currentOffset += pageSize

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let filter = noteListFilter
                let items = try Database.shared.read { db in
                    try NoteListItem.fetch(db: db, filter: filter, limit: pageSize, offset: currentOffset)
                }

                DispatchQueue.main.async {
                    noteItems.append(contentsOf: items)
                    hasMoreNotes = items.count == pageSize
                    isLoadingMore = false
                }
            } catch {
                DispatchQueue.main.async {
                    print("Failed to load more notes: \(error)")
                    isLoadingMore = false
                }
            }
        }
    }

    private func loadFullNote(id: UUID) {
        do {
            if let note = try Database.shared.read({ db in
                try Note.fetchOne(db, key: id)
            }) {
                selectedNote = note
            }
        } catch {
            print("Failed to load full note: \(error)")
        }
    }

    private var noteListFilter: NoteListFilter {
        switch sidebarItem {
        case .inbox:
            return .inbox
        case .allNotes:
            return .all
        case .context(let context):
            return .context(context.id)
        case .archive:
            return .archived
        case .meetings, .calendar, .none:
            return .all
        }
    }
}

struct NoteListRow: View {
    let item: NoteListItem
    var isSelected: Bool = false

    // Get text content without image markdown
    private var textContent: String {
        item.contentPreview.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]+\)"#, with: "[img]", options: .regularExpression)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(textContent.prefix(100))
                .lineLimit(2)
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textPrimary)

            HStack(spacing: 8) {
                Text(item.createdAt, style: .relative)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(NootTheme.textMuted)

                if item.hasImages {
                    Image(systemName: "photo")
                        .font(.system(size: 9))
                        .foregroundColor(NootTheme.magenta.opacity(0.7))
                }

                if item.isOpen {
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
        .background(isSelected ? NootTheme.cyan.opacity(0.15) : NootTheme.background)
    }
}

#Preview {
    NoteListView(sidebarItem: .allNotes, selectedNote: .constant(nil))
        .frame(width: 300)
}
