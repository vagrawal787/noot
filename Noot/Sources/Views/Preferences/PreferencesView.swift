import SwiftUI

struct PreferencesView: View {
    @State private var selectedTab: PreferencesTab = .general

    enum PreferencesTab: String, CaseIterable {
        case general = "General"
        case data = "Data"
        case integrations = "Integrations"
        case calendar = "Calendar"
        case hotkeys = "Hotkeys"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .data: return "externaldrive"
            case .integrations: return "link"
            case .calendar: return "calendar"
            case .hotkeys: return "keyboard"
            }
        }
    }

    var body: some View {
        HSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 4) {
                ForEach(PreferencesTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        HStack {
                            Image(systemName: tab.icon)
                                .frame(width: 20)
                            Text(tab.rawValue)
                            Spacer()
                        }
                        .font(NootTheme.monoFont)
                        .foregroundColor(selectedTab == tab ? NootTheme.cyan : NootTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? NootTheme.surface : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 150)
            .background(NootTheme.backgroundLight)

            // Content
            VStack {
                switch selectedTab {
                case .general:
                    GeneralPreferencesView()
                case .data:
                    DataPreferencesView()
                case .integrations:
                    IntegrationsPreferencesView()
                case .calendar:
                    CalendarPreferencesView()
                case .hotkeys:
                    HotkeyPreferencesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NootTheme.background)
    }
}

// MARK: - General Preferences

struct GeneralPreferencesView: View {
    @State private var compressionLevel: CompressionLevel = UserPreferences.shared.compressionLevel
    @State private var autoCloseNotes: Bool = UserPreferences.shared.autoCloseNotes
    @State private var autoCloseDelay: Int = UserPreferences.shared.autoCloseDelayMinutes
    @State private var largeFileWarning: Int = UserPreferences.shared.largeFileWarningMB

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Compression Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .foregroundColor(NootTheme.cyan)
                        Text("Media Compression")
                            .font(NootTheme.monoFontLarge)
                            .foregroundColor(NootTheme.textPrimary)
                    }

                    Picker("Compression Level", selection: $compressionLevel) {
                        Text("None").tag(CompressionLevel.none)
                        Text("Low").tag(CompressionLevel.low)
                        Text("Medium").tag(CompressionLevel.medium)
                        Text("High").tag(CompressionLevel.high)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: compressionLevel) { newValue in
                        UserPreferences.shared.compressionLevel = newValue
                    }
                }

                Divider()
                    .background(NootTheme.textMuted)

                // Auto-close Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(NootTheme.magenta)
                        Text("Note Auto-Close")
                            .font(NootTheme.monoFontLarge)
                            .foregroundColor(NootTheme.textPrimary)
                    }

                    Toggle(isOn: $autoCloseNotes) {
                        Text("Automatically close notes after inactivity")
                            .font(NootTheme.monoFont)
                            .foregroundColor(NootTheme.textPrimary)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: NootTheme.cyan))
                    .onChange(of: autoCloseNotes) { newValue in
                        UserPreferences.shared.autoCloseNotes = newValue
                    }

                    if autoCloseNotes {
                        HStack {
                            Text("Close after")
                                .font(NootTheme.monoFontSmall)
                                .foregroundColor(NootTheme.textSecondary)
                            Picker("", selection: $autoCloseDelay) {
                                Text("5 minutes").tag(5)
                                Text("15 minutes").tag(15)
                                Text("30 minutes").tag(30)
                                Text("1 hour").tag(60)
                            }
                            .pickerStyle(.menu)
                            .onChange(of: autoCloseDelay) { newValue in
                                UserPreferences.shared.autoCloseDelayMinutes = newValue
                            }
                        }
                    }
                }

                Divider()
                    .background(NootTheme.textMuted)

                // File Size Warning
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(NootTheme.warning)
                        Text("File Size Warning")
                            .font(NootTheme.monoFontLarge)
                            .foregroundColor(NootTheme.textPrimary)
                    }

                    HStack {
                        Text("Warn when recordings exceed")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textSecondary)
                        Picker("", selection: $largeFileWarning) {
                            Text("50 MB").tag(50)
                            Text("100 MB").tag(100)
                            Text("250 MB").tag(250)
                            Text("500 MB").tag(500)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: largeFileWarning) { newValue in
                            UserPreferences.shared.largeFileWarningMB = newValue
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .background(NootTheme.background)
    }
}

// MARK: - Hotkey Preferences

struct HotkeyPreferencesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Image(systemName: "keyboard")
                        .foregroundColor(NootTheme.cyan)
                    Text("Keyboard Shortcuts")
                        .font(NootTheme.monoFontLarge)
                        .foregroundColor(NootTheme.textPrimary)
                }

                Text("Hotkey customization coming soon. Current shortcuts:")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    HotkeyRow(action: "New Note", shortcut: "⌥ Space")
                    HotkeyRow(action: "Continue Note", shortcut: "⌘⌥ Space")
                    HotkeyRow(action: "Screenshot", shortcut: "⌘⌥ 2")
                    HotkeyRow(action: "Screen Recording", shortcut: "⌘⌥ 3")
                    HotkeyRow(action: "Toggle Meeting", shortcut: "⌘⌥ M")
                    HotkeyRow(action: "Open Inbox", shortcut: "⌘⌥ I")
                    HotkeyRow(action: "Open Noot", shortcut: "⌘⌥ O")
                    HotkeyRow(action: "Close Note", shortcut: "⇧ Escape")
                }
                .padding()
                .background(NootTheme.surface)
                .cornerRadius(8)

                Spacer()
            }
            .padding(20)
        }
        .background(NootTheme.background)
    }
}

struct HotkeyRow: View {
    let action: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(action)
                .font(NootTheme.monoFont)
                .foregroundColor(NootTheme.textPrimary)
            Spacer()
            Text(shortcut)
                .font(NootTheme.monoFont)
                .foregroundColor(NootTheme.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(NootTheme.backgroundLight)
                .cornerRadius(4)
        }
    }
}

#Preview {
    PreferencesView()
        .frame(width: 550, height: 650)
        .preferredColorScheme(.dark)
}
