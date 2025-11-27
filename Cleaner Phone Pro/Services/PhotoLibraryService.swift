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

// MARK: - Async Semaphore for concurrency limiting

actor AsyncSemaphore {
    private let limit: Int
    private var count: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func wait() async {
        if count < limit {
            count += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            count -= 1
        }
    }
}

class PhotoLibraryService: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    static let shared = PhotoLibraryService()

    private let imageManager = PHCachingImageManager()

    // OPTIMIZATION: Semaphore to limit concurrent thumbnail loads
    private let thumbnailSemaphore = AsyncSemaphore(limit: 6)

    // OPTIMIZATION: Thumbnail cache to avoid reloading
    private var thumbnailCache = NSCache<NSString, UIImage>()

    private init() {
        // Configure cache limits
        thumbnailCache.countLimit = 200 // Max 200 thumbnails in memory
        thumbnailCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB max

        // Configure caching image manager
        imageManager.allowsCachingHighQualityImages = false // Prefer speed
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = status
        }
        return status
    }

    // MARK: - Diagnostic: Get total counts from library

    func getLibraryDiagnostics() -> LibraryDiagnostics {
        // Get ALL photos (no filters at all)
        let allAssetsOptions = PHFetchOptions()
        let allAssets = PHAsset.fetchAssets(with: allAssetsOptions)

        // Get all images
        let allImagesOptions = PHFetchOptions()
        let allImages = PHAsset.fetchAssets(with: .image, options: allImagesOptions)

        // Get all videos
        let allVideosOptions = PHFetchOptions()
        let allVideos = PHAsset.fetchAssets(with: .video, options: allVideosOptions)

        // Get all audio
        let allAudioOptions = PHFetchOptions()
        let allAudio = PHAsset.fetchAssets(with: .audio, options: allAudioOptions)

        // Get smart albums to check "All Photos" album
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumUserLibrary,
            options: nil
        )

        var allPhotosAlbumCount = 0
        if let allPhotosAlbum = smartAlbums.firstObject {
            let assets = PHAsset.fetchAssets(in: allPhotosAlbum, options: nil)
            allPhotosAlbumCount = assets.count
        }

        // Count hidden photos
        let hiddenAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumAllHidden,
            options: nil
        )
        var hiddenCount = 0
        if let hiddenAlbum = hiddenAlbums.firstObject {
            let assets = PHAsset.fetchAssets(in: hiddenAlbum, options: nil)
            hiddenCount = assets.count
        }

        // Count burst photos
        let burstOptions = PHFetchOptions()
        burstOptions.includeAllBurstAssets = true
        let burstAssets = PHAsset.fetchAssets(with: .image, options: burstOptions)
        let burstCount = burstAssets.count - allImages.count

        // Count iCloud-only photos using PHAssetResource
        // A photo is "local" if it has a resource that is available locally
        var iCloudOnlyCount = 0
        var localCount = 0

        // Sample first 100 assets to get an estimate (full enumeration is slow)
        let sampleSize = min(100, allAssets.count)
        for i in 0..<sampleSize {
            let asset = allAssets.object(at: i)
            let resources = PHAssetResource.assetResources(for: asset)

            // Check if any resource has locallyAvailable flag
            var isLocal = false
            for resource in resources {
                // Use the more reliable locallyAvailable check
                if let locallyAvailable = resource.value(forKey: "locallyAvailable") as? Bool {
                    if locallyAvailable {
                        isLocal = true
                        break
                    }
                }
            }

            if isLocal {
                localCount += 1
            } else {
                iCloudOnlyCount += 1
            }
        }

        // Extrapolate to total count
        if sampleSize > 0 {
            let localRatio = Double(localCount) / Double(sampleSize)
            localCount = Int(Double(allAssets.count) * localRatio)
            iCloudOnlyCount = allAssets.count - localCount
        }

        return LibraryDiagnostics(
            totalAssets: allAssets.count,
            totalImages: allImages.count,
            totalVideos: allVideos.count,
            totalAudio: allAudio.count,
            allPhotosAlbumCount: allPhotosAlbumCount,
            hiddenCount: hiddenCount,
            burstExtraCount: burstCount,
            localCount: localCount,
            iCloudOnlyCount: iCloudOnlyCount
        )
    }

    // MARK: - Fetch methods (metadata only, no thumbnails)

    private func createFetchOptions(includeHidden: Bool = false, includeAllBursts: Bool = false) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // NE PAS définir includeAssetSourceTypes !
        // Le défaut (quand non défini) inclut TOUS les types de sources
        // Définir explicitement limite les résultats de manière inattendue
        options.includeHiddenAssets = includeHidden
        options.includeAllBurstAssets = includeAllBursts
        return options
    }

    func fetchScreenshots() async -> [MediaItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let allAssets = PHAsset.fetchAssets(with: .image, options: options)

        var items: [MediaItem] = []
        allAssets.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                let fileSize = self.getFileSize(for: asset)
                items.append(MediaItem(asset: asset, thumbnail: nil, fileSize: fileSize))
            }
        }

        return items
    }

    func fetchLargeVideos(minSizeMB: Int64 = 10) async -> [MediaItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets = PHAsset.fetchAssets(with: .video, options: options)
        var items = fetchMediaItemsMetadataOnly(from: assets)

        let minSizeBytes = minSizeMB * 1024 * 1024
        items = items.filter { $0.fileSize >= minSizeBytes }

        return items.sorted { $0.fileSize > $1.fileSize }
    }

    func fetchAllPhotos() async -> [MediaItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let allAssets = PHAsset.fetchAssets(with: .image, options: options)

        var items: [MediaItem] = []
        allAssets.enumerateObjects { asset, _, _ in
            if !asset.mediaSubtypes.contains(.photoScreenshot) {
                let fileSize = self.getFileSize(for: asset)
                items.append(MediaItem(asset: asset, thumbnail: nil, fileSize: fileSize))
            }
        }

        return items
    }

    func fetchAllVideos() async -> [MediaItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets = PHAsset.fetchAssets(with: .video, options: options)
        return fetchMediaItemsMetadataOnly(from: assets)
    }

    /// Fetch ALL photos including hidden and all burst photos
    func fetchAllPhotosIncludingHiddenAndBursts() async -> [MediaItem] {
        let options = createFetchOptions(includeHidden: true, includeAllBursts: true)
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) == 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )

        let assets = PHAsset.fetchAssets(with: .image, options: options)
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

    /// Load thumbnails for a batch of items (used in detail view) - OPTIMIZED with concurrency limit
    func loadThumbnailsBatch(for items: [MediaItem], quality: ThumbnailQuality = .detail) async -> [MediaItem] {
        var updatedItems = items

        // OPTIMIZATION: Load in batches with limited concurrency
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, item) in items.enumerated() {
                // Skip if already has thumbnail
                if item.thumbnail != nil {
                    continue
                }

                // Check cache first
                let cacheKey = "\(item.id)_\(quality)" as NSString
                if let cached = thumbnailCache.object(forKey: cacheKey) {
                    updatedItems[index].thumbnail = cached
                    continue
                }

                group.addTask {
                    // Wait for semaphore before loading
                    await self.thumbnailSemaphore.wait()
                    defer { Task { await self.thumbnailSemaphore.signal() } }

                    let thumbnail = await self.loadThumbnail(for: item.asset, quality: quality)

                    // Cache the result
                    if let thumbnail = thumbnail {
                        self.thumbnailCache.setObject(thumbnail, forKey: cacheKey)
                    }

                    return (index, thumbnail)
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

    /// Load thumbnails progressively for visible items only - OPTIMIZED for large collections
    func loadThumbnailsProgressive(
        for items: [MediaItem],
        visibleRange: Range<Int>,
        quality: ThumbnailQuality = .detail,
        onUpdate: @escaping (Int, UIImage) -> Void
    ) async {
        // Prioritize visible items + small buffer
        let bufferSize = 10
        let start = max(0, visibleRange.lowerBound - bufferSize)
        let end = min(items.count, visibleRange.upperBound + bufferSize)

        guard start < end else { return }

        let indicesToLoad = Array(start..<end)

        await withTaskGroup(of: Void.self) { group in
            for index in indicesToLoad {
                let item = items[index]

                // Skip if already has thumbnail
                if item.thumbnail != nil { continue }

                // Check cache
                let cacheKey = "\(item.id)_\(quality)" as NSString
                if let cached = thumbnailCache.object(forKey: cacheKey) {
                    onUpdate(index, cached)
                    continue
                }

                group.addTask {
                    await self.thumbnailSemaphore.wait()
                    defer { Task { await self.thumbnailSemaphore.signal() } }

                    if let thumbnail = await self.loadThumbnail(for: item.asset, quality: quality) {
                        self.thumbnailCache.setObject(thumbnail, forKey: cacheKey)
                        await MainActor.run {
                            onUpdate(index, thumbnail)
                        }
                    }
                }
            }
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
