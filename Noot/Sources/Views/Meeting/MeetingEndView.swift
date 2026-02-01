import SwiftUI
import GRDB

struct MeetingEndView: View {
    let meeting: Meeting
    let onDismiss: () -> Void

    @State private var title: String = ""
    @State private var selectedContexts: Set<UUID> = []
    @State private var availableContexts: [Context] = []
    @State private var searchText: String = ""
    @FocusState private var isTitleFocused: Bool

    private var filteredContexts: [Context] {
        if searchText.isEmpty {
            return availableContexts
        }
        return availableContexts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(NootTheme.cyan)
                    .font(.title2)
                    .neonGlow(NootTheme.cyan, radius: 6)
                Text("MEETING ENDED")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(NootTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Rectangle()
                .fill(NootTheme.cyan.opacity(0.3))
                .frame(height: 1)

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Duration info
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(NootTheme.textMuted)
                    if let duration = meeting.duration {
                        Text("Duration: \(formatDuration(duration))")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textMuted)
                    }
                    Spacer()
                }

                // Title field
                VStack(alignment: .leading, spacing: 4) {
                    Text("MEETING TITLE")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                    TextField("Enter a title...", text: $title)
                        .font(NootTheme.monoFont)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(NootTheme.surface)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(NootTheme.cyan.opacity(0.3), lineWidth: 1)
                        )
                        .focused($isTitleFocused)
                }

                // Context picker
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ASSIGN CONTEXTS")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textMuted)
                        Spacer()
                        if !selectedContexts.isEmpty {
                            Text("\(selectedContexts.count) selected")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.cyan)
                        }
                    }

                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(NootTheme.textMuted)
                        TextField("Search contexts...", text: $searchText)
                            .font(NootTheme.monoFontSmall)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(NootTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(NootTheme.surface)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(NootTheme.cyan.opacity(0.3), lineWidth: 1)
                    )

                    if availableContexts.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .font(.title2)
                                .foregroundColor(NootTheme.textMuted)
                            Text("No contexts available")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else if filteredContexts.isEmpty {
                        Text("No matching contexts")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(filteredContexts) { context in
                                    MeetingEndContextRow(
                                        context: context,
                                        isSelected: selectedContexts.contains(context.id)
                                    ) {
                                        toggleContext(context.id)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: 200)
                        .background(NootTheme.surface)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(NootTheme.cyan.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
            .padding()

            Rectangle()
                .fill(NootTheme.cyan.opacity(0.3))
                .frame(height: 1)

            // Actions
            HStack {
                Button("Skip") {
                    onDismiss()
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

                Spacer()

                Button("Save") {
                    saveMeeting()
                }
                .font(NootTheme.monoFont)
                .foregroundColor(NootTheme.background)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(NootTheme.cyan)
                .cornerRadius(4)
                .neonGlow(NootTheme.cyan, radius: 4)
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(width: 380)
        .background(NootTheme.background)
        .onAppear {
            title = meeting.title ?? ""
            isTitleFocused = true
            loadContexts()
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) minutes"
        }
    }

    private func toggleContext(_ id: UUID) {
        if selectedContexts.contains(id) {
            selectedContexts.remove(id)
        } else {
            selectedContexts.insert(id)
        }
    }

    private func loadContexts() {
        do {
            availableContexts = try Database.shared.read { db in
                try Context.active().fetchAll(db)
            }

            // Pre-populate with existing meeting contexts
            let existingContextIds = try Database.shared.read { db in
                try MeetingContext
                    .filter(MeetingContext.Columns.meetingId == meeting.id)
                    .fetchAll(db)
                    .map { $0.contextId }
            }
            selectedContexts = Set(existingContextIds)
        } catch {
            print("Failed to load contexts: \(error)")
        }
    }

    private func saveMeeting() {
        do {
            try Database.shared.write { db in
                // Update meeting title if changed
                if !title.isEmpty {
                    var updatedMeeting = meeting
                    updatedMeeting.title = title
                    try updatedMeeting.update(db)
                }

                // Save context associations
                for contextId in selectedContexts {
                    let meetingContext = MeetingContext(
                        meetingId: meeting.id,
                        contextId: contextId
                    )
                    try? meetingContext.insert(db)
                }
            }
        } catch {
            print("Failed to save meeting: \(error)")
        }

        onDismiss()
    }
}

private struct MeetingEndContextRow: View {
    let context: Context
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? NootTheme.cyan : NootTheme.textMuted)

                Image(systemName: context.type == .domain ? "folder" : "arrow.triangle.branch")
                    .foregroundColor(NootTheme.textMuted)
                    .font(.caption)

                Text(context.name)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textPrimary)

                Spacer()

                Text(context.type.rawValue)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? NootTheme.cyan.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MeetingEndView(
        meeting: Meeting(title: nil, startedAt: Date().addingTimeInterval(-3600), endedAt: Date())
    ) {
        print("Dismissed")
    }
}
