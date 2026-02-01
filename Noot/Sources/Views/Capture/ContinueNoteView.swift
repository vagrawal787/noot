import SwiftUI
import GRDB

struct ContinueNoteView: View {
    @State private var recentNotes: [Note] = []
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("CONTINUE NOTE")
                        .font(NootTheme.monoFontLarge)
                        .foregroundColor(NootTheme.cyan)
                    Spacer()
                    Text("\(filteredNotes.count)")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(NootTheme.surface)
                        )
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Search/filter bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(NootTheme.cyan.opacity(0.6))
                    TextField("Search recent notes...", text: $searchText)
                        .font(NootTheme.monoFontSmall)
                        .textFieldStyle(.plain)
                        .foregroundColor(NootTheme.textPrimary)
                        .focused($isSearchFocused)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(NootTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(NootTheme.surface.opacity(0.5))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(NootTheme.cyan.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Rectangle()
                    .fill(NootTheme.cyan.opacity(0.3))
                    .frame(height: 1)

                // Notes list
                if filteredNotes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.system(size: 32))
                            .foregroundColor(NootTheme.cyan.opacity(0.5))
                            .neonGlow(NootTheme.cyan, radius: 8)
                        Text("NO RECENT NOTES")
                            .font(NootTheme.monoFont)
                            .foregroundColor(NootTheme.textMuted)
                        Text("Create a new note with Option+Space")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textMuted.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filteredNotes) { note in
                                ContinueNoteRow(note: note) {
                                    selectNote(note)
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }

            // Scan lines overlay
            ScanLines(spacing: 3, opacity: 0.03)
                .allowsHitTesting(false)
        }
        .frame(width: 500, height: 380)
        .background(
            ZStack {
                NootTheme.background
                LinearGradient(
                    colors: [NootTheme.cyan.opacity(0.03), NootTheme.magenta.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [NootTheme.cyan.opacity(0.5), NootTheme.magenta.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: NootTheme.cyan.opacity(0.2), radius: 20, x: 0, y: 0)
        .shadow(color: NootTheme.magenta.opacity(0.1), radius: 30, x: 0, y: 10)
        .onAppear {
            isSearchFocused = true
            loadRecentNotes()
        }
        .background(
            Button("") { dismissWindow() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
        )
    }

    private var filteredNotes: [Note] {
        if searchText.isEmpty {
            return recentNotes
        }
        return recentNotes.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    private func loadRecentNotes() {
        do {
            recentNotes = try Database.shared.read { db in
                // Get notes from current session (today or rolling hours)
                try Note.recentFromSession(hours: 8).limit(20).fetchAll(db)
            }
        } catch {
            print("Failed to load recent notes: \(error)")
        }
    }

    private func selectNote(_ note: Note) {
        // Post notification with the selected note
        NotificationCenter.default.post(
            name: .continueWithNote,
            object: nil,
            userInfo: ["noteId": note.id]
        )
    }

    private func dismissWindow() {
        NotificationCenter.default.post(name: .hideCaptureWindow, object: nil)
    }
}

struct ContinueNoteRow: View {
    let note: Note
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(note.content.prefix(100))
                    .lineLimit(2)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textPrimary)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    Text(note.updatedAt, style: .relative)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(NootTheme.textMuted)

                    if note.isOpen {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(NootTheme.success)
                                .frame(width: 5, height: 5)
                                .neonGlow(NootTheme.success, radius: 2)
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

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(isHovered ? NootTheme.cyan : NootTheme.textMuted.opacity(0.5))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? NootTheme.cyan.opacity(0.1) : NootTheme.surface.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? NootTheme.cyan.opacity(0.4) : NootTheme.surface, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    ContinueNoteView()
}
