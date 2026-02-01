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
                    .foregroundColor(.green)
                    .font(.title2)
                Text("Meeting Ended")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Duration info
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    if let duration = meeting.duration {
                        Text("Duration: \(formatDuration(duration))")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .font(.caption)

                // Title field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meeting Title")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Enter a title...", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTitleFocused)
                }

                // Context picker
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Assign to Contexts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if !selectedContexts.isEmpty {
                            Text("\(selectedContexts.count) selected")
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                        }
                    }

                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search contexts...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.textBackgroundColor))
                    )

                    if availableContexts.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("No contexts available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else if filteredContexts.isEmpty {
                        Text("No matching contexts")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.controlBackgroundColor))
                        )
                    }
                }
            }
            .padding()

            Divider()

            // Actions
            HStack {
                Button("Skip") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Save") {
                    saveMeeting()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(width: 380)
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
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Image(systemName: context.type == .domain ? "folder" : "arrow.triangle.branch")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Text(context.name)
                    .foregroundColor(.primary)

                Spacer()

                Text(context.type.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
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
