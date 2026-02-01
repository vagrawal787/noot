import SwiftUI
import GRDB

struct InboxView: View {
    @State private var notes: [Note] = []
    @State private var currentIndex: Int = 0
    @State private var contexts: [Context] = []
    @State private var showContextPicker: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var swipeDirection: SwipeDirection? = nil

    enum SwipeDirection {
        case left, right, up
    }

    var body: some View {
        VStack {
            if notes.isEmpty {
                emptyState
            } else {
                cardView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(NootTheme.background)
        .onAppear {
            loadNotes()
            loadContexts()
        }
        // Keyboard shortcuts
        .background(
            Group {
                Button("") { skipNote() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .hidden()
                Button("") { showContextPicker = true }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .hidden()
                Button("") { archiveNote() }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .hidden()
            }
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(NootTheme.cyan.opacity(0.6))
                .neonGlow(NootTheme.cyan, radius: 10)
            Text("INBOX CLEAR")
                .font(NootTheme.monoFontLarge)
                .foregroundColor(NootTheme.textPrimary)
            Text("All notes organized")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NootTheme.background)
    }

    @ViewBuilder
    private var cardView: some View {
        VStack(spacing: 16) {
            // Progress indicator
            VStack(spacing: 4) {
                HStack {
                    Text("\(currentIndex + 1) / \(notes.count)")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.cyan)
                    Spacer()
                    Text("← SKIP • → ASSIGN • ↑ ARCHIVE")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }

                // Cyber progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(NootTheme.surface)
                            .frame(height: 4)
                            .cornerRadius(2)

                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [NootTheme.cyan, NootTheme.magenta],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: notes.count > 0 ? geometry.size.width * (CGFloat(currentIndex + 1) / CGFloat(notes.count)) : 0, height: 4)
                            .cornerRadius(2)
                            .shadow(color: NootTheme.cyan.opacity(0.5), radius: 4, x: 0, y: 0)
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal)

            // Note card with swipe gesture
            if currentIndex < notes.count {
                NoteCardView(note: notes[currentIndex])
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                                // Determine swipe direction
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    swipeDirection = value.translation.width > 0 ? .right : .left
                                } else if value.translation.height < -50 {
                                    swipeDirection = .up
                                }
                            }
                            .onEnded { value in
                                let threshold: CGFloat = 100
                                withAnimation(.spring()) {
                                    if value.translation.width > threshold {
                                        // Swipe right - assign contexts
                                        showContextPicker = true
                                    } else if value.translation.width < -threshold {
                                        // Swipe left - skip
                                        skipNote()
                                    } else if value.translation.height < -threshold {
                                        // Swipe up - archive
                                        archiveNote()
                                    }
                                    dragOffset = .zero
                                    swipeDirection = nil
                                }
                            }
                    )
                    .overlay(swipeOverlay)
                    .animation(.spring(), value: dragOffset)

                // Action buttons
                HStack(spacing: 24) {
                    CyberActionButton(
                        icon: "arrow.left",
                        label: "SKIP",
                        color: NootTheme.textMuted
                    ) {
                        skipNote()
                    }

                    CyberActionButton(
                        icon: "archivebox",
                        label: "ARCHIVE",
                        color: NootTheme.warning
                    ) {
                        archiveNote()
                    }

                    CyberActionButton(
                        icon: "tag",
                        label: "ASSIGN",
                        color: NootTheme.cyan
                    ) {
                        showContextPicker = true
                    }
                }
                .padding(.top, 16)
            }
        }
        .padding()
        .sheet(isPresented: $showContextPicker) {
            ContextPickerSheet(
                contexts: contexts,
                onSelect: { selectedContexts in
                    assignContexts(selectedContexts)
                }
            )
        }
    }

    @ViewBuilder
    private var swipeOverlay: some View {
        ZStack {
            // Left swipe indicator (skip)
            if dragOffset.width < -30 {
                HStack {
                    Spacer()
                    VStack {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.system(size: 40))
                            .neonGlow(NootTheme.textMuted, radius: 6)
                        Text("SKIP")
                            .font(NootTheme.monoFontSmall)
                    }
                    .foregroundColor(NootTheme.textMuted)
                    .opacity(min(1.0, abs(dragOffset.width) / 100.0))
                    .padding()
                }
            }

            // Right swipe indicator (assign)
            if dragOffset.width > 30 {
                HStack {
                    VStack {
                        Image(systemName: "tag.circle.fill")
                            .font(.system(size: 40))
                            .neonGlow(NootTheme.cyan, radius: 6)
                        Text("ASSIGN")
                            .font(NootTheme.monoFontSmall)
                    }
                    .foregroundColor(NootTheme.cyan)
                    .opacity(min(1.0, dragOffset.width / 100.0))
                    .padding()
                    Spacer()
                }
            }

            // Up swipe indicator (archive)
            if dragOffset.height < -30 {
                VStack {
                    Spacer()
                    VStack {
                        Image(systemName: "archivebox.circle.fill")
                            .font(.system(size: 40))
                            .neonGlow(NootTheme.warning, radius: 6)
                        Text("ARCHIVE")
                            .font(NootTheme.monoFontSmall)
                    }
                    .foregroundColor(NootTheme.warning)
                    .opacity(min(1.0, abs(dragOffset.height) / 100.0))
                    .padding()
                }
            }
        }
    }

    private func loadNotes() {
        do {
            notes = try Database.shared.read { db in
                try Note.ungrouped().fetchAll(db)
            }
        } catch {
            print("Failed to load notes: \(error)")
        }
    }

    private func loadContexts() {
        do {
            contexts = try Database.shared.read { db in
                try Context.active().fetchAll(db)
            }
        } catch {
            print("Failed to load contexts: \(error)")
        }
    }

    private func skipNote() {
        withAnimation {
            if currentIndex < notes.count - 1 {
                currentIndex += 1
            } else {
                // Wrap around or close
                currentIndex = 0
            }
        }
    }

    private func archiveNote() {
        guard currentIndex < notes.count else { return }
        var note = notes[currentIndex]
        note.archived = true

        do {
            try Database.shared.write { db in
                try note.update(db)
            }
            notes.remove(at: currentIndex)
            if currentIndex >= notes.count && notes.count > 0 {
                currentIndex = notes.count - 1
            }
        } catch {
            print("Failed to archive note: \(error)")
        }
    }

    private func assignContexts(_ contextIds: Set<UUID>) {
        guard currentIndex < notes.count else { return }
        let note = notes[currentIndex]

        do {
            try Database.shared.write { db in
                for contextId in contextIds {
                    let noteContext = NoteContext(noteId: note.id, contextId: contextId)
                    try noteContext.insert(db)
                }
            }
            notes.remove(at: currentIndex)
            if currentIndex >= notes.count && notes.count > 0 {
                currentIndex = notes.count - 1
            }
        } catch {
            print("Failed to assign contexts: \(error)")
        }
    }
}

struct NoteCardView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with timestamp and status
            HStack {
                Text(note.createdAt, format: .dateTime.weekday().month().day().hour().minute())
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)

                Spacer()

                if note.isOpen {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(NootTheme.success)
                            .frame(width: 6, height: 6)
                            .neonGlow(NootTheme.success, radius: 3)
                        Text("OPEN")
                            .font(NootTheme.monoFontSmall)
                    }
                    .foregroundColor(NootTheme.success)
                }
            }

            Rectangle()
                .fill(NootTheme.cyan.opacity(0.3))
                .frame(height: 1)

            // Content with inline images
            ScrollView {
                MarkdownNoteView(content: note.content, onNoteLinkTap: { noteId in
                    NotificationCenter.default.post(
                        name: .navigateToNote,
                        object: nil,
                        userInfo: ["noteId": noteId]
                    )
                })
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 250, maxHeight: 400)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(NootTheme.surface)
                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [NootTheme.cyan.opacity(0.02), NootTheme.magenta.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [NootTheme.cyan.opacity(0.4), NootTheme.magenta.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: NootTheme.cyan.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: NootTheme.magenta.opacity(0.1), radius: 20, x: 0, y: 10)
    }
}

struct CyberActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .neonGlow(color, radius: 4)
                Text(label)
                    .font(NootTheme.monoFontSmall)
            }
            .foregroundColor(color)
            .frame(width: 80, height: 60)
        }
        .buttonStyle(.plain)
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .foregroundColor(color)
            .frame(width: 80, height: 60)
        }
        .buttonStyle(.plain)
    }
}

struct ContextPickerSheet: View {
    let contexts: [Context]
    let onSelect: (Set<UUID>) -> Void
    @State private var selectedContexts: Set<UUID> = []
    @State private var availableContexts: [Context] = []
    @State private var showNewContext: Bool = false
    @State private var focusedIndex: Int = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("ASSIGN CONTEXTS")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
                Spacer()
                Button(action: { showNewContext = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption)
                        Text("NEW")
                            .font(NootTheme.monoFontSmall)
                    }
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.magenta))
            }

            // Help text for keyboard navigation
            Text("↑↓ NAVIGATE • ENTER SELECT • → CONFIRM")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textMuted)

            if availableContexts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.title)
                        .foregroundColor(NootTheme.cyan.opacity(0.5))
                        .neonGlow(NootTheme.cyan, radius: 6)
                    Text("NO CONTEXTS")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                    Button("CREATE CONTEXT") {
                        showNewContext = true
                    }
                    .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))
                }
                .frame(height: 200)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(availableContexts.enumerated()), id: \.element.id) { index, context in
                                InboxContextPickerRow(
                                    context: context,
                                    isSelected: selectedContexts.contains(context.id),
                                    isFocused: index == focusedIndex
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleContext(context.id)
                                    focusedIndex = index
                                }
                            }
                        }
                        .padding()
                    }
                    .frame(height: 300)
                    .onChange(of: focusedIndex) { _ in
                        withAnimation {
                            proxy.scrollTo(focusedIndex, anchor: .center)
                        }
                    }
                }
            }

            HStack {
                Button("CANCEL") {
                    dismiss()
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.textMuted))
                .keyboardShortcut(.escape, modifiers: [])

                Button("ASSIGN [\(selectedContexts.count)]") {
                    confirmSelection()
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))
                .disabled(selectedContexts.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(NootTheme.background)
        .onAppear {
            availableContexts = contexts
            focusedIndex = 0
        }
        // Keyboard navigation
        .background(
            Group {
                // Up arrow - move focus up
                Button("") { moveFocus(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .hidden()
                // Down arrow - move focus down
                Button("") { moveFocus(1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    .hidden()
                // Enter - toggle selection
                Button("") { toggleFocusedContext() }
                    .keyboardShortcut(.return, modifiers: [])
                    .hidden()
                // Space - also toggle selection
                Button("") { toggleFocusedContext() }
                    .keyboardShortcut(.space, modifiers: [])
                    .hidden()
                // Right arrow - confirm and assign
                Button("") { confirmSelection() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .hidden()
                // Left arrow - cancel
                Button("") { dismiss() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .hidden()
            }
        )
        .sheet(isPresented: $showNewContext) {
            QuickContextCreateSheet(onCreated: { newContext in
                availableContexts.append(newContext)
                selectedContexts.insert(newContext.id)
                focusedIndex = availableContexts.count - 1
            })
        }
    }

    private func moveFocus(_ delta: Int) {
        guard !availableContexts.isEmpty else { return }
        let newIndex = focusedIndex + delta
        if newIndex >= 0 && newIndex < availableContexts.count {
            focusedIndex = newIndex
        }
    }

    private func toggleFocusedContext() {
        guard focusedIndex < availableContexts.count else { return }
        let context = availableContexts[focusedIndex]
        toggleContext(context.id)
    }

    private func toggleContext(_ id: UUID) {
        if selectedContexts.contains(id) {
            selectedContexts.remove(id)
        } else {
            selectedContexts.insert(id)
        }
    }

    private func confirmSelection() {
        guard !selectedContexts.isEmpty else { return }
        onSelect(selectedContexts)
        dismiss()
    }
}

struct InboxContextPickerRow: View {
    let context: Context
    let isSelected: Bool
    let isFocused: Bool

    private var contextColor: Color {
        context.type == .domain ? NootTheme.cyan : NootTheme.magenta
    }

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? contextColor : NootTheme.textMuted)
                .neonGlow(isSelected ? contextColor : .clear, radius: isSelected ? 3 : 0)
            Image(systemName: context.type == .domain ? "folder" : "arrow.triangle.branch")
                .font(.caption)
                .foregroundColor(contextColor.opacity(0.7))
            Text(context.name)
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textPrimary)
            Spacer()
            Text(context.type.rawValue.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(NootTheme.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isFocused ? contextColor.opacity(0.15) : (isSelected ? contextColor.opacity(0.1) : NootTheme.surface.opacity(0.5)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? contextColor.opacity(0.6) : (isSelected ? contextColor.opacity(0.3) : Color.clear), lineWidth: 1)
        )
    }
}

struct QuickContextCreateSheet: View {
    let onCreated: (Context) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var type: ContextType = .domain
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("NEW CONTEXT")
                .font(NootTheme.monoFontLarge)
                .foregroundColor(NootTheme.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                Text("NAME")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
                TextField("e.g., payments-service", text: $name)
                    .font(NootTheme.monoFont)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(NootTheme.surface)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(NootTheme.cyan.opacity(0.4), lineWidth: 1)
                    )
                    .focused($isNameFocused)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("TYPE")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
                HStack(spacing: 8) {
                    CyberTypePill(label: "DOMAIN", isSelected: type == .domain, color: NootTheme.cyan) {
                        type = .domain
                    }
                    CyberTypePill(label: "WORKSTREAM", isSelected: type == .workstream, color: NootTheme.magenta) {
                        type = .workstream
                    }
                }
            }

            HStack {
                Button("CANCEL") {
                    dismiss()
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.textMuted))

                Button("CREATE") {
                    createContext()
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(NootTheme.background)
        .onAppear {
            isNameFocused = true
        }
    }

    private func createContext() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        do {
            var newContext = Context(name: trimmedName, type: type)
            try Database.shared.write { db in
                try newContext.insert(db)
            }
            onCreated(newContext)
            NotificationCenter.default.post(name: .contextsDidChange, object: nil)
            dismiss()
        } catch {
            print("Failed to create context: \(error)")
        }
    }
}

struct CyberTypePill: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(NootTheme.monoFontSmall)
                .foregroundColor(isSelected ? color : NootTheme.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? color.opacity(0.2) : NootTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? color.opacity(0.6) : NootTheme.textMuted.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    InboxView()
}
