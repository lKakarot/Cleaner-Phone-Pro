//
//  PhotoLibraryService.swift
//  Cleaner Phone Pro
//

import Photos
import UIKit
import AVFoundation
import Combine

enum ThumbnailQuality {
    case preview    // Pour les 3 previews des cards (bonne qualité)
    case detail     // Pour la vue détail (bonne qualité)

    var size: CGSize {
        switch self {
        case .preview: return CGSize(width: 400, height: 400)
        case .detail: return CGSize(width: 300, height: 300)
        }
    }
}

// MARK: - Video Loading State

enum VideoLoadingState: Equatable {
    case idle
    case loading
    case downloadingFromCloud(progress: Double)
    case ready(AVPlayerItem)
    case error(VideoLoadingError)

    static func == (lhs: VideoLoadingState, rhs: VideoLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.loading, .loading): return true
        case (.downloadingFromCloud(let p1), .downloadingFromCloud(let p2)): return p1 == p2
        case (.ready, .ready): return true
        case (.error(let e1), .error(let e2)): return e1 == e2
        default: return false
        }
    }
}

enum VideoLoadingError: Error, Equatable {
    case assetNotFound
    case downloadFailed
    case networkUnavailable
    case timeout
    case cancelled
    case unknown(String)

    var localizedDescription: String {
        switch self {
        case .assetNotFound: return "Vidéo introuvable"
        case .downloadFailed: return "Échec du téléchargement"
        case .networkUnavailable: return "Connexion internet requise"
        case .timeout: return "Délai d'attente dépassé"
        case .cancelled: return "Annulé"
        case .unknown(let msg): return msg
        }
    }
}

// MARK: - Video Loader (Observable for SwiftUI)

@MainActor
class VideoLoader: ObservableObject {
    @Published private(set) var state: VideoLoadingState = .idle
    @Published private(set) var playerItem: AVPlayerItem?

    private var requestID: PHImageRequestID?
    private var progressObserver: NSKeyValueObservation?
    private let imageManager = PHCachingImageManager()
    private var loadTask: Task<Void, Never>?

    func load(asset: PHAsset, timeout: TimeInterval = 60) {
        cancel()
        state = .loading

        loadTask = Task {
            await loadVideo(asset: asset, timeout: timeout)
        }
    }

    private func loadVideo(asset: PHAsset, timeout: TimeInterval) async {
        let assetId = asset.localIdentifier

        // Check cache first (VideoCache is @MainActor, we're already on MainActor)
        if let cachedItem = VideoCache.shared.get(for: assetId) {
            await preparePlayerItem(cachedItem)
            self.playerItem = cachedItem
            state = .ready(cachedItem)
            return
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current

        // Use highQualityFormat to ensure callback is called only once
        options.deliveryMode = .highQualityFormat

        // Progress handler for iCloud downloads
        options.progressHandler = { [weak self] progress, error, stop, info in
            Task { @MainActor in
                guard let self = self else { return }
                if error != nil {
                    self.state = .error(.downloadFailed)
                    return
                }
                if progress < 1.0 {
                    self.state = .downloadingFromCloud(progress: progress)
                }
            }
        }

        // Create timeout task
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return true
        }

        // Load video with proper continuation handling
        let result: AVPlayerItem? = await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            self.requestID = self.imageManager.requestPlayerItem(
                forVideo: asset,
                options: options
            ) { playerItem, info in
                resumeLock.lock()
                defer { resumeLock.unlock() }

                // Ensure we only resume once
                guard !hasResumed else { return }

                // Check for degraded/placeholder response - skip these
                if let info = info,
                   let isDegraded = info[PHImageResultIsDegradedKey] as? Bool,
                   isDegraded {
                    return
                }

                hasResumed = true
                continuation.resume(returning: playerItem)
            }
        }

        // Cancel timeout
        timeoutTask.cancel()

        // Check if we timed out
        if Task.isCancelled {
            state = .error(.cancelled)
            return
        }

        if let playerItem = result {
            // Pre-load the item for faster playback start
            await preparePlayerItem(playerItem)

            // Cache the AVAsset for future use
            let assetId = asset.localIdentifier
            let avAsset = playerItem.asset
            VideoCache.shared.set(avAsset, for: assetId)

            self.playerItem = playerItem
            state = .ready(playerItem)
        } else {
            state = .error(.assetNotFound)
        }
    }

    private func preparePlayerItem(_ playerItem: AVPlayerItem) async {
        // Preload asset keys for faster playback
        let asset = playerItem.asset

        do {
            // Load essential properties asynchronously
            let _ = try await asset.load(.isPlayable, .duration, .tracks)
        } catch {
            // Non-fatal, continue anyway
            print("Warning: Could not preload asset properties: \(error)")
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil

        if let requestID = requestID {
            imageManager.cancelImageRequest(requestID)
            self.requestID = nil
        }

        progressObserver?.invalidate()
        progressObserver = nil

        playerItem = nil
        state = .idle
    }

    deinit {
        if let requestID = requestID {
            imageManager.cancelImageRequest(requestID)
        }
        progressObserver?.invalidate()
    }
}

// MARK: - Video Cache

@MainActor
final class VideoCache {
    static let shared = VideoCache()

    private var cache: [String: CachedVideo] = [:]
    private let maxCacheSize = 5 // Keep last 5 videos in cache
    private var accessOrder: [String] = []

    struct CachedVideo {
        let avAsset: AVAsset
        let createdAt: Date
    }

    private init() {}

    func get(for assetId: String) -> AVPlayerItem? {
        if let cached = cache[assetId] {
            // Move to end of access order (most recently used)
            accessOrder.removeAll { $0 == assetId }
            accessOrder.append(assetId)

            // Create a new player item from the cached AVAsset
            return AVPlayerItem(asset: cached.avAsset)
        }
        return nil
    }

    func set(_ avAsset: AVAsset, for assetId: String) {
        // Evict oldest if at capacity
        while cache.count >= maxCacheSize && !accessOrder.isEmpty {
            let oldest = accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }

        cache[assetId] = CachedVideo(avAsset: avAsset, createdAt: Date())
        accessOrder.append(assetId)
    }

    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }
}

class PhotoLibraryService: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    static let shared = PhotoLibraryService()

    private let imageManager = PHCachingImageManager()

    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = status
        }
        return status
    }

    // MARK: - Fetch methods (metadata only, no thumbnails)

    func fetchScreenshots() async -> [MediaItem] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        return fetchMediaItemsMetadataOnly(from: assets)
    }

    func fetchLargeVideos(minSizeMB: Int64 = 10) async -> [MediaItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        let assets = PHAsset.fetchAssets(with: .video, options: options)
        var items = fetchMediaItemsMetadataOnly(from: assets)

        let minSizeBytes = minSizeMB * 1024 * 1024
        items = items.filter { $0.fileSize >= minSizeBytes }

        return items.sorted { $0.fileSize > $1.fileSize }
    }

    func fetchAllPhotos() async -> [MediaItem] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) == 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        return fetchMediaItemsMetadataOnly(from: assets)
    }

    func fetchAllVideos() async -> [MediaItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        let assets = PHAsset.fetchAssets(with: .video, options: options)
        return fetchMediaItemsMetadataOnly(from: assets)
    }

    // MARK: - Fast metadata-only fetch (no thumbnails)

    private func fetchMediaItemsMetadataOnly(from fetchResult: PHFetchResult<PHAsset>) -> [MediaItem] {
        var items: [MediaItem] = []

        fetchResult.enumerateObjects { asset, _, _ in
            let fileSize = self.getFileSize(for: asset)
            items.append(MediaItem(asset: asset, thumbnail: nil, fileSize: fileSize))
        }

        return items
    }

    // MARK: - Thumbnail loading

    func loadThumbnail(for asset: PHAsset, quality: ThumbnailQuality = .detail) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            imageManager.requestImage(
                for: asset,
                targetSize: quality.size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Load thumbnails for preview items (first 3 of each category) - in parallel
    func loadPreviewThumbnails(for items: [MediaItem]) async -> [MediaItem] {
        guard !items.isEmpty else { return items }

        var updatedItems = items
        let previewCount = min(3, items.count)

        // Load all 3 previews in parallel
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for i in 0..<previewCount {
                group.addTask {
                    let thumbnail = await self.loadThumbnail(for: items[i].asset, quality: .preview)
                    return (i, thumbnail)
                }
            }

            for await (index, thumbnail) in group {
                if let thumbnail = thumbnail {
                    updatedItems[index].thumbnail = thumbnail
                }
            }
        }

        return updatedItems
    }

    /// Load thumbnails for a batch of items (used in detail view)
    func loadThumbnailsBatch(for items: [MediaItem], quality: ThumbnailQuality = .detail) async -> [MediaItem] {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            var updatedItems = items

            for (index, item) in items.enumerated() {
                group.addTask {
                    let thumbnail = await self.loadThumbnail(for: item.asset, quality: quality)
                    return (index, thumbnail)
                }
            }

            for await (index, thumbnail) in group {
                if let thumbnail = thumbnail {
                    updatedItems[index].thumbnail = thumbnail
                }
            }

            return updatedItems
        }
    }

    // MARK: - Full resolution image

    func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    // MARK: - Video Playback

    /// Get a player item optimized for streaming (fast start) - FIXED version
    func getPlayerItem(for asset: PHAsset) async -> AVPlayerItem? {
        await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            // Use highQualityFormat to ensure single callback
            options.deliveryMode = .highQualityFormat
            options.version = .current

            imageManager.requestPlayerItem(forVideo: asset, options: options) { playerItem, info in
                resumeLock.lock()
                defer { resumeLock.unlock() }

                // Prevent multiple resume calls
                guard !hasResumed else { return }

                // Skip degraded responses
                if let info = info,
                   let isDegraded = info[PHImageResultIsDegradedKey] as? Bool,
                   isDegraded {
                    return
                }

                hasResumed = true
                continuation.resume(returning: playerItem)
            }
        }
    }

    /// Get video URL for advanced playback control
    func getVideoURL(for asset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current

            imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                resumeLock.lock()
                defer { resumeLock.unlock() }

                guard !hasResumed else { return }

                if let info = info,
                   let isDegraded = info[PHImageResultIsDegradedKey] as? Bool,
                   isDegraded {
                    return
                }

                hasResumed = true

                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Get video duration formatted
    func getVideoDuration(for asset: PHAsset) -> String {
        let duration = asset.duration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - File size

    func getFileSize(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)

        let targetTypes: [PHAssetResourceType] = [
            .video,
            .fullSizeVideo,
            .photo,
            .fullSizePhoto,
            .adjustmentBaseVideo,
            .adjustmentBasePhoto
        ]

        for targetType in targetTypes {
            if let resource = resources.first(where: { $0.type == targetType }),
               let fileSize = resource.value(forKey: "fileSize") as? Int64,
               fileSize > 0 {
                return fileSize
            }
        }

        if let resource = resources.first,
           let fileSize = resource.value(forKey: "fileSize") as? Int64 {
            return fileSize
        }

        if asset.mediaType == .video {
            let estimatedBytesPerSecond: Double = 170_000
            return Int64(asset.duration * estimatedBytesPerSecond)
        }

        return 0
    }
}
