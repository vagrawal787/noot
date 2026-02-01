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
                Spacer()
                if inboxCount > 0 {
                    Text("\(inboxCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                Text("⌘⌥I")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
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

            MenuBarButton(title: "Preferences...", shortcut: "Cmd+,") {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.openPreferences()
                }
            }

            Divider()

            MenuBarButton(title: "Quit Noot", shortcut: "Cmd+Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 220)
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
                Spacer()
                Text(shortcut)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
}
