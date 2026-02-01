import SwiftUI
import GRDB

struct ContextPicker: View {
    @Binding var selectedContexts: Set<UUID>
    @State private var contexts: [Context] = []
    @State private var searchText: String = ""
    @State private var showCreateNew: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(NootTheme.cyan)
                TextField("Search or create context...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(NootTheme.monoFont)
                    .foregroundColor(NootTheme.textPrimary)
                    .onSubmit {
                        if filteredContexts.isEmpty && !searchText.isEmpty {
                            showCreateNew = true
                        }
                    }
            }
            .padding(8)
            .background(NootTheme.surface)

            Rectangle()
                .fill(NootTheme.cyan.opacity(0.3))
                .frame(height: 1)

            // Context list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredContexts) { context in
                        ContextPickerRow(
                            context: context,
                            isSelected: selectedContexts.contains(context.id)
                        ) {
                            toggleContext(context.id)
                        }
                    }

                    if filteredContexts.isEmpty && !searchText.isEmpty {
                        Button(action: { showCreateNew = true }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Create \"\(searchText)\"")
                                    .font(NootTheme.monoFontSmall)
                            }
                            .foregroundColor(NootTheme.cyan)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
                .padding(8)
            }
            .background(NootTheme.background)
        }
        .frame(width: 280, height: 300)
        .background(NootTheme.background)
        .onAppear {
            loadContexts()
        }
        .sheet(isPresented: $showCreateNew) {
            CreateContextSheet(name: searchText) { newContext in
                contexts.append(newContext)
                selectedContexts.insert(newContext.id)
                searchText = ""
            }
        }
    }

    private var filteredContexts: [Context] {
        if searchText.isEmpty {
            return contexts
        }
        return contexts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
            contexts = try Database.shared.read { db in
                try Context.active().fetchAll(db)
            }
        } catch {
            print("Failed to load contexts: \(error)")
        }
    }
}

struct ContextPickerRow: View {
    let context: Context
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? context.themeColor : NootTheme.textMuted)

                Image(systemName: context.iconName)
                    .font(.caption)
                    .foregroundColor(context.themeColor.opacity(0.7))

                Text(context.name)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textPrimary)

                Spacer()

                if context.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundColor(NootTheme.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? context.themeColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CreateContextSheet: View {
    let name: String
    let onCreate: (Context) -> Void

    @State private var contextName: String = ""
    @State private var contextType: ContextType = .domain
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("CREATE CONTEXT")
                .font(NootTheme.monoFontLarge)
                .foregroundColor(NootTheme.cyan)

            TextField("Name", text: $contextName)
                .textFieldStyle(.plain)
                .font(NootTheme.monoFont)
                .foregroundColor(NootTheme.textPrimary)
                .padding(10)
                .background(NootTheme.surface)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(NootTheme.cyan.opacity(0.4), lineWidth: 1)
                )

            HStack(spacing: 12) {
                TypeButton(
                    label: "DOMAIN",
                    icon: "folder.fill",
                    isSelected: contextType == .domain,
                    color: NootTheme.cyan
                ) {
                    contextType = .domain
                }

                TypeButton(
                    label: "WORKSTREAM",
                    icon: "arrow.triangle.branch",
                    isSelected: contextType == .workstream,
                    color: NootTheme.magenta
                ) {
                    contextType = .workstream
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
                .disabled(contextName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(NootTheme.background)
        .onAppear {
            contextName = name
        }
    }

    private func createContext() {
        let context = Context(name: contextName, type: contextType)

        do {
            try Database.shared.write { db in
                var record = context
                try record.insert(db)
            }
            onCreate(context)
            dismiss()
        } catch {
            print("Failed to create context: \(error)")
        }
    }
}

private struct TypeButton: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(NootTheme.monoFontSmall)
            }
            .foregroundColor(isSelected ? color : NootTheme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? color.opacity(0.15) : NootTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color.opacity(0.6) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContextPicker(selectedContexts: .constant([]))
        .preferredColorScheme(.dark)
}
