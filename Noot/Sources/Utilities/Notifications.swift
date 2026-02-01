import Foundation

extension Notification.Name {
    // Window management
    static let hideCaptureWindow = Notification.Name("hideCaptureWindow")
    static let showCaptureWindow = Notification.Name("showCaptureWindow")
    static let dismissCaptureWindow = Notification.Name("dismissCaptureWindow")
    static let triggerCaptureSave = Notification.Name("triggerCaptureSave")
    static let captureWindowNeedsResize = Notification.Name("captureWindowNeedsResize")
    static let showContinueNote = Notification.Name("showContinueNote")
    static let showInbox = Notification.Name("showInbox")
    static let showMainWindow = Notification.Name("showMainWindow")

    // Note actions
    static let continueWithNote = Notification.Name("continueWithNote")
    static let loadNoteIntoCapture = Notification.Name("loadNoteIntoCapture")
    static let navigateToNote = Notification.Name("navigateToNote")

    // Data changes
    static let contextsDidChange = Notification.Name("contextsDidChange")

    // Meeting
    static let toggleMeeting = Notification.Name("toggleMeeting")
    static let showMeetingEndPopup = Notification.Name("showMeetingEndPopup")

    // Media capture
    static let captureScreenshot = Notification.Name("captureScreenshot")
    static let toggleScreenRecording = Notification.Name("toggleScreenRecording")
    static let addMediaToCapture = Notification.Name("addMediaToCapture")
    static let screenRecordingStarted = Notification.Name("screenRecordingStarted")
    static let screenRecordingStopped = Notification.Name("screenRecordingStopped")
    static let recordingFileSizeWarning = Notification.Name("recordingFileSizeWarning")
}
