import Cocoa
import ScreenCaptureKit
import AVFoundation

final class ScreenCaptureService: NSObject {
    static let shared = ScreenCaptureService()

    private var isRecording = false
    private var currentRecordingURL: URL?
    private var screenRecorder: SCStream?
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var screenshotContinuation: CheckedContinuation<CGImage, Error>?
    private var fileSizeCheckTimer: Timer?
    private var hasWarnedAboutFileSize = false

    override private init() {
        super.init()
    }

    // MARK: - Public Sync Wrappers

    /// Capture a screenshot and open it in the capture window
    func captureScreenshot() {
        Task {
            do {
                let url = try await captureScreenshotToFile()
                await MainActor.run {
                    // Open capture window with the screenshot
                    NotificationCenter.default.post(name: .showCaptureWindow, object: nil)
                    // After a short delay, add the screenshot to the note
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NotificationCenter.default.post(
                            name: .addMediaToCapture,
                            object: nil,
                            userInfo: ["url": url, "type": "screenshot"]
                        )
                    }
                }
            } catch {
                print("Screenshot capture failed: \(error)")
            }
        }
    }

    /// Toggle screen recording on/off
    func toggleRecording() {
        Task {
            if isRecording {
                do {
                    if let url = try await stopRecording() {
                        await MainActor.run {
                            // Open capture window with the recording
                            NotificationCenter.default.post(name: .showCaptureWindow, object: nil)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                NotificationCenter.default.post(
                                    name: .addMediaToCapture,
                                    object: nil,
                                    userInfo: ["url": url, "type": "recording"]
                                )
                            }
                        }
                    }
                } catch {
                    print("Stop recording failed: \(error)")
                }
            } else {
                do {
                    try await startRecording()
                    await MainActor.run {
                        // Show recording indicator
                        NotificationCenter.default.post(name: .screenRecordingStarted, object: nil)
                    }
                } catch {
                    print("Start recording failed: \(error)")
                }
            }
        }
    }

    // MARK: - Screenshot

    func captureScreenshotToFile() async throws -> URL {
        // Request screen capture permission if needed
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw ScreenCaptureError.permissionDenied
        }

        // Get available content
        let content = try await SCShareableContent.current

        guard let display = content.displays.first else {
            throw ScreenCaptureError.noDisplayAvailable
        }

        // Create filter for the display
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Configure screenshot
        let config = SCStreamConfiguration()
        config.width = display.width * 2 // Retina
        config.height = display.height * 2
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        // Capture using stream-based approach (works on macOS 13+)
        let image = try await captureFrame(filter: filter, config: config)

        // Save to file
        var url = try saveScreenshot(image)

        // Apply compression based on user preferences
        url = try await MediaCompressionService.shared.compressScreenshot(at: url)

        return url
    }

    private func captureFrame(filter: SCContentFilter, config: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            self.screenshotContinuation = continuation

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)

            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)

                Task {
                    do {
                        try await stream.startCapture()
                        // Wait for frame capture
                        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                        try await stream.stopCapture()

                        // If we haven't captured a frame yet, fail
                        if self.screenshotContinuation != nil {
                            self.screenshotContinuation?.resume(throwing: ScreenCaptureError.encodingFailed)
                            self.screenshotContinuation = nil
                        }
                    } catch {
                        if self.screenshotContinuation != nil {
                            self.screenshotContinuation?.resume(throwing: error)
                            self.screenshotContinuation = nil
                        }
                    }
                }
            } catch {
                self.screenshotContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func saveScreenshot(_ image: CGImage) throws -> URL {
        let attachmentsURL = try FileManager.nootAttachmentsDirectory()
        let screenshotsURL = attachmentsURL.appendingPathComponent("screenshots")

        let filename = "screenshot_\(Date().timeIntervalSince1970).png"
        let fileURL = screenshotsURL.appendingPathComponent(filename)

        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw ScreenCaptureError.encodingFailed
        }

        try pngData.write(to: fileURL)
        return fileURL
    }

    // MARK: - Screen Recording

    func startRecording() async throws {
        guard !isRecording else { return }

        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw ScreenCaptureError.permissionDenied
        }

        let content = try await SCShareableContent.current

        guard let display = content.displays.first else {
            throw ScreenCaptureError.noDisplayAvailable
        }

        // Setup recording file
        let attachmentsURL = try FileManager.nootAttachmentsDirectory()
        let recordingsURL = attachmentsURL.appendingPathComponent("recordings")

        let filename = "recording_\(Date().timeIntervalSince1970).mp4"
        let fileURL = recordingsURL.appendingPathComponent(filename)

        currentRecordingURL = fileURL

        // Setup AVAssetWriter
        videoWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)

        let bitrate = MediaCompressionService.shared.videoBitrate(for: UserPreferences.shared.compressionLevel)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: display.width,
            AVVideoHeightKey: display.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate
            ]
        ]

        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = true

        if let input = videoWriterInput {
            videoWriter?.add(input)
        }

        // Setup SCStream
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 fps
        config.pixelFormat = kCVPixelFormatType_32BGRA

        screenRecorder = SCStream(filter: filter, configuration: config, delegate: nil)

        try screenRecorder?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))

        videoWriter?.startWriting()
        videoWriter?.startSession(atSourceTime: .zero)

        try await screenRecorder?.startCapture()
        isRecording = true
        hasWarnedAboutFileSize = false

        // Start file size monitoring
        startFileSizeMonitoring()
    }

    private func startFileSizeMonitoring() {
        fileSizeCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkFileSize()
        }
    }

    private func stopFileSizeMonitoring() {
        fileSizeCheckTimer?.invalidate()
        fileSizeCheckTimer = nil
    }

    private func checkFileSize() {
        guard !hasWarnedAboutFileSize,
              let url = currentRecordingURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? Int else { return }

        let thresholdMB = UserPreferences.shared.largeFileWarningMB
        let thresholdBytes = thresholdMB * 1024 * 1024

        if fileSize > thresholdBytes {
            hasWarnedAboutFileSize = true
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .recordingFileSizeWarning,
                    object: nil,
                    userInfo: ["fileSize": fileSize, "thresholdMB": thresholdMB]
                )
            }
        }
    }

    func stopRecording() async throws -> URL? {
        guard isRecording else { return nil }

        stopFileSizeMonitoring()

        try await screenRecorder?.stopCapture()
        screenRecorder = nil

        videoWriterInput?.markAsFinished()

        await videoWriter?.finishWriting()

        isRecording = false

        let url = currentRecordingURL
        currentRecordingURL = nil

        return url
    }

    var recordingState: Bool {
        isRecording
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Handle screenshot capture
        if let continuation = screenshotContinuation {
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                let context = CIContext()
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    continuation.resume(returning: cgImage)
                    screenshotContinuation = nil
                    return
                }
            }
        }

        // Handle video recording
        guard let input = videoWriterInput,
              input.isReadyForMoreMediaData else {
            return
        }

        input.append(sampleBuffer)
    }
}

// MARK: - Errors

enum ScreenCaptureError: Error {
    case permissionDenied
    case noDisplayAvailable
    case encodingFailed
    case recordingFailed
}
