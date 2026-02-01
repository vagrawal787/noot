import Foundation
import AppKit
import AVFoundation

final class MediaCompressionService {
    static let shared = MediaCompressionService()

    private init() {}

    // MARK: - Screenshot Compression

    /// Compress an image based on user preferences
    func compressScreenshot(at url: URL) async throws -> URL {
        let level = UserPreferences.shared.compressionLevel

        guard level != .none else { return url }

        guard let image = NSImage(contentsOf: url) else {
            throw CompressionError.failedToLoadImage
        }

        let quality: CGFloat
        let scale: CGFloat

        switch level {
        case .none:
            return url
        case .low:
            quality = 0.9
            scale = 1.0
        case .medium:
            quality = 0.75
            scale = 0.75
        case .high:
            quality = 0.5
            scale = 0.5
        }

        // Get original file size for tracking
        let originalSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0

        // Resize if needed
        let resizedImage: NSImage
        if scale < 1.0 {
            let newSize = NSSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            resizedImage = resizeImage(image, to: newSize)
        } else {
            resizedImage = image
        }

        // Compress to JPEG
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw CompressionError.compressionFailed
        }

        // Create new URL with .jpg extension
        let compressedURL = url.deletingPathExtension().appendingPathExtension("jpg")

        try jpegData.write(to: compressedURL)

        // Delete original if it's different
        if compressedURL.path != url.path {
            try? FileManager.default.removeItem(at: url)
        }

        // Log compression ratio
        let compressedSize = try FileManager.default.attributesOfItem(atPath: compressedURL.path)[.size] as? Int ?? 0
        let ratio = 1.0 - (Double(compressedSize) / Double(originalSize))
        print("Screenshot compressed: \(ByteCountFormatter.string(fromByteCount: Int64(originalSize), countStyle: .file)) -> \(ByteCountFormatter.string(fromByteCount: Int64(compressedSize), countStyle: .file)) (\(Int(ratio * 100))% reduction)")

        return compressedURL
    }

    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: image.size),
                  operation: .copy,
                  fraction: 1.0)
        resizedImage.unlockFocus()
        return resizedImage
    }

    // MARK: - Video Compression

    /// Get video bitrate based on compression level
    func videoBitrate(for level: CompressionLevel) -> Int {
        switch level {
        case .none: return 5_000_000  // 5 Mbps
        case .low: return 3_000_000   // 3 Mbps
        case .medium: return 2_000_000 // 2 Mbps
        case .high: return 1_000_000   // 1 Mbps
        }
    }

    /// Compress a video file (for post-processing if needed)
    func compressVideo(at url: URL) async throws -> URL {
        let level = UserPreferences.shared.compressionLevel

        guard level != .none else { return url }

        let asset = AVAsset(url: url)
        let originalSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0

        // Create output URL
        let outputURL = url.deletingPathExtension().appendingPathExtension("compressed.mp4")

        // Check if already compressed (prevent double compression)
        if url.path.contains("compressed") {
            return url
        }

        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetForLevel(level)) else {
            throw CompressionError.compressionFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        await exportSession.export()

        guard exportSession.status == .completed else {
            if let error = exportSession.error {
                throw error
            }
            throw CompressionError.compressionFailed
        }

        // Delete original
        try? FileManager.default.removeItem(at: url)

        // Log compression ratio
        let compressedSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int ?? 0
        let ratio = 1.0 - (Double(compressedSize) / Double(originalSize))
        print("Video compressed: \(ByteCountFormatter.string(fromByteCount: Int64(originalSize), countStyle: .file)) -> \(ByteCountFormatter.string(fromByteCount: Int64(compressedSize), countStyle: .file)) (\(Int(ratio * 100))% reduction)")

        return outputURL
    }

    private func presetForLevel(_ level: CompressionLevel) -> String {
        switch level {
        case .none: return AVAssetExportPresetPassthrough
        case .low: return AVAssetExportPreset1920x1080
        case .medium: return AVAssetExportPreset1280x720
        case .high: return AVAssetExportPreset960x540
        }
    }
}

enum CompressionError: Error {
    case failedToLoadImage
    case compressionFailed
}
