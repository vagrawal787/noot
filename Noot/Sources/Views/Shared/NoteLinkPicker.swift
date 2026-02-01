import SwiftUI
import GRDB

struct NoteLinkPicker: View {
    let sourceNoteId: UUID
    let onSelect: (Note, NoteLinkRelationship) -> Void

    @State private var searchText: String = ""
    @State private var notes: [Note] = []
    @State private var selectedRelationship: NoteLinkRelationship = .related
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search notes...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)

            Divider()

            // Relationship picker
            Picker("Relationship", selection: $selectedRelationship) {
                Text("Related").tag(NoteLinkRelationship.related)
                Text("Continues").tag(NoteLinkRelationship.continues)
                Text("Informed by").tag(NoteLinkRelationship.informedBy)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            // Notes list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredNotes) { note in
                        NoteLinkRow(note: note) {
                            onSelect(note, selectedRelationship)
                            dismiss()
                        }
                    }

                    if filteredNotes.isEmpty {
                        Text("No matching notes")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 400, height: 400)
        .onAppear {
            loadNotes()
        }
    }

    private var filteredNotes: [Note] {
        let filtered = notes.filter { $0.id != sourceNoteId }
        if searchText.isEmpty {
            return filtered
        }
        return filtered.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    private func loadNotes() {
        do {
            notes = try Database.shared.read { db in
                try Note
                    .filter(Note.Columns.archived == false)
                    .order(Note.Columns.updatedAt.desc)
                    .limit(100)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to load notes: \(error)")
        }
    }
}

struct NoteLinkRow: View {
    let note: Note
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.content.prefix(100))
                    .lineLimit(2)
                    .foregroundColor(.primary)

                Text(note.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NoteLinkPicker(sourceNoteId: UUID()) { note, relationship in
        print("Selected: \(note.id) with relationship: \(relationship)")
    }
}
