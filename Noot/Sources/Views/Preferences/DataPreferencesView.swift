import SwiftUI

// Wrapper for sheet(item:) to work properly
struct ImportPreviewItem: Identifiable {
    let id = UUID()
    let preview: ImportPreview
    let url: URL
}

struct DataPreferencesView: View {
    @State private var includeAttachments: Bool = UserPreferences.shared.exportIncludeAttachments
    @State private var includeArchived: Bool = UserPreferences.shared.exportIncludeArchived
    @State private var organizeBy: MarkdownExportOptions.OrganizeBy = MarkdownExportOptions.OrganizeBy(rawValue: UserPreferences.shared.exportOrganizeBy) ?? .context

    @State private var autoBackupEnabled: Bool = UserPreferences.shared.autoBackupEnabled
    @State private var autoBackupInterval: Int = UserPreferences.shared.autoBackupIntervalDays
    @State private var autoBackupLocation: String = UserPreferences.shared.autoBackupLocation ?? defaultBackupLocation

    @State private var isExporting: Bool = false
    @State private var isImporting: Bool = false
    @State private var exportProgress: ExportProgress?
    @State private var importProgress: ImportProgress?

    @State private var showingExportSuccess: Bool = false
    @State private var showingImportSuccess: Bool = false
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var exportedURL: URL?
    @State private var importReport: ImportReport?

    @State private var importPreviewItem: ImportPreviewItem?

    private static var defaultBackupLocation: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Noot Backups", isDirectory: true).path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Backup & Restore Section
                backupSection

                Divider()
                    .background(NootTheme.textMuted)

                // Export Section
                exportSection

                Divider()
                    .background(NootTheme.textMuted)

                // Import Section
                importSection
            }
            .padding(20)
        }
        .background(NootTheme.background)
        .alert("Export Complete", isPresented: $showingExportSuccess) {
            Button("Show in Finder") {
                if let url = exportedURL {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            if let url = exportedURL {
                Text("Export saved to:\n\(url.lastPathComponent)")
            }
        }
        .alert("Import Complete", isPresented: $showingImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            if let report = importReport {
                Text("Imported \(report.notesImported) notes, \(report.contextsImported) contexts, \(report.meetingsImported) meetings, \(report.attachmentsImported) attachments.")
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(item: $importPreviewItem) { item in
            ImportPreviewSheet(
                preview: item.preview,
                importURL: item.url,
                onImport: { mode in
                    importPreviewItem = nil
                    performImport(from: item.url, mode: mode)
                },
                onCancel: {
                    importPreviewItem = nil
                }
            )
        }
    }

    // MARK: - Backup Section

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundColor(NootTheme.cyan)
                Text("Backup & Restore")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
            }

            Text("Create a full backup of all your notes, contexts, meetings, and attachments.")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textSecondary)

            HStack(spacing: 12) {
                Button(action: exportFullBackup) {
                    HStack {
                        if isExporting && exportProgress?.phase.contains("attachments") != true {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Image(systemName: "square.and.arrow.up")
                        Text(isExporting ? "Exporting..." : "Export Full Backup")
                    }
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))
                .disabled(isExporting || isImporting)

                Button(action: importFullBackup) {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Image(systemName: "square.and.arrow.down")
                        Text(isImporting ? "Importing..." : "Import Backup")
                    }
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.magenta))
                .disabled(isExporting || isImporting)
            }

            if let progress = exportProgress, isExporting {
                HStack {
                    ProgressView(value: progress.fractionCompleted)
                        .progressViewStyle(.linear)
                        .tint(NootTheme.cyan)
                    Text(progress.phase)
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }
            }

            // Last backup info
            if let lastBackup = UserPreferences.shared.lastBackupDate {
                Text("Last backup: \(lastBackup.formatted())")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
            }

            Divider()
                .background(NootTheme.textMuted)
                .padding(.vertical, 8)

            // Auto-backup settings
            Toggle(isOn: $autoBackupEnabled) {
                VStack(alignment: .leading) {
                    Text("Auto-backup")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.textPrimary)
                    Text("Automatically create backups on a schedule")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: NootTheme.cyan))
            .onChange(of: autoBackupEnabled) { newValue in
                UserPreferences.shared.autoBackupEnabled = newValue
            }

            if autoBackupEnabled {
                HStack {
                    Text("Backup every")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textSecondary)
                    Picker("", selection: $autoBackupInterval) {
                        Text("1 day").tag(1)
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: autoBackupInterval) { newValue in
                        UserPreferences.shared.autoBackupIntervalDays = newValue
                    }
                }

                HStack {
                    Text("Location:")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textSecondary)
                    Text(autoBackupLocation)
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change...") {
                        selectBackupLocation()
                    }
                    .buttonStyle(NeonButtonStyle(color: NootTheme.textSecondary))
                }
            }
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(NootTheme.magenta)
                Text("Export to Markdown")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
            }

            Text("Export notes as human-readable markdown files for use with other apps.")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textSecondary)

            // Export options
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $includeAttachments) {
                    Text("Include attachments")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.textPrimary)
                }
                .toggleStyle(SwitchToggleStyle(tint: NootTheme.cyan))
                .onChange(of: includeAttachments) { newValue in
                    UserPreferences.shared.exportIncludeAttachments = newValue
                }

                Toggle(isOn: $includeArchived) {
                    Text("Include archived notes")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.textPrimary)
                }
                .toggleStyle(SwitchToggleStyle(tint: NootTheme.cyan))
                .onChange(of: includeArchived) { newValue in
                    UserPreferences.shared.exportIncludeArchived = newValue
                }

                HStack {
                    Text("Organize by")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textSecondary)
                    Picker("", selection: $organizeBy) {
                        ForEach(MarkdownExportOptions.OrganizeBy.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: organizeBy) { newValue in
                        UserPreferences.shared.exportOrganizeBy = newValue.rawValue
                    }
                }
            }
            .padding()
            .background(NootTheme.surface)
            .cornerRadius(8)

            Button(action: exportMarkdown) {
                HStack {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Image(systemName: "arrow.down.doc")
                    Text(isExporting ? "Exporting..." : "Export to Markdown")
                }
            }
            .buttonStyle(NeonButtonStyle(color: NootTheme.magenta))
            .disabled(isExporting || isImporting)
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundColor(NootTheme.cyan)
                Text("Import")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
            }

            Text("Import notes from markdown files or a Noot backup.")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textSecondary)

            HStack(spacing: 12) {
                Button(action: importMarkdownFolder) {
                    HStack {
                        Image(systemName: "folder")
                        Text("Import Markdown Folder")
                    }
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))
                .disabled(isExporting || isImporting)
            }

            // Drop zone hint
            HStack {
                Image(systemName: "arrow.down.circle.dotted")
                    .foregroundColor(NootTheme.textMuted)
                Text("Or drag and drop .md files here")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundColor(NootTheme.textMuted)
            )
        }
    }

    // MARK: - Actions

    private func exportFullBackup() {
        let panel = NSSavePanel()
        panel.title = "Export Full Backup"
        panel.nameFieldStringValue = "noot-backup"
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            DispatchQueue.main.async {
                isExporting = true
                exportProgress = ExportProgress(phase: "Starting...", current: 0, total: 1)
            }

            Task {
                do {
                    let exportURL = try await ExportService.shared.exportFull(to: url.deletingLastPathComponent()) { progress in
                        Task { @MainActor in
                            exportProgress = progress
                        }
                    }

                    await MainActor.run {
                        isExporting = false
                        exportProgress = nil
                        exportedURL = exportURL
                        showingExportSuccess = true
                        UserPreferences.shared.lastBackupDate = Date()
                    }
                } catch {
                    await MainActor.run {
                        isExporting = false
                        exportProgress = nil
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
        }
    }

    private func importFullBackup() {
        let panel = NSOpenPanel()
        panel.title = "Import Backup"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let preview = try ImportService.shared.validateExport(at: url)
                DispatchQueue.main.async {
                    importPreviewItem = ImportPreviewItem(preview: preview, url: url)
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func performImport(from url: URL, mode: ImportMode) {
        isImporting = true
        importProgress = ImportProgress(phase: "Starting...", current: 0, total: 1)

        Task {
            do {
                let report = try await ImportService.shared.importFull(from: url, mode: mode) { progress in
                    Task { @MainActor in
                        importProgress = progress
                    }
                }

                await MainActor.run {
                    isImporting = false
                    importProgress = nil
                    importReport = report
                    showingImportSuccess = true
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importProgress = nil
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.title = "Export to Markdown"
        panel.nameFieldStringValue = "noot-export"
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let options = MarkdownExportOptions(
                includeAttachments: includeAttachments,
                includeArchived: includeArchived,
                organizeBy: organizeBy
            )

            DispatchQueue.main.async {
                isExporting = true
                exportProgress = ExportProgress(phase: "Starting...", current: 0, total: 1)
            }

            Task {
                do {
                    let exportURL = try await ExportService.shared.exportMarkdown(to: url.deletingLastPathComponent(), options: options) { progress in
                        Task { @MainActor in
                            exportProgress = ExportProgress(phase: progress.phase, current: progress.current, total: progress.total)
                        }
                    }

                    await MainActor.run {
                        isExporting = false
                        exportProgress = nil
                        exportedURL = exportURL
                        showingExportSuccess = true
                    }
                } catch {
                    await MainActor.run {
                        isExporting = false
                        exportProgress = nil
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
        }
    }

    private func importMarkdownFolder() {
        let panel = NSOpenPanel()
        panel.title = "Import Markdown Files"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let options = MarkdownImportOptions(
                createContextsFromFolders: true,
                parseFrontmatter: true,
                importImages: true
            )

            DispatchQueue.main.async {
                isImporting = true
                importProgress = ImportProgress(phase: "Starting...", current: 0, total: 1)
            }

            Task {
                do {
                    let report = try await ImportService.shared.importMarkdown(from: url, options: options) { progress in
                        Task { @MainActor in
                            importProgress = progress
                        }
                    }

                    await MainActor.run {
                        isImporting = false
                        importProgress = nil
                        importReport = report
                        showingImportSuccess = true
                    }
                } catch {
                    await MainActor.run {
                        isImporting = false
                        importProgress = nil
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
        }
    }

    private func selectBackupLocation() {
        let panel = NSOpenPanel()
        panel.title = "Select Backup Location"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                autoBackupLocation = url.path
                UserPreferences.shared.autoBackupLocation = url.path
            }
        }
    }
}

#Preview {
    DataPreferencesView()
        .frame(width: 500, height: 700)
        .preferredColorScheme(.dark)
}
