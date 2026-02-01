import SwiftUI
import GRDB

struct ContextManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var contexts: [Context] = []
    @State private var showNewContextSheet: Bool = false
    @State private var editingContext: Context?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Contexts")
                    .font(.headline)
                Spacer()
                Button(action: { showNewContextSheet = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Context list
            if contexts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No contexts yet")
                        .font(.headline)
                    Text("Create contexts to organize your notes and meetings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Create Context") {
                        showNewContextSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    Section("Domains") {
                        ForEach(contexts.filter { $0.type == .domain }) { context in
                            ContextRow(context: context, onEdit: { editingContext = context })
                        }
                    }

                    Section("Workstreams") {
                        ForEach(contexts.filter { $0.type == .workstream }) { context in
                            ContextRow(context: context, onEdit: { editingContext = context })
                        }
                    }

                    if contexts.contains(where: { $0.archived }) {
                        Section("Archived") {
                            ForEach(contexts.filter { $0.archived }) { context in
                                ContextRow(context: context, onEdit: { editingContext = context })
                            }
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
        .onAppear {
            loadContexts()
        }
        .sheet(isPresented: $showNewContextSheet) {
            ContextEditSheet(context: nil, onSave: {
                loadContexts()
            })
        }
        .sheet(item: $editingContext) { context in
            ContextEditSheet(context: context, onSave: {
                loadContexts()
            })
        }
    }

    private func loadContexts() {
        do {
            contexts = try Database.shared.read { db in
                try Context
                    .order(Context.Columns.pinned.desc, Context.Columns.name)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to load contexts: \(error)")
        }
    }
}

struct ContextRow: View {
    let context: Context
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Image(systemName: context.type == .domain ? "folder.fill" : "arrow.triangle.branch")
                .foregroundColor(context.archived ? .secondary : .accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(context.name)
                        .foregroundColor(context.archived ? .secondary : .primary)
                    if context.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                Text(context.type.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

struct ContextEditSheet: View {
    let context: Context?
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var type: ContextType = .domain
    @State private var pinned: Bool = false
    @State private var archived: Bool = false
    @FocusState private var isNameFocused: Bool

    private var isEditing: Bool { context != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Context" : "New Context")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 16) {
                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g., payments-service", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFocused)
                }

                // Type
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Type", selection: $type) {
                        Text("Domain").tag(ContextType.domain)
                        Text("Workstream").tag(ContextType.workstream)
                    }
                    .pickerStyle(.segmented)

                    Text(type == .domain 
                        ? "Long-lived categories (projects, clients, services)"
                        : "Temporary goal-oriented work (migrations, refactors)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Options
                Toggle("Pin to top of sidebar", isOn: $pinned)
                    .font(.callout)

                if isEditing {
                    Toggle("Archived", isOn: $archived)
                        .font(.callout)
                }
            }
            .padding()

            Spacer()

            Divider()

            // Actions
            HStack {
                if isEditing {
                    Button("Delete", role: .destructive) {
                        deleteContext()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(isEditing ? "Save" : "Create") {
                    saveContext()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 350, height: 350)
        .onAppear {
            if let context = context {
                name = context.name
                type = context.type
                pinned = context.pinned
                archived = context.archived
            }
            isNameFocused = true
        }
    }

    private func saveContext() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        do {
            try Database.shared.write { db in
                if var existingContext = context {
                    existingContext.name = trimmedName
                    existingContext.type = type
                    existingContext.pinned = pinned
                    existingContext.archived = archived
                    try existingContext.update(db)
                } else {
                    var newContext = Context(
                        name: trimmedName,
                        type: type,
                        pinned: pinned
                    )
                    try newContext.insert(db)
                }
            }
            onSave()
            dismiss()
        } catch {
            print("Failed to save context: \(error)")
        }
    }

    private func deleteContext() {
        guard let context = context else { return }

        do {
            try Database.shared.write { db in
                try context.delete(db)
            }
            onSave()
            dismiss()
        } catch {
            print("Failed to delete context: \(error)")
        }
    }
}

#Preview {
    ContextManagerView()
}
