import SwiftUI

struct CalendarPreferencesView: View {
    @ObservedObject private var calendarService = CalendarSyncService.shared

    @State private var clientId: String = UserPreferences.shared.googleOAuthCredentials.clientId ?? ""
    @State private var clientSecret: String = UserPreferences.shared.googleOAuthCredentials.clientSecret ?? ""
    @State private var pollInterval: Int = UserPreferences.shared.calendarPollIntervalSeconds
    @State private var syncDaysAhead: Int = UserPreferences.shared.calendarSyncDaysAhead
    @State private var showInMenubar: Bool = UserPreferences.shared.showCalendarInMenubar
    @State private var autoStartMeetingNotes: Bool = UserPreferences.shared.autoStartMeetingNotes

    @State private var isConnecting: Bool = false
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var ignoredEvents: [IgnoredCalendarEvent] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // OAuth Credentials Section
                credentialsSection

                Divider()
                    .background(NootTheme.textMuted)

                // Connection Section
                connectionSection

                if calendarService.isConnected {
                    Divider()
                        .background(NootTheme.textMuted)

                    // Settings Section
                    settingsSection

                    if !ignoredEvents.isEmpty {
                        Divider()
                            .background(NootTheme.textMuted)

                        // Ignored Events Section
                        ignoredEventsSection
                    }
                }
            }
            .padding(20)
        }
        .background(NootTheme.background)
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadIgnoredEvents()
        }
    }

    // MARK: - Credentials Section

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(NootTheme.cyan)
                Text("Google OAuth Credentials")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
            }

            Text("To use Google Calendar, you need to provide your own OAuth credentials from Google Cloud Console.")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Client ID")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
                TextField("", text: $clientId)
                    .textFieldStyle(NeonTextFieldStyle())
                    .onChange(of: clientId) { _ in
                        saveCredentials()
                    }

                Text("Client Secret")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
                SecureField("", text: $clientSecret)
                    .textFieldStyle(NeonTextFieldStyle())
                    .onChange(of: clientSecret) { _ in
                        saveCredentials()
                    }
            }

            Button(action: openGoogleCloudConsole) {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("Open Google Cloud Console")
                }
            }
            .buttonStyle(NeonButtonStyle(color: NootTheme.textSecondary))
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(NootTheme.magenta)
                Text("Calendar Connection")
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

                        Spacer()

                        Button("Disconnect") {
                            disconnect()
                        }
                        .buttonStyle(NeonButtonStyle(color: NootTheme.error))
                    }
                    .padding()
                    .background(NootTheme.surface)
                    .cornerRadius(8)

                    if let lastSync = account.lastSyncAt {
                        Text("Last synced: \(lastSync.formatted())")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textMuted)
                    }

                    if calendarService.isSyncing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Syncing...")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textSecondary)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect your Google Calendar to detect active meetings and associate notes with calendar events.")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textSecondary)

                    if !hasCredentials {
                        Text("Please add your OAuth credentials above first.")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.warning)
                    }

                    Button(action: connect) {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Image(systemName: "link")
                            Text(isConnecting ? "Connecting..." : "Connect Google Calendar")
                        }
                    }
                    .buttonStyle(NeonButtonStyle(color: NootTheme.magenta))
                    .disabled(!hasCredentials || isConnecting)
                }
            }
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "gearshape")
                    .foregroundColor(NootTheme.cyan)
                Text("Calendar Settings")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
            }

            // Poll Interval
            VStack(alignment: .leading, spacing: 4) {
                Text("Check for active events every")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textSecondary)

                HStack {
                    Picker("", selection: $pollInterval) {
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: pollInterval) { newValue in
                        UserPreferences.shared.calendarPollIntervalSeconds = newValue
                    }
                }
            }

            // Sync Days Ahead
            VStack(alignment: .leading, spacing: 4) {
                Text("Sync events for the next")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textSecondary)

                HStack {
                    Picker("", selection: $syncDaysAhead) {
                        Text("1 day").tag(1)
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: syncDaysAhead) { newValue in
                        UserPreferences.shared.calendarSyncDaysAhead = newValue
                    }
                }
            }

            Divider()
                .background(NootTheme.textMuted)

            // Toggle Settings
            Toggle(isOn: $showInMenubar) {
                VStack(alignment: .leading) {
                    Text("Show calendar events in menubar")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.textPrimary)
                    Text("Display current meeting in the Noot menu")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: NootTheme.cyan))
            .onChange(of: showInMenubar) { newValue in
                UserPreferences.shared.showCalendarInMenubar = newValue
            }

            Toggle(isOn: $autoStartMeetingNotes) {
                VStack(alignment: .leading) {
                    Text("Auto-start meeting notes")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.textPrimary)
                    Text("Automatically show capture window when a meeting starts")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: NootTheme.cyan))
            .onChange(of: autoStartMeetingNotes) { newValue in
                UserPreferences.shared.autoStartMeetingNotes = newValue
            }

            // Manual Sync Button
            HStack {
                Button(action: syncNow) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Sync Now")
                    }
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(calendarService.isSyncing)

                if let error = calendarService.lastError {
                    Text(error.localizedDescription)
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.error)
                }
            }
        }
    }

    // MARK: - Ignored Events Section

    private var ignoredEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "eye.slash")
                    .foregroundColor(NootTheme.warning)
                Text("Ignored Events")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
            }

            Text("These events won't appear in your menubar notifications.")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(ignoredEvents) { ignored in
                    HStack {
                        if let eventId = ignored.googleEventId {
                            Text("Event: \(eventId.prefix(20))...")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textMuted)
                        } else if let seriesId = ignored.googleSeriesId {
                            Text("Series: \(seriesId.prefix(20))...")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(8)
            .background(NootTheme.surface)
            .cornerRadius(6)

            Button(action: clearIgnored) {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear All Ignored Events")
                }
            }
            .buttonStyle(NeonButtonStyle(color: NootTheme.warning))
        }
    }

    // MARK: - Helpers

    private var hasCredentials: Bool {
        !clientId.isEmpty && !clientSecret.isEmpty
    }

    private func saveCredentials() {
        UserPreferences.shared.googleOAuthCredentials = GoogleOAuthCredentials(
            clientId: clientId.isEmpty ? nil : clientId,
            clientSecret: clientSecret.isEmpty ? nil : clientSecret
        )
    }

    private func connect() {
        isConnecting = true

        Task {
            do {
                try await calendarService.connectAccount()
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

    private func disconnect() {
        do {
            try calendarService.disconnectAccount()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func syncNow() {
        Task {
            await calendarService.syncEvents()
        }
    }

    private func openGoogleCloudConsole() {
        if let url = URL(string: "https://console.cloud.google.com/apis/credentials") {
            NSWorkspace.shared.open(url)
        }
    }

    private func loadIgnoredEvents() {
        do {
            ignoredEvents = try calendarService.getIgnoredEvents()
        } catch {
            print("Failed to load ignored events: \(error)")
        }
    }

    private func clearIgnored() {
        do {
            try calendarService.clearAllIgnoredEvents()
            loadIgnoredEvents()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

#Preview {
    CalendarPreferencesView()
        .frame(width: 500, height: 700)
        .preferredColorScheme(.dark)
}
