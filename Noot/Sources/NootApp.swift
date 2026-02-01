import SwiftUI
import ApplicationServices

@main
struct NootApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var captureWindow: NSWindow?
    private var captureWindowController: NSWindowController?
    private var continueNoteWindow: NSWindow?
    private var continueNoteWindowController: NSWindowController?
    private var mainWindow: NSWindow?
    private var mainWindowController: NSWindowController?
    private var inboxWindow: NSWindow?
    private var inboxWindowController: NSWindowController?
    private var meetingStatusWindow: NSWindow?
    private var meetingEndWindow: NSWindow?
    private var meetingStartWindow: NSWindow?
    private var meetingMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize database
        do {
            try Database.shared.initialize()
        } catch {
            print("Failed to initialize database: \(error)")
        }

        setupMenuBar()
        setupHotkeys()

        // Start note auto-close service
        NoteAutoCloseService.shared.start()

        // Listen for window notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hideCaptureWindow),
            name: .hideCaptureWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowCaptureWindow),
            name: .showCaptureWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowInbox),
            name: .showInbox,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowMainWindow),
            name: .showMainWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowContinueNote),
            name: .showContinueNote,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleContinueWithNote),
            name: .continueWithNote,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleMeeting),
            name: .toggleMeeting,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissCaptureWindow),
            name: .dismissCaptureWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureWindowResize),
            name: .captureWindowNeedsResize,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureScreenshot),
            name: .captureScreenshot,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleScreenRecording),
            name: .toggleScreenRecording,
            object: nil
        )
    }

    @objc private func handleDismissCaptureWindow() {
        // Post notification to trigger save in the capture window view
        NotificationCenter.default.post(name: .triggerCaptureSave, object: nil)
    }

    @objc private func handleCaptureWindowResize(_ notification: Notification) {
        guard let window = captureWindow,
              let screen = NSScreen.main,
              let newHeight = notification.userInfo?["height"] as? CGFloat else { return }

        let screenFrame = screen.visibleFrame
        let maxHeight = screenFrame.height * 0.7
        let targetHeight = min(newHeight, maxHeight)

        // Only resize if the new height is larger than current
        let currentFrame = window.frame
        if targetHeight > currentFrame.height {
            // Keep the top-right corner anchored
            let padding: CGFloat = 20
            let newY = screenFrame.maxY - targetHeight - padding

            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: newY,
                width: currentFrame.width,
                height: targetHeight
            )

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        }
    }

    @objc private func handleToggleMeeting() {
        toggleMeeting()
    }

    @objc private func handleCaptureScreenshot() {
        ScreenCaptureService.shared.captureScreenshot()
    }

    @objc private func handleToggleScreenRecording() {
        ScreenCaptureService.shared.toggleRecording()
    }

    @objc private func handleShowContinueNote() {
        showContinueNoteWindow()
    }

    @objc private func handleContinueWithNote(_ notification: Notification) {
        // Hide the continue note picker
        continueNoteWindow?.orderOut(nil)

        // Show capture window first
        showCaptureWindow()

        // Post a separate notification to load the note (only the view listens to this)
        // Use a short delay to ensure the view is ready after window creation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: .loadNoteIntoCapture,
                object: nil,
                userInfo: notification.userInfo
            )
        }
    }

    @objc private func handleShowCaptureWindow() {
        showCaptureWindow()
    }

    @objc private func handleShowInbox() {
        openInbox()
    }

    @objc private func handleShowMainWindow() {
        openMainWindow()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Noot")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "New Note", action: #selector(newNote), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Continue Note", action: #selector(continueNote), keyEquivalent: " "))
        menu.addItem(NSMenuItem.separator())

        meetingMenuItem = NSMenuItem(title: "Start Meeting", action: #selector(toggleMeeting), keyEquivalent: "m")
        menu.addItem(meetingMenuItem!)
        menu.addItem(NSMenuItem.separator())

        let inboxItem = NSMenuItem(title: "Open Inbox", action: #selector(openInbox), keyEquivalent: "i")
        menu.addItem(inboxItem)

        menu.addItem(NSMenuItem(title: "Open Noot", action: #selector(openMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Grant Accessibility Permissions...", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Noot", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func setupHotkeys() {
        // Register global hotkeys using HotkeyManager
        HotkeyManager.shared.register()
    }

    @objc func newNote() {
        showCaptureWindow()
    }

    @objc func continueNote() {
        showContinueNoteWindow()
    }

    func showContinueNoteWindow() {
        if continueNoteWindow == nil {
            let contentView = ContinueNoteView()
            let hostingController = NSHostingController(rootView: contentView)

            let window = CapturePanel(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hostingController
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.hidesOnDeactivate = false

            // Center on screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - 250
                let y = screenFrame.midY + 50
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }

            continueNoteWindow = window
            continueNoteWindowController = NSWindowController(window: window)
        }

        continueNoteWindow?.makeKeyAndOrderFront(nil)
        continueNoteWindow?.makeFirstResponder(continueNoteWindow?.contentView)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleMeeting() {
        print("toggleMeeting called, isInMeeting: \(MeetingManager.shared.isInMeeting)")
        if MeetingManager.shared.isInMeeting {
            // End meeting
            do {
                let endedMeeting = try MeetingManager.shared.endMeeting()
                meetingMenuItem?.title = "Start Meeting"
                hideMeetingStatusWindow()
                updateMenuBarIcon(isMeeting: false)
                showMeetingEndPopup(meeting: endedMeeting)
            } catch {
                print("Failed to end meeting: \(error)")
            }
        } else {
            // Show start meeting dialog
            print("Showing start meeting dialog...")
            showMeetingStartDialog()
        }
    }

    private func showMeetingStartDialog() {
        print("showMeetingStartDialog called")
        let contentView = MeetingStartView(
            onStart: { [weak self] audioSource in
                self?.meetingStartWindow?.orderOut(nil)
                self?.startMeetingWithSource(audioSource)
            },
            onCancel: { [weak self] in
                self?.meetingStartWindow?.orderOut(nil)
            }
        )
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Start Meeting"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 320, height: 400))
        window.level = .floating
        window.center()

        meetingStartWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        print("Meeting start window shown: \(window.isVisible), frame: \(window.frame)")
    }

    private func startMeetingWithSource(_ audioSource: AudioSource) {
        do {
            try MeetingManager.shared.startMeeting(recordAudio: true, audioSource: audioSource)
            meetingMenuItem?.title = "End Meeting"
            showMeetingStatusWindow()
            updateMenuBarIcon(isMeeting: true)
        } catch {
            print("Failed to start meeting: \(error)")
        }
    }

    private func showMeetingEndPopup(meeting: Meeting) {
        let contentView = MeetingEndView(meeting: meeting) { [weak self] in
            self?.meetingEndWindow?.orderOut(nil)
        }
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Meeting Ended"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 380, height: 480))
        window.level = .floating

        // Position at top right
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let padding: CGFloat = 20
            let windowSize = window.frame.size
            let x = screenFrame.maxX - windowSize.width - padding
            let y = screenFrame.maxY - windowSize.height - padding
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        meetingEndWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateMenuBarIcon(isMeeting: Bool) {
        if let button = statusItem?.button {
            let symbolName = isMeeting ? "record.circle" : "note.text"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Noot")
            button.image?.isTemplate = !isMeeting
            if isMeeting {
                button.contentTintColor = .red
            } else {
                button.contentTintColor = nil
            }
        }
    }

    private func showMeetingStatusWindow() {
        if meetingStatusWindow == nil {
            let contentView = MeetingStatusView()
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.styleMask = NSWindow.StyleMask.borderless
            window.isOpaque = false
            window.backgroundColor = NSColor.clear
            window.level = NSWindow.Level.floating
            window.collectionBehavior = [NSWindow.CollectionBehavior.canJoinAllSpaces, NSWindow.CollectionBehavior.stationary]
            window.setContentSize(NSSize(width: 180, height: 40))

            // Position in top right of screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.maxX - 200
                let y = screenFrame.maxY - 60
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }

            meetingStatusWindow = window
        }

        meetingStatusWindow?.orderFront(nil)
    }

    private func hideMeetingStatusWindow() {
        meetingStatusWindow?.orderOut(nil)
    }

    @objc func openInbox() {
        if inboxWindow == nil {
            let contentView = InboxView()
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Inbox"
            window.styleMask = [NSWindow.StyleMask.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 700, height: 500))
            window.center()

            inboxWindow = window
            inboxWindowController = NSWindowController(window: window)
        }

        inboxWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openMainWindow() {
        if mainWindow == nil {
            let contentView = MainWindowView()
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Noot"
            window.styleMask = [NSWindow.StyleMask.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 1000, height: 600))
            window.center()

            mainWindow = window
            mainWindowController = NSWindowController(window: window)
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openAccessibilitySettings() {
        // Prompt for accessibility permissions - this opens System Settings
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if trusted {
            print("✅ Accessibility permissions already granted")
        } else {
            print("Opening System Settings for accessibility permissions...")
            print("After enabling, restart Noot for global hotkeys to work")
        }
    }

    @objc func openPreferences() {
        // TODO: Open preferences window
        print("Open preferences - not yet implemented")
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func showCaptureWindow() {
        print("showCaptureWindow called")

        if captureWindow == nil {
            print("  Creating new capture window...")
            let contentView = CaptureWindowView()
            let hostingController = NSHostingController(rootView: contentView)

            // Initial size - comfortable starting size with room to type
            let initialWidth: CGFloat = 400
            let initialHeight: CGFloat = 250

            let window = CapturePanel(
                contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
                styleMask: [.borderless, .fullSizeContentView, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hostingController
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.hidesOnDeactivate = false
            window.isMovableByWindowBackground = true // Allow dragging anywhere

            // Set size constraints
            window.minSize = NSSize(width: 350, height: 200)
            if let screen = NSScreen.main {
                window.maxSize = NSSize(width: screen.visibleFrame.width / 2, height: screen.visibleFrame.height * 0.8)
            }

            // Position at top right of screen - use setFrame to ensure both size and position
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let padding: CGFloat = 20
                let x = screenFrame.maxX - initialWidth - padding
                let y = screenFrame.maxY - initialHeight - padding
                window.setFrame(NSRect(x: x, y: y, width: initialWidth, height: initialHeight), display: true)
                print("  Window frame: (\(x), \(y), \(initialWidth), \(initialHeight))")
                print("  Screen visibleFrame: \(screenFrame)")
            } else {
                print("  ⚠️ No main screen found!")
            }

            captureWindow = window
            captureWindowController = NSWindowController(window: window)
            print("  Window created")
        } else {
            print("  Reusing existing capture window")
            // Reset size and position to top right when reopening
            if let screen = NSScreen.main, let window = captureWindow {
                let screenFrame = screen.visibleFrame
                let padding: CGFloat = 20
                let initialWidth: CGFloat = 400
                let initialHeight: CGFloat = 250
                let x = screenFrame.maxX - initialWidth - padding
                let y = screenFrame.maxY - initialHeight - padding
                window.setFrame(NSRect(x: x, y: y, width: initialWidth, height: initialHeight), display: true)
            }
        }

        print("  Showing window...")
        captureWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Find and focus the text view after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            if let textView = self?.findTextView(in: self?.captureWindow?.contentView) {
                self?.captureWindow?.makeFirstResponder(textView)
            }
        }
        print("  Window visible: \(captureWindow?.isVisible ?? false)")
        print("  Window frame: \(captureWindow?.frame ?? .zero)")
    }

    private func findTextView(in view: NSView?) -> NSTextView? {
        guard let view = view else { return nil }

        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let found = findTextView(in: subview) {
                return found
            }
        }

        return nil
    }

    @objc func hideCaptureWindow() {
        captureWindow?.orderOut(nil)
        continueNoteWindow?.orderOut(nil)
    }
}

// Custom panel that can become key window (required for borderless windows to receive keyboard input)
class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
