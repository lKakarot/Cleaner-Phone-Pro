//
//  CompressionService.swift
//  Cleaner Phone Pro
//

import Foundation
import UIKit
import Photos
import AVFoundation

// MARK: - Compression Level

enum CompressionLevel: String, CaseIterable {
    case low = "Faible"
    case medium = "Moyenne"
    case high = "Forte"

    var description: String {
        switch self {
        case .low: return "Qualité préservée"
        case .medium: return "Bon équilibre"
        case .high: return "Maximum d'espace"
        }
    }

    var icon: String {
        switch self {
        case .low: return "dial.low"
        case .medium: return "dial.medium"
        case .high: return "dial.high"
        }
    }

    var color: UIColor {
        switch self {
        case .low: return .systemGreen
        case .medium: return .systemOrange
        case .high: return .systemRed
        }
    }

    // Image compression quality (0.0 - 1.0)
    var imageQuality: CGFloat {
        switch self {
        case .low: return 0.7
        case .medium: return 0.5
        case .high: return 0.3
        }
    }

    // Video bitrate multiplier (lower = more compression)
    var videoBitrateMultiplier: Float {
        switch self {
        case .low: return 0.6
        case .medium: return 0.4
        case .high: return 0.2
        }
    }

    // Max dimension for images
    var maxImageDimension: CGFloat {
        switch self {
        case .low: return 3000
        case .medium: return 2000
        case .high: return 1500
        }
    }
}

// MARK: - Compression Result

struct CompressionResult {
    let originalSize: Int64
    let compressedSize: Int64
    let originalURL: URL?
    let compressedURL: URL
    let compressedImage: UIImage?
    let isVideo: Bool
    let asset: PHAsset

    var savedBytes: Int64 {
        originalSize - compressedSize
    }

    var savedPercentage: Double {
        guard originalSize > 0 else { return 0 }
        return Double(savedBytes) / Double(originalSize) * 100
    }

    var formattedOriginalSize: String {
        ByteCountFormatter.string(fromByteCount: originalSize, countStyle: .file)
    }

    var formattedCompressedSize: String {
        ByteCountFormatter.string(fromByteCount: compressedSize, countStyle: .file)
    }

    var formattedSavedSize: String {
        ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file)
    }
}

// MARK: - Compression Service

@MainActor
class CompressionService: ObservableObject {
    static let shared = CompressionService()

    @Published var isCompressing = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""

    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Main Compression Method

    func compress(asset: PHAsset, level: CompressionLevel) async -> CompressionResult? {
        isCompressing = true
        progress = 0
        statusMessage = "Préparation..."

        defer {
            isCompressing = false
            progress = 1.0
        }

        if asset.mediaType == .video {
            return await compressVideo(asset: asset, level: level)
        } else {
            return await compressImage(asset: asset, level: level)
        }
    }

    // MARK: - Image Compression

    private func compressImage(asset: PHAsset, level: CompressionLevel) async -> CompressionResult? {
        statusMessage = "Chargement de l'image..."
        progress = 0.1

        // Get original image
        guard let originalImage = await loadFullImage(for: asset) else {
            return nil
        }

        // Get original size
        let originalSize = await getAssetSize(asset: asset)

        progress = 0.3
        statusMessage = "Compression..."

        // Resize if needed
        var imageToCompress = originalImage
        let maxDim = level.maxImageDimension
        if originalImage.size.width > maxDim || originalImage.size.height > maxDim {
            imageToCompress = resizeImage(originalImage, maxDimension: maxDim)
        }

        progress = 0.6

        // Compress to JPEG
        guard let compressedData = imageToCompress.jpegData(compressionQuality: level.imageQuality) else {
            return nil
        }

        progress = 0.8
        statusMessage = "Sauvegarde..."

        // Save to temp file
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try compressedData.write(to: tempURL)
        } catch {
            print("Error saving compressed image: \(error)")
            return nil
        }

        progress = 1.0

        let compressedImage = UIImage(data: compressedData)

        return CompressionResult(
            originalSize: originalSize,
            compressedSize: Int64(compressedData.count),
            originalURL: nil,
            compressedURL: tempURL,
            compressedImage: compressedImage,
            isVideo: false,
            asset: asset
        )
    }

    // MARK: - Video Compression

    private func compressVideo(asset: PHAsset, level: CompressionLevel) async -> CompressionResult? {
        statusMessage = "Chargement de la vidéo..."
        progress = 0.1

        // Get original video URL
        guard let originalURL = await getVideoURL(for: asset) else {
            return nil
        }

        let originalSize = await getAssetSize(asset: asset)

        progress = 0.2
        statusMessage = "Compression de la vidéo..."

        // Create output URL
        let outputURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")

        // Compress video
        let success = await compressVideoFile(inputURL: originalURL, outputURL: outputURL, level: level)

        guard success else {
            return nil
        }

        // Get compressed size
        let compressedSize: Int64
        do {
            let attrs = try fileManager.attributesOfItem(atPath: outputURL.path)
            compressedSize = attrs[.size] as? Int64 ?? 0
        } catch {
            compressedSize = 0
        }

        progress = 1.0

        return CompressionResult(
            originalSize: originalSize,
            compressedSize: compressedSize,
            originalURL: originalURL,
            compressedURL: outputURL,
            compressedImage: nil,
            isVideo: true,
            asset: asset
        )
    }

    private func compressVideoFile(inputURL: URL, outputURL: URL, level: CompressionLevel) async -> Bool {
        let asset = AVAsset(url: inputURL)

        // Get video track
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return false
        }

        // Get original bitrate and dimensions
        let originalBitrate = try? await videoTrack.load(.estimatedDataRate)
        let naturalSize = try? await videoTrack.load(.naturalSize)
        let transform = try? await videoTrack.load(.preferredTransform)

        let targetBitrate = Int((originalBitrate ?? 5_000_000) * level.videoBitrateMultiplier)

        // Determine output size
        var outputSize = naturalSize ?? CGSize(width: 1920, height: 1080)
        if let t = transform {
            if t.a == 0 && t.d == 0 {
                outputSize = CGSize(width: outputSize.height, height: outputSize.width)
            }
        }

        // Scale down if needed
        let maxDim: CGFloat = level == .high ? 720 : (level == .medium ? 1080 : 1920)
        if outputSize.width > maxDim || outputSize.height > maxDim {
            let scale = maxDim / max(outputSize.width, outputSize.height)
            outputSize = CGSize(width: outputSize.width * scale, height: outputSize.height * scale)
        }

        // Round to even numbers (required by video encoders)
        outputSize.width = CGFloat(Int(outputSize.width / 2) * 2)
        outputSize.height = CGFloat(Int(outputSize.height / 2) * 2)

        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            return false
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Monitor progress
        let progressTask = Task {
            while !Task.isCancelled && exportSession.status == .exporting {
                await MainActor.run {
                    self.progress = 0.2 + Double(exportSession.progress) * 0.7
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        // Export
        await exportSession.export()
        progressTask.cancel()

        return exportSession.status == .completed
    }

    // MARK: - Save Compressed Media

    func saveCompressedMedia(_ result: CompressionResult, replaceOriginal: Bool) async -> Bool {
        statusMessage = "Sauvegarde..."

        do {
            if result.isVideo {
                // Save video to photo library
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: result.compressedURL)
                }
            } else {
                // Save image to photo library
                if let imageData = try? Data(contentsOf: result.compressedURL),
                   let image = UIImage(data: imageData) {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }
                }
            }

            // Delete original if requested
            if replaceOriginal {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets([result.asset] as NSFastEnumeration)
                }
            }

            // Clean up temp file
            try? fileManager.removeItem(at: result.compressedURL)

            return true
        } catch {
            print("Error saving compressed media: \(error)")
            return false
        }
    }

    // MARK: - Helpers

    private func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func getVideoURL(for asset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func getAssetSize(asset: PHAsset) async -> Int64 {
        await withCheckedContinuation { continuation in
            let resources = PHAssetResource.assetResources(for: asset)
            var totalSize: Int64 = 0

            for resource in resources {
                if let size = resource.value(forKey: "fileSize") as? Int64 {
                    totalSize += size
                }
            }

            continuation.resume(returning: totalSize)
        }
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)

        if ratio >= 1 { return image }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage ?? image
    }

    // MARK: - Cleanup

    func cleanupTempFiles() {
        let tempDir = fileManager.temporaryDirectory
        if let files = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in files {
                if file.pathExtension == "jpg" || file.pathExtension == "mp4" {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }
}
