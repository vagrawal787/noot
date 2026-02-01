import AVFoundation
import Foundation
import ScreenCaptureKit

enum AudioSource: String, CaseIterable {
    case microphone = "Microphone"
    case system = "System Audio"
    case both = "Both"
}

final class AudioRecorderService: NSObject {
    static let shared = AudioRecorderService()

    private var audioRecorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var isRecording = false
    private var currentAudioSource: AudioSource = .microphone

    // For system audio capture
    private var screenCaptureStream: SCStream?
    private var audioWriter: AVAssetWriter?
    private var audioWriterInput: AVAssetWriterInput?
    private var systemAudioURL: URL?
    private var isFirstAudioSample = true
    private var audioSampleCount = 0

    // For combined recording
    private var micRecordingURL: URL?

    override private init() {
        super.init()
    }

    func startRecording(source: AudioSource = .microphone) throws -> URL {
        currentAudioSource = source

        switch source {
        case .microphone:
            return try startMicrophoneRecording()
        case .system:
            return try startSystemAudioRecording()
        case .both:
            return try startCombinedRecording()
        }
    }

    private func startMicrophoneRecording() throws -> URL {
        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw AudioRecorderError.permissionDenied
        default:
            throw AudioRecorderError.permissionDenied
        }

        // Setup recording file
        let attachmentsURL = try FileManager.nootAttachmentsDirectory()
        let audioURL = attachmentsURL.appendingPathComponent("audio")

        let filename = "audio_\(Date().timeIntervalSince1970).m4a"
        let fileURL = audioURL.appendingPathComponent(filename)

        currentRecordingURL = fileURL

        // Configure audio settings optimized for speech and small file size
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050, // Lower sample rate for speech
            AVNumberOfChannelsKey: 1, // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 64000 // 64 kbps as per spec
        ]

        audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()

        isRecording = true

        return fileURL
    }

    private func startSystemAudioRecording() throws -> URL {
        let attachmentsURL = try FileManager.nootAttachmentsDirectory()
        let audioURL = attachmentsURL.appendingPathComponent("audio")

        let filename = "system_audio_\(Date().timeIntervalSince1970).m4a"
        let fileURL = audioURL.appendingPathComponent(filename)

        systemAudioURL = fileURL
        currentRecordingURL = fileURL

        // Reset state
        isFirstAudioSample = true
        audioSampleCount = 0

        // Setup AVAssetWriter for audio - writer input will be created when we get the first sample
        // to match the actual audio format from ScreenCaptureKit
        audioWriter = try AVAssetWriter(outputURL: fileURL, fileType: .m4a)

        // Start ScreenCaptureKit stream for audio only
        Task {
            await startScreenCaptureForAudio()
        }

        isRecording = true
        print("System audio recording started, file: \(fileURL.path)")
        return fileURL
    }

    private func startCombinedRecording() throws -> URL {
        // Start microphone recording
        let attachmentsURL = try FileManager.nootAttachmentsDirectory()
        let audioURL = attachmentsURL.appendingPathComponent("audio")

        let micFilename = "mic_\(Date().timeIntervalSince1970).m4a"
        let micFileURL = audioURL.appendingPathComponent(micFilename)
        micRecordingURL = micFileURL

        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw AudioRecorderError.permissionDenied
        default:
            throw AudioRecorderError.permissionDenied
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 64000
        ]

        audioRecorder = try AVAudioRecorder(url: micFileURL, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()

        // Also start system audio - writer input will be created on first sample
        let sysFilename = "system_audio_\(Date().timeIntervalSince1970).m4a"
        let sysFileURL = audioURL.appendingPathComponent(sysFilename)
        systemAudioURL = sysFileURL

        audioWriter = try AVAssetWriter(outputURL: sysFileURL, fileType: .m4a)

        // Reset state
        isFirstAudioSample = true
        audioSampleCount = 0

        Task {
            await startScreenCaptureForAudio()
        }

        // Return mic URL as primary, system audio is secondary
        currentRecordingURL = micFileURL
        isRecording = true
        print("Combined recording started")
        return micFileURL
    }

    @MainActor
    private func startScreenCaptureForAudio() async {
        print("Starting screen capture for audio...")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

            guard let display = content.displays.first else {
                print("No display found for audio capture")
                return
            }

            print("Found display: \(display.displayID)")

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true // Don't capture our own audio
            config.width = 2 // Minimal video since we only want audio
            config.height = 2

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            screenCaptureStream = stream

            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            print("Added stream outputs")

            try await stream.startCapture()
            print("Screen capture started successfully")

        } catch {
            print("Failed to start system audio capture: \(error)")
        }
    }

    func stopRecording() -> URL? {
        guard isRecording else { return nil }

        print("Stopping recording... Audio samples captured: \(audioSampleCount)")

        // Stop microphone recording
        audioRecorder?.stop()
        audioRecorder = nil

        // Stop system audio capture
        if let stream = screenCaptureStream {
            Task {
                try? await stream.stopCapture()
                print("Screen capture stopped")
            }
            screenCaptureStream = nil
        }

        // Finish writing system audio
        if let writer = audioWriter {
            print("Finishing audio writer, status: \(writer.status.rawValue)")
            audioWriterInput?.markAsFinished()
            let semaphore = DispatchSemaphore(value: 0)
            writer.finishWriting {
                print("Audio writer finished, status: \(writer.status.rawValue)")
                if let error = writer.error {
                    print("Writer error: \(error)")
                }
                semaphore.signal()
            }
            semaphore.wait()
            audioWriter = nil
            audioWriterInput = nil
        }

        isRecording = false

        let url = currentRecordingURL
        currentRecordingURL = nil
        micRecordingURL = nil
        systemAudioURL = nil

        print("Recording stopped, returning URL: \(url?.path ?? "nil")")
        return url
    }

    /// Returns both audio URLs when recording both sources
    func stopRecordingWithSystemAudio() -> (mic: URL?, system: URL?) {
        guard isRecording else { return (nil, nil) }

        let micURL = micRecordingURL
        let sysURL = systemAudioURL

        // Stop microphone recording
        audioRecorder?.stop()
        audioRecorder = nil

        // Stop system audio capture
        if let stream = screenCaptureStream {
            Task {
                try? await stream.stopCapture()
            }
            screenCaptureStream = nil
        }

        // Finish writing system audio
        if let writer = audioWriter {
            audioWriterInput?.markAsFinished()
            let semaphore = DispatchSemaphore(value: 0)
            writer.finishWriting {
                semaphore.signal()
            }
            semaphore.wait()
            audioWriter = nil
            audioWriterInput = nil
        }

        isRecording = false
        currentRecordingURL = nil
        micRecordingURL = nil
        systemAudioURL = nil

        return (micURL, sysURL)
    }

    func pauseRecording() {
        audioRecorder?.pause()
    }

    func resumeRecording() {
        audioRecorder?.record()
    }

    var recordingState: Bool {
        isRecording
    }

    var currentDuration: TimeInterval? {
        audioRecorder?.currentTime
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Audio recording failed")
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Audio encoding error: \(error)")
        }
    }
}

extension AudioRecorderService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        audioSampleCount += 1

        // Setup writer on first audio sample using actual format
        if isFirstAudioSample {
            isFirstAudioSample = false

            guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                print("No format description in audio sample")
                return
            }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            print("First audio sample received, timestamp: \(timestamp.seconds)")

            // Get the audio stream basic description
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                print("Audio format: \(asbd.pointee.mSampleRate) Hz, \(asbd.pointee.mChannelsPerFrame) channels, \(asbd.pointee.mBitsPerChannel) bits")
            }

            // Create audio writer input with AAC output settings
            let audioSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]

            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings, sourceFormatHint: formatDesc)
            input.expectsMediaDataInRealTime = true

            if let writer = audioWriter, writer.canAdd(input) {
                writer.add(input)
                audioWriterInput = input

                writer.startWriting()
                writer.startSession(atSourceTime: timestamp)
                print("Writer started, status: \(writer.status.rawValue)")
            } else {
                print("Cannot add audio input to writer")
                return
            }
        }

        guard let input = audioWriterInput,
              input.isReadyForMoreMediaData,
              audioWriter?.status == .writing else {
            if audioSampleCount % 100 == 0 {
                print("Audio sample \(audioSampleCount), writer status: \(audioWriter?.status.rawValue ?? -1), ready: \(audioWriterInput?.isReadyForMoreMediaData ?? false)")
            }
            return
        }

        if !input.append(sampleBuffer) {
            if audioSampleCount % 100 == 0 {
                print("Failed to append audio sample \(audioSampleCount)")
            }
        }
    }
}

enum AudioRecorderError: Error {
    case permissionDenied
    case recordingFailed
}
