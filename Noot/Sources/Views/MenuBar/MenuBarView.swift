import SwiftUI
import GRDB

struct MenuBarView: View {
    @State private var inboxCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MenuBarButton(title: "New Note", shortcut: "⌥Space") {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.newNote()
                }
            }

            MenuBarButton(title: "Continue Note", shortcut: "⌘⌥Space") {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.continueNote()
                }
            }

            Divider()

            MenuBarButton(title: "Start Meeting", shortcut: "⌘⌥M") {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.toggleMeeting()
                }
            }

            Divider()

            HStack {
                Text("Open Inbox")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textPrimary)
                Spacer()
                if inboxCount > 0 {
                    Text("\(inboxCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NootTheme.magenta)
                        .foregroundColor(NootTheme.textPrimary)
                        .clipShape(Capsule())
                }
                Text("⌘⌥I")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.openInbox()
                }
            }

            MenuBarButton(title: "Open Noot", shortcut: "⌘⌥O") {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.openMainWindow()
                }
            }

            Divider()

            MenuBarButton(title: "Preferences...", shortcut: "⌘,") {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.openPreferences()
                }
            }

            Divider()

            MenuBarButton(title: "Quit Noot", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 220)
        .background(NootTheme.background)
        .onAppear {
            loadInboxCount()
        }
    }

    private func loadInboxCount() {
        do {
            inboxCount = try Database.shared.read { db in
                try Note.ungrouped().fetchCount(db)
            }
        } catch {
            print("Failed to load inbox count: \(error)")
        }
    }
}

struct MenuBarButton: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textPrimary)
                Spacer()
                Text(shortcut)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    MenuBarView()
        .preferredColorScheme(.dark)
}
