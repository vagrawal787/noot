import SwiftUI
import GRDB
import AppKit

struct QuickContextPicker: View {
    @Binding var selectedContexts: Set<UUID>
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    @State private var contexts: [Context] = []
    @State private var searchText: String = ""
    @State private var focusedIndex: Int = 0
    @State private var eventMonitor: Any?
    @State private var previousApp: NSRunningApplication?
    @FocusState private var isSearchFocused: Bool

    private var filteredContexts: [Context] {
        if searchText.isEmpty {
            return contexts
        }
        return contexts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(NootTheme.cyan)
                    .font(.system(size: 12, design: .monospaced))

                TextField("", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(NootTheme.monoFont)
                    .foregroundColor(NootTheme.textPrimary)
                    .focused($isSearchFocused)
                    .placeholder(when: searchText.isEmpty) {
                        Text("Search contexts...")
                            .font(NootTheme.monoFont)
                            .foregroundColor(NootTheme.textMuted)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NootTheme.surface)

            // Divider with glow
            Rectangle()
                .fill(NootTheme.cyan.opacity(0.3))
                .frame(height: 1)

            // Context list
            if filteredContexts.isEmpty {
                VStack(spacing: 8) {
                    Text("NO CONTEXTS FOUND")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                    if !searchText.isEmpty {
                        Text("[ENTER] to save without context")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textMuted.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NootTheme.background)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredContexts.enumerated()), id: \.element.id) { index, context in
                                QuickContextRow(
                                    context: context,
                                    isSelected: selectedContexts.contains(context.id),
                                    isFocused: index == focusedIndex
                                ) {
                                    toggleContext(context.id)
                                }
                                .id(context.id)
                            }
                        }
                        .padding(6)
                    }
                    .background(NootTheme.background)
                    .onChange(of: focusedIndex) { newIndex in
                        if newIndex < filteredContexts.count {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(filteredContexts[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }

            // Divider with glow
            Rectangle()
                .fill(NootTheme.cyan.opacity(0.3))
                .frame(height: 1)

            // Keyboard hints
            HStack {
                HStack(spacing: 4) {
                    KeyHint(key: "ESC")
                    Text("INBOX")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }

                Spacer()

                HStack(spacing: 4) {
                    KeyHint(key: "SPC")
                    Text("SELECT")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }

                Spacer()

                HStack(spacing: 4) {
                    KeyHint(key: "RET")
                    Text("SAVE")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.cyan)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NootTheme.surface)
        }
        .frame(width: 300, height: 240)
        .background(NootTheme.background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(NootTheme.cyan.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: NootTheme.cyan.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            loadContexts()
            isSearchFocused = true
            setupKeyboardMonitor()

            // Store the currently active app before we steal focus
            previousApp = NSWorkspace.shared.frontmostApplication

            // Activate the app and bring window to front for keyboard focus
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.keyWindow {
                window.makeKey()
            }
        }
        .onDisappear {
            removeKeyboardMonitor()
            restorePreviousApp()
        }
        .onChange(of: searchText) { _ in
            focusedIndex = 0
        }
    }

    private func setupKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return handleKeyEvent(event)
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func restorePreviousApp() {
        // Return focus to the app that was active before the picker appeared
        if let app = previousApp, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate(options: [])
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 126: // Arrow Up
            moveSelection(by: -1)
            return nil // Consume the event
        case 125: // Arrow Down
            moveSelection(by: 1)
            return nil
        case 49: // Space
            toggleFocusedContext()
            return nil
        case 53: // Escape
            onDismiss()
            return nil
        case 36, 76: // Return, Enter
            onConfirm()
            return nil
        default:
            return event // Let other keys pass through (for typing in search)
        }
    }

    private func toggleContext(_ id: UUID) {
        if selectedContexts.contains(id) {
            selectedContexts.remove(id)
        } else {
            selectedContexts.insert(id)
        }
    }

    private func toggleFocusedContext() {
        guard focusedIndex < filteredContexts.count else { return }
        let context = filteredContexts[focusedIndex]
        toggleContext(context.id)
    }

    private func moveSelection(by offset: Int) {
        let newIndex = focusedIndex + offset
        if newIndex >= 0 && newIndex < filteredContexts.count {
            focusedIndex = newIndex
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
}

struct QuickContextRow: View {
    let context: Context
    let isSelected: Bool
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isSelected ? context.themeColor : NootTheme.textMuted)

                // Context type icon
                Image(systemName: context.iconName)
                    .font(.system(size: 10))
                    .foregroundColor(context.themeColor.opacity(0.8))

                // Context name
                Text(context.name.uppercased())
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(isFocused ? NootTheme.textPrimary : NootTheme.textSecondary)
                    .lineLimit(1)

                Spacer()

                // Pinned indicator
                if context.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundColor(NootTheme.textMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isFocused ? context.themeColor.opacity(0.15) : (isSelected ? context.themeColor.opacity(0.08) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isFocused ? context.themeColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct KeyHint: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(NootTheme.cyan)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(NootTheme.cyan.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(NootTheme.cyan.opacity(0.3), lineWidth: 0.5)
            )
    }
}

#Preview {
    ZStack {
        NootTheme.background
            .ignoresSafeArea()

        QuickContextPicker(
            selectedContexts: .constant([]),
            onConfirm: {},
            onDismiss: {}
        )
    }
    .preferredColorScheme(.dark)
}
