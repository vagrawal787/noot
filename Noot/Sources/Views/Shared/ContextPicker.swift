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
                    .foregroundColor(.secondary)
                TextField("Search or create context...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if filteredContexts.isEmpty && !searchText.isEmpty {
                            showCreateNew = true
                        }
                    }
            }
            .padding(8)

            Divider()

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
                            }
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 280, height: 300)
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
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Image(systemName: context.type == .domain ? "folder" : "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(context.name)
                    .foregroundColor(.primary)

                Spacer()

                if context.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
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
            Text("Create Context")
                .font(.headline)

            TextField("Name", text: $contextName)
                .textFieldStyle(.roundedBorder)

            Picker("Type", selection: $contextType) {
                Text("Domain").tag(ContextType.domain)
                Text("Workstream").tag(ContextType.workstream)
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Create") {
                    createContext()
                }
                .buttonStyle(.borderedProminent)
                .disabled(contextName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
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

#Preview {
    ContextPicker(selectedContexts: .constant([]))
}
