import SwiftUI

struct IntegrationsPreferencesView: View {
    @ObservedObject private var notionService = NotionSyncService.shared
    @ObservedObject private var calendarService = CalendarSyncService.shared

    @State private var notionApiToken: String = ""

    @State private var notionAutoSync: Bool = UserPreferences.shared.notionAutoSyncEnabled
    @State private var notionSyncInterval: Int = UserPreferences.shared.notionAutoSyncIntervalMinutes
    @State private var notionSyncArchived: Bool = UserPreferences.shared.notionSyncArchivedNotes

    @State private var isConnecting: Bool = false
    @State private var isSyncing: Bool = false
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showingSyncSuccess: Bool = false
    @State private var syncReport: NotionSyncReport?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Notion Section
                notionSection

                Divider()
                    .background(NootTheme.textMuted)

                // Google Calendar Section
                calendarSection
            }
            .padding(20)
        }
        .background(NootTheme.background)
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Sync Complete", isPresented: $showingSyncSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            if let report = syncReport {
                Text("Created: \(report.notesCreated)\nUpdated: \(report.notesUpdated)\nFailed: \(report.notesFailed)")
            }
        }
    }

    // MARK: - Notion Section

    private var notionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(NootTheme.cyan)
                Text("Notion")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
            }

            Text("Sync your notes to a Notion database for easy access and sharing.")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textSecondary)

            if notionService.isConnected {
                notionConnectedView
            } else {
                notionSetupView
            }
        }
    }

    private var notionSetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("To sync with Notion, create an internal integration:")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text("1.")
                        .foregroundColor(NootTheme.cyan)
                    Text("Go to notion.so/my-integrations and create a new integration")
                }
                HStack(alignment: .top) {
                    Text("2.")
                        .foregroundColor(NootTheme.cyan)
                    Text("Copy the \"Internal Integration Secret\"")
                }
                HStack(alignment: .top) {
                    Text("3.")
                        .foregroundColor(NootTheme.cyan)
                    Text("In Notion, share a database with your integration")
                }
            }
            .font(NootTheme.monoFontSmall)
            .foregroundColor(NootTheme.textMuted)

            Button(action: openNotionIntegrations) {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("Open Notion Integrations")
                }
            }
            .buttonStyle(NeonButtonStyle(color: NootTheme.textSecondary))

            Divider()
                .background(NootTheme.textMuted)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Internal Integration Secret")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
                SecureField("ntn_... or secret_...", text: $notionApiToken)
                    .textFieldStyle(NeonTextFieldStyle())
            }

            Button(action: connectNotion) {
                HStack {
                    if isConnecting {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Image(systemName: "link")
                    Text(isConnecting ? "Connecting..." : "Connect Notion")
                }
            }
            .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))
            .disabled(notionApiToken.isEmpty || isConnecting)
        }
    }

    private var notionConnectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Connection status
            if let sync = notionService.getConnectedSync() {
                HStack {
                    NeonStatusIndicator(status: .active, label: nil)
                    VStack(alignment: .leading) {
                        Text("Connected to \(sync.workspaceName ?? "Notion")")
                            .font(NootTheme.monoFont)
                            .foregroundColor(NootTheme.textPrimary)
                        if let dbName = sync.databaseName {
                            Text("Database: \(dbName)")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textMuted)
                        }
                    }
                    Spacer()
                    Button("Disconnect") {
                        disconnectNotion()
                    }
                    .buttonStyle(NeonButtonStyle(color: NootTheme.error))
                }
                .padding()
                .background(NootTheme.surface)
                .cornerRadius(8)

                if let lastSync = notionService.lastSync {
                    Text("Last synced: \(lastSync.formatted())")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }
            }

            // Sync actions
            HStack(spacing: 12) {
                Button(action: syncNow) {
                    HStack {
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Image(systemName: "arrow.clockwise")
                        Text(isSyncing ? "Syncing..." : "Sync Now")
                    }
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.cyan))
                .disabled(isSyncing)

                Button(action: forceResync) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Force Resync")
                    }
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.warning))
                .disabled(isSyncing)

                Button(action: openInNotion) {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open in Notion")
                    }
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.textSecondary))
            }

            // Sync progress
            if let progress = notionService.syncProgress, isSyncing {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.fractionCompleted)
                        .progressViewStyle(.linear)
                        .tint(NootTheme.cyan)
                    HStack {
                        Text(progress.phase)
                        if let noteName = progress.currentNote {
                            Text("- \(noteName)")
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
                }
            }

            Divider()
                .background(NootTheme.textMuted)
                .padding(.vertical, 8)

            // Settings
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $notionAutoSync) {
                    VStack(alignment: .leading) {
                        Text("Auto-sync")
                            .font(NootTheme.monoFont)
                            .foregroundColor(NootTheme.textPrimary)
                        Text("Automatically sync notes to Notion")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textMuted)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: NootTheme.cyan))
                .onChange(of: notionAutoSync) { newValue in
                    UserPreferences.shared.notionAutoSyncEnabled = newValue
                    if newValue {
                        notionService.startAutoSync()
                    } else {
                        notionService.stopAutoSync()
                    }
                }

                if notionAutoSync {
                    HStack {
                        Text("Sync every")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textSecondary)
                        Picker("", selection: $notionSyncInterval) {
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                            Text("2 hours").tag(120)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: notionSyncInterval) { newValue in
                            UserPreferences.shared.notionAutoSyncIntervalMinutes = newValue
                            if notionAutoSync {
                                notionService.startAutoSync()
                            }
                        }
                    }
                }

                Toggle(isOn: $notionSyncArchived) {
                    Text("Include archived notes")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.textPrimary)
                }
                .toggleStyle(SwitchToggleStyle(tint: NootTheme.cyan))
                .onChange(of: notionSyncArchived) { newValue in
                    UserPreferences.shared.notionSyncArchivedNotes = newValue
                    try? notionService.updateSyncSettings(syncArchived: newValue)
                }
            }

            // Error display
            if let error = notionService.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(NootTheme.error)
                    Text(error.localizedDescription)
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.error)
                }
            }
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(NootTheme.magenta)
                Text("Google Calendar")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
            }

            if calendarService.isConnected {
                if let account = calendarService.getConnectedAccount() {
                    HStack {
                        NeonStatusIndicator(status: .active, label: nil)
                        Text("Connected as \(account.email)")
                            .font(NootTheme.monoFont)
                            .foregroundColor(NootTheme.textPrimary)
                    }
                    .padding()
                    .background(NootTheme.surface)
                    .cornerRadius(8)

                    Text("Calendar settings are available in the Calendar tab.")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }
            } else {
                Text("Google Calendar is not connected. Set it up in Preferences > General > Calendar.")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textSecondary)
            }
        }
    }

    // MARK: - Actions

    private func openNotionIntegrations() {
        if let url = URL(string: "https://www.notion.so/my-integrations") {
            NSWorkspace.shared.open(url)
        }
    }

    private func connectNotion() {
        isConnecting = true

        Task {
            do {
                try await notionService.connectWithToken(notionApiToken)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }

            await MainActor.run {
                isConnecting = false
            }
        }
    }

    private func disconnectNotion() {
        do {
            try notionService.disconnect()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func syncNow() {
        isSyncing = true

        Task {
            do {
                let report = try await notionService.syncAll { progress in
                    // Progress is handled by the published property
                }

                await MainActor.run {
                    syncReport = report
                    showingSyncSuccess = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }

            await MainActor.run {
                isSyncing = false
            }
        }
    }

    private func forceResync() {
        isSyncing = true

        Task {
            do {
                // Clear all sync states first
                try notionService.clearSyncStates()

                // Then sync all notes
                let report = try await notionService.syncAll { progress in
                    // Progress is handled by the published property
                }

                await MainActor.run {
                    syncReport = report
                    showingSyncSuccess = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }

            await MainActor.run {
                isSyncing = false
            }
        }
    }

    private func openInNotion() {
        guard let sync = notionService.getConnectedSync() else { return }

        // Open the database in Notion
        let cleanId = sync.databaseId.replacingOccurrences(of: "-", with: "")
        if let url = URL(string: "https://notion.so/\(cleanId)") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    IntegrationsPreferencesView()
        .frame(width: 500, height: 700)
        .preferredColorScheme(.dark)
}
