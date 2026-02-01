import SwiftUI
import GRDB

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @State private var inboxCount: Int = 0
    @State private var pinnedContexts: [Context] = []
    @State private var domains: [Context] = []
    @State private var workstreams: [Context] = []
    @State private var showContextManager: Bool = false

    var body: some View {
        List {
            Section {
                SidebarRowView(
                    title: "Inbox",
                    icon: "tray",
                    badge: inboxCount > 0 ? inboxCount : nil,
                    isSelected: selection == .inbox
                ) {
                    selection = .inbox
                }

                SidebarRowView(
                    title: "All Notes",
                    icon: "note.text",
                    isSelected: selection == .allNotes
                ) {
                    selection = .allNotes
                }
            }

            if !pinnedContexts.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedContexts) { context in
                        SidebarContextRow(
                            context: context,
                            isSelected: selection == .context(context),
                            onSelect: { selection = .context(context) },
                            onUpdate: { loadData() }
                        )
                    }
                }
            }

            if !domains.isEmpty {
                Section("Domains") {
                    ForEach(domains) { context in
                        SidebarContextRow(
                            context: context,
                            isSelected: selection == .context(context),
                            onSelect: { selection = .context(context) },
                            onUpdate: { loadData() }
                        )
                    }
                }
            }

            if !workstreams.isEmpty {
                Section("Workstreams") {
                    ForEach(workstreams) { context in
                        SidebarContextRow(
                            context: context,
                            isSelected: selection == .context(context),
                            onSelect: { selection = .context(context) },
                            onUpdate: { loadData() }
                        )
                    }
                }
            }

            Section {
                SidebarRowView(
                    title: "Meetings",
                    icon: "person.2",
                    isSelected: selection == .meetings
                ) {
                    selection = .meetings
                }

                SidebarRowView(
                    title: "Archive",
                    icon: "archivebox",
                    isSelected: selection == .archive
                ) {
                    selection = .archive
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(NootTheme.background)
        .safeAreaInset(edge: .bottom) {
            Button(action: { showContextManager = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.caption)
                    Text("MANAGE CONTEXTS")
                        .font(NootTheme.monoFontSmall)
                }
                .foregroundColor(NootTheme.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(NootTheme.textMuted.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .onAppear {
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextsDidChange)) { _ in
            loadData()
        }
        .sheet(isPresented: $showContextManager) {
            ContextManagerView()
        }
        .onChange(of: showContextManager) { isShowing in
            if !isShowing {
                // Reload data when context manager closes
                loadData()
            }
        }
    }

    private func loadData() {
        do {
            try Database.shared.read { db in
                inboxCount = try Note.ungrouped().fetchCount(db)
                pinnedContexts = try Context.pinned().fetchAll(db)
                domains = try Context
                    .filter(Context.Columns.type == ContextType.domain.rawValue)
                    .filter(Context.Columns.pinned == false)
                    .filter(Context.Columns.archived == false)
                    .order(Context.Columns.name)
                    .fetchAll(db)
                workstreams = try Context
                    .filter(Context.Columns.type == ContextType.workstream.rawValue)
                    .filter(Context.Columns.pinned == false)
                    .filter(Context.Columns.archived == false)
                    .order(Context.Columns.name)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to load sidebar data: \(error)")
        }
    }
}

enum SidebarItem: Hashable, Equatable {
    case inbox
    case allNotes
    case context(Context)
    case meetings
    case archive

    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        switch (lhs, rhs) {
        case (.inbox, .inbox): return true
        case (.allNotes, .allNotes): return true
        case (.meetings, .meetings): return true
        case (.archive, .archive): return true
        case (.context(let lContext), .context(let rContext)): return lContext.id == rContext.id
        default: return false
        }
    }
}

struct SidebarRowView: View {
    let title: String
    let icon: String
    var badge: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(isSelected ? NootTheme.cyan : NootTheme.textMuted)
                    .frame(width: 20)
                Text(title)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(isSelected ? NootTheme.textPrimary : NootTheme.textSecondary)
                Spacer()
                if let badge = badge {
                    Text("\(badge)")
                        .font(NootTheme.monoFontSmall)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(NootTheme.magenta.opacity(0.2))
                        )
                        .foregroundColor(NootTheme.magenta)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? NootTheme.cyan.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? NootTheme.cyan.opacity(0.4) : Color.clear, lineWidth: 1)
                )
                .padding(.horizontal, 4)
        )
    }
}

struct SidebarContextRow: View {
    let context: Context
    let isSelected: Bool
    let onSelect: () -> Void
    let onUpdate: () -> Void

    @State private var showRenameSheet = false
    @State private var newName = ""

    private var contextColor: Color {
        context.type == .domain ? NootTheme.cyan : NootTheme.magenta
    }

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: context.type == .domain ? "folder" : "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundColor(isSelected ? contextColor : NootTheme.textMuted)
                    .frame(width: 20)
                Text(context.name)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(isSelected ? NootTheme.textPrimary : NootTheme.textSecondary)
                Spacer()
                if context.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundColor(NootTheme.textMuted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? contextColor.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? contextColor.opacity(0.4) : Color.clear, lineWidth: 1)
                )
                .padding(.horizontal, 4)
        )
        .contextMenu {
            Button(action: togglePin) {
                Label(context.pinned ? "Unpin" : "Pin", systemImage: context.pinned ? "pin.slash" : "pin")
            }

            Button(action: { showRenameSheet = true }) {
                Label("Rename", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive, action: archiveContext) {
                Label("Archive", systemImage: "archivebox")
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameContextSheet(context: context, onSave: { newName in
                renameContext(to: newName)
            })
        }
    }

    private func togglePin() {
        do {
            try Database.shared.write { db in
                var updated = context
                updated.pinned.toggle()
                try updated.update(db)
            }
            onUpdate()
            NotificationCenter.default.post(name: .contextsDidChange, object: nil)
        } catch {
            print("Failed to toggle pin: \(error)")
        }
    }

    private func renameContext(to newName: String) {
        do {
            try Database.shared.write { db in
                var updated = context
                updated.name = newName
                try updated.update(db)
            }
            onUpdate()
            NotificationCenter.default.post(name: .contextsDidChange, object: nil)
        } catch {
            print("Failed to rename context: \(error)")
        }
    }

    private func archiveContext() {
        do {
            try Database.shared.write { db in
                var updated = context
                updated.archived = true
                try updated.update(db)
            }
            onUpdate()
            NotificationCenter.default.post(name: .contextsDidChange, object: nil)
        } catch {
            print("Failed to archive context: \(error)")
        }
    }
}

struct RenameContextSheet: View {
    let context: Context
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("RENAME CONTEXT")
                .font(NootTheme.monoFontLarge)
                .foregroundColor(NootTheme.textPrimary)

            TextField("Name", text: $name)
                .font(NootTheme.monoFont)
                .textFieldStyle(.plain)
                .padding(10)
                .background(NootTheme.surface)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(NootTheme.cyan.opacity(0.4), lineWidth: 1)
                )
                .focused($isFocused)

            HStack {
                Button("CANCEL") {
                    dismiss()
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.textMuted))

                Button("SAVE") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onSave(trimmed)
                    }
                    dismiss()
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(NootTheme.background)
        .onAppear {
            name = context.name
            isFocused = true
        }
    }
}

#Preview {
    SidebarView(selection: .constant(.inbox))
        .frame(width: 250)
}
